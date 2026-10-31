#!/usr/bin/env bash
# Scripted stand-in for the agents, so the real gate runs at no model cost.
#
#   SCENARIO=<scenario> RUN_ID=<id> [ATTEMPT=<n>] stub.sh lead|build|review
#
# Run it from the checkout the agent would work in. `review` also needs GITHUB_OUTPUT
# and RUNNER_TEMP. Scenarios: pass, impossible, tamper-test, tamper-config,
# tamper-workflow, secret, review-block, retry-pass, retry-review, retry-fail.
set -euo pipefail

role=${1:-}
run_id=${RUN_ID:?RUN_ID is required}
attempt=${ATTEMPT:-1}

case "${SCENARIO:-}" in
  pass | impossible | tamper-test | tamper-config | tamper-workflow | secret | review-block) ;;
  retry-pass | retry-review | retry-fail) ;;
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

# True if the last attempt's feedback reached this one, from <source>.
fed_back() {
  jq -e --arg source "$1" '.source == $source' team-feedback.json >/dev/null 2>&1
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
    ;;
  build)
    printf 'export const teamStub = "%s";\n' "$run_id" >"$change"
    case "$SCENARIO" in
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
      # The second attempt fails unless the Reviewer's finding reached it.
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
    if [ "$SCENARIO" = review-block ] || { [ "$SCENARIO" = retry-review ] && [ "$attempt" -eq 1 ]; }; then
      blocking=1
    fi
    echo "blocking=$blocking" >>"${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
    mkdir -p "${RUNNER_TEMP:?RUNNER_TEMP is required}/record"
    jq -n --argjson blocking "$blocking" \
      '{works: {verdict: "pass", checked: "stub"}, good: {verdict: "pass", checked: "stub"},
        blocking: [range($blocking) | {file: "stub", problem: "stub finding", evidence: "stub"}]}' \
      >"$RUNNER_TEMP/record/review-$attempt.json"
    ;;
  *)
    echo "Usage: stub.sh lead|build|review" >&2
    exit 1
    ;;
esac
