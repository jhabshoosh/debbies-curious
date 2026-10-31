#!/usr/bin/env bash
# Trusted. Product's limits, and the workspace it reads. No agent decides either.
#
#   product.sh check <records>
#     Prints go=true or go=false and reason=<text>, at the very end, so a failure here
#     starts nothing. <records> holds runs/<id>/record.json from team-runs. Needs
#     GH_REPO, and takes TEAM_PAUSED.
#   product.sh blocked <records>
#     Prints how many of the latest runs in a row ended BLOCKED.
#   product.sh workspace <main> <records>
#     Fills this directory with what Product may read and nothing else, so it never
#     holds an issue, a comment, a stub's record, or team's scripts and specs.
#
# Only real runs count. A stub or a paused run spends nothing, and solo always ends
# BLOCKED by design.
set -euo pipefail

team=$(cd "$(dirname "$0")" && pwd -P)
config=$team/config.json

fail() {
  echo "PRODUCT FAIL: $*" >&2
  exit 1
}

# Oldest first. A run ID only grows, and every record has one, even the fixed-field
# fallback that record.sh writes. That fallback has no scenario, so it reads as real.
real_runs() { # <records>
  [ -d "$1/runs" ] || fail "no records in: $1"
  jq -s 'map(select((.scenario // "") == "" and .reason != "paused")) | sort_by(.run_id | tonumber)' \
    "$1"/runs/*/record.json
}

blocked() { # <records>
  real_runs "${1:-}" |
    jq 'map(select(.mode != "solo")) | reverse | (map(.outcome == "BLOCKED") | index(false)) // length'
}

# A run with no readable time counts, so an odd record can't lift the cap.
this_week() { # <records>
  real_runs "$1" | jq '(now - 604800) as $since
    | map(select((.finished_at // "" | try fromdate catch now) > $since)) | length'
}

stop() { # <key> <text>
  echo "PRODUCT STOP: $1: $2" >&2
  # A stopped run is green, so this is where the owner can see why.
  [ -z "${GITHUB_STEP_SUMMARY:-}" ] || echo "Product stopped: $2" >>"$GITHUB_STEP_SUMMARY"
  echo "go=false"
  echo "reason=$2"
}

check() {
  local records=${1:-} cap most active row week
  cap=$(jq -er .limits.runs_per_week "$config") || fail "config has no runs_per_week"
  most=$(jq -er .limits.blocked_in_a_row "$config") || fail "config has no blocked_in_a_row"

  if [ "${TEAM_PAUSED:-}" = true ]; then
    stop paused "TEAM_PAUSED is true"
    return
  fi

  active=$(gh api "repos/${GH_REPO:?GH_REPO is required}/actions/workflows/team.yml/runs?per_page=20" \
    --jq '[.workflow_runs[] | select(.status != "completed")] | length')
  if [ "$active" != 0 ]; then
    stop running "a team run is in progress"
    return
  fi

  row=$(blocked "$records")
  if [ "$row" -ge "$most" ]; then
    stop blocked "$row blocked runs in a row"
    return
  fi

  week=$(this_week "$records")
  if [ "$week" -ge "$cap" ]; then
    stop cap "$week runs this week, and the cap is $cap"
    return
  fi

  echo "go=true"
  echo "reason=$week of $cap runs this week"
}

limits() {
  local tmp
  tmp=$(mktemp -d)
  gh api "repos/${GH_REPO:?GH_REPO is required}/tarball/team-runs" | tar -xz --strip-components=1 -C "$tmp"
  if [ -n "${SCENARIO:-}" ]; then
    "$team/stub.sh" limits "$tmp"
  fi
  check "$tmp"
  rm -rf "${tmp:?}"
}

# All Product learns from a run. Everything else in a record, and every file beside it,
# holds text that agents or PR code wrote, which could steer every later goal. So there
# are no goals here, and a value outside these lists reads as `other`.
summary() { # <records>
  real_runs "$1" | jq '
    def fixed($pattern): if type == "string" and test($pattern) then . else "other" end;
    def date: fixed("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
    def reasons: "no blocking findings|blocking findings: [0-9]+|gate failed|gate did not finish"
      + "|test job failed outside the gate, in checkout or setup|stopped before review"
      + "|stopped before any attempt|stopped before the gate: build [a-z]*, publish [a-z]*"
      + "|review gave no count|invalid review output|no verdict from the last attempt"
      + "|merge refused|team-gate could not be posted"
      + "|usage limit in (lead|build|review)|agent failed in (lead|build|review)";
    map({run_id: (.run_id | tonumber),
      mode: (.mode | fixed("^(team|solo)$")),
      outcome: (.outcome | fixed("^(MERGED|BLOCKED)$")),
      blocked_at: (.blocked_at | fixed("^(lead|pin|red|build|publish|test|review|verdict|merge|solo)?$")),
      reason: (.reason | fixed("^(\(reasons))$")),
      cost_usd: ([.agents.lead.cost_usd?, .agents.solo.cost_usd?, .attempts[]?.agents.build.cost_usd?,
        .attempts[]?.agents.review.cost_usd?] | map(numbers) | add // 0),
      started_at: (.started_at | date),
      finished_at: (.finished_at | date)})'
}

workspace() {
  local main=${1:-} records=${2:-} path
  [ -f "$main/team/product.md" ] || fail "no product brief in: $main"
  [ -d "$records/runs" ] || fail "no records in: $records"
  mkdir team runs
  cp "$main/team/product.md" team/
  for path in src public e2e evals package.json README.md; do
    [ ! -e "$main/$path" ] || cp -R "$main/$path" .
  done
  summary "$records" >runs.json
}

note() {
  local out=${1:-} outcome=failed
  [ -n "$out" ] || fail "usage: product.sh note <out-dir>"
  if [ -n "${OPENED:-}" ]; then
    outcome=opened
  elif [ "${OPEN_RESULT:-}" = success ]; then
    outcome=stopped
  fi
  mkdir -p "$out"
  jq -n --arg run_id "${RUN_ID:?RUN_ID is required}" --arg scenario "${SCENARIO:-}" \
    --arg outcome "$outcome" --arg stats "${STATS:-}" \
    'def number: if type == "number" then . else null end;
    (try ($stats | fromjson) catch null) as $spent
    | {run_id: $run_id, scenario: $scenario, outcome: $outcome,
        turns: ($spent.turns? | number), cost_usd: ($spent.cost_usd? | number),
        finished_at: (now | floor | todate)}' >"$out/record.json"
}

command=${1:-}
[ "$#" -eq 0 ] || shift
case "$command" in
  check) check "$@" ;;
  blocked) blocked "$@" ;;
  workspace) workspace "$@" ;;
  *) fail "usage: product.sh check <records> | blocked <records> | workspace <main> <records>" ;;
esac
