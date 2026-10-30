#!/usr/bin/env bash
# Scripted stand-in for the agents, so the real gate runs at no model cost.
#
#   SCENARIO=<scenario> RUN_ID=<id> stub.sh lead|build|review
#
# Run it from the checkout the agent would work in. `review` also needs
# GITHUB_OUTPUT. Scenarios: pass, impossible, tamper-test, tamper-config,
# tamper-workflow, secret, review-block.
set -euo pipefail

role=${1:-}
run_id=${RUN_ID:?RUN_ID is required}

case "${SCENARIO:-}" in
  pass | impossible | tamper-test | tamper-config | tamper-workflow | secret | review-block) ;;
  "")
    echo "No scenario set, and real agents don't exist until task 2." >&2
    exit 1
    ;;
  *)
    echo "Unknown scenario: $SCENARIO" >&2
    exit 1
    ;;
esac

spec_dir=team/specs/$run_id
change=src/lib/team-stub-$run_id.ts

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
    esac
    ;;
  review)
    blocking=0
    if [ "$SCENARIO" = review-block ]; then
      blocking=1
    fi
    echo "blocking=$blocking" >>"${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
    ;;
  *)
    echo "Usage: stub.sh lead|build|review" >&2
    exit 1
    ;;
esac
