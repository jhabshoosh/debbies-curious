#!/usr/bin/env bash
# Trusted. Decides one attempt. Agents' job outputs reach it as env and are only read.
#
#   verdict.sh decide <attempt.json>
#     Prints verdict=pass|blocked and reason=<text>, and writes numbers and fixed
#     text to <attempt.json> for the run record. Needs ATTEMPT, TEST_RESULT,
#     PUBLISH_RESULT, REVIEW_RESULT and BLOCKING, plus LEAD_AGENT, BUILD_AGENT,
#     REVIEW_AGENT, BUILD_STATS and REVIEW_STATS where they exist.
set -euo pipefail

fail() {
  echo "VERDICT FAIL: $*" >&2
  exit 1
}

# Valid JSON, or null. Stats are never worth failing a verdict over.
json_or_null() {
  jq -cs 'if length == 1 then .[0] else null end' <<<"${1:-}" 2>/dev/null || echo null
}

decide() {
  local out=${1:-} verdict=blocked reason="" agent
  [ -n "$out" ] || fail "usage: verdict.sh decide <attempt.json>"

  # What each agent's execution file showed comes first, so a usage limit never reads
  # as a bad review. A failure stops the run, so at most one is set.
  for agent in "lead=${LEAD_AGENT:-}" "build=${BUILD_AGENT:-}" "review=${REVIEW_AGENT:-}"; do
    case "$agent" in
      *=limit) reason="usage limit in ${agent%=*}" ;;
      *=failed) reason="agent failed in ${agent%=*}" ;;
      *=invalid) reason="invalid review output" ;;
    esac
  done

  if [ -n "$reason" ]; then
    :
  elif [ "${REVIEW_RESULT:-}" != success ]; then
    reason="stopped before review"
  elif [ "${BLOCKING:-}" = 0 ]; then
    verdict=pass
    reason="no blocking findings"
  else
    reason="blocking findings: ${BLOCKING:-unknown}"
  fi

  jq -n --argjson attempt "${ATTEMPT:?ATTEMPT is required}" \
    --arg verdict "$verdict" --arg reason "$reason" \
    --arg publish "${PUBLISH_RESULT:-}" --arg test "${TEST_RESULT:-}" \
    --arg review "${REVIEW_RESULT:-}" --arg blocking "${BLOCKING:-}" \
    --argjson build_stats "$(json_or_null "${BUILD_STATS:-}")" \
    --argjson review_stats "$(json_or_null "${REVIEW_STATS:-}")" \
    '{attempt: $attempt, verdict: $verdict, reason: $reason,
      jobs: {publish: $publish, test: $test, review: $review},
      blocking: (try ($blocking | tonumber) catch null),
      agents: {build: $build_stats, review: $review_stats}}' >"$out"

  echo "verdict=$verdict"
  echo "reason=$reason"
}

command=${1:-}
[ "$#" -eq 0 ] || shift
case "$command" in
  decide) decide "$@" ;;
  *) fail "usage: verdict.sh decide <attempt.json>" ;;
esac
