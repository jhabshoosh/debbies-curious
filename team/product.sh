#!/usr/bin/env bash
# Trusted. Product's limits, what it reads, and its own record. No agent decides these.
#
#   product.sh limits
#     Fetches team-runs, then does `check`. With SCENARIO set, stub.sh adds its records.
#   product.sh check <records>
#     Prints go=true or go=false and reason=<text>, at the very end, so a failure here
#     starts nothing. <records> holds team-runs. Needs GH_REPO. Takes TEAM_PRODUCT_ENABLED
#     and TEAM_PAUSED as the workflows set them: true or false, by GitHub's own comparison.
#     Anything else reads as off, and as paused.
#   product.sh blocked <records>
#     Prints how many of the latest runs in a row ended BLOCKED. Needs GH_REPO.
#   product.sh workspace <main> <records>
#     Fills this directory with what Product may read and nothing else, so it never
#     holds an issue, a comment, team's scripts and specs, or any text from a run.
#   product.sh note <out-dir>
#     Writes the record of one Product run. Needs RUN_ID. Takes SCENARIO, STATS,
#     OPEN_RESULT and OPENED.
#
# Only real runs count. A stub spends nothing, a paused run was the owner's call and not
# the team's failure, and solo always ends BLOCKED by design.
set -euo pipefail

team=$(cd "$(dirname "$0")" && pwd -P)
config=$team/config.json

fail() {
  echo "PRODUCT FAIL: $*" >&2
  exit 1
}

# The fixed-field fallback that record.sh writes has no scenario, so it reads as real.
real='select((.scenario // "") == "" and .reason != "paused")'

# Oldest first. A run ID only grows, and every record has one, even that fallback.
real_runs() { # <records>
  [ -d "$1/runs" ] || fail "no records in: $1"
  jq -s "map($real) | sort_by(.run_id | tonumber)" "$1"/runs/*/record.json
}

team_runs() { # What GitHub says about team.yml, newest first.
  gh api "repos/${GH_REPO:?GH_REPO is required}/actions/workflows/team.yml/runs?per_page=100" \
    --jq '[.workflow_runs[] | {id, status, updated_at}]'
}

# Writing a record is best-effort, so a finished run with none reads as blocked: that
# stops Product, which is the safe way to be wrong. Older runs came before records. The
# records stay in files, because a record can be 200 KB and Linux caps one argument at 128.
known_runs() { # <records> <team_runs JSON>
  [ -d "$1/runs" ] || fail "no records in: $1"
  jq -s --argjson seen "$2" "map(.run_id | tonumber) as \$ids
    | map($real | {run_id, mode, outcome, finished_at})
      + [\$seen[] | select(.status == \"completed\" and .id > (\$ids | min) and (.id | IN(\$ids[]) | not))
        | {run_id: (.id | tostring), mode: \"team\", outcome: \"BLOCKED\", finished_at: .updated_at}]
    | sort_by(.run_id | tonumber)" "$1"/runs/*/record.json
}

streak() { # Reads runs. Prints how many of the newest ended BLOCKED.
  jq 'map(select(.mode != "solo")) | reverse | (map(.outcome == "BLOCKED") | index(false)) // length'
}

blocked() { # <records>
  local seen
  seen=$(team_runs)
  known_runs "${1:-}" "$seen" | streak
}

# A run with no readable time counts, so an odd record can't lift the cap.
this_week() { # Reads runs.
  jq '(now - 604800) as $since | map(select((.finished_at // "" | try fromdate catch now) > $since)) | length'
}

# What Product itself has spent, oldest first.
product_runs() { # <records>
  local files=("$1"/product/*/record.json)
  if [ -e "${files[0]}" ]; then
    jq -s 'map(select((.scenario // "") == "")) | sort_by(.run_id | tonumber)' "${files[@]}"
  else
    echo '[]'
  fi
}

stop() { # <key> <text>
  echo "PRODUCT STOP: $1: $2" >&2
  # A stopped run is green, so this is where the owner can see why.
  [ -z "${GITHUB_STEP_SUMMARY:-}" ] || echo "Product stopped: $2" >>"$GITHUB_STEP_SUMMARY"
  echo "go=false"
  echo "reason=$2"
}

check() {
  local records=${1:-} cap most daily seen runs row week own today failing
  cap=$(jq -er .limits.runs_per_week "$config") || fail "config has no runs_per_week"
  most=$(jq -er .limits.blocked_in_a_row "$config") || fail "config has no blocked_in_a_row"
  daily=$(jq -er .limits.product.runs_per_day "$config") || fail "config has no product.runs_per_day"

  if [ "${TEAM_PRODUCT_ENABLED:-false}" != true ]; then
    stop off "TEAM_PRODUCT_ENABLED isn't true"
    return
  fi
  if [ "${TEAM_PAUSED:-false}" != false ]; then
    stop paused "TEAM_PAUSED is true"
    return
  fi

  seen=$(team_runs)
  if ! jq -e 'all(.[]; .status == "completed")' <<<"$seen" >/dev/null; then
    stop running "a team run is in progress"
    return
  fi

  runs=$(known_runs "$records" "$seen")
  row=$(streak <<<"$runs")
  if [ "$row" -ge "$most" ]; then
    stop blocked "$row blocked runs in a row"
    return
  fi

  week=$(this_week <<<"$runs")
  if [ "$week" -ge "$cap" ]; then
    stop cap "$week runs this week, and the cap is $cap"
    return
  fi

  # A failing Product spends and starts nothing, so nothing above would ever see it.
  own=$(product_runs "$records")
  today=$(jq '(now | floor | todate | .[:10]) as $day
    | map(select(((.finished_at // $day) | .[:10]) == $day)) | length' <<<"$own")
  if [ "$today" -ge "$daily" ]; then
    stop daily "$today Product runs today, and the limit is $daily"
    return
  fi
  # Only the last week's, or this could never clear: a stop writes no record to end it.
  failing=$(jq '(now - 604800) as $since | map(select((.finished_at // "" | try fromdate catch now) > $since))
    | reverse | (map(.outcome == "failed") | index(false)) // length' <<<"$own")
  if [ "$failing" -ge "$most" ]; then
    stop failing "$failing failed Product runs in a row"
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
  mkdir team
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
  limits) limits ;;
  check) check "$@" ;;
  blocked) blocked "$@" ;;
  workspace) workspace "$@" ;;
  note) note "$@" ;;
  *) fail "usage: product.sh limits | check <records> | blocked <records> | workspace <main> <records> | note <out-dir>" ;;
esac
