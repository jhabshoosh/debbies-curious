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

workspace() {
  local main=${1:-} records=${2:-} path
  [ -f "$main/team/product.md" ] || fail "no product brief in: $main"
  [ -d "$records/runs" ] || fail "no records in: $records"
  mkdir team runs
  cp "$main/team/product.md" team/
  for path in src public e2e evals package.json README.md; do
    [ ! -e "$main/$path" ] || cp -R "$main/$path" .
  done
  # Stubs outnumber real runs, and their goals read like past work.
  for path in "$records"/runs/*; do
    if jq -e '(.scenario // "") == ""' "$path/record.json" >/dev/null 2>&1; then
      cp -R "$path" runs/
    fi
  done
}

command=${1:-}
[ "$#" -eq 0 ] || shift
case "$command" in
  check) check "$@" ;;
  blocked) blocked "$@" ;;
  workspace) workspace "$@" ;;
  *) fail "usage: product.sh check <records> | blocked <records> | workspace <main> <records>" ;;
esac
