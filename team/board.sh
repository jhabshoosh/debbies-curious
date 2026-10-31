#!/usr/bin/env bash
# Trusted. The task board, on GitHub Issues. Text in an issue is data here: it arrives
# in a file, passes a scan and leaves as one argument, and nothing ever runs it.
#
#   board.sh open <goal.json>
#     Product's goal: opens its issue and starts its run. Takes SCENARIO.
#   board.sh intake <event.json>
#     An `issues` event. Starts a run only if the owner wrote the issue and the owner
#     labelled it team:go, and anything else does nothing. Takes TEAM_PAUSED.
#   board.sh finish <records>
#     Labels and comments with how a run ended, and closes the issue on a merge.
#     Needs ISSUE, OUTCOME, BRANCH and RUN_ID, and takes REASON and BLOCKED_AT.
#   board.sh pr-body
#     Prints a run's pull request body. Needs GOAL, and takes ISSUE.
#
# All but `pr-body` need GH_REPO. `open` and `intake` need gitleaks on PATH. TEAM_PAUSED
# is true or false, as the workflows set it, and anything else reads as paused. `open`
# also takes what `product.sh check` does. A label moves through
# team:go, team:running, then team:merged or team:blocked. team:stub on an owner's issue
# puts stand-ins in place of agents, as `scenario` does, and the gate still decides.
set -euo pipefail

team=$(cd "$(dirname "$0")" && pwd -P)
config=$team/config.json

fail() {
  echo "BOARD FAIL: $*" >&2
  exit 1
}

# Refused once a label exists, and a real problem shows up in the next call.
ensure_labels() {
  local label
  for label in team:go team:stub team:running team:blocked team:merged; do
    gh api --method POST "repos/$GH_REPO/labels" -f name="$label" -f color=1d76db >/dev/null 2>&1 || true
  done
}

add_label() { # <issue> <label>
  gh api --method POST "repos/$GH_REPO/issues/$1/labels" -f "labels[]=$2" >/dev/null
}

remove_label() { # <issue> <label> It may not be there.
  gh api --method DELETE "repos/$GH_REPO/issues/$1/labels/${2/:/%3A}" >/dev/null 2>&1 || true
}

comment() { # <issue> <text>
  gh api --method POST "repos/$GH_REPO/issues/$1/comments" -f body="$2" >/dev/null
}

# scan.sh trims, and a goal cut short is a different goal, so a long one is refused.
clean() { # <in> <out> Fails if the text is too long or fails the scan.
  local max
  max=$(jq -er .limits.goal_max_bytes "$config") || fail "config has no goal_max_bytes"
  [ "$(wc -c <"$1")" -le "$max" ] && "$team/scan.sh" text "$1" "$2" "$max" >/dev/null 2>&1
}

# As an indented code block, because under this job's token GitHub acts on a closing
# keyword or an @mention in a body, and not on either in code. A fence could be closed
# from inside, and an indent can't.
quoted() { # Reads text.
  sed 's/^/    /'
}

pr_body() {
  printf '%s\n' "${GOAL:?GOAL is required}" | quoted
  # Only a link. `finish` is what closes the issue, and only on a merge.
  if [[ ${ISSUE:-} =~ ^[0-9]+$ ]]; then
    printf '\nIssue: #%s\n' "$ISSUE"
  fi
}

refuse() { # <issue> <why> The owner asked, so they hear why, and can add team:go again.
  remove_label "$1" team:go
  comment "$1" "This didn't start: $2 Add \`team:go\` again to retry."
  echo "BOARD: issue $1 was refused"
}

start() { # <issue> <goal file> <scenario>
  add_label "$1" team:running
  if ! gh workflow run team.yml --repo "$GH_REPO" --ref main \
    -f goal="$(cat "$2")" -f scenario="$3" -f issue="$1"; then
    remove_label "$1" team:running
    add_label "$1" team:blocked
    comment "$1" "The run didn't start, because the dispatch was refused."
    fail "the run for issue $1 didn't start"
  fi
  echo "BOARD: started a run for issue $1"
}

open() {
  local file=${1:-} tmp title number go
  [ -f "$file" ] || fail "no goal: $file"
  # The agent took a while, so what `limits` said may no longer hold.
  go=$("$team/product.sh" limits | sed -n 's/^go=//p')
  if [ "$go" != true ]; then
    echo "BOARD: the limits no longer allow this, so nothing opens"
    return
  fi
  tmp=$(mktemp -d)
  # Checked where it was written too, but this job trusts no agent's file.
  jq -e 'def text: type == "string" and length > 0;
    type == "object" and keys == ["goal", "reason"] and (.goal | text) and (.reason | text)' \
    "$file" >/dev/null || fail "not a goal: $file"
  jq -r .goal "$file" >"$tmp/goal"
  jq -r .reason "$file" >"$tmp/reason"
  clean "$tmp/goal" "$tmp/goal.clean" || fail "the goal is too long or failed the scan"
  clean "$tmp/reason" "$tmp/reason.clean" || fail "the reason is too long or failed the scan"

  ensure_labels
  title=$(jq -Rsr 'sub("^\\s+"; "") | (split("\n")[0] // "")[:100]' "$tmp/goal.clean")
  [ -n "$title" ] || fail "the goal is blank"
  number=$(gh api --method POST "repos/$GH_REPO/issues" -f title="$title" \
    -f body="$(quoted <"$tmp/goal.clean")

Why this goal:

$(quoted <"$tmp/reason.clean")

Chosen by the Product agent." --jq .number)
  start "$number" "$tmp/goal.clean" "${SCENARIO:-}"
  [ -z "${GITHUB_OUTPUT:-}" ] || echo "issue=$number" >>"$GITHUB_OUTPUT"
  rm -rf "${tmp:?}"
}

intake() {
  local event=${1:-} number labels active scenario="" tmp
  [ -f "$event" ] || fail "no event: $event"

  # IDs, because a login can change hands. Both come from GitHub, not from anything
  # the issue's writer controls.
  if ! jq -e '(.repository.owner.id | type == "number")
    and .label.name == "team:go"
    and .issue.user.id == .repository.owner.id
    and .sender.id == .repository.owner.id' "$event" >/dev/null; then
    echo "BOARD: not the owner's go-ahead, so nothing happens"
    return
  fi
  number=$(jq -er .issue.number "$event")
  [[ $number =~ ^[0-9]+$ ]] || fail "not an issue number: $number"

  if [ "$(jq -r .issue.state "$event")" != open ]; then
    refuse "$number" "the issue is closed."
    return
  fi
  if [ "${TEAM_PAUSED:-false}" != false ]; then
    refuse "$number" "the team is paused."
    return
  fi

  # Asked for now, since labels set on a new issue each send their own event.
  labels=$(gh api "repos/$GH_REPO/issues/$number/labels" --jq '[.[].name]')
  if jq -e 'index("team:running")' <<<"$labels" >/dev/null; then
    # A label can outlive its run, so GitHub decides. team.yml's run-name holds this title.
    active=$(gh api "repos/$GH_REPO/actions/workflows/team.yml/runs?per_page=100" \
      --jq "[.workflow_runs[] | select(.status != \"completed\" and .display_title == \"Team run, issue $number\")] | length")
    if [ "$active" != 0 ]; then
      refuse "$number" "a run for this issue is still going."
      return
    fi
  fi
  if jq -e 'index("team:stub")' <<<"$labels" >/dev/null; then
    scenario=pass
  fi

  tmp=$(mktemp -d)
  jq -r '"\(.issue.title)\n\n\(.issue.body // "")"' "$event" >"$tmp/goal"
  if ! clean "$tmp/goal" "$tmp/goal.clean"; then
    refuse "$number" "the issue is too long or failed the secret scan."
    return
  fi
  ensure_labels
  remove_label "$number" team:go
  remove_label "$number" team:blocked
  remove_label "$number" team:running
  start "$number" "$tmp/goal.clean" "$scenario"
  rm -rf "${tmp:?}"
}

finish() {
  local records=${1:-} issue=${ISSUE:-} pr links row most text
  [[ $issue =~ ^[0-9]+$ ]] || fail "not an issue number: $issue"
  pr=$(gh pr view "${BRANCH:?BRANCH is required}" --repo "$GH_REPO" --json url --jq .url) || pr=none
  links="Pull request: $pr
Run record: https://github.com/$GH_REPO/blob/team-runs/runs/${RUN_ID:?RUN_ID is required}/record.json"

  ensure_labels
  remove_label "$issue" team:running
  if [ "${OUTCOME:?OUTCOME is required}" = MERGED ]; then
    add_label "$issue" team:merged
    comment "$issue" "Merged: ${REASON:-no reason}.

$links"
    gh api --method PATCH "repos/$GH_REPO/issues/$issue" -f state=closed -f state_reason=completed >/dev/null
    return
  fi

  add_label "$issue" team:blocked
  text="Blocked at ${BLOCKED_AT:-unknown}: ${REASON:-no reason}.

$links"
  row=$("$team/product.sh" blocked "$records" 2>/dev/null) || row=0
  most=$(jq -er .limits.blocked_in_a_row "$config") || most=0
  if [ "$most" -gt 0 ] && [ "$row" -ge "$most" ]; then
    text="$text

That's $row blocked runs in a row, so Product has stopped. It stays stopped until a run merges."
  fi
  comment "$issue" "$text"
}

command=${1:-}
[ "$#" -eq 0 ] || shift
[ "$command" = pr-body ] || : "${GH_REPO:?GH_REPO is required}"
case "$command" in
  open) open "$@" ;;
  intake) intake "$@" ;;
  finish) finish "$@" ;;
  pr-body) pr_body ;;
  *) fail "usage: board.sh open <goal.json> | intake <event.json> | finish <records> | pr-body" ;;
esac
