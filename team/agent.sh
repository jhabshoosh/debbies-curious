#!/usr/bin/env bash
# Setup and result reading for the agent steps. Both print GITHUB_OUTPUT lines.
#
#   agent.sh sandbox
#     Install what the sandbox needs, then prove it works. Run this before any
#     agent step: the action installs bubblewrap only for allowed_non_write_users.
#   agent.sh prep <lead|build|review>
#     The fixed prompt, plus limits and agent settings from config. Needs RUN_ID,
#     and GOAL for lead and review. The Reviewer gets the goal as data, in goal.md
#     in the current directory, and its prompt stays fixed.
#   agent.sh links
#     Fail on any symlink in the workspace, before it's uploaded.
#   agent.sh result <execution-file> [review]
#     agent=ok|limit|failed|invalid, plus blocking=<count> for a valid review,
#     which counts each finding and each `fail` verdict.
#     Exit 0 only for agent=ok.
set -euo pipefail

team=$(cd "$(dirname "$0")" && pwd -P)

fail() {
  echo "AGENT FAIL: $*" >&2
  exit 1
}

sandbox() {
  sudo apt-get update -qq
  sudo apt-get install -y --no-install-recommends bubblewrap socat
  if [ -f /proc/sys/kernel/apparmor_restrict_unprivileged_userns ]; then
    sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
  fi
  bwrap --unshare-user --unshare-pid --ro-bind / / --proc /proc true ||
    fail "bubblewrap can't create a sandbox here"
}

prep() {
  local role=${1:-} config=$team/config.json prompt turns minutes settings schema delimiter
  case "$role" in
    lead) prompt=$team/prompts/lead.md ;;
    build) prompt=$team/prompts/builder.md ;;
    review) prompt=$team/prompts/reviewer.md ;;
    *) fail "unknown role: $role" ;;
  esac
  [ -f "$prompt" ] || fail "no prompt: $prompt"
  turns=$(jq -er --arg role "$role" '.limits[$role].max_turns' "$config") ||
    fail "config has no max_turns for $role"
  minutes=$(jq -er --arg role "$role" '.limits[$role].timeout_minutes' "$config") ||
    fail "config has no timeout_minutes for $role"
  settings=$(jq -ce '.agent_settings' "$config") || fail "config has no agent_settings"
  echo "turns=$turns"
  echo "minutes=$minutes"
  echo "settings=$settings"

  if [ "$role" = review ]; then
    schema=$(jq -c . "$team/review.schema.json") || fail "invalid review schema"
    # It's passed in single quotes through claude_args.
    case "$schema" in
      *"'"*) fail "the review schema can't contain a single quote" ;;
    esac
    echo "schema=$schema"
    printf '%s\n' "${GOAL:?GOAL is required}" >goal.md
  fi

  # The goal is free text, so nothing in it can match a random delimiter.
  delimiter=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
  echo "prompt<<$delimiter"
  cat "$prompt"
  if [ "$role" != review ]; then
    printf '\nRun ID: %s\n' "${RUN_ID:?RUN_ID is required}"
  fi
  if [ "$role" = lead ]; then
    printf 'Goal: %s\n' "${GOAL:?GOAL is required}"
  fi
  echo "$delimiter"
}

links() {
  local found
  found=$(find . \( -path ./.git -o -path ./node_modules -o -path ./.next \) -prune \
    -o -type l -print)
  [ -z "$found" ] || fail "symlinks aren't allowed: $found"
}

report() {
  echo "agent=$1"
  [ "$1" = ok ]
}

result() {
  local file=${1:-} mode=${2:-} final
  final=$(jq -ce 'map(select(.type == "result")) | last' "$file" 2>/dev/null) || {
    report failed
    return
  }

  # Outcome fields only. The summary is public, so agent text never goes in it.
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    jq -r '"subtype=\(.subtype) is_error=\(.is_error) turns=\(.num_turns)"
      + " cost_usd=\(.total_cost_usd) api_error_status=\(.api_error_status)"' \
      <<<"$final" >>"$GITHUB_STEP_SUMMARY" || true
  fi

  # A limit comes first. It arrives as subtype success with is_error, and with
  # --json-schema the action blames the schema, so it could pass for a bad review.
  if jq -e '.is_error == true and (.api_error_status == 429
    or ([.result, .errors[]?] | map(tostring) | join(" ") | test("hit your .*limit"; "i")))' \
    <<<"$final" >/dev/null; then
    report limit
    return
  fi

  if jq -e '.is_error != false or .subtype != "success"' <<<"$final" >/dev/null; then
    report failed
    return
  fi

  if [ "$mode" != review ]; then
    report ok
    return
  fi

  # Mirrors team/review.schema.json. The verdict job has no way to run a validator.
  jq -e 'def text: type == "string" and length > 0;
    def part: type == "object" and (.verdict == "pass" or .verdict == "fail") and (.checked | text);
    .structured_output as $review
    | ($review | type) == "object"
      and ($review.works | part)
      and ($review.good | part)
      and ($review.blocking | type) == "array"
      and ($review.blocking
        | all(type == "object" and (.file | text) and (.problem | text) and (.evidence | text)))' \
    <<<"$final" >/dev/null 2>&1 || {
    report invalid
    return
  }

  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    jq -r '.structured_output
      | "works=\(.works.verdict) good=\(.good.verdict) findings=\(.blocking | length)"' \
      <<<"$final" >>"$GITHUB_STEP_SUMMARY" || true
  fi
  echo "blocking=$(jq -e '.structured_output
    | (.blocking | length) + ([.works.verdict, .good.verdict] | map(select(. == "fail")) | length)' <<<"$final")"
  report ok
}

command=${1:-}
[ "$#" -eq 0 ] || shift
case "$command" in
  sandbox) sandbox ;;
  prep) prep "$@" ;;
  links) links ;;
  result) result "$@" ;;
  *) fail "usage: agent.sh sandbox | agent.sh prep <role> | agent.sh result <execution-file> [review]" ;;
esac
