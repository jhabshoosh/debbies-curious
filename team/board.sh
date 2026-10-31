#!/usr/bin/env bash
# Trusted. The task board, on GitHub Issues. Text in an issue is data here: it arrives
# in a file, passes a scan and leaves as one argument, and nothing ever runs it.
#
#   board.sh open <goal.json>
#     Product's goal: opens its issue and starts its run. Takes SCENARIO.
#
# Needs GH_REPO, and gitleaks on PATH.
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
  local file=${1:-} tmp title number
  [ -f "$file" ] || fail "no goal: $file"
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
  title=$(jq -Rsr 'ltrimstr("\n") | split("\n")[0][:100]' "$tmp/goal.clean")
  number=$(gh api --method POST "repos/$GH_REPO/issues" -f title="$title" \
    -f body="$(cat "$tmp/goal.clean")

**Why this goal:** $(cat "$tmp/reason.clean")

Chosen by the Product agent." --jq .number)
  start "$number" "$tmp/goal.clean" "${SCENARIO:-}"
  rm -rf "${tmp:?}"
}

command=${1:-}
[ "$#" -eq 0 ] || shift
: "${GH_REPO:?GH_REPO is required}"
case "$command" in
  open) open "$@" ;;
  *) fail "usage: board.sh open <goal.json>" ;;
esac
