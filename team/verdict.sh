#!/usr/bin/env bash
# Trusted. Decides one attempt, and builds what the next one is told. Agents' job
# outputs reach it as env, and what they wrote reaches it as files. It only reads them.
#
#   verdict.sh decide <artifact-dir>
#     Prints verdict=pass|retry|blocked, reason=<text>, record=<json> and
#     feedback=<json>, all at the very end, so a failure here publishes no verdict.
#     Needs ATTEMPT, TEST_RESULT, GATE_OUTCOME, PUBLISH_RESULT, BUILD_RESULT,
#     REVIEW_RESULT and BLOCKING, plus BUILD_AGENT, REVIEW_AGENT, BUILD_STATS and
#     REVIEW_STATS where they exist. ATTEMPTS replaces the limit in config. Of
#     <artifact-dir>, only record-gate-<n>/gate-<n>.log and
#     record-review-<n>/review-<n>.json are read.
#
# On a retry, feedback holds the failed gate step with trimmed output, or the Reviewer's
# blocking findings. Text that fails the scan is withheld, and each field is capped, so
# it fits a job output.
set -euo pipefail

team=$(cd "$(dirname "$0")" && pwd -P)
config=$team/config.json

fail() {
  echo "VERDICT FAIL: $*" >&2
  exit 1
}

gate_feedback() { # <artifact-dir> <scratch-dir> Prints one line of JSON.
  local log=$1/record-gate-$ATTEMPT/gate-$ATTEMPT.log step=unknown last="" max withheld=false
  max=$(jq -er .limits.feedback_max_bytes "$config") || fail "config has no feedback_max_bytes"
  [ ! -f "$log" ] || last=$(sed -n 's/^==> //p' "$log" | tail -1)

  # A step the gate really has, because the log is free text from PR code.
  if jq -e --arg step "$last" \
    '[.install, .commands[], "frozen paths", "diff limits", "gitleaks"] | any(. == $step)' \
    "$config" >/dev/null; then
    step=$last
  fi

  : >"$2/output"
  if [ ! -f "$log" ] || ! "$team/scan.sh" text "$log" "$2/output" "$max" >/dev/null 2>&1; then
    withheld=true
  fi
  jq -cn --arg step "$step" --rawfile output "$2/output" --argjson withheld "$withheld" \
    '{source: "gate", step: $step, output: $output, withheld: $withheld}'
}

review_feedback() { # <artifact-dir> <scratch-dir> Prints one line of JSON.
  local review=$1/record-review-$ATTEMPT/review-$ATTEMPT.json max withheld=false
  max=$(jq -er .limits.feedback_max_bytes "$config") || fail "config has no feedback_max_bytes"

  # Only what stopped the merge: the findings, and a `fail` verdict that has none.
  : >"$2/findings"
  if ! jq -r '[(.blocking[] | "\(.file): \(.problem) Evidence: \(.evidence)"),
      ({works, good} | to_entries[] | select(.value.verdict == "fail")
        | "\(.key) failed: \(.value.checked)")] | join("\n")' "$review" >"$2/text" 2>/dev/null ||
    ! "$team/scan.sh" text "$2/text" "$2/findings" "$max" >/dev/null 2>&1; then
    withheld=true
  fi
  jq -cn --rawfile findings "$2/findings" --argjson withheld "$withheld" \
    '{source: "review", findings: $findings, withheld: $withheld}'
}

decide() {
  local in=${1:-} verdict=blocked reason="" retry=no agent attempts=${ATTEMPTS:-} record tmp feedback=""
  [ -d "$in" ] || fail "usage: verdict.sh decide <artifact-dir>"
  [ -n "$attempts" ] || attempts=$(jq -er .limits.attempts "$config") || fail "config has no attempts limit"

  # What each agent's execution file showed comes first, so a usage limit never reads
  # as a bad review. These don't retry, and a failure stops the run, so at most one
  # is set.
  for agent in "build=${BUILD_AGENT:-}" "review=${REVIEW_AGENT:-}"; do
    case "$agent" in
      *=limit) reason="usage limit in ${agent%=*}" ;;
      *=failed) reason="agent failed in ${agent%=*}" ;;
      *=invalid) reason="invalid review output" ;;
    esac
  done

  # Only gate.sh failing or a review blocking goes back to the Builder. A test job that
  # failed anywhere else says nothing about the change, so a Builder can't fix it.
  if [ -n "$reason" ]; then
    :
  elif [ "${PUBLISH_RESULT:-}" != success ]; then
    reason="stopped before the gate: build ${BUILD_RESULT:-unknown}, publish ${PUBLISH_RESULT:-unknown}"
  elif [ "${TEST_RESULT:-}" = failure ] && [ "${GATE_OUTCOME:-}" = failure ]; then
    reason="gate failed"
    retry=yes
  elif [ "${TEST_RESULT:-}" = failure ]; then
    reason="test job failed outside the gate, in checkout or setup"
  elif [ "${TEST_RESULT:-}" != success ]; then
    reason="gate did not finish"
  elif [ "${REVIEW_RESULT:-}" != success ]; then
    reason="stopped before review"
  elif [[ ! ${BLOCKING:-} =~ ^[0-9]+$ ]]; then
    reason="review gave no count"
  elif [ "$BLOCKING" -eq 0 ]; then
    verdict=pass
    reason="no blocking findings"
  else
    reason="blocking findings: $BLOCKING"
    retry=yes
  fi

  if [ "$retry" = yes ] && [ "${ATTEMPT:?ATTEMPT is required}" -lt "$attempts" ]; then
    verdict=retry
    tmp=$(mktemp -d)
    if [ "${TEST_RESULT:-}" = failure ]; then
      feedback=$(gate_feedback "$in" "$tmp")
    else
      feedback=$(review_feedback "$in" "$tmp")
    fi
    rm -rf "${tmp:?}"
  fi

  record=$(jq -cn --argjson attempt "${ATTEMPT:?ATTEMPT is required}" \
    --arg verdict "$verdict" --arg reason "$reason" \
    --arg build "${BUILD_RESULT:-}" --arg publish "${PUBLISH_RESULT:-}" --arg test "${TEST_RESULT:-}" \
    --arg review "${REVIEW_RESULT:-}" --arg blocking "${BLOCKING:-}" \
    --arg build_stats "${BUILD_STATS:-}" --arg review_stats "${REVIEW_STATS:-}" \
    'def stats: try fromjson catch null; # Never worth failing a verdict over.
    {attempt: $attempt, verdict: $verdict, reason: $reason,
      jobs: {build: $build, publish: $publish, test: $test, review: $review},
      blocking: (try ($blocking | tonumber) catch null),
      agents: {build: ($build_stats | stats), review: ($review_stats | stats)}}')

  echo "verdict=$verdict"
  echo "reason=$reason"
  echo "record=$record"
  echo "feedback=$feedback"
}

command=${1:-}
[ "$#" -eq 0 ] || shift
case "$command" in
  decide) decide "$@" ;;
  *) fail "usage: verdict.sh decide <artifact-dir>" ;;
esac
