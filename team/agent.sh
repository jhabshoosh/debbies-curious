#!/usr/bin/env bash
# Setup and result reading for the agent steps. Both print GITHUB_OUTPUT lines.
#
#   agent.sh sandbox
#     Install what the sandbox needs, then prove it works. This needs sudo, so it
#     comes before no-admin. The action installs bubblewrap only for
#     allowed_non_write_users.
#   agent.sh no-admin
#     Remove sudo and docker from this job, then prove they're gone. Nothing after
#     this needs either. Run this before any step holds the token.
#   agent.sh prep <lead|solo|build|review>
#     The fixed prompt, plus limits and agent settings from config. Needs RUN_ID,
#     and GOAL for lead, solo and review. The Reviewer gets the goal as data, in
#     goal.md in the current directory, and its prompt stays fixed.
#   agent.sh files
#     Fail on anything in the workspace but files and directories, before upload.
#   agent.sh result <execution-file> [review <review-out>]
#     agent=ok|limit|failed|invalid, plus blocking=<count> for a valid review,
#     which counts each finding and each `fail` verdict. A valid review is also
#     written to <review-out>, for the run record. stats=<json> carries numbers and
#     booleans only, so it's safe in logs. Exit 0 only for agent=ok.
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

no_admin() {
  # The runner keeps its docker group for the whole job, so the socket has to go.
  sudo systemctl stop docker.service docker.socket || true
  sudo rm -f /var/run/docker.sock
  sudo gpasswd -d "$(id -un)" docker || true
  sudo sh -c 'rm -f /etc/sudoers.d/*; sed -i "/NOPASSWD/d" /etc/sudoers'
  sudo -k || true
  if sudo -n true 2>/dev/null; then
    fail "sudo still works"
  fi
  if docker version >/dev/null 2>&1; then
    fail "docker can still be reached"
  fi
}

prep() {
  local role=${1:-} config=$team/config.json prompt turns minutes settings schema delimiter
  case "$role" in
    lead) prompt=$team/prompts/lead.md ;;
    solo) prompt=$team/prompts/solo.md ;;
    build) prompt=$team/prompts/builder.md ;;
    review) prompt=$team/prompts/reviewer.md ;;
    *) fail "unknown role: $role" ;;
  esac
  [ -f "$prompt" ] || fail "no prompt: $prompt"
  if [ "$role" = solo ]; then
    # What the whole team may spend, so the baseline is a fair comparison.
    turns=$(jq -er '.limits | .lead.max_turns + .attempts * (.build.max_turns + .review.max_turns)' "$config") ||
      fail "config has no limits for solo"
    minutes=$(jq -er '.limits | .lead.timeout_minutes + .attempts * (.build.timeout_minutes + .review.timeout_minutes)' "$config") ||
      fail "config has no limits for solo"
  else
    turns=$(jq -er --arg role "$role" '.limits[$role].max_turns' "$config") ||
      fail "config has no max_turns for $role"
    minutes=$(jq -er --arg role "$role" '.limits[$role].timeout_minutes' "$config") ||
      fail "config has no timeout_minutes for $role"
  fi
  echo "turns=$turns"
  echo "minutes=$minutes"

  if [ "$role" != review ]; then
    # Claude Code protects .git only if it's there at startup, and here it isn't.
    settings=$(jq -ce --arg git "$PWD/.git" \
      '.agent_settings | .sandbox.filesystem.denyWrite = [$git]' "$config") ||
      fail "config has no agent_settings"
    # Passed in single quotes through claude_args, like the schema.
    case "$settings" in
      *"'"*) fail "agent_settings can't contain a single quote" ;;
    esac
    echo "settings=$settings"
  else
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
  if [ "$role" = lead ] || [ "$role" = solo ]; then
    printf 'Goal: %s\n' "${GOAL:?GOAL is required}"
  fi
  echo "$delimiter"
}

files() {
  local found
  found=$(find . \( -path ./node_modules -o -path ./.next \) -prune \
    -o ! -type f ! -type d -print)
  [ -z "$found" ] || fail "only files and directories are allowed: $found"
}

report() {
  echo "agent=$1"
  [ "$1" = ok ]
}

# Numbers, plus whether the agent ran each gate command, which is how a record shows
# it tested. No agent text gets through, so a bad field reads as null.
stats() {
  local commands
  commands=$(jq -c .commands "$team/config.json")
  jq -c --argjson commands "$commands" '
    def number: if type == "number" then . else null end;
    (map(objects | select(.type == "result")) | last) as $final
    | [.[] | objects | select(.type == "assistant") | .message.content? | arrays | .[]
        | objects | select(.type == "tool_use" and .name == "Bash")
        | .input.command | strings] as $ran
    | {turns: ($final.num_turns | number),
       cost_usd: ($final.total_cost_usd | number),
       input_tokens: ($final.usage.input_tokens | number),
       output_tokens: ($final.usage.output_tokens | number),
       cache_read_tokens: ($final.usage.cache_read_input_tokens | number),
       cache_write_tokens: ($final.usage.cache_creation_input_tokens | number),
       ran: ($commands | map({key: ., value: (. as $command | $ran | any(contains($command)))})
         | from_entries)}' "$1"
}

result() {
  local file=${1:-} mode=${2:-} review_out=${3:-} final
  final=$(jq -ce 'map(select(.type == "result")) | last' "$file" 2>/dev/null) || {
    report failed
    return
  }

  # First, so a run that hits a limit still reports what it spent. Never fatal here,
  # because numbers can't change what the agent's result was.
  echo "stats=$(stats "$file" 2>/dev/null || echo null)"

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

  # A file, because job outputs reach public logs through `env:`. As an artifact it's
  # public until `finish` deletes it, as the trees are, and it reaches the record only
  # after a scan.
  if [ -n "$review_out" ]; then
    mkdir -p "$(dirname "$review_out")"
    jq '.structured_output' <<<"$final" >"$review_out"
  fi

  echo "blocking=$(jq -e '.structured_output
    | (.blocking | length) + ([.works.verdict, .good.verdict] | map(select(. == "fail")) | length)' <<<"$final")"
  report ok
}

command=${1:-}
[ "$#" -eq 0 ] || shift
case "$command" in
  sandbox) sandbox ;;
  no-admin) no_admin ;;
  prep) prep "$@" ;;
  files) files ;;
  result) result "$@" ;;
  *) fail "usage: agent.sh sandbox | no-admin | prep <role> | files | result <execution-file> [review <out>]" ;;
esac
