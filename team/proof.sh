#!/usr/bin/env bash
# Dispatches stub scenarios on main, one at a time, and asserts how each ended. Run by a
# human or a supervising agent, never by a workflow. Stubs cost no model time, but each
# MERGED scenario adds stub files to main, and all of them take over an hour.
#
#   team/proof.sh [pattern]    Every scenario, or those matching an extended regex.
#
# Start with `retry-pass`. It's the one run that shows a called workflow's outputs
# survive a failed job, which every retry depends on. PROOF_GH_LIMIT is how many seconds
# one gh call gets, 120 by default.
#
# Mode `product` needs TEAM_PRODUCT_ENABLED set to true, and it and `go` leave issues
# behind. `go` is a real issue with team:go, and team:stub to keep agents out of it. A
# stranger needs a second account, so those two read a stub event, not a real one.
set -euo pipefail

# scenario mode outcome blocked-at attempts test-job
scenarios="
retry-pass team MERGED - 2 success
pass team MERGED - 1 success
impossible team BLOCKED test 4 failure
tamper-test team BLOCKED test 4 failure
tamper-config team BLOCKED test 4 failure
tamper-workflow team BLOCKED publish 1 skipped
secret team BLOCKED publish 1 skipped
review-block team BLOCKED verdict 4 success
retry-review team MERGED - 2 success
retry-fail team BLOCKED test 4 failure
retry-same team BLOCKED publish 2 skipped
pass solo BLOCKED solo 1 success
impossible solo BLOCKED solo 1 failure
tamper-config solo BLOCKED solo 1 failure
review-block solo BLOCKED solo 1 success
paused product STOPPED - - -
cap product STOPPED - - -
blocked product STOPPED - - -
pass product MERGED - 1 success
impossible product BLOCKED test 4 failure
stranger board NOTHING - - -
stranger-label board NOTHING - - -
go board MERGED - 1 success
"

pattern=${1:-.}
pause=${PROOF_PAUSE:-20}
gh_limit=${PROOF_GH_LIMIT:-120}

# One call hung for 75 minutes. This is plain bash because macOS has no `timeout`. The
# watcher writes nowhere, or `$(gh ...)` would stay open until its sleep ended.
gh() {
  local pid watcher code=0
  command gh "$@" &
  pid=$!
  (sleep "$gh_limit" && kill "$pid" && sleep 5 && kill -9 "$pid") >/dev/null 2>&1 &
  watcher=$!
  wait "$pid" || code=$?
  kill "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true
  return "$code"
}

repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
failed=0

newest() { # <workflow> Prints its latest run's ID.
  gh run list --workflow "$1" --limit 1 --json databaseId --jq '.[0].databaseId // 0'
}

next_run() { # <workflow> <run ID> Prints the ID of a newer run, or fails.
  local id="" tries=0
  while [ -z "$id" ]; do
    tries=$((tries + 1))
    [ "$tries" -le 30 ] || return 1
    sleep "$pause"
    id=$(gh run list --workflow "$1" --limit 1 --json databaseId \
      --jq ".[] | select(.databaseId > $2) | .databaseId")
  done
  echo "$id"
}

dispatch() { # <workflow> <gh field args...> Prints the new run's ID, or fails.
  local workflow=$1 before
  shift
  before=$(newest "$workflow") || return 1
  gh workflow run "$workflow" --ref main "$@" >&2 || return 1
  next_run "$workflow" "$before"
}

finished() { # <run id> Fails if it never ends.
  local tries=0
  until [ "$(gh run view "$1" --json status --jq .status)" = completed ]; do
    tries=$((tries + 1))
    [ "$tries" -le 360 ] || return 1
    sleep "$pause"
  done
}

record_of() { # <run id>
  gh api "repos/$repo/contents/runs/$1/record.json?ref=team-runs" \
    -H 'Accept: application/vnd.github.raw+json' 2>/dev/null
}

outcome_of() { # <run id> Prints "mode outcome blocked-at attempts test-job head", from the record.
  record_of "$1" |
    jq -r '"\(.mode) \(.outcome) \(if .blocked_at == "" then "-" else .blocked_at end) \(.attempts_run) \(.attempts[-1].jobs.test) \(.head)"'
}

check() { # <scenario> <mode> <outcome> <blocked-at> <attempts> <test-job> <run id>
  local got head gate state gate_wanted=failure state_wanted=CLOSED problem=""
  if ! finished "$7"; then
    echo "FAIL  $1 ($2), run $7: still not finished"
    failed=$((failed + 1))
    return
  fi

  got=$(outcome_of "$7") || got="no record"
  head=${got##* }
  gate=$(gh api "repos/$repo/commits/$head/check-runs" \
    --jq '[.check_runs[] | select(.name == "team-gate")][0].conclusion') || gate=none
  state=$(gh pr view "team/run-$7" --json state --jq .state) || state=none
  if [ "$3" = MERGED ]; then
    gate_wanted=success
    state_wanted=MERGED
  fi

  [ "${got% *}" = "$2 $3 $4 $5 $6" ] || problem="record says: $got"
  [ "$gate" = "$gate_wanted" ] || problem="$problem team-gate is $gate"
  [ "$state" = "$state_wanted" ] || problem="$problem PR is $state"
  if gh api "repos/$repo/git/ref/heads/team/run-$7" >/dev/null 2>&1; then
    problem="$problem run branch is still there"
  fi
  # A gate that ran leaves its output, even as the only artifact in the run.
  if [ "$6" != skipped ] && ! gh api "repos/$repo/contents/runs/$7/gate-1.txt?ref=team-runs" >/dev/null 2>&1; then
    problem="$problem the record has no gate output"
  fi

  if [ -z "$problem" ]; then
    echo "PASS  $1 ($2): $3 $4, attempts $5, run $7"
  else
    echo "FAIL  $1 ($2), run $7: $problem"
    failed=$((failed + 1))
  fi
}

# Ends with no team run started, and says why in its log.
stopped() { # <scenario> <mode> <workflow> <wanted text in the log>
  local before run log problem=""
  if ! before=$(newest team.yml) || ! run=$(dispatch "$3" -f scenario="$1") || ! finished "$run"; then
    echo "FAIL  $1 ($2): no run finished"
    failed=$((failed + 1))
    return
  fi
  log=$(gh run view "$run" --log) || log=""
  [[ $log == *"$4"* ]] || problem="its log doesn't say: $4"
  [ "$(newest team.yml)" = "$before" ] || problem="$problem a team run started"
  if [ -z "$problem" ]; then
    echo "PASS  $1 ($2): $4, run $run"
  else
    echo "FAIL  $1 ($2), run $run: $problem"
    failed=$((failed + 1))
  fi
}

# Starts a team run through an issue. The run has to end as `check` says, and the issue
# has to say the same.
through_issue() { # <scenario> <mode> <outcome> <blocked-at> <attempts> <test-job>
  local before run issue got wanted="OPEN team:blocked" scenario=$1
  [ "$3" != MERGED ] || wanted="CLOSED team:merged"
  if ! before=$(newest team.yml); then
    echo "FAIL  $1 ($2): no run started"
    failed=$((failed + 1))
    return
  fi
  if [ "$2" = product ]; then
    dispatch product.yml -f scenario="$1" >/dev/null || before=none
  else
    scenario=pass
    gh label create team:go --force >/dev/null 2>&1 || true
    gh label create team:stub --force >/dev/null 2>&1 || true
    gh issue create --title "Proof scenario: $1" --body "A proof of team:go." \
      --label team:stub --label team:go >&2 || before=none
  fi
  if [ "$before" = none ] || ! run=$(next_run team.yml "$before"); then
    echo "FAIL  $1 ($2): no run started"
    failed=$((failed + 1))
    return
  fi

  check "$scenario" team "$3" "$4" "$5" "$6" "$run"
  issue=$(record_of "$run" | jq -r .issue) || issue=""
  got=$(gh issue view "$issue" --json state,labels \
    --jq '"\(.state) \([.labels[].name | select(. != "team:stub")] | join(" "))"') || got=none
  if [ "$got" = "$wanted" ]; then
    echo "PASS  $1 ($2): issue $issue is $got"
  else
    echo "FAIL  $1 ($2), run $run: issue $issue is $got"
    failed=$((failed + 1))
  fi
}

while read -r scenario mode outcome blocked_at attempts test_job <&3; do
  [ -n "$scenario" ] && grep -qE -- "$pattern" <<<"$scenario $mode" || continue
  case "$mode $outcome" in
    "product STOPPED") stopped "$scenario" "$mode" product.yml "PRODUCT STOP: $scenario" ;;
    "board NOTHING") stopped "$scenario" "$mode" board.yml "nothing happens" ;;
    product* | board*) through_issue "$scenario" "$mode" "$outcome" "$blocked_at" "$attempts" "$test_job" ;;
    *)
      if run=$(dispatch team.yml -f goal="Proof scenario: $scenario" -f scenario="$scenario" -f mode="$mode"); then
        check "$scenario" "$mode" "$outcome" "$blocked_at" "$attempts" "$test_job" "$run"
      else
        echo "FAIL  $scenario ($mode): no run started"
        failed=$((failed + 1))
      fi
      ;;
  esac
done 3<<<"$scenarios"

[ "$failed" -eq 0 ]
