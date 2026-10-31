#!/usr/bin/env bash
# Trusted. Writes a run's record and pushes it to the orphan branch team-runs. `finish`
# runs this after the run's outcome is settled, and nothing here can change it.
#
#   record.sh write <artifact-dir> <out-dir>
#     Needs RUN_ID and OUTCOME. Takes GOAL, MODE, SCENARIO, BLOCKED_AT, REASON, BASE,
#     P, HEAD_SHA, LEAD_STATS, STARTED_AT and ATTEMPT_RECORDS, one JSON object a line,
#     where they exist. <artifact-dir> holds gate-<n>.log, review-<n>.json, and the
#     spec's own files.
#   record.sh push <out-dir> <clone>
#     Commits <out-dir> as runs/<id>/ in a clone of this repo, on team-runs. It's never
#     force-pushed, so a failed push loses this record and no others.
#
# This repo is public. Everything written here is numbers, fixed text, or free text
# that passed `scan.sh text`. Anything that doesn't pass is left out, and `omitted`
# says so. Raw transcripts never reach this script.
set -euo pipefail

team=$(cd "$(dirname "$0")" && pwd -P)

fail() {
  echo "RECORD FAIL: $*" >&2
  exit 1
}

write() {
  local in=${1:-} out=${2:-} max omitted="" tmp file name goal=null attempts
  [ -d "$in" ] && [ -n "$out" ] || fail "usage: record.sh write <artifact-dir> <out-dir>"
  max=$(jq -er .limits.record_max_bytes "$team/config.json") || fail "config has no record_max_bytes"
  mkdir -p "$out"
  tmp=$(mktemp -d)

  for file in "$in"/gate-*.log; do
    [ -f "$file" ] || continue
    name=$(basename "$file" .log).txt
    "$team/scan.sh" text "$file" "$out/$name" "$max" >/dev/null 2>&1 ||
      omitted+="$name: failed the secret scan"$'\n'
  done

  # Trimming can only break a review, and then it's left out as well.
  for file in "$in"/review-*.json; do
    [ -f "$file" ] || continue
    name=$(basename "$file")
    if ! "$team/scan.sh" text "$file" "$out/$name" "$max" >/dev/null 2>&1 ||
      ! jq -e . "$out/$name" >/dev/null 2>&1; then
      rm -f "${out:?}/${name:?}"
      omitted+="$name: failed the secret scan, or is too large"$'\n'
    fi
  done

  # The branch of a blocked run is deleted, so this is what stays of its spec.
  for file in "$in"/spec.md "$in"/*.test.ts "$in"/*.test.tsx; do
    [ -f "$file" ] || continue
    name=$(basename "$file")
    mkdir -p "$out/spec"
    "$team/scan.sh" text "$file" "$out/spec/$name" "$max" >/dev/null 2>&1 ||
      omitted+="spec/$name: failed the secret scan"$'\n'
  done

  printf '%s\n' "${GOAL:-}" >"$tmp/goal"
  if "$team/scan.sh" text "$tmp/goal" "$tmp/goal.clean" "$max" >/dev/null 2>&1; then
    goal=$(jq -Rs 'rtrimstr("\n")' "$tmp/goal.clean")
  else
    omitted+="goal: failed the secret scan"$'\n'
  fi

  # Job outputs, which PR code can't reach, and only the fields `verdict` writes.
  attempts=$(jq -Rsc 'split("\n") | map(try fromjson catch null | objects
    | {attempt, verdict, reason, jobs, blocking, agents})' <<<"${ATTEMPT_RECORDS:-}")

  jq -n --arg run_id "${RUN_ID:?RUN_ID is required}" --arg mode "${MODE:-team}" \
    --arg scenario "${SCENARIO:-}" --arg outcome "${OUTCOME:?OUTCOME is required}" \
    --arg blocked_at "${BLOCKED_AT:-}" --arg reason "${REASON:-}" \
    --arg base "${BASE:-}" --arg p "${P:-}" --arg head "${HEAD_SHA:-}" \
    --arg started "${STARTED_AT:-}" --arg finished "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson goal "$goal" --argjson attempts "$attempts" \
    --arg first_agent "${LEAD_STATS:-}" --arg omitted "$omitted" \
    '{run_id: $run_id, mode: $mode, scenario: $scenario, goal: $goal,
      outcome: $outcome, blocked_at: $blocked_at, reason: $reason,
      started_at: $started, finished_at: $finished,
      duration_seconds: (try (($finished | fromdate) - ($started | fromdate)) catch null),
      base: $base, p: $p, head: $head, attempts_run: ($attempts | length),
      agents: {(if $mode == "solo" then "solo" else "lead" end): (try ($first_agent | fromjson) catch null)},
      attempts: $attempts,
      omitted: ($omitted | split("\n") | map(select(length > 0)))}' >"$tmp/record.json"

  # Each field above was clean or fixed, so a hit here means something got past that.
  # The record still lands, because a run must leave one, with fixed fields only. So
  # `omitted` is a count here: its entries name files, and an agent names some of those.
  if ! "$team/scan.sh" text "$tmp/record.json" "$out/record.json" "$max" >/dev/null 2>&1; then
    jq '{run_id, mode, outcome, base, p, head, attempts_run, omitted: ((.omitted | length) + 1)}' \
      "$tmp/record.json" >"$out/record.json"
  fi
  rm -rf "${tmp:?}"
}

push() {
  local out=${1:-} clone=${2:-}
  [ -f "$out/record.json" ] || fail "no record in: $out"
  [ -n "$clone" ] && git -C "$clone" rev-parse --git-dir >/dev/null || fail "not a clone: $clone"
  git -C "$clone" config user.name "github-actions[bot]"
  git -C "$clone" config user.email "41898282+github-actions[bot]@users.noreply.github.com"

  if git -C "$clone" fetch -q --depth=1 origin team-runs 2>/dev/null; then
    git -C "$clone" checkout -q -B team-runs FETCH_HEAD
  else
    git -C "$clone" checkout -q --orphan team-runs
    git -C "$clone" rm -rfq --ignore-unmatch .
  fi

  mkdir -p "$clone/runs"
  rm -rf "${clone:?}/runs/${RUN_ID:?RUN_ID is required}"
  cp -R "$out" "$clone/runs/$RUN_ID"
  git -C "$clone" add "runs/$RUN_ID"
  git -C "$clone" commit -qm "record: run $RUN_ID"
  git -C "$clone" push -q origin team-runs
}

command=${1:-}
[ "$#" -eq 0 ] || shift
case "$command" in
  write) write "$@" ;;
  push) push "$@" ;;
  *) fail "usage: record.sh write <artifact-dir> <out-dir> | push <out-dir> <clone>" ;;
esac
