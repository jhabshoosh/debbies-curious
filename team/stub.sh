#!/usr/bin/env bash
# Scripted stand-in for the agents, so the real gate runs at no model cost.
#
#   SCENARIO=<scenario> RUN_ID=<id> [ATTEMPT=<n>] [MODE=solo] stub.sh lead|build|review
#   SCENARIO=<scenario> RUN_ID=<id> stub.sh product
#   SCENARIO=<scenario> RUN_ID=<id> stub.sh limits <records>
#
# Run it from the checkout the agent would work in. `review` also needs GITHUB_OUTPUT
# and RUNNER_TEMP, as `product` needs RUNNER_TEMP. Scenarios: pass, impossible,
# tamper-test, tamper-config, tamper-workflow, secret, review-block, retry-pass,
# retry-review, retry-fail, retry-same. With MODE=solo, `lead` also does the work of
# `build`. Scenarios for Product's limits: paused, cap, blocked. `limits` adds records
# that reach the cap or the blocked limit, and real checks then refuse the run.
set -euo pipefail

role=${1:-}
run_id=${RUN_ID:?RUN_ID is required}
attempt=${ATTEMPT:-1}

case "${SCENARIO:-}" in
  pass | impossible | tamper-test | tamper-config | tamper-workflow | secret | review-block) ;;
  retry-pass | retry-review | retry-fail | retry-same) ;;
  paused | cap | blocked) ;;
  "")
    echo "SCENARIO is required." >&2
    exit 1
    ;;
  *)
    echo "Unknown scenario: $SCENARIO" >&2
    exit 1
    ;;
esac

spec_dir=team/specs/$run_id
change=src/lib/team-stub-$run_id.ts
wrong=src/lib/team-stub-$run_id-wrong.ts

# True if the last attempt's feedback reached this one, from <source>. Gate feedback has
# to carry the gate's output too, or a Builder learns only that something failed.
fed_back() {
  jq -e --arg source "$1" '.source == $source and (.source != "gate" or (.output | length > 0))' \
    team-feedback.txt >/dev/null 2>&1
}

case "$role" in
  lead)
    # The spec test passes once the Builder adds $change. In `impossible`, it
    # looks for a file that no stub ever writes.
    target=$change
    if [ "$SCENARIO" = impossible ]; then
      target=src/lib/team-stub-$run_id-never.ts
    fi
    mkdir -p "$spec_dir"
    printf '# Stub spec\n\nScenario: %s\n' "$SCENARIO" >"$spec_dir/spec.md"
    cat >"$spec_dir/stub.test.ts" <<EOF
import { existsSync } from "node:fs";
import { expect, it } from "vitest";

const target = "$target";

it("has the stub change", () => {
  expect(existsSync(target)).toBe(true);
});
EOF
    if [ "${MODE:-}" = solo ]; then
      "$0" build
    fi
    ;;
  build)
    # A retry must change the tree, except in the scenario that proves that.
    printf 'export const teamStub = "%s"; // attempt %s\n' "$run_id" "$attempt" >"$change"
    case "$SCENARIO" in
      retry-same) printf 'export const teamStub = "%s";\n' "$run_id" >"$change" ;;
      tamper-test) printf '// tampered\n' >>"$spec_dir/stub.test.ts" ;;
      tamper-config) printf '// tampered\n' >>vitest.config.ts ;;
      tamper-workflow) printf '# tampered\n' >>.github/workflows/ci.yml ;;
      secret)
        # Obviously fake, and split so this file never holds the whole marker.
        # It matches gitleaks' default private-key rule.
        marker="PRIVATE KEY"
        filler=FAKE-NOT-A-REAL-SECRET-FAKE-NOT-A-REAL-SECRET-FAKE-NOT-A-REAL-SECRET-FAKE-NOT-A-REAL-SECRET
        printf 'export const fake = "-----BEGIN FAKE %s-----%s-----END FAKE %s-----";\n' \
          "$marker" "$filler" "$marker" >>"$change"
        ;;
      # The spec wants $change, so the gate fails until the feedback says to write it.
      retry-pass)
        if ! fed_back gate; then
          mv "$change" "$wrong"
        fi
        ;;
      retry-fail) mv "$change" "$wrong" ;;
      # The second attempt fails unless the Reviewer's finding reached it, and the next
      # Reviewer blocks it unless that finding reached the Reviewer too.
      retry-review)
        if [ "$attempt" -gt 1 ] && ! fed_back review; then
          echo "The Reviewer's findings didn't reach attempt $attempt." >&2
          exit 1
        fi
        ;;
    esac
    ;;
  review)
    blocking=0
    case "$SCENARIO" in
      review-block | retry-same) blocking=1 ;;
      retry-review)
        if ! grep -q 'stub finding' previous-findings.txt; then
          blocking=1
        fi
        ;;
    esac
    echo "blocking=$blocking" >>"${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
    mkdir -p "${RUNNER_TEMP:?RUNNER_TEMP is required}/record"
    jq -n --argjson blocking "$blocking" \
      '{works: {verdict: "pass", checked: "stub"}, good: {verdict: "pass", checked: "stub"},
        blocking: [range($blocking) | {file: "stub", problem: "stub finding", evidence: "stub"}]}' \
      >"$RUNNER_TEMP/record/review-$attempt.json"
    ;;
  product)
    mkdir -p "${RUNNER_TEMP:?RUNNER_TEMP is required}/product"
    jq -n --arg scenario "$SCENARIO" '{goal: "Proof scenario: \($scenario)", reason: "stub"}' \
      >"$RUNNER_TEMP/product/goal.json"
    ;;
  limits)
    records=${2:?a records directory is required}
    config=$(dirname "$0")/config.json
    count=0
    outcome=MERGED
    case "$SCENARIO" in
      cap) count=$(jq -er .limits.runs_per_week "$config") ;;
      blocked)
        count=$(jq -er .limits.blocked_in_a_row "$config")
        outcome=BLOCKED
        ;;
    esac
    # Run IDs past any real one, because the latest runs are what the limits read.
    for ((n = 1; n <= count; n++)); do
      mkdir -p "$records/runs/stub-$n"
      jq -n --arg id "9000000000000$n" --arg outcome "$outcome" \
        '{run_id: $id, mode: "team", scenario: "", outcome: $outcome, finished_at: (now | floor | todate)}' \
        >"$records/runs/stub-$n/record.json"
    done
    ;;
  *)
    echo "Usage: stub.sh lead|build|review|product|limits <records>" >&2
    exit 1
    ;;
esac
