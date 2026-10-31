#!/usr/bin/env bash
# The red check: the spec's tests must fail at P, and for the right reason.
#
#   red.sh <checkout-at-P> <run-id> <config.json>
#
# Exit 0 needs at least one collected test, at least one assertion failure, no
# file that failed to load and no crash outside a test. A spec that can't load is
# broken, not red, so it must not import code that doesn't exist yet at the top of
# a test file. A spec whose setup crashes the app is broken too, even when some of
# its tests fail on an assertion: no Builder can fix it.
set -euo pipefail

fail() {
  echo "RED FAIL: $*" >&2
  exit 1
}

[ "$#" -eq 3 ] || fail "usage: red.sh <checkout-at-P> <run-id> <config.json>"
for arg in "$@"; do
  [ -n "$arg" ] || fail "an input is empty"
done
[ -f "$3" ] || fail "config not found: $3"
config=$(cd "$(dirname "$3")" && pwd -P)/$(basename "$3")
spec_dir=team/specs/$2

cd "$1" || fail "no checkout: $1"
[ -d "$spec_dir" ] || fail "no spec directory: $spec_dir"
install=$(jq -er '.install' "$config") || fail "config has no install"
spec_test=$(jq -er '.spec_test' "$config") || fail "config has no spec_test"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
report=$tmp/report.json

bash -euo pipefail -c "$install" </dev/null || fail "install failed"

# Vitest exits non-zero for a crash as well as a failing test, so the report
# decides, not the exit code.
NO_COLOR=1 bash -euo pipefail -c "$spec_test --reporter=default --reporter=json --outputFile.json=$report $spec_dir/" \
  </dev/null 2>&1 | tee "$tmp/output" || true
[ -s "$report" ] || fail "vitest wrote no report"
! grep -q 'Unhandled Error' "$tmp/output" || fail "the spec crashed outside a test"

jq -e 'all(.testResults[]; .message == "")' "$report" >/dev/null ||
  fail "a spec file failed to load"
jq -e '.numTotalTests >= 1' "$report" >/dev/null || fail "no tests collected"
# Testing Library raises its own error for a missing element, which is how a test
# of a feature that doesn't exist yet should fail.
jq -e 'any(.testResults[].assertionResults[];
  .status == "failed" and
  any(.failureMessages[]; test("^(AssertionError|TestingLibraryElementError):")))' \
  "$report" >/dev/null || fail "no test failed on an assertion"

echo "RED OK: $spec_dir fails on an assertion"
