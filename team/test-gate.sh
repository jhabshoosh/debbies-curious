#!/usr/bin/env bash
# Runs the real team/gate.sh against throwaway git fixtures. No network.
#
# gitleaks is replaced by a shim, so only the gate's handling of it is tested,
# except for the planted-secret case, which needs the real scanner on PATH and
# is reported as NOT RUN without it.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd -P)
gate=$root/team/gate.sh
real_config=$root/team/config.json
real_gitleaks=$(command -v gitleaks || true)
real_path=$PATH

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
export GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
export MARKER=$tmp/commands-ran SHIM_LOG=$tmp/shim.log SHIM_EXIT=0

mkdir -p "$tmp/bin" "$tmp/tools" "$tmp/plain-dir"
cat >"$tmp/bin/gitleaks" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$SHIM_LOG"
exit "$SHIM_EXIT"
EOF
chmod +x "$tmp/bin/gitleaks"
export PATH="$tmp/bin:$PATH"

# A PATH with everything the gate needs except gitleaks.
for tool in bash dirname git jq mktemp rm; do
  ln -s "$(command -v "$tool")" "$tmp/tools/$tool"
done

# Real frozen and test lists, with harmless project commands.
config=$tmp/config.json
jq '.install = "true" | .commands = ["touch \"$MARKER\""]' "$real_config" >"$config"

# The fixture: a base commit, then P, which adds the spec.
base=$tmp/base
git init -q "$base"
mkdir -p "$base"/{.claude,.github/workflows,e2e,src/lib/__tests__,src/test,team/specs/1}
for file in .claude/settings.json .env.example .github/workflows/ci.yml .prettierrc CLAUDE.md e2e/a.spec.ts \
  package-lock.json package.json src/lib/__tests__/a.test.ts src/lib/a.ts src/test/setup.ts \
  team/gate.sh tsconfig.json vitest.config.ts; do
  echo "original" >"$base/$file"
done
git -C "$base" add -A
git -C "$base" commit -qm base
echo "original" >"$base/team/specs/1/stub.test.ts"
git -C "$base" add -A
git -C "$base" commit -qm P
p=$(git -C "$base" rev-parse HEAD)

passed=0
failed=0
not_run=0
n=0

record() { # <PASS|FAIL> <name> [detail]
  printf '%-5s %s\n' "$1" "$2"
  if [ "$1" = PASS ]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    printf '      %s\n' "${3:-}"
  fi
}

new_case() { # A fresh clone at P, in $repo.
  n=$((n + 1))
  repo=$tmp/case-$n
  git clone -q "$base" "$repo"
}

commit_case() { # Commits everything in $repo, and sets $sha.
  git -C "$repo" add -A
  git -C "$repo" commit -qm change
  sha=$(git -C "$repo" rev-parse HEAD)
}

run_gate() { # <gate args...> Sets $code and $out.
  rm -f "$MARKER"
  code=0
  out=$("$gate" "$@" 2>&1) || code=$?
}

expect_fail() { # <name> <expected text> Checks the last run_gate.
  if [ "$code" -eq 0 ]; then
    record FAIL "$1" "gate passed: $out"
  elif [[ $out != *"$2"* ]]; then
    record FAIL "$1" "failed for the wrong reason: $out"
  else
    record PASS "$1"
  fi
}

expect_frozen() { # <name> <expected text> Also proves no project command ran.
  if [ -e "$MARKER" ]; then
    record FAIL "$1" "project commands ran after a failed check"
  else
    expect_fail "$1" "$2"
  fi
}

change_case() { # <name> <expected text> <shell snippet run in the fixture>
  new_case
  (cd "$repo" && bash -euc "$3")
  commit_case
  run_gate "$repo" "$p" "$sha" "$config"
  expect_frozen "$1" "$2"
}

# Passing changes.
new_case
echo "change" >>"$repo/src/lib/a.ts"
commit_case
: >"$SHIM_LOG"
run_gate "$repo" "$p" "$sha" "$config"
if [ "$code" -eq 0 ] && [ -e "$MARKER" ] && grep -qF -- "--log-opts=--text $p^..$sha" "$SHIM_LOG" &&
  grep -qF -- "--ignore-gitleaks-allow" "$SHIM_LOG"; then
  record PASS "clean change passes, scans P^..SHA as text, runs project commands"
else
  record FAIL "clean change passes, scans P^..SHA as text, runs project commands" "exit $code: $out"
fi

new_case
echo "new" >"$repo/src/lib/__tests__/b.test.ts"
commit_case
run_gate "$repo" "$p" "$sha" "$config"
if [ "$code" -eq 0 ]; then
  record PASS "new test file passes"
else
  record FAIL "new test file passes" "exit $code: $out"
fi

# Frozen paths and existing tests.
change_case "edited spec test fails" "frozen path changed: team/specs/1/stub.test.ts" \
  'echo x >>team/specs/1/stub.test.ts'
change_case "edited existing test fails" "existing test changed: src/lib/__tests__/a.test.ts" \
  'echo x >>src/lib/__tests__/a.test.ts'
change_case "edited E2E test fails" "existing test changed: e2e/a.spec.ts" \
  'echo x >>e2e/a.spec.ts'
change_case "edited package.json fails" "frozen path changed: package.json" \
  'echo x >>package.json'
change_case "edited package-lock.json fails" "frozen path changed: package-lock.json" \
  'echo x >>package-lock.json'
change_case "edited vitest.config.ts fails" "frozen path changed: vitest.config.ts" \
  'echo x >>vitest.config.ts'
change_case "edited workflow fails" "frozen path changed: .github/workflows/ci.yml" \
  'echo x >>.github/workflows/ci.yml'
change_case "edited team/ file fails" "frozen path changed: team/gate.sh" \
  'echo x >>team/gate.sh'
change_case "edited src/test file fails" "frozen path changed: src/test/setup.ts" \
  'echo x >>src/test/setup.ts'
change_case "edited CLAUDE.md fails" "frozen path changed: CLAUDE.md" \
  'echo x >>CLAUDE.md'
change_case "edited .claude file fails" "frozen path changed: .claude/settings.json" \
  'echo x >>.claude/settings.json'
change_case "edited tsconfig.json fails" "frozen path changed: tsconfig.json" \
  'echo x >>tsconfig.json'
change_case "edited .prettierrc fails" "frozen path changed: .prettierrc" \
  'echo x >>.prettierrc'
change_case "added .npmrc fails" "frozen path changed: .npmrc" \
  'echo x >.npmrc'
change_case "added .gitleaks.toml fails" "frozen path changed: .gitleaks.toml" \
  'echo x >.gitleaks.toml'
change_case "added .gitleaksignore fails" "frozen path changed: .gitleaksignore" \
  'echo x >.gitleaksignore'
change_case "added nested config fails" "frozen path changed: src/vitest.config.ts" \
  'echo x >src/vitest.config.ts'
change_case "added npm-shrinkwrap.json fails" "frozen path changed: npm-shrinkwrap.json" \
  'echo x >npm-shrinkwrap.json'
change_case "added .gitignore fails" "frozen path changed: .gitignore" \
  'echo x >.gitignore'
change_case "added nested package.json fails" "frozen path changed: src/package.json" \
  'echo x >src/package.json'
change_case "added nested tsconfig.json fails" "frozen path changed: src/tsconfig.json" \
  'echo x >src/tsconfig.json'
change_case "added nested .npmrc fails" "frozen path changed: src/.npmrc" \
  'echo x >src/.npmrc'
change_case "added .env.production fails" "frozen path changed: .env.production" \
  'echo x >.env.production'
change_case "edited .env.example fails" "frozen path changed: .env.example" \
  'echo x >>.env.example'
change_case "added .gitattributes fails" "frozen path changed: .gitattributes" \
  'echo "*.ts -diff" >.gitattributes'
change_case "added nested .gitattributes fails" "frozen path changed: src/.gitattributes" \
  'echo "*.ts -diff" >src/.gitattributes'
change_case "added nested CLAUDE.md fails" "frozen path changed: src/CLAUDE.md" \
  'echo x >src/CLAUDE.md'
change_case "added nested .claude file fails" "frozen path changed: src/.claude/settings.json" \
  'mkdir src/.claude && echo x >src/.claude/settings.json'
change_case "deleted test fails" "existing test changed: src/lib/__tests__/a.test.ts" \
  'rm src/lib/__tests__/a.test.ts'
change_case "renamed test fails" "existing test changed: src/lib/__tests__/a.test.ts" \
  'git mv src/lib/__tests__/a.test.ts src/lib/__tests__/renamed.test.ts'
change_case "test renamed to a non-test name fails" "existing test changed: src/lib/__tests__/a.test.ts" \
  'git mv src/lib/__tests__/a.test.ts src/lib/a-old.ts'
change_case "test mode change fails" "existing test changed: src/lib/__tests__/a.test.ts" \
  'chmod +x src/lib/__tests__/a.test.ts'
change_case "file renamed into a frozen path fails" "frozen path changed: team/moved.ts" \
  'git mv src/lib/a.ts team/moved.ts'

# gitleaks.
new_case
marker="PRIVATE KEY"
filler=FAKE-NOT-A-REAL-SECRET-FAKE-NOT-A-REAL-SECRET-FAKE-NOT-A-REAL-SECRET-FAKE-NOT-A-REAL-SECRET
printf 'export const fake = "-----BEGIN FAKE %s-----%s-----END FAKE %s-----";\n' \
  "$marker" "$filler" "$marker" >>"$repo/src/lib/a.ts"
commit_case
if [ -n "$real_gitleaks" ]; then
  PATH=$real_path run_gate "$repo" "$p" "$sha" "$config"
  expect_frozen "planted fake secret fails (real gitleaks)" "gitleaks found a secret"
else
  echo "NOT RUN planted fake secret fails: gitleaks is not installed"
  not_run=$((not_run + 1))
fi

new_case
echo "change" >>"$repo/src/lib/a.ts"
commit_case
SHIM_EXIT=1 run_gate "$repo" "$p" "$sha" "$config"
expect_frozen "gitleaks non-zero exit fails (shim)" "gitleaks found a secret"
PATH=$tmp/tools run_gate "$repo" "$p" "$sha" "$config"
expect_frozen "gitleaks not installed fails" "gitleaks is not installed"

# Project commands.
jq '.commands = ["false", "touch \"$MARKER\""]' "$config" >"$tmp/failing.json"
run_gate "$repo" "$p" "$sha" "$tmp/failing.json"
expect_frozen "failing project command fails, stops later commands" "project command failed: false"
jq '.install = "false"' "$config" >"$tmp/failing-install.json"
run_gate "$repo" "$p" "$sha" "$tmp/failing-install.json"
expect_frozen "failing install fails" "project command failed: false"

# Missing and bad inputs, against a valid candidate in $repo at $sha.
run_gate
expect_fail "no inputs fail" "usage:"
run_gate "$repo" "$p" "$sha"
expect_fail "missing config input fails" "usage:"
run_gate "" "$p" "$sha" "$config"
expect_fail "empty repo input fails" "an input is empty"
run_gate "$repo" "" "$sha" "$config"
expect_fail "empty P input fails" "an input is empty"
run_gate "$repo" "$p" "" "$config"
expect_fail "empty candidate input fails" "an input is empty"
run_gate "$repo" "$p" "$sha" ""
expect_fail "empty config input fails" "an input is empty"
run_gate "$repo" HEAD~1 "$sha" "$config"
expect_fail "P given as a ref name fails" "P is not a full commit SHA"
run_gate "$repo" "$p" HEAD "$config"
expect_fail "candidate given as a ref name fails" "candidate is not a full commit SHA"
run_gate "$tmp/no-such-dir" "$p" "$sha" "$config"
expect_fail "missing repo fails" "not a git checkout"
run_gate "$tmp/plain-dir" "$p" "$sha" "$config"
expect_fail "directory that isn't a repo fails" "not a git checkout"
run_gate "$repo" "$p" "$sha" "$tmp/no-such-config.json"
expect_fail "missing config file fails" "config not found"
echo "{" >"$tmp/broken.json"
run_gate "$repo" "$p" "$sha" "$tmp/broken.json"
expect_fail "invalid config JSON fails" "config has no frozen_paths"
jq '.frozen_paths = []' "$config" >"$tmp/no-frozen.json"
run_gate "$repo" "$p" "$sha" "$tmp/no-frozen.json"
expect_fail "empty frozen_paths fails" "config has no frozen_paths"
jq 'del(.test_paths)' "$config" >"$tmp/no-tests.json"
run_gate "$repo" "$p" "$sha" "$tmp/no-tests.json"
expect_fail "missing test_paths fails" "config has no test_paths"
jq '.commands = []' "$config" >"$tmp/no-commands.json"
run_gate "$repo" "$p" "$sha" "$tmp/no-commands.json"
expect_fail "empty commands fails" "config has no commands"
jq 'del(.install)' "$config" >"$tmp/no-install.json"
run_gate "$repo" "$p" "$sha" "$tmp/no-install.json"
expect_fail "missing install fails" "config has no install"

# The candidate must be what's checked out, and must descend from P.
missing_sha=0000000000000000000000000000000000000001
run_gate "$repo" "$p" "$missing_sha" "$config"
expect_fail "unknown candidate SHA fails" "checkout is not at the candidate"
run_gate "$repo" "$missing_sha" "$sha" "$config"
expect_fail "unknown P fails" "candidate does not descend from P"
run_gate "$repo" "$sha" "$sha" "$config"
expect_fail "P equal to the candidate fails" "no change between P and the candidate"

new_case
echo "change" >>"$repo/src/lib/a.ts"
commit_case
git -C "$repo" checkout -q "$p"
run_gate "$repo" "$p" "$sha" "$config"
expect_fail "checkout not at the candidate fails" "checkout is not at the candidate"

new_case
echo "change" >>"$repo/src/lib/a.ts"
commit_case
echo "dirty" >>"$repo/src/lib/a.ts"
run_gate "$repo" "$p" "$sha" "$config"
expect_fail "dirty checkout fails" "uncommitted changes"

new_case
git -C "$repo" reset -q --hard HEAD~1
echo "change" >>"$repo/src/lib/a.ts"
commit_case
run_gate "$repo" "$p" "$sha" "$config"
expect_fail "candidate not descended from P fails" "candidate does not descend from P"

new_case
root_sha=$(git -C "$repo" rev-list --max-parents=0 HEAD)
git -C "$repo" reset -q --hard "$root_sha"
echo "change" >>"$repo/src/lib/a.ts"
commit_case
run_gate "$repo" "$root_sha" "$sha" "$config"
expect_fail "P with no parent fails" "P has no parent commit"

# The gate and config must come from main.
new_case
echo "change" >>"$repo/src/lib/a.ts"
commit_case
cp "$gate" "$repo/.git/gate.sh"
cp "$config" "$repo/.git/config.json"
code=0
out=$("$repo/.git/gate.sh" "$repo" "$p" "$sha" "$config" 2>&1) || code=$?
expect_fail "gate run from inside the candidate fails" "must come from main"
run_gate "$repo" "$p" "$sha" "$repo/.git/config.json"
expect_fail "config from inside the candidate fails" "must come from main"

echo
echo "$passed passed, $failed failed, $not_run not run"
[ "$failed" -eq 0 ]
