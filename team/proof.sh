#!/usr/bin/env bash
# Dispatches stub scenarios on main, one at a time, and asserts how each ended. Run by a
# human or a supervising agent, never by a workflow. Stubs cost no model time, but each
# MERGED scenario adds stub files to main, and all of them take over an hour.
#
#   team/proof.sh [pattern]    Every scenario, or those matching an extended regex.
#
# Start with `retry-pass`. It's the one run that shows a called workflow's outputs
# survive a failed job, which every retry depends on.
set -euo pipefail

# scenario mode outcome blocked-at attempts
scenarios="
retry-pass team MERGED - 2
pass team MERGED - 1
impossible team BLOCKED test 4
tamper-test team BLOCKED test 4
tamper-config team BLOCKED test 4
tamper-workflow team BLOCKED publish 1
secret team BLOCKED publish 1
review-block team BLOCKED verdict 4
retry-review team MERGED - 2
retry-fail team BLOCKED test 4
pass solo MERGED - 1
impossible solo BLOCKED test 1
tamper-config solo BLOCKED test 1
review-block solo MERGED - 1
"

pattern=${1:-.}
pause=${PROOF_PAUSE:-20}
repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
failed=0

dispatch() { # <scenario> <mode> Prints the new run's ID, or fails.
  local before id="" tries=0
  before=$(gh run list --workflow team.yml --limit 1 --json databaseId --jq '.[0].databaseId // 0') || return 1
  gh workflow run team.yml --ref main -f goal="Proof scenario: $1" -f scenario="$1" -f mode="$2" >&2 || return 1
  while [ -z "$id" ]; do
    tries=$((tries + 1))
    [ "$tries" -le 30 ] || return 1
    sleep "$pause"
    id=$(gh run list --workflow team.yml --limit 1 --json databaseId \
      --jq ".[] | select(.databaseId > $before) | .databaseId")
  done
  echo "$id"
}

outcome_of() { # <run id> Prints "mode outcome blocked-at attempts head", from the record.
  gh api "repos/$repo/contents/runs/$1/record.json?ref=team-runs" \
    -H 'Accept: application/vnd.github.raw+json' 2>/dev/null |
    jq -r '"\(.mode) \(.outcome) \(if .blocked_at == "" then "-" else .blocked_at end) \(.attempts_run) \(.head)"'
}

check() { # <scenario> <mode> <outcome> <blocked-at> <attempts> <run id>
  local got head gate state gate_wanted=failure state_wanted=CLOSED problem="" tries=0
  until [ "$(gh run view "$6" --json status --jq .status)" = completed ]; do
    tries=$((tries + 1))
    if [ "$tries" -gt 360 ]; then
      echo "FAIL  $1 ($2), run $6: still not finished"
      failed=$((failed + 1))
      return
    fi
    sleep "$pause"
  done

  got=$(outcome_of "$6") || got="no record"
  head=${got##* }
  gate=$(gh api "repos/$repo/commits/$head/check-runs" \
    --jq '[.check_runs[] | select(.name == "team-gate")][0].conclusion') || gate=none
  state=$(gh pr view "team/run-$6" --json state --jq .state) || state=none
  if [ "$3" = MERGED ]; then
    gate_wanted=success
    state_wanted=MERGED
  fi

  [ "${got% *}" = "$2 $3 $4 $5" ] || problem="record says: $got"
  [ "$gate" = "$gate_wanted" ] || problem="$problem team-gate is $gate"
  [ "$state" = "$state_wanted" ] || problem="$problem PR is $state"
  if gh api "repos/$repo/git/ref/heads/team/run-$6" >/dev/null 2>&1; then
    problem="$problem run branch is still there"
  fi

  if [ -z "$problem" ]; then
    echo "PASS  $1 ($2): $3 $4, attempts $5, run $6"
  else
    echo "FAIL  $1 ($2), run $6: $problem"
    failed=$((failed + 1))
  fi
}

while read -r scenario mode outcome blocked_at attempts <&3; do
  [ -n "$scenario" ] && grep -qE -- "$pattern" <<<"$scenario $mode" || continue
  if run=$(dispatch "$scenario" "$mode"); then
    check "$scenario" "$mode" "$outcome" "$blocked_at" "$attempts" "$run"
  else
    echo "FAIL  $scenario ($mode): no run started"
    failed=$((failed + 1))
  fi
done 3<<<"$scenarios"

[ "$failed" -eq 0 ]
