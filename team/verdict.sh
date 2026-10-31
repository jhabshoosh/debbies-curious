#!/usr/bin/env bash
# Trusted. Decides one attempt, and builds what the next one is told. Agents' job
# outputs reach it as env, and what they wrote reaches it as files. It only reads them.
#
#   verdict.sh decide <attempt.json>
#     Prints verdict=pass|retry|blocked, reason=<text> and next=<attempt>, and writes
#     numbers and fixed text to <attempt.json> for the run record. Needs ATTEMPT,
#     TEST_RESULT, GATE_OUTCOME, PUBLISH_RESULT, BUILD_RESULT, REVIEW_RESULT and
#     BLOCKING, plus BUILD_AGENT,
#     REVIEW_AGENT, BUILD_STATS and REVIEW_STATS where they exist. ATTEMPTS replaces
#     the limit in config.
#   verdict.sh feedback <artifact-dir> <feedback.json>
#     Writes what a retry's Builder gets: the failed gate step with trimmed output, or
#     the Reviewer's blocking findings. Needs ATTEMPT and TEST_RESULT. <artifact-dir>
#     holds gate-<n>.log and review-<n>.json. Text that fails the scan is withheld.
set -euo pipefail

team=$(cd "$(dirname "$0")" && pwd -P)
config=$team/config.json

fail() {
  echo "VERDICT FAIL: $*" >&2
  exit 1
}

decide() {
  local out=${1:-} verdict=blocked reason="" retry=no agent attempts=${ATTEMPTS:-}
  [ -n "$out" ] || fail "usage: verdict.sh decide <attempt.json>"
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
  fi

  jq -n --argjson attempt "${ATTEMPT:?ATTEMPT is required}" \
    --arg verdict "$verdict" --arg reason "$reason" \
    --arg build "${BUILD_RESULT:-}" --arg publish "${PUBLISH_RESULT:-}" --arg test "${TEST_RESULT:-}" \
    --arg review "${REVIEW_RESULT:-}" --arg blocking "${BLOCKING:-}" \
    --arg build_stats "${BUILD_STATS:-}" --arg review_stats "${REVIEW_STATS:-}" \
    'def stats: try fromjson catch null; # Never worth failing a verdict over.
    {attempt: $attempt, verdict: $verdict, reason: $reason,
      jobs: {build: $build, publish: $publish, test: $test, review: $review},
      blocking: (try ($blocking | tonumber) catch null),
      agents: {build: ($build_stats | stats), review: ($review_stats | stats)}}' >"$out"

  echo "verdict=$verdict"
  echo "reason=$reason"
  echo "next=$((ATTEMPT + 1))"
}

gate_feedback() { # <artifact-dir> <feedback.json> <scratch-dir>
  local log=$1/gate-${ATTEMPT:?ATTEMPT is required}.log step=unknown last="" max
  max=$(jq -er .limits.feedback_max_bytes "$config") || fail "config has no feedback_max_bytes"
  [ ! -f "$log" ] || last=$(sed -n 's/^==> //p' "$log" | tail -1)

  # A step the gate really has, because the log is free text from PR code.
  if jq -e --arg step "$last" \
    '[.install, .commands[], "frozen paths", "diff limits", "gitleaks"] | any(. == $step)' \
    "$config" >/dev/null; then
    step=$last
  fi

  if [ -f "$log" ] && "$team/scan.sh" text "$log" "$3/output" "$max" >/dev/null 2>&1; then
    jq -n --arg step "$step" --rawfile output "$3/output" \
      '{source: "gate", step: $step, output: $output}' >"$2"
  else
    jq -n --arg step "$step" \
      '{source: "gate", step: $step, withheld: "The output is missing, or failed the secret scan."}' >"$2"
  fi
}

review_feedback() { # <artifact-dir> <feedback.json> <scratch-dir>
  local review=$1/review-${ATTEMPT:?ATTEMPT is required}.json max
  max=$(jq -er .limits.record_max_bytes "$config") || fail "config has no record_max_bytes"

  # Only what stopped the merge: the findings, and a `fail` verdict that has none.
  if jq '{source: "review", blocking,
      failed: ({works, good} | with_entries(select(.value.verdict == "fail")))}' \
    "$review" >"$3/findings" 2>/dev/null &&
    "$team/scan.sh" text "$3/findings" "$2" "$max" >/dev/null 2>&1 &&
    jq -e . "$2" >/dev/null 2>&1; then
    return
  fi
  jq -n '{source: "review", withheld: "The findings are missing, or failed the secret scan."}' >"$2"
}

feedback() {
  local in=${1:-} out=${2:-} tmp
  [ -d "$in" ] && [ -n "$out" ] || fail "usage: verdict.sh feedback <artifact-dir> <feedback.json>"
  tmp=$(mktemp -d)
  if [ "${TEST_RESULT:-}" = failure ]; then
    gate_feedback "$in" "$out" "$tmp"
  else
    review_feedback "$in" "$out" "$tmp"
  fi
  rm -rf "${tmp:?}"
}

command=${1:-}
[ "$#" -eq 0 ] || shift
case "$command" in
  decide) decide "$@" ;;
  feedback) feedback "$@" ;;
  *) fail "usage: verdict.sh decide <attempt.json> | feedback <artifact-dir> <feedback.json>" ;;
esac
