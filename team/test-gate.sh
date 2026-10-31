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
export MARKER=$tmp/commands-ran SHIM_LOG=$tmp/shim.log SHIM_EXIT=0 SHIM_MATCH=

mkdir -p "$tmp/bin" "$tmp/tools" "$tmp/plain-dir"
cat >"$tmp/bin/gitleaks" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$SHIM_LOG"
printf 'scanned dir holds %s entries\n' "$(ls -A | wc -l | tr -d ' ')" >>"$SHIM_LOG"
if [ -f candidate.diff ]; then
  printf 'first line holds %s bytes\n' "$(head -1 candidate.diff | wc -c | tr -d ' ')" >>"$SHIM_LOG"
fi
# Like real gitleaks in `dir` mode, this skips a file that opens like an application
# type, whether the mark is at the start or deeper in.
if [ -n "${SHIM_MATCH:-}" ]; then
  for file in *; do
    [ "$(head -c 5 "$file")" != "%PDF-" ] || continue
    [ "$(tail -c +258 "$file" | head -c 5)" != ustar ] || continue
    if grep -qF -- "$SHIM_MATCH" "$file"; then
      exit 1
    fi
  done
fi
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
mkdir -p "$base"/{.claude,.github/workflows,docs,e2e,src/lib/__tests__,src/test,team/prompts,team/specs/1}
for file in .claude/settings.json .env.example .github/workflows/ci.yml .prettierrc CLAUDE.md docs/a.md e2e/a.spec.ts \
  package-lock.json package.json src/lib/__tests__/a.test.ts src/lib/a.ts src/test/setup.ts \
  team/gate.sh team/prompts/builder.md team/prompts/lead.md team/prompts/reviewer.md \
  team/review.schema.json tsconfig.json vitest.config.ts; do
  echo "original" >"$base/$file"
done
echo "build-output" >"$base/.gitignore"
chmod +x "$base/team/gate.sh"
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
  grep -qF -- "--ignore-gitleaks-allow" "$SHIM_LOG" &&
  grep -qF -- "--config $root/team/gitleaks.toml" "$SHIM_LOG"; then
  record PASS "clean change passes, scans P^..SHA as text with main's rules, runs project commands"
else
  record FAIL "clean change passes, scans P^..SHA as text with main's rules, runs project commands" "exit $code: $out"
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
change_case "added nested .gitignore fails" "frozen path changed: src/.gitignore" \
  'echo x >src/.gitignore'
change_case "edited Lead prompt fails" "frozen path changed: team/prompts/lead.md" \
  'echo x >>team/prompts/lead.md'
change_case "edited Builder prompt fails" "frozen path changed: team/prompts/builder.md" \
  'echo x >>team/prompts/builder.md'
change_case "edited Reviewer prompt fails" "frozen path changed: team/prompts/reviewer.md" \
  'echo x >>team/prompts/reviewer.md'
change_case "edited review schema fails" "frozen path changed: team/review.schema.json" \
  'echo x >>team/review.schema.json'
change_case "added .mcp.json fails" "frozen path changed: .mcp.json" \
  'echo x >.mcp.json'
change_case "added CLAUDE.local.md fails" "frozen path changed: CLAUDE.local.md" \
  'echo x >CLAUDE.local.md'
change_case "added nested CLAUDE.local.md fails" "frozen path changed: src/CLAUDE.local.md" \
  'echo x >src/CLAUDE.local.md'
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

# File types, in allowed paths.
change_case "new symlink fails" "the change adds a symlink or a gitlink" \
  'ln -s ../../package.json src/lib/link.ts'
change_case "new gitlink fails" "the change adds a symlink or a gitlink" \
  'mkdir src/vendor && git -C src/vendor init -q && echo x >src/vendor/a &&
   git -C src/vendor add -A && git -C src/vendor commit -qm nested'

# The allowlist. These paths aren't frozen, so only it stops them.
change_case "new vercel.json fails" "path not allowed: vercel.json" \
  'echo x >vercel.json'
change_case "new nested config file fails" "path not allowed: config/nested.json" \
  'mkdir config && echo x >config/nested.json'
change_case "new root file fails" "path not allowed: notes.md" \
  'echo x >notes.md'
change_case "new E2E test fails" "path not allowed: e2e/b.spec.ts" \
  'echo x >e2e/b.spec.ts'
change_case "deleted file outside the allowlist fails" "path not allowed: docs/a.md" \
  'rm docs/a.md'
change_case "every path outside the allowlist is named" "path not allowed: two.md" \
  'echo x >one.md && echo x >two.md'

new_case
mkdir "$repo/public"
echo "new" >"$repo/public/logo.txt"
commit_case
run_gate "$repo" "$p" "$sha" "$config"
if [ "$code" -eq 0 ]; then
  record PASS "new file under public passes"
else
  record FAIL "new file under public passes" "exit $code: $out"
fi

# Diff limits, against small values, so the fixture stays small. $repo holds one
# new file with one short line.
jq '.limits.diff_max_bytes = 10' "$config" >"$tmp/small-diff.json"
run_gate "$repo" "$p" "$sha" "$tmp/small-diff.json"
expect_frozen "diff over the size limit fails" "diff is over 10 bytes"
jq '.limits.diff_max_line = 5' "$config" >"$tmp/short-lines.json"
run_gate "$repo" "$p" "$sha" "$tmp/short-lines.json"
expect_frozen "diff line over the limit fails" "diff has a line over 5 characters"
size=$(git -C "$repo" diff --text "$p" "$sha" | wc -c | tr -d ' ')
jq --argjson size "$size" '.limits.diff_max_bytes = $size' "$config" >"$tmp/exact-diff.json"
run_gate "$repo" "$p" "$sha" "$tmp/exact-diff.json"
if [ "$code" -eq 0 ]; then
  record PASS "diff exactly at the size limit passes"
else
  record FAIL "diff exactly at the size limit passes" "exit $code: $out"
fi
jq 'del(.limits.diff_max_bytes)' "$config" >"$tmp/no-size.json"
run_gate "$repo" "$p" "$sha" "$tmp/no-size.json"
expect_fail "missing diff_max_bytes fails" "config has no diff_max_bytes"
jq 'del(.limits.diff_max_line)' "$config" >"$tmp/no-line.json"
run_gate "$repo" "$p" "$sha" "$tmp/no-line.json"
expect_fail "missing diff_max_line fails" "config has no diff_max_line"

jq 'del(.allowed_paths)' "$config" >"$tmp/no-allowed.json"
run_gate "$repo" "$p" "$sha" "$tmp/no-allowed.json"
expect_fail "missing allowed_paths fails" "config has no allowed_paths"
jq '.allowed_paths = []' "$config" >"$tmp/empty-allowed.json"
run_gate "$repo" "$p" "$sha" "$tmp/empty-allowed.json"
expect_fail "empty allowed_paths fails" "config has no allowed_paths"

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

# An obviously fake OAuth token, split so this file never holds the whole pattern.
token_prefix=sk-ant
fake_token="$token_prefix-oat01-FAKE-NOT-A-REAL-TOKEN-FAKE-NOT-A-REAL-TOKEN"
token_regex=$(sed -n "s/^regex = '''\(.*\)'''$/\1/p" "$root/team/gitleaks.toml")
if [ -n "$token_regex" ] && grep -qE "$token_regex" <<<"$fake_token" &&
  ! grep -qE "$token_regex" "$root/team/test-gate.sh"; then
  record PASS "main's rule matches an OAuth token, and this file holds none"
else
  record FAIL "main's rule matches an OAuth token, and this file holds none" "regex: $token_regex"
fi

new_case
echo "export const fake = \"$fake_token\";" >>"$repo/src/lib/a.ts"
commit_case
if [ -n "$real_gitleaks" ]; then
  PATH=$real_path run_gate "$repo" "$p" "$sha" "$config"
  expect_frozen "planted fake OAuth token fails (real gitleaks)" "gitleaks found a secret"
else
  echo "NOT RUN planted fake OAuth token fails: gitleaks is not installed"
  not_run=$((not_run + 1))
fi

new_case
echo "change" >>"$repo/src/lib/a.ts"
commit_case
mkdir "$tmp/no-rules"
cp "$gate" "$root/team/scan.sh" "$tmp/no-rules/"
rm -f "$MARKER"
code=0
out=$("$tmp/no-rules/gate.sh" "$repo" "$p" "$sha" "$config" 2>&1) || code=$?
expect_frozen "missing gitleaks rules fails" "no gitleaks rules"
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

# Every candidate file is rechecked after each command, and a change stops the rest.
runtime_case() { # <name> <shell run as a project command>
  new_case
  echo "change" >>"$repo/src/lib/a.ts"
  commit_case
  jq --arg cmd "$2" '.commands = [$cmd, "touch \"$MARKER\""]' "$config" >"$tmp/runtime.json"
  run_gate "$repo" "$p" "$sha" "$tmp/runtime.json"
  expect_frozen "$1" "project command changed the checkout"
}

runtime_case "command editing a spec test fails, stops later commands" \
  'echo x >>team/specs/1/stub.test.ts'
runtime_case "edit hidden with skip-worktree fails" \
  'git update-index --skip-worktree team/specs/1/stub.test.ts && echo x >>team/specs/1/stub.test.ts'
runtime_case "edit hidden with assume-unchanged fails" \
  'git update-index --assume-unchanged team/specs/1/stub.test.ts && echo x >>team/specs/1/stub.test.ts'
runtime_case "edit behind a nested .gitignore fails" \
  'echo "*" >team/specs/1/.gitignore && echo x >>team/specs/1/stub.test.ts'
runtime_case "edit committed in the checkout fails" \
  'echo x >>team/specs/1/stub.test.ts && git commit -qam edited'
runtime_case "deleting a tracked file fails" \
  'rm team/specs/1/stub.test.ts'
runtime_case "editing a source file fails" \
  'echo x >>src/lib/a.ts'
runtime_case "planting a new file fails" \
  'echo x >next.config.js'
runtime_case "new file behind a nested .gitignore fails" \
  'echo "*" >src/.gitignore && echo x >src/next.config.js'
runtime_case "new file added to the index fails" \
  'echo x >next.config.js && git add next.config.js'
runtime_case "new file hidden by .git/info/exclude fails" \
  'echo next.config.js >>.git/info/exclude && echo x >next.config.js'

# git calls this checkout clean, and only an export of the candidate shows otherwise.
new_case
echo "change" >>"$repo/src/lib/a.ts"
commit_case
git -C "$repo" update-index --skip-worktree team/specs/1/stub.test.ts
echo "x" >>"$repo/team/specs/1/stub.test.ts"
run_gate "$repo" "$p" "$sha" "$config"
expect_frozen "edit hidden before the gate starts fails" "project command changed the checkout"

new_case
echo "change" >>"$repo/src/lib/a.ts"
commit_case
jq '.install = "echo x >>src/lib/a.ts"' "$config" >"$tmp/install-edit.json"
run_gate "$repo" "$p" "$sha" "$tmp/install-edit.json"
expect_frozen "install editing a tracked file fails" "project command changed the checkout"
git -C "$repo" checkout -q -- .

jq '.commands = ["touch build-output"]' "$config" >"$tmp/outputs.json"
run_gate "$repo" "$p" "$sha" "$tmp/outputs.json"
if [ "$code" -eq 0 ]; then
  record PASS "command leaving what .gitignore covers passes"
else
  record FAIL "command leaving what .gitignore covers passes" "exit $code: $out"
fi
rm -f "$repo/build-output"

jq '.commands = ["touch planted-file"]' "$config" >"$tmp/planted.json"
run_gate "$repo" "$p" "$sha" "$tmp/planted.json"
expect_fail "a new file is named in the failure" "planted-file"
rm -f "$repo/planted-file"

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

# The red check, against real vitest, so a change in its report shows up here.
vitest=$root/node_modules/.bin/vitest
red_config=$tmp/red-config.json
jq --arg spec_test "$vitest run" '.install = "true" | .spec_test = $spec_test' \
  "$real_config" >"$red_config"

new_red_case() { # An empty spec directory in $repo, with real node_modules.
  n=$((n + 1))
  repo=$tmp/case-$n
  mkdir -p "$repo/team/specs/1"
  ln -s "$root/node_modules" "$repo/node_modules"
}

run_red() { # <red.sh args...> Sets $code and $out.
  code=0
  out=$("$root/team/red.sh" "$@" 2>&1) || code=$?
}

red_case() { # <name> <expected text> <test file on stdin>
  new_red_case
  cat >"$repo/team/specs/1/spec.test.ts"
  run_red "$repo" 1 "$red_config"
  expect_fail "$1" "$2"
}

if [ -x "$vitest" ]; then
  new_red_case
  cat >"$repo/team/specs/1/spec.test.ts" <<'EOF'
import { expect, it } from "vitest";
it("fails", () => {
  expect(1).toBe(2);
});
EOF
  run_red "$repo" 1 "$red_config"
  if [ "$code" -eq 0 ] && [[ $out == *"RED OK"* ]]; then
    record PASS "red: assertion failure passes"
  else
    record FAIL "red: assertion failure passes" "exit $code: $out"
  fi

  # The example in the Lead's prompt, as written, because the Lead will copy it.
  new_red_case
  {
    echo '// @vitest-environment jsdom'
    sed -n '/^```ts$/,/^```$/p' "$root/team/prompts/lead.md" | sed '1d;$d'
  } >"$repo/team/specs/1/spec.test.ts"
  run_red "$repo" 1 "$red_config"
  if [ "$code" -eq 0 ] && [[ $out == *"RED OK"* ]]; then
    record PASS "red: the Lead prompt's example fails on an assertion"
  else
    record FAIL "red: the Lead prompt's example fails on an assertion" "exit $code: $out"
  fi
  code=0
  out=$("$root/node_modules/.bin/tsc" --noEmit --skipLibCheck --strict --target es2022 \
    --module esnext --moduleResolution bundler "$repo/team/specs/1/spec.test.ts" 2>&1) || code=$?
  if [ "$code" -eq 0 ]; then
    record PASS "the Lead prompt's example type-checks"
  else
    record FAIL "the Lead prompt's example type-checks" "exit $code: $out"
  fi

  # This repo tests under jsdom, where Vite resolves a literal import at load time.
  red_case "red: a literal import of new code is blocked" "a spec file failed to load" <<'EOF'
// @vitest-environment jsdom
import { expect, it } from "vitest";
it("greets by name", async () => {
  const mod = await import("./not-written-yet").catch(() => null);
  expect(mod).not.toBeNull();
});
EOF
  new_red_case
  cat >"$repo/team/specs/1/spec.test.ts" <<'EOF'
import { it } from "vitest";

it("finds no element", () => {
  const error = new Error("Unable to find an accessible element");
  error.name = "TestingLibraryElementError";
  throw error;
});
EOF
  run_red "$repo" 1 "$red_config"
  if [ "$code" -eq 0 ] && [[ $out == *"RED OK"* ]]; then
    record PASS "red: a missing element counts as failing for the right reason"
  else
    record FAIL "red: a missing element counts as failing for the right reason" "exit $code: $out"
  fi
  red_case "red: a TypeError in a test is blocked" "no test failed on an assertion" <<'EOF'
import { it } from "vitest";

it("crashes", () => {
  throw new TypeError("Cannot read properties of undefined");
});
EOF
  red_case "red: a crash outside a test is blocked, despite an assertion failure" \
    "the spec crashed outside a test" <<'EOF'
import { expect, it } from "vitest";

it("fails on an assertion, but its setup crashes", async () => {
  setTimeout(() => {
    throw new TypeError("Cannot read properties of undefined");
  }, 0);
  await new Promise((resolve) => setTimeout(resolve, 20));
  expect(1).toBe(2);
});
EOF
  red_case "red: passing spec is blocked" "no test failed on an assertion" <<'EOF'
import { expect, it } from "vitest";
it("passes", () => {
  expect(1).toBe(1);
});
EOF
  red_case "red: skipped-only spec is blocked" "no test failed on an assertion" <<'EOF'
import { expect, it } from "vitest";
it.skip("skipped", () => {
  expect(1).toBe(2);
});
EOF
  red_case "red: thrown non-assertion error is blocked" "no test failed on an assertion" <<'EOF'
import { it } from "vitest";
it("throws", () => {
  throw new TypeError("not an assertion");
});
EOF
  red_case "red: syntax error is blocked" "a spec file failed to load" <<'EOF'
import { expect, it } from "vitest";
it("broken", () => {
  expect(1).toBe(2);
EOF
  red_case "red: bad import is blocked" "a spec file failed to load" <<'EOF'
import { expect, it } from "vitest";
import { missing } from "./does-not-exist";
it("broken", () => {
  expect(missing).toBe(2);
});
EOF
  red_case "red: file with no tests is blocked" "a spec file failed to load" <<'EOF'
export const notATest = 1;
EOF
  red_case "red: failing beforeAll is blocked" "a spec file failed to load" <<'EOF'
import { beforeAll, expect, it } from "vitest";
beforeAll(() => {
  throw new Error("setup failed");
});
it("never runs", () => {
  expect(1).toBe(2);
});
EOF

  # One real assertion failure doesn't excuse another file that can't load.
  new_red_case
  cat >"$repo/team/specs/1/good.test.ts" <<'EOF'
import { expect, it } from "vitest";
it("fails", () => {
  expect(1).toBe(2);
});
EOF
  echo 'import "./does-not-exist";' >"$repo/team/specs/1/bad.test.ts"
  run_red "$repo" 1 "$red_config"
  expect_fail "red: assertion failure plus a broken file is blocked" "a spec file failed to load"

  new_red_case
  run_red "$repo" 1 "$red_config"
  expect_fail "red: empty spec directory is blocked" "no tests collected"
else
  echo "NOT RUN red cases against real vitest: node_modules is not installed"
  not_run=$((not_run + 1))
fi

# The red check's own inputs. These need no vitest.
n=$((n + 1))
repo=$tmp/case-$n
mkdir -p "$repo/team/specs/1"
run_red
expect_fail "red: no inputs fail" "usage:"
run_red "$repo" "" "$config"
expect_fail "red: empty run ID fails" "an input is empty"
run_red "$repo" 1 "$tmp/no-such-config.json"
expect_fail "red: missing config fails" "config not found"
run_red "$tmp/no-such-dir" 1 "$config"
expect_fail "red: missing checkout fails" "no checkout"
run_red "$repo" 2 "$config"
expect_fail "red: missing spec directory fails" "no spec directory"
jq 'del(.spec_test)' "$config" >"$tmp/no-spec-test.json"
run_red "$repo" 1 "$tmp/no-spec-test.json"
expect_fail "red: missing spec_test fails" "config has no spec_test"
jq '.install = "false"' "$config" >"$tmp/red-no-install.json"
run_red "$repo" 1 "$tmp/red-no-install.json"
expect_fail "red: failing install fails" "install failed"
jq '.spec_test = "false"' "$config" >"$tmp/red-no-report.json"
run_red "$repo" 1 "$tmp/red-no-report.json"
expect_fail "red: a runner that writes no report fails" "vitest wrote no report"

# Reading an agent's result. These are shaped like claude-execution-output.json.
agent=$root/team/agent.sh
init='{"type":"system","subtype":"init","session_id":"fixture"}'

run_result() { # <execution-file contents> [review [review-out]] Sets $code, $out and $stats.
  printf '%s' "$1" >"$tmp/execution.json"
  code=0
  out=$("$agent" result "$tmp/execution.json" ${2:+"$2"} ${3:+"$3"} 2>&1) || code=$?
  stats=$(sed -n 's/^stats=//p' <<<"$out")
  out=$(grep -v '^stats=' <<<"$out" || true)
}

expect_result() { # <name> <expected exit> <expected output>
  if [ "$code" -eq "$2" ] && [ "$out" = "$3" ]; then
    record PASS "$1"
  else
    record FAIL "$1" "exit $code: $out"
  fi
}

review() { # <structured_output JSON>
  printf '[%s,{"type":"result","subtype":"success","is_error":false,"num_turns":4,"result":"done","structured_output":%s}]' \
    "$init" "$1"
}

# The signature reported for an OAuth session limit: subtype success, is_error,
# 429, no cost, and nothing else in the stream to say what happened.
limit='[
  {"type":"system","subtype":"init","session_id":"fixture"},
  {"type":"result","subtype":"success","is_error":true,"api_error_status":429,
   "duration_ms":350,"num_turns":1,"total_cost_usd":0,"permission_denials":[],
   "modelUsage":{},"result":"You'"'"'ve hit your session limit · resets 1:10am (UTC)"}
]'
run_result "$limit"
expect_result "result: usage limit is a limit" 1 "agent=limit"
run_result "$limit" review
expect_result "result: usage limit in review isn't a bad review" 1 "agent=limit"
run_result '[{"type":"result","subtype":"success","is_error":true,"result":"You have hit your weekly limit"}]'
expect_result "result: limit text without a status is a limit" 1 "agent=limit"
run_result '[{"type":"result","subtype":"error_during_execution","is_error":true,"api_error_status":429}]'
expect_result "result: 429 on an error subtype is a limit" 1 "agent=limit"
run_result '[{"type":"result","subtype":"error_during_execution","is_error":true,"errors":["You have hit your session limit"]}]'
expect_result "result: limit text in errors is a limit" 1 "agent=limit"

run_result "[$init,{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"num_turns\":9}]"
expect_result "result: success is ok" 0 "agent=ok"
run_result '[{"type":"result","subtype":"success","is_error":true,"api_error_status":500}]'
expect_result "result: is_error with no limit failed" 1 "agent=failed"
run_result '[{"type":"result","subtype":"error_max_turns","is_error":true,"num_turns":31}]'
expect_result "result: too many turns failed" 1 "agent=failed"
run_result '[{"type":"result","subtype":"error_max_turns"}]'
expect_result "result: no is_error field failed" 1 "agent=failed"
run_result "[$init]"
expect_result "result: no result message failed" 1 "agent=failed"
run_result '[]'
expect_result "result: empty execution file failed" 1 "agent=failed"
run_result 'not json'
expect_result "result: unreadable execution file failed" 1 "agent=failed"
rm -f "$tmp/execution.json"
code=0
out=$("$agent" result "$tmp/execution.json" 2>&1) || code=$?
expect_result "result: missing execution file failed" 1 "agent=failed"

run_result "$(review '{"works":{"verdict":"pass","checked":"c"},"good":{"verdict":"pass","checked":"c"},"blocking":[]}')" review
expect_result "review: no findings" 0 "blocking=0
agent=ok"
run_result "$(review '{"works":{"verdict":"pass","checked":"c"},"good":{"verdict":"pass","checked":"c"},"blocking":[{"file":"a.ts","problem":"p","evidence":"e"},{"file":"b.ts","problem":"p","evidence":"e"}]}')" review
expect_result "review: findings are counted" 0 "blocking=2
agent=ok"
run_result "[$init,{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false}]" review
expect_result "review: no structured output is invalid" 1 "agent=invalid"
run_result "$(review 'null')" review
expect_result "review: null structured output is invalid" 1 "agent=invalid"
run_result "$(review '"approved"')" review
expect_result "review: a string is invalid" 1 "agent=invalid"
run_result "$(review '{"works":{"verdict":"pass","checked":"c"},"good":{"verdict":"pass","checked":"c"}}')" review
expect_result "review: missing blocking is invalid" 1 "agent=invalid"
run_result "$(review '{"works":{"verdict":"pass","checked":"c"},"good":{"verdict":"pass","checked":"c"},"blocking":"none"}')" review
expect_result "review: blocking that isn't a list is invalid" 1 "agent=invalid"
run_result "$(review '{"works":{"verdict":"pass","checked":"c"},"good":{"verdict":"pass","checked":"c"},"blocking":{}}')" review
expect_result "review: an empty object isn't an empty list" 1 "agent=invalid"
run_result "$(review '{"works":{"verdict":"pass","checked":""},"good":{"verdict":"pass","checked":"c"},"blocking":[]}')" review
expect_result "review: empty works is invalid" 1 "agent=invalid"
run_result "$(review '{"works":"fail","good":{"verdict":"pass","checked":"c"},"blocking":[]}')" review
expect_result "review: a bare string verdict is invalid" 1 "agent=invalid"
run_result "$(review '{"works":{"verdict":"maybe","checked":"c"},"good":{"verdict":"pass","checked":"c"},"blocking":[]}')" review
expect_result "review: an unknown verdict is invalid" 1 "agent=invalid"
run_result "$(review '{"works":{"verdict":"pass"},"good":{"verdict":"pass","checked":"c"},"blocking":[]}')" review
expect_result "review: a verdict without checked is invalid" 1 "agent=invalid"
run_result "$(review '{"works":{"verdict":"fail","checked":"c"},"good":{"verdict":"pass","checked":"c"},"blocking":[]}')" review
expect_result "review: a fail in works blocks with no findings" 0 "blocking=1
agent=ok"
run_result "$(review '{"works":{"verdict":"pass","checked":"c"},"good":{"verdict":"fail","checked":"c"},"blocking":[]}')" review
expect_result "review: a fail in good blocks with no findings" 0 "blocking=1
agent=ok"
run_result "$(review '{"works":{"verdict":"fail","checked":"c"},"good":{"verdict":"fail","checked":"c"},"blocking":[{"file":"a.ts","problem":"p","evidence":"e"}]}')" review
expect_result "review: findings and fails add up" 0 "blocking=3
agent=ok"
run_result "$(review '{"works":{"verdict":"pass","checked":"c"},"blocking":[]}')" review
expect_result "review: missing good is invalid" 1 "agent=invalid"
run_result "$(review '{"works":{"verdict":"pass","checked":"c"},"good":{"verdict":"pass","checked":"c"},"blocking":[{"file":"a.ts","problem":"p"}]}')" review
expect_result "review: a finding without evidence is invalid" 1 "agent=invalid"
run_result "$(review '{"works":{"verdict":"pass","checked":"c"},"good":{"verdict":"pass","checked":"c"},"blocking":["bad"]}')" review
expect_result "review: a finding that isn't an object is invalid" 1 "agent=invalid"

# The public summary carries outcome fields, and never what the agent wrote.
summary_is() { # <name> <wanted text> <text that must not appear>
  if grep -qF -- "$2" "$tmp/summary" && ! grep -qF -- "$3" "$tmp/summary"; then
    record PASS "$1"
  else
    record FAIL "$1" "summary: $(cat "$tmp/summary" 2>/dev/null)"
  fi
}

: >"$tmp/summary"
GITHUB_STEP_SUMMARY=$tmp/summary run_result "$(review '{"works":{"verdict":"pass","checked":"the checked text"},"good":{"verdict":"pass","checked":"the checked text"},"blocking":[{"file":"a.ts","problem":"the problem text","evidence":"e"}]}')" review
summary_is "summary: a review shows its verdicts and count" "works=pass good=pass findings=1" "turns=null"
summary_is "summary: a review's text stays out" "subtype=success" "the problem text"
summary_is "summary: what was checked stays out" "subtype=success" "the checked text"
: >"$tmp/summary"
GITHUB_STEP_SUMMARY=$tmp/summary run_result "$limit"
summary_is "summary: a limit shows its status, not its text" "api_error_status=429" "resets 1:10am"
: >"$tmp/summary"
GITHUB_STEP_SUMMARY=$tmp/summary run_result '[{"type":"result","subtype":"error_during_execution","is_error":true,"errors":["the error text"]}]'
summary_is "summary: errors stay out" "subtype=error_during_execution" "the error text"

# What a record gets from an execution file. Numbers, and what ran, with no agent text.
stats_is() { # <name> <jq filter that must be true of $stats>
  if jq -e "$2" <<<"$stats" >/dev/null 2>&1; then
    record PASS "$1"
  else
    record FAIL "$1" "stats: $stats"
  fi
}

ran_bash='{"type":"assistant","message":{"content":[{"type":"text","text":"the agent text"},{"type":"tool_use","name":"Bash","input":{"command":"npm run lint && npx tsc --noEmit"}}]}}'
spent='"num_turns":17,"total_cost_usd":0.12,"usage":{"input_tokens":100,"output_tokens":20,"cache_read_input_tokens":30,"cache_creation_input_tokens":40}'
run_result "[$init,$ran_bash,{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,$spent,\"result\":\"the result text\"}]"
stats_is "stats: turns, tokens and cost" \
  '.turns == 17 and .cost_usd == 0.12 and .input_tokens == 100 and .output_tokens == 20 and .cache_read_tokens == 30 and .cache_write_tokens == 40'
stats_is "stats: shows which gate commands ran, and which didn't" \
  '.ran["npm run lint"] and .ran["npx tsc --noEmit"] and (.ran["npm run test:run"] | not)'
if [[ $stats != *"the agent text"* ]] && [[ $stats != *"the result text"* ]]; then
  record PASS "stats: no agent text"
else
  record FAIL "stats: no agent text" "$stats"
fi
if [ "$(wc -l <<<"$stats" | tr -d ' ')" -eq 1 ]; then
  record PASS "stats: fits on one output line"
else
  record FAIL "stats: fits on one output line" "$stats"
fi
run_result '[{"type":"result","subtype":"success","is_error":false,"num_turns":"the agent text","usage":"x"}]'
stats_is "stats: a field that isn't a number reads as null" '.turns == null and .input_tokens == null'
run_result "$limit"
stats_is "stats: a limit still reports what it spent" '.turns == 1 and .cost_usd == 0'
expect_result "stats: don't change a limit's outcome" 1 "agent=limit"
run_result "[{\"type\":\"assistant\",\"message\":{\"content\":\"text\"}},$(jq -nc --argjson s "{$spent}" '$s + {type:"result",subtype:"success",is_error:false}')]"
stats_is "stats: a message in an unexpected shape is skipped" '.turns == 17 and (.ran["npm run lint"] | not)'
expect_result "stats: an unexpected shape doesn't change the outcome" 0 "agent=ok"

# The Reviewer's findings reach the record by file, and only when they're valid.
rm -f "$tmp/review-out.json"
run_result "$(review '{"works":{"verdict":"pass","checked":"c"},"good":{"verdict":"pass","checked":"c"},"blocking":[{"file":"a.ts","problem":"the problem text","evidence":"e"}]}')" review "$tmp/review-out/1.json"
if [ "$(jq -r '.blocking[0].problem' "$tmp/review-out/1.json")" = "the problem text" ] && [[ $out != *"the problem text"* ]]; then
  record PASS "review: its JSON goes to the file, and never to an output"
else
  record FAIL "review: its JSON goes to the file, and never to an output" "$out"
fi
run_result "$(review '"approved"')" review "$tmp/review-out/2.json"
if [ ! -e "$tmp/review-out/2.json" ]; then
  record PASS "review: invalid output writes no file"
else
  record FAIL "review: invalid output writes no file" "$(cat "$tmp/review-out/2.json")"
fi

# upload-artifact would follow a symlink and hang on a FIFO, outside the sandbox.
files_case() { # <name> <wanted text, or nothing to pass> <shell to set up the tree>
  rm -rf "$tmp/files"
  mkdir -p "$tmp/files/src" "$tmp/files/node_modules/.bin"
  (cd "$tmp/files" && bash -euc "$3")
  code=0
  out=$(cd "$tmp/files" && "$agent" files 2>&1) || code=$?
  if [ -n "$2" ]; then
    expect_fail "$1" "$2"
  elif [ "$code" -eq 0 ]; then
    record PASS "$1"
  else
    record FAIL "$1" "exit $code: $out"
  fi
}

files_case "files: files and directories pass" "" 'echo x >src/a.ts'
files_case "files: symlinks in node_modules pass, because it isn't uploaded" "" \
  'ln -s /etc/hosts node_modules/.bin/tool'
files_case "files: a symlink fails" "are allowed: ./src/env.txt" \
  'ln -s /proc/self/environ src/env.txt'
files_case "files: a FIFO fails" "are allowed: ./src/pipe" \
  'mkfifo src/pipe'

# Proving the sandbox, with stand-ins for sudo and bwrap, which only exist on Linux.
mkdir -p "$tmp/sandbox-bin"
cat >"$tmp/sandbox-bin/sudo" <<'EOF'
#!/bin/sh
echo "sudo $*" >>"$SANDBOX_LOG"
EOF
cat >"$tmp/sandbox-bin/bwrap" <<'EOF'
#!/bin/sh
echo "bwrap $*" >>"$SANDBOX_LOG"
exit "${BWRAP_EXIT:-0}"
EOF
chmod +x "$tmp/sandbox-bin/sudo" "$tmp/sandbox-bin/bwrap"
export SANDBOX_LOG=$tmp/sandbox.log

: >"$SANDBOX_LOG"
code=0
out=$(PATH="$tmp/sandbox-bin:$PATH" "$agent" sandbox 2>&1) || code=$?
if [ "$code" -eq 0 ] && grep -q 'install .*bubblewrap socat' "$SANDBOX_LOG" &&
  grep -q '^bwrap --unshare-user --unshare-pid ' "$SANDBOX_LOG" &&
  [ "$(grep -n 'bwrap --unshare' "$SANDBOX_LOG" | cut -d: -f1)" -gt "$(grep -n 'install' "$SANDBOX_LOG" | cut -d: -f1)" ]; then
  record PASS "sandbox: installs, then proves bubblewrap works"
else
  record FAIL "sandbox: installs, then proves bubblewrap works" "exit $code: $out"
fi
code=0
out=$(BWRAP_EXIT=1 PATH="$tmp/sandbox-bin:$PATH" "$agent" sandbox 2>&1) || code=$?
expect_fail "sandbox: a failing bubblewrap fails" "bubblewrap can't create a sandbox"

# Removing admin rights, with stand-ins that remember what was removed.
mkdir -p "$tmp/admin-bin"
cat >"$tmp/admin-bin/sudo" <<'EOF'
#!/bin/sh
echo "sudo $*" >>"$ADMIN_LOG"
case "$1" in
  -n) [ -n "${SUDO_STAYS:-}" ] || [ ! -e "$ADMIN_LOG.gone" ] ;;
  sh) touch "$ADMIN_LOG.gone" ;;
esac
EOF
cat >"$tmp/admin-bin/docker" <<'EOF'
#!/bin/sh
exit "${DOCKER_EXIT:-1}"
EOF
chmod +x "$tmp/admin-bin/sudo" "$tmp/admin-bin/docker"
export ADMIN_LOG=$tmp/admin.log

admin_run() { # Sets $code and $out, from a clean start.
  rm -f "$ADMIN_LOG" "$ADMIN_LOG.gone"
  code=0
  out=$(PATH="$tmp/admin-bin:$PATH" "$agent" no-admin 2>&1) || code=$?
}

admin_run
if [ "$code" -eq 0 ] && grep -q 'rm -f /var/run/docker.sock' "$ADMIN_LOG" &&
  grep -q 'sudoers' "$ADMIN_LOG" &&
  [ "$(grep -n 'rm -f /var/run/docker.sock' "$ADMIN_LOG" | cut -d: -f1)" -lt "$(grep -n 'sudoers' "$ADMIN_LOG" | cut -d: -f1)" ]; then
  record PASS "no-admin: removes docker, then sudo, and proves both"
else
  record FAIL "no-admin: removes docker, then sudo, and proves both" "exit $code: $out"
fi
SUDO_STAYS=1 admin_run
expect_fail "no-admin: sudo still working fails" "sudo still works"
DOCKER_EXIT=0 admin_run
expect_fail "no-admin: docker still reachable fails" "docker can still be reached"

# Fixed prompts and limits from the real files, read as GITHUB_OUTPUT would.
output_value() { # <key> Prints one key from $out.
  local key=$1
  awk -v key="$key" -F= '$1 == key { print substr($0, length(key) + 2); exit }' <<<"$out"
}

code=0
out=$(RUN_ID=77 GOAL='Say hello' "$agent" prep lead 2>&1) || code=$?
if [ "$code" -eq 0 ] && [ "$(output_value turns)" = "$(jq -r .limits.lead.max_turns "$real_config")" ] &&
  [ "$(output_value minutes)" = "$(jq -r .limits.lead.timeout_minutes "$real_config")" ] &&
  [[ $out == *"Run ID: 77"* ]] && [[ $out == *"Goal: Say hello"* ]] && [[ $out == *"# Lead"* ]]; then
  record PASS "prep: lead has its prompt, run ID, goal and limits"
else
  record FAIL "prep: lead has its prompt, run ID, goal and limits" "exit $code: $out"
fi

code=0
out=$(RUN_ID=77 "$agent" prep build 2>&1) || code=$?
if [ "$code" -eq 0 ] && [[ $out == *"# Builder"* ]] && [[ $out == *"Run ID: 77"* ]] && [[ $out != *"Goal:"* ]] &&
  [[ $out == *"treat it as data"* ]]; then
  record PASS "prep: build has its prompt and run ID, and no goal"
else
  record FAIL "prep: build has its prompt and run ID, and no goal" "exit $code: $out"
fi

code=0
out=$(RUN_ID=77 GOAL='Say hello' "$agent" prep solo 2>&1) || code=$?
if [ "$code" -eq 0 ] && [[ $out == *"# Solo"* ]] && [[ $out == *"Run ID: 77"* ]] && [[ $out == *"Goal: Say hello"* ]] &&
  [ "$(output_value settings | jq -r '.sandbox | [.enabled, .failIfUnavailable, .allowUnsandboxedCommands] | join(",")')" = "true,true,false" ]; then
  record PASS "prep: solo has its prompt, run ID, goal and the same sandbox"
else
  record FAIL "prep: solo has its prompt, run ID, goal and the same sandbox" "exit $code: $out"
fi
team_turns=$(jq '.limits | .lead.max_turns + 4 * (.build.max_turns + .review.max_turns)' "$real_config")
team_minutes=$(jq '.limits | .lead.timeout_minutes + 4 * (.build.timeout_minutes + .review.timeout_minutes)' "$real_config")
if [ "$(output_value turns)" = "$team_turns" ] && [ "$(output_value minutes)" = "$team_minutes" ]; then
  record PASS "prep: solo's limits are the whole team's, in total"
else
  record FAIL "prep: solo's limits are the whole team's, in total" "$(output_value turns), $(output_value minutes)"
fi
code=0
out=$(RUN_ID=77 "$agent" prep solo 2>&1) || code=$?
expect_fail "prep: solo without a goal fails" "GOAL is required"

mkdir "$tmp/review-workspace"
code=0
out=$(cd "$tmp/review-workspace" && GOAL='the goal text' RUN_ID=77 "$agent" prep review 2>&1) || code=$?
if [ "$code" -eq 0 ] && [[ $out == *"# Reviewer"* ]] && [[ $out != *"the goal text"* ]] &&
  [[ $out != *"Run ID"* ]] && [ "$(output_value schema | jq -r '.required | join(",")')" = "works,good,blocking" ] &&
  [ "$(cat "$tmp/review-workspace/goal.md")" = "the goal text" ]; then
  record PASS "prep: review gets the goal as data, and a fixed prompt with the compact schema"
else
  record FAIL "prep: review gets the goal as data, and a fixed prompt with the compact schema" "exit $code: $out"
fi
if [ -f "$tmp/review-workspace/previous-findings.txt" ] && [ ! -s "$tmp/review-workspace/previous-findings.txt" ]; then
  record PASS "prep: a first review has no previous findings, and the same four inputs"
else
  record FAIL "prep: a first review has no previous findings, and the same four inputs" "$(ls -A "$tmp/review-workspace")"
fi
findings_json=$(jq -cn '{source: "review", findings: "a.ts: the old problem Evidence: e", withheld: false}')
out=$(cd "$tmp/review-workspace" && FEEDBACK=$findings_json GOAL=x RUN_ID=77 "$agent" prep review 2>&1)
if [ "$(cat "$tmp/review-workspace/previous-findings.txt")" = "a.ts: the old problem Evidence: e" ] &&
  [[ $out != *"the old problem"* ]] && [[ $out == *"addressed"* ]]; then
  record PASS "prep: earlier findings go to the Reviewer as data, and it must address them"
else
  record FAIL "prep: earlier findings go to the Reviewer as data, and it must address them" "$out"
fi
code=0
out=$(cd "$tmp/review-workspace" && RUN_ID=77 "$agent" prep review 2>&1) || code=$?
expect_fail "prep: review without a goal fails" "GOAL is required"

if [ "$(output_value settings)" = "" ]; then
  record PASS "prep: review gets no sandbox settings, because it has no shell"
else
  record FAIL "prep: review gets no sandbox settings, because it has no shell" "$(output_value settings)"
fi

out=$(RUN_ID=77 "$agent" prep build)
if [ "$(output_value settings | jq -r '.sandbox | [.enabled, .failIfUnavailable, .allowUnsandboxedCommands, (.network.allowedDomains // [] | length), .network.strictAllowlist] | join(",")')" = "true,true,false,0,true" ]; then
  record PASS "prep: settings make the sandbox mandatory, with no network"
else
  record FAIL "prep: settings make the sandbox mandatory, with no network" "$(output_value settings)"
fi
if [ "$(output_value settings | jq -r '.sandbox.filesystem.denyWrite[0]')" = "$(pwd -P)/.git" ]; then
  record PASS "prep: settings stop a shell making a .git in the workspace"
else
  record FAIL "prep: settings stop a shell making a .git in the workspace" "$(output_value settings)"
fi

mkdir -p "$tmp/quoted-settings/team"
cp -R "$root/team/agent.sh" "$root/team/prompts" "$tmp/quoted-settings/team/"
jq '.agent_settings.note = "can'"'"'t"' "$real_config" >"$tmp/quoted-settings/team/config.json"
code=0
out=$(RUN_ID=77 "$tmp/quoted-settings/team/agent.sh" prep build 2>&1) || code=$?
expect_fail "prep: a single quote in the settings fails" "agent_settings can't contain a single quote"

# Every delimiter differs, and a goal can't forge one or add an output.
code=0
out=$(RUN_ID=77 GOAL=$'first line\nturns=999\nEOF' "$agent" prep lead 2>&1) || code=$?
delimiter=$(sed -n 's/^prompt<<//p' <<<"$out")
if [ "$code" -eq 0 ] && [ "${#delimiter}" -eq 32 ] && [ "$(tail -1 <<<"$out")" = "$delimiter" ] &&
  [ "$(grep -c '^turns=' <<<"$(sed "/^prompt<</q" <<<"$out")")" -eq 1 ]; then
  record PASS "prep: a multi-line goal stays inside the prompt"
else
  record FAIL "prep: a multi-line goal stays inside the prompt" "exit $code: $out"
fi

# The schema reaches claude_args inside single quotes.
mkdir -p "$tmp/quote/team"
cp -R "$root/team/agent.sh" "$root/team/config.json" "$root/team/prompts" "$tmp/quote/team/"
echo '{"description":"can'"'"'t"}' >"$tmp/quote/team/review.schema.json"
code=0
out=$(cd "$tmp/quote" && GOAL=x "$tmp/quote/team/agent.sh" prep review 2>&1) || code=$?
expect_fail "prep: a single quote in the schema fails" "can't contain a single quote"

code=0
out=$(RUN_ID=77 "$agent" prep lead 2>&1) || code=$?
expect_fail "prep: lead without a goal fails" "GOAL is required"
code=0
out=$(GOAL=x "$agent" prep build 2>&1) || code=$?
expect_fail "prep: build without a run ID fails" "RUN_ID is required"
code=0
out=$("$agent" prep reviewer 2>&1) || code=$?
expect_fail "prep: unknown role fails" "unknown role"
code=0
out=$("$agent" 2>&1) || code=$?
expect_fail "agent.sh with no command fails" "usage:"

# Staging an agent's tree, as pin and publish do. The artifact is a plain tree with
# no exec bits, and the checkout must stay as it was.
stage_case() { # <shell run in the tree> Sets $code, $out and $staged, in $repo.
  new_case
  n=$((n + 1))
  tree=$tmp/tree-$n
  mkdir "$tree"
  git -C "$repo" archive HEAD | tar -x -C "$tree"
  find "$tree" -type f -exec chmod 644 {} +
  (cd "$tree" && bash -euc "$1")
  : >"$SHIM_LOG"
  code=0
  out=$(cd "$repo" && "$root/team/scan.sh" stage "$tree" 2>&1) || code=$?
  staged=$(git -C "$repo" diff --cached --name-status | tr '\t' ' ' | tr '\n' ';')
}

expect_staged() { # <name> <wanted list>
  if [ "$code" -eq 0 ] && [ "$staged" = "$2" ]; then
    record PASS "$1"
  else
    record FAIL "$1" "exit $code, staged: $staged, $out"
  fi
}

stage_case 'echo x >>src/lib/a.ts && rm docs/a.md && echo x >src/lib/new.ts && echo x >build-output'
expect_staged "stage: edits, deletes and new files, without what main ignores" \
  "D docs/a.md;M src/lib/a.ts;A src/lib/new.ts;"
if [ -z "$(git -C "$repo" diff --name-only -- team/gate.sh)" ] &&
  [ "$(git -C "$repo" ls-files -s team/gate.sh | cut -c1-6)" = 100755 ]; then
  record PASS "stage: exec bits survive a tree that lost them"
else
  record FAIL "stage: exec bits survive a tree that lost them" "$staged"
fi
if ! grep -q change "$repo/src/lib/a.ts" && [ -f "$repo/docs/a.md" ] && [ ! -e "$repo/src/lib/new.ts" ]; then
  record PASS "stage: nothing from the tree lands in the checkout"
else
  record FAIL "stage: nothing from the tree lands in the checkout" "$staged"
fi
if grep -qF -- "dir --no-banner" "$SHIM_LOG" && grep -qF -- "--config $root/team/gitleaks.toml" "$SHIM_LOG" &&
  grep -qF "scanned dir holds 1 entries" "$SHIM_LOG"; then
  record PASS "stage: scans only the diff, away from the tree, with main's rules"
else
  record FAIL "stage: scans only the diff, away from the tree, with main's rules" "$(cat "$SHIM_LOG")"
fi
stage_case 'printf "*\n" >.gitignore && echo x >vercel.json'
expect_staged "stage: an agent's .gitignore hides nothing" "M .gitignore;A vercel.json;"
stage_case ': >.npmrc && : >.gitmodules && : >.env.production && : >bunfig.toml && echo x >src/lib/new.ts'
expect_staged "stage: the sandbox's empty placeholders are dropped" "A src/lib/new.ts;"
stage_case 'echo "registry=https://evil.invalid" >.npmrc && echo x >src/lib/new.ts'
expect_staged "stage: a placeholder path with content is kept, for the checks to refuse" \
  "A .npmrc;A src/lib/new.ts;"
stage_case ': >.npmrc-extra && : >src/.npmrc && echo x >src/lib/new.ts'
expect_staged "stage: an empty file off the list is kept, for the checks to refuse" \
  "A .npmrc-extra;A src/.npmrc;A src/lib/new.ts;"
stage_case 'printf "*\n" >src/.gitignore && echo x >src/hidden.config.ts'
expect_staged "stage: a new nested .gitignore hides nothing" "A src/.gitignore;A src/hidden.config.ts;"
stage_case 'true'
expect_staged "stage: an unchanged tree stages nothing" ""

# A retry's tree is staged over P, and its commit goes on the last attempt.
stage_case 'echo x >src/lib/retry.ts'
head_before=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" commit-tree HEAD^{tree} -p HEAD -m "last attempt" >"$tmp/parent"
parent=$(cat "$tmp/parent")
code=0
out=$(cd "$repo" && "$root/team/scan.sh" commit-on "$parent" "the message" 2>&1) || code=$?
if [ "$code" -eq 0 ] && [ "$(git -C "$repo" rev-parse "$out^")" = "$parent" ] &&
  [ "$(git -C "$repo" diff --name-status "$head_before" "$out" | tr '\t' ' ')" = "A src/lib/retry.ts" ] &&
  [ "$(git -C "$repo" log -1 --format=%s "$out")" = "the message" ] &&
  [ "$(git -C "$repo" rev-parse HEAD)" = "$head_before" ]; then
  record PASS "commit-on: goes on the given parent, with the staged tree, and leaves HEAD"
else
  record FAIL "commit-on: goes on the given parent, with the staged tree, and leaves HEAD" "exit $code: $out"
fi
stage_case 'true'
code=0
out=$(cd "$repo" && "$root/team/scan.sh" commit-on HEAD "the message" 2>&1) || code=$?
expect_fail "commit-on: an empty change fails" "the change is empty"
code=0
out=$(cd "$repo" && "$root/team/scan.sh" commit-on 2>&1) || code=$?
expect_fail "commit-on: no parent fails" "commit-on needs"
stage_case 'echo x >src/lib/retry.ts'
parent=$(cd "$repo" && git commit-tree "$(git write-tree)" -p HEAD -m "last attempt")
code=0
out=$(cd "$repo" && "$root/team/scan.sh" commit-on "$parent" "the message" 2>&1) || code=$?
expect_fail "commit-on: a retry that matches the last attempt fails" "the tree matches the last attempt"
# Solo's tree holds spec and code, and only the spec goes into P.
stage_only_case() { # <shell run in the tree> <only>
  stage_case "$1"
  code=0
  git -C "$repo" reset -q
  out=$(cd "$repo" && "$root/team/scan.sh" stage "$tree" "$2" 2>&1) || code=$?
  staged=$(git -C "$repo" diff --cached --name-status | tr '\t' ' ' | tr '\n' ';')
}

stage_only_case 'echo x >>src/lib/a.ts && echo x >team/specs/1/spec.md && rm docs/a.md' team/specs/1
expect_staged "stage: only keeps that path staged" "A team/specs/1/spec.md;"
if grep -qF -- "dir --no-banner" "$SHIM_LOG"; then
  record PASS "stage: only still scans the whole tree first"
else
  record FAIL "stage: only still scans the whole tree first" "$(cat "$SHIM_LOG")"
fi
SHIM_EXIT=1 stage_only_case 'echo x >>src/lib/a.ts && echo x >team/specs/1/spec.md' team/specs/1
if [ "$code" -ne 0 ]; then
  record PASS "stage: only fails on a finding outside that path"
else
  record FAIL "stage: only fails on a finding outside that path" "$out"
fi
stage_case 'mkdir .git && echo x >.git/config'
expect_fail "stage: a .git in the tree fails" "the tree holds a .git"
stage_case 'mkdir -p src/vendor/.git'
expect_fail "stage: a nested .git fails" "the tree holds a .git"
SHIM_EXIT=1 stage_case 'echo x >>src/lib/a.ts'
if [ "$code" -ne 0 ]; then
  record PASS "stage: a finding fails"
else
  record FAIL "stage: a finding fails" "$out"
fi
code=0
out=$(cd "$repo" && "$root/team/scan.sh" stage "$tmp/no-such-tree" 2>&1) || code=$?
expect_fail "stage: a missing tree fails" "no tree"
code=0
out=$("$root/team/scan.sh" 2>&1) || code=$?
expect_fail "scan.sh with no command fails" "usage:"

# Free text on its way to a public record or an agent.
scan_text() { # <max-bytes> Reads $tmp/text-in. Sets $code and $out.
  rm -f "$tmp/text-out"
  : >"$SHIM_LOG"
  code=0
  out=$("$root/team/scan.sh" text "$tmp/text-in" "$tmp/text-out" "$1" 2>&1) || code=$?
}

printf 'one\ntwo\n' >"$tmp/text-in"
scan_text 100
if [ "$code" -eq 0 ] && [ "$(cat "$tmp/text-out")" = $'one\ntwo' ] &&
  grep -qF -- "--config $root/team/gitleaks.toml" "$SHIM_LOG" &&
  grep -qF "scanned dir holds 1 entries" "$SHIM_LOG"; then
  record PASS "text: clean text is kept, scanned alone with main's rules"
else
  record FAIL "text: clean text is kept, scanned alone with main's rules" "exit $code: $out"
fi
printf 'head\nTHE-SECRET\ntail\n' >"$tmp/text-in"
SHIM_MATCH=THE-SECRET scan_text 100
if [ "$code" -ne 0 ] && [ ! -e "$tmp/text-out" ]; then
  record PASS "text: a hit writes nothing"
else
  record FAIL "text: a hit writes nothing" "exit $code: $(cat "$tmp/text-out" 2>/dev/null)"
fi
SHIM_MATCH=THE-SECRET scan_text 5
if [ "$code" -ne 0 ] && [ ! -e "$tmp/text-out" ]; then
  record PASS "text: a hit in what would be trimmed away still counts"
else
  record FAIL "text: a hit in what would be trimmed away still counts" "exit $code: $out"
fi
printf 'THE-\033[0mSECRET\n' >"$tmp/text-in"
SHIM_MATCH=THE-SECRET scan_text 100
if [ "$code" -ne 0 ] && [ ! -e "$tmp/text-out" ]; then
  record PASS "text: a secret split by a colour code is found"
else
  record FAIL "text: a secret split by a colour code is found" "exit $code: $(cat "$tmp/text-out" 2>/dev/null)"
fi
printf '%%PDF-1.7\nTHE-SECRET\n' >"$tmp/text-in"
SHIM_MATCH=THE-SECRET scan_text 100
if [ "$code" -ne 0 ] && [ ! -e "$tmp/text-out" ]; then
  record PASS "text: a log that opens like a PDF is still scanned"
else
  record FAIL "text: a log that opens like a PDF is still scanned" "exit $code"
fi
{
  head -c 257 /dev/zero | tr '\0' 'x'
  printf 'ustar\nTHE-SECRET\n'
} >"$tmp/text-in"
SHIM_MATCH=THE-SECRET scan_text 100
if [ "$code" -ne 0 ] && [ ! -e "$tmp/text-out" ]; then
  record PASS "text: a mark deeper in a log can't skip the scan either"
else
  record FAIL "text: a mark deeper in a log can't skip the scan either" "exit $code"
fi
# A mark can sit past 32 KB, as a disc image's does, and any prefix moves the marks
# above, so only the line's own length shows it runs past them all.
printf 'x\n' >"$tmp/text-in"
scan_text 100
fixed_line=$(sed -n 's/^first line holds \([0-9]*\) bytes$/\1/p' "$SHIM_LOG")
if [ "${fixed_line:-0}" -gt 32774 ]; then
  record PASS "text: the fixed line runs past the deepest mark"
else
  record FAIL "text: the fixed line runs past the deepest mark" "${fixed_line:-no line} bytes"
fi
printf '%%PDF-1.7\nkept\n' >"$tmp/text-in"
scan_text 100
if [ "$code" -eq 0 ] && [ "$(cat "$tmp/text-out")" = $'%PDF-1.7\nkept' ]; then
  record PASS "text: the scan's fixed line stays out of what's kept"
else
  record FAIL "text: the scan's fixed line stays out of what's kept" "$(head -c 200 "$tmp/text-out")"
fi
printf '\033[31mred\033[0m\ttab\001\n' >"$tmp/text-in"
scan_text 100
if [ "$code" -eq 0 ] && [ "$(cat "$tmp/text-out")" = $'red\ttab' ]; then
  record PASS "text: colour codes and control characters go, tabs and lines stay"
else
  record FAIL "text: colour codes and control characters go, tabs and lines stay" "exit $code: $(od -c "$tmp/text-out" 2>/dev/null)"
fi
printf '0123456789\n' >"$tmp/text-in"
scan_text 4
if [ "$code" -eq 0 ] && [ "$(cat "$tmp/text-out")" = 789 ]; then
  record PASS "text: trims to the last bytes, where failures are"
else
  record FAIL "text: trims to the last bytes, where failures are" "exit $code: $(cat "$tmp/text-out" 2>/dev/null)"
fi
SHIM_EXIT=1 scan_text 100
if [ "$code" -ne 0 ] && [ ! -e "$tmp/text-out" ]; then
  record PASS "text: a scanner that can't run counts as a hit"
else
  record FAIL "text: a scanner that can't run counts as a hit" "exit $code: $out"
fi
code=0
out=$("$root/team/scan.sh" text "$tmp/no-such-file" "$tmp/text-out" 100 2>&1) || code=$?
expect_fail "text: a missing file fails" "no file"
code=0
out=$("$root/team/scan.sh" text "$tmp/text-in" "$tmp/text-out" lots 2>&1) || code=$?
expect_fail "text: a bad size fails" "text needs"

# The verdict. Every value that came from an agent can only stop a run.
mkdir "$tmp/verdict-in"

verdict_case() { # <name> <wanted verdict> <wanted reason> [VAR=value...]
  local name=$1 wanted=$2 reason=$3
  shift 3
  code=0
  out=$(env ATTEMPT=1 BUILD_RESULT=success PUBLISH_RESULT=success TEST_RESULT=success GATE_OUTCOME=success \
    REVIEW_RESULT=success BLOCKING=0 "$@" "$root/team/verdict.sh" decide "$tmp/verdict-in" 2>&1) || code=$?
  if [ "$code" -eq 0 ] && [ "$(grep -E '^(verdict|reason)=' <<<"$out")" = "verdict=$wanted
reason=$reason" ]; then
    record PASS "$name"
  else
    record FAIL "$name" "exit $code: $out"
  fi
}

verdict_case "verdict: a clean review passes" pass "no blocking findings"
verdict_case "verdict: a blocking review goes back" retry "blocking findings: 2" BLOCKING=2
verdict_case "verdict: a failed gate goes back" retry "gate failed" TEST_RESULT=failure GATE_OUTCOME=failure REVIEW_RESULT=skipped
verdict_case "verdict: a third failure still goes back" retry "gate failed" ATTEMPT=3 TEST_RESULT=failure GATE_OUTCOME=failure
verdict_case "verdict: a fourth failed gate blocks" blocked "gate failed" ATTEMPT=4 TEST_RESULT=failure GATE_OUTCOME=failure
verdict_case "verdict: a fourth blocking review blocks" blocked "blocking findings: 1" ATTEMPT=4 BLOCKING=1
verdict_case "verdict: a fourth attempt can still pass" pass "no blocking findings" ATTEMPT=4
verdict_case "verdict: a limit doesn't go back" blocked "usage limit in build" BUILD_AGENT=limit TEST_RESULT=failure GATE_OUTCOME=failure
verdict_case "verdict: an agent failure doesn't go back" blocked "agent failed in review" REVIEW_AGENT=failed BLOCKING=1
verdict_case "verdict: a failed publish doesn't go back" blocked "stopped before the gate: build success, publish failure" \
  PUBLISH_RESULT=failure TEST_RESULT=skipped
verdict_case "verdict: a failed download in build doesn't go back" blocked "stopped before the gate: build failure, publish skipped" \
  BUILD_RESULT=failure PUBLISH_RESULT=skipped TEST_RESULT=skipped
outside="test job failed outside the gate, in checkout or setup"
verdict_case "verdict: a checkout or setup failure doesn't go back" blocked "$outside" TEST_RESULT=failure GATE_OUTCOME=skipped
verdict_case "verdict: a failure after a passed gate doesn't go back" blocked "$outside" TEST_RESULT=failure GATE_OUTCOME=success
verdict_case "verdict: no word from the gate doesn't go back" blocked "$outside" TEST_RESULT=failure GATE_OUTCOME=
verdict_case "verdict: a gate that timed out doesn't go back" blocked "gate did not finish" TEST_RESULT=cancelled
verdict_case "verdict: a skipped gate can't pass" blocked "gate did not finish" TEST_RESULT=skipped
verdict_case "verdict: a clean review can't pass a failed gate" retry "gate failed" TEST_RESULT=failure GATE_OUTCOME=failure BLOCKING=0
verdict_case "verdict: no count blocks" blocked "review gave no count" BLOCKING=
verdict_case "verdict: a limit of one attempt sends nothing back" blocked "gate failed" ATTEMPTS=1 TEST_RESULT=failure GATE_OUTCOME=failure
verdict_case "verdict: nor a blocking review" blocked "blocking findings: 1" ATTEMPTS=1 BLOCKING=1
verdict_case "verdict: a count that isn't a number blocks" blocked "review gave no count" BLOCKING=none
verdict_case "verdict: a skipped review blocks" blocked "stopped before review" REVIEW_RESULT=skipped
verdict_case "verdict: a limit comes before a review" blocked "usage limit in review" REVIEW_AGENT=limit
verdict_case "verdict: a limit in the Builder blocks" blocked "usage limit in build" BUILD_AGENT=limit
verdict_case "verdict: an agent failure blocks" blocked "agent failed in build" BUILD_AGENT=failed
verdict_case "verdict: invalid review output blocks" blocked "invalid review output" REVIEW_AGENT=invalid
verdict_case "verdict: an agent reporting ok changes nothing" blocked "stopped before review" \
  REVIEW_AGENT=ok REVIEW_RESULT=failure
verdict_case "verdict: stats that aren't JSON change nothing" pass "no blocking findings" \
  'BUILD_STATS=not json' 'REVIEW_STATS={'
verdict_case "verdict: stats are recorded" pass "no blocking findings" \
  'BUILD_STATS={"turns":17}' 'REVIEW_STATS={"turns":8}'
if [ "$(sed -n 's/^record=//p' <<<"$out" | jq -c '[.attempt, .verdict, .agents.build.turns, .agents.review.turns, .jobs.test, .blocking]')" = '[1,"pass",17,8,"success",0]' ]; then
  record PASS "verdict: the attempt's record holds numbers and fixed text"
else
  record FAIL "verdict: the attempt's record holds numbers and fixed text" "$out"
fi
mkdir "$tmp/no-attempts"
cp "$root/team/verdict.sh" "$tmp/no-attempts/"
jq 'del(.limits.attempts)' "$real_config" >"$tmp/no-attempts/config.json"
code=0
out=$(ATTEMPT=1 "$tmp/no-attempts/verdict.sh" decide "$tmp/verdict-in" 2>&1) || code=$?
expect_fail "verdict: a config with no attempts limit fails" "no attempts limit"
code=0
out=$("$root/team/verdict.sh" decide "$tmp/no-such-dir" 2>&1) || code=$?
expect_fail "verdict: a missing directory fails" "usage:"
code=0
out=$("$root/team/verdict.sh" 2>&1) || code=$?
expect_fail "verdict.sh with no command fails" "usage:"

# What a retry's Builder is told. It's agent-made data, so only structure gets through.
fb=$tmp/feedback
mkdir -p "$fb/record-gate-1" "$fb/record-review-1"
gate_log=$fb/record-gate-1/gate-1.log
review_json=$fb/record-review-1/review-1.json

feedback_run() { # [VAR=value...] Sets $code, $out and $feedback.
  code=0
  out=$(env ATTEMPT=1 BUILD_RESULT=success PUBLISH_RESULT=success "$@" "$root/team/verdict.sh" decide "$fb" 2>&1) || code=$?
  feedback=$(sed -n 's/^feedback=//p' <<<"$out")
}

gate_failed() { feedback_run TEST_RESULT=failure GATE_OUTCOME=failure "$@"; }
review_blocked() { feedback_run TEST_RESULT=success GATE_OUTCOME=success REVIEW_RESULT=success BLOCKING=1 "$@"; }

feedback_is() { # <name> <jq filter that must be true of the feedback>
  if [ "$code" -eq 0 ] && jq -e "$2" <<<"$feedback" >/dev/null 2>&1; then
    record PASS "$1"
  else
    record FAIL "$1" "exit $code: $out"
  fi
}

printf '==> frozen paths\n==> npm run lint\n\033[31mthe lint error\033[0m\nGATE FAIL: project command failed: npm run lint\n' >"$gate_log"
gate_failed
feedback_is "feedback: names the failed gate step, with its output" \
  '.source == "gate" and .step == "npm run lint" and (.output | test("the lint error")) and (.output | test("\u001b") | not)'
feedback_is "feedback: carries only structured fields" 'keys == ["findings", "output", "source", "step", "withheld"] and .withheld == false'
if [ "$(wc -l <<<"$out" | tr -d ' ')" -eq 4 ]; then
  record PASS "feedback: stays on one output line"
else
  record FAIL "feedback: stays on one output line" "$out"
fi

{
  head -c 20000 /dev/zero | tr '\0' 'x'
  printf '\n==> npm run lint\nthe last line\n'
} >"$gate_log"
gate_failed
max=$(jq -r .limits.feedback_max_bytes "$real_config")
feedback_is "feedback: output is trimmed to the end of the log" \
  "(.output | length) <= $max and (.output | test(\"the last line\"))"

printf '==> anything PR code printed\nGATE FAIL: x\n' >"$gate_log"
gate_failed
feedback_is "feedback: a step the gate doesn't have reads as unknown" '.step == "unknown"'

printf '==> npm run lint\nTHE-SECRET\n' >"$gate_log"
SHIM_MATCH=THE-SECRET gate_failed
feedback_is "feedback: output with a hit is withheld, and the step stays" \
  '.step == "npm run lint" and .withheld == true and .output == ""'
if [[ $out != *THE-SECRET* ]]; then
  record PASS "feedback: nothing of a hit gets through"
else
  record FAIL "feedback: nothing of a hit gets through" "$out"
fi

rm -f "$gate_log"
echo 'a forged log' >"$fb/gate-1.log"
echo 'another forged log' >"$fb/record-review-1/gate-1.log"
gate_failed
feedback_is "feedback: a log anywhere but its expected path is ignored" '.step == "unknown" and .output == "" and .withheld == true'

echo '{"works":{"verdict":"pass","checked":"the passing note"},"good":{"verdict":"fail","checked":"the failing note"},"blocking":[{"file":"a.ts","problem":"the problem","evidence":"e"}]}' >"$review_json"
review_blocked
feedback_is "feedback: gives the Reviewer's findings, and any failed verdict" \
  '.source == "review" and (.findings | test("a.ts: the problem")) and (.findings | test("good failed: the failing note"))'
feedback_is "feedback: leaves out what passed" '(.findings | test("the passing note") | not)'
SHIM_MATCH='the problem' review_blocked
feedback_is "feedback: findings with a hit are withheld" '.source == "review" and .withheld == true and .findings == ""'
jq '.blocking = [range(500) | {file: "a.ts", problem: "a long problem", evidence: "long evidence"}]' "$review_json" >"$fb/many.json"
mv "$fb/many.json" "$review_json"
review_blocked
feedback_is "feedback: findings are capped" "(.findings | length) <= $max"
rm -f "$review_json"
review_blocked
feedback_is "feedback: no findings still reach the Builder" '.source == "review" and .withheld == true'

echo '==> npm run lint' >"$gate_log"
gate_failed 'FEEDBACK={"source":"review","findings":"the earlier finding"}'
feedback_is "feedback: a failed gate keeps earlier findings for the next review" '.source == "gate" and .findings == "the earlier finding"'

feedback_run TEST_RESULT=success GATE_OUTCOME=success REVIEW_RESULT=success BLOCKING=0
if [ "$code" -eq 0 ] && [ -z "$feedback" ] && [[ $out == *"verdict=pass"* ]]; then
  record PASS "feedback: there's none unless the run goes back"
else
  record FAIL "feedback: there's none unless the run goes back" "$out"
fi

# `retry` means feedback is ready, so a failure building it publishes nothing.
mkdir "$tmp/no-feedback"
cp "$root/team/verdict.sh" "$root/team/scan.sh" "$tmp/no-feedback/"
jq 'del(.limits.feedback_max_bytes)' "$real_config" >"$tmp/no-feedback/config.json"
code=0
out=$(ATTEMPT=1 PUBLISH_RESULT=success TEST_RESULT=failure GATE_OUTCOME=failure "$tmp/no-feedback/verdict.sh" decide "$fb" 2>&1) || code=$?
if [ "$code" -ne 0 ] && [[ $out != *"verdict="* ]] && [[ $out != *"record="* ]]; then
  record PASS "feedback: a failure building it publishes no verdict"
else
  record FAIL "feedback: a failure building it publishes no verdict" "exit $code: $out"
fi

# A whole run with stand-ins for the jobs: the real stub, stage, gate and verdict, in
# the order attempt.yml runs them. Every job starts from a fresh checkout, of P except
# for the gate's. The spec's target has to exist, which is what the stub's test checks.
jq --arg check 'test -e "$(sed -n "s/^const target = \"\(.*\)\";$/\1/p" team/specs/9/stub.test.ts)"' \
  '.install = "true" | .commands = [$check]' "$real_config" >"$tmp/loop.json"

loop_stub() { # <dir> <role> [VAR=value...] Runs the stub in <dir> for $loop_scenario.
  local dir=$1 role=$2
  shift 2
  (cd "$dir" && env SCENARIO="$loop_scenario" RUN_ID=9 ATTEMPT="$attempt" MODE="$loop_mode" "$@" "$root/team/stub.sh" "$role")
}

loop_attempt() { # Runs $attempt from $loop_p. Sets $loop_verdict.
  local tree=$tmp/loop-tree in=$tmp/loop-in publish=success test=skipped review=skipped blocking="" decision limit=""
  if [ "$loop_mode" = team ]; then
    rm -rf "${tmp:?}/loop-tree"
    mkdir "$tree"
    git -C "$repo" archive "$loop_p" | tar -x -C "$tree"
    [ "$attempt" -eq 1 ] || printf '%s\n' "$loop_feedback" >"$tree/team-feedback.txt"
    loop_stub "$tree" build
    [ ! -e "$tree/team-feedback.txt" ] || mv "$tree/team-feedback.txt" "$tmp/loop-fed-back"
  fi

  rm -rf "${tmp:?}/loop-publish" "${tmp:?}/loop-gate" "${tmp:?}/loop-review"
  git clone -q "$repo" "$tmp/loop-publish"
  git -C "$tmp/loop-publish" checkout -q "$loop_p"
  (cd "$tmp/loop-publish" && "$root/team/scan.sh" stage "$tree") >/dev/null 2>&1
  sha=$(cd "$tmp/loop-publish" && "$root/team/scan.sh" commit-on "$loop_head" "attempt $attempt" 2>/dev/null) || publish=failure

  if [ "$publish" = success ]; then
    git -C "$tmp/loop-publish" push -q origin "$sha:refs/heads/run"
    loop_head=$sha
    git clone -q "$repo" "$tmp/loop-gate"
    git -C "$tmp/loop-gate" checkout -q "$sha"
    run_gate "$tmp/loop-gate" "$loop_p" "$sha" "$tmp/loop.json"
    mkdir "$in/record-gate-$attempt" "$in/record-review-$attempt"
    printf '%s\n' "$out" >"$in/record-gate-$attempt/gate-$attempt.log"
    if [ "$code" -eq 0 ]; then
      test=success
      mkdir "$tmp/loop-review"
      (cd "$tmp/loop-review" && FEEDBACK=$loop_feedback GOAL=x RUN_ID=9 "$root/team/agent.sh" prep review >/dev/null)
      : >"$tmp/loop-output"
      loop_stub "$tmp/loop-review" review GITHUB_OUTPUT="$tmp/loop-output" RUNNER_TEMP="$tmp/loop-temp"
      blocking=$(sed -n 's/^blocking=//p' "$tmp/loop-output")
      cp "$tmp/loop-temp/record/review-$attempt.json" "$in/record-review-$attempt/"
      review=success
    else
      test=failure
    fi
  fi

  [ "$loop_mode" = team ] || limit=1
  decision=$(env ATTEMPT="$attempt" ATTEMPTS="$limit" BUILD_RESULT=success PUBLISH_RESULT="$publish" \
    TEST_RESULT="$test" GATE_OUTCOME="$test" REVIEW_RESULT="$review" BLOCKING="$blocking" FEEDBACK="$loop_feedback" \
    "$root/team/verdict.sh" decide "$in")
  loop_verdict=$(sed -n 's/^verdict=//p' <<<"$decision")
  loop_feedback=$(sed -n 's/^feedback=//p' <<<"$decision")
  loop_records="$loop_records$(sed -n 's/^record=//p' <<<"$decision")"$'\n'
}

loop_run() { # <scenario> [mode] Sets $loop_verdicts, and $repo and $sha at the end of the run.
  loop_scenario=$1
  loop_mode=${2:-team}
  attempt=1
  loop_verdicts=""
  loop_records=""
  loop_feedback=""
  rm -rf "${tmp:?}/loop-in" "${tmp:?}/loop-tree"
  mkdir "$tmp/loop-in" "$tmp/loop-tree"
  new_case
  git -C "$repo" archive HEAD | tar -x -C "$tmp/loop-tree"
  loop_stub "$tmp/loop-tree" lead
  if [ "$loop_mode" = solo ]; then
    (cd "$repo" && "$root/team/scan.sh" stage "$tmp/loop-tree" team/specs/9) >/dev/null 2>&1
  else
    (cd "$repo" && "$root/team/scan.sh" stage "$tmp/loop-tree") >/dev/null 2>&1
  fi
  git -C "$repo" commit -qm "P"
  git -C "$repo" reset -q --hard
  loop_p=$(git -C "$repo" rev-parse HEAD)
  git -C "$repo" branch run
  loop_head=$loop_p
  while :; do
    loop_attempt
    loop_verdicts="$loop_verdicts$loop_verdict "
    [ "$loop_verdict" = retry ] || break
    attempt=$((attempt + 1))
  done
}

loop_case() { # <scenario> <wanted verdicts>
  loop_run "$1"
  if [ "$loop_verdicts" = "$2 " ]; then
    record PASS "loop: $1 ends $2"
  else
    record FAIL "loop: $1 ends $2" "got: $loop_verdicts"
  fi
}

four_failures="retry retry retry blocked"
loop_case pass "pass"
loop_case impossible "$four_failures"
loop_case retry-fail "$four_failures"
loop_case review-block "$four_failures"
loop_case tamper-test "$four_failures"
loop_case tamper-config "$four_failures"

loop_case retry-same "retry blocked"
if [ "$(jq -rs '.[-1].reason' <<<"$loop_records")" = "stopped before the gate: build success, publish failure" ]; then
  record PASS "loop: a retry that changed nothing ends the run at publish"
else
  record FAIL "loop: a retry that changed nothing ends the run at publish" "$loop_records"
fi

loop_case retry-review "retry pass"
if grep -q 'stub finding' "$tmp/loop-review/previous-findings.txt"; then
  record PASS "loop: the next Reviewer gets the last one's findings"
else
  record FAIL "loop: the next Reviewer gets the last one's findings" "$(cat "$tmp/loop-review/previous-findings.txt")"
fi
if [ "$(jq -rs '.[0].reason' <<<"$loop_records")" = "blocking findings: 1" ]; then
  record PASS "loop: the first attempt's record says why it went back"
else
  record FAIL "loop: the first attempt's record says why it went back" "$loop_records"
fi

loop_case retry-pass "retry pass"
if [ "$(git -C "$repo" rev-parse "run")" = "$sha" ]; then
  record PASS "loop: the branch ends on the last attempt, with no force"
else
  record FAIL "loop: the branch ends on the last attempt, with no force" "$(git -C "$repo" log --oneline run)"
fi
if jq -e '.source == "gate" and (.output | test("project command failed"))' "$tmp/loop-fed-back" >/dev/null; then
  record PASS "loop: the gate's failure reached the next attempt"
else
  record FAIL "loop: the gate's failure reached the next attempt" "$(cat "$tmp/loop-fed-back" 2>/dev/null)"
fi
if git -C "$repo" diff --quiet "$loop_p" "$sha" -- team/specs/9 && git -C "$repo" merge-base --is-ancestor "$loop_p" "$sha"; then
  record PASS "loop: a retry changes neither P nor the spec"
else
  record FAIL "loop: a retry changes neither P nor the spec" "$(git -C "$repo" diff --stat "$loop_p" "$sha")"
fi
if [ "$(git -C "$repo" diff --name-status --no-renames "$loop_p" "$sha" | tr '\t' ' ')" = "A src/lib/team-stub-9.ts" ]; then
  record PASS "loop: nothing of a failed attempt survives in the change"
else
  record FAIL "loop: nothing of a failed attempt survives in the change" "$(git -C "$repo" diff --name-status "$loop_p" "$sha")"
fi
if [ "$(git -C "$repo" rev-list --count "$loop_p..$sha")" -eq 2 ]; then
  record PASS "loop: each attempt is a commit on the last, so the branch only moves forward"
else
  record FAIL "loop: each attempt is a commit on the last, so the branch only moves forward" "$(git -C "$repo" log --oneline)"
fi

# Solo goes through the same pin, stage, gate and review, with one attempt.
solo_case() { # <scenario> <wanted verdicts>
  loop_run "$1" solo
  if [ "$loop_verdicts" = "$2 " ]; then
    record PASS "loop: solo $1 ends $2"
  else
    record FAIL "loop: solo $1 ends $2" "got: $loop_verdicts"
  fi
}

solo_case pass "pass"
if [ "$(git -C "$repo" diff --name-only "$loop_p^" "$loop_p" | sed 's|/[^/]*$||' | sort -u)" = team/specs/9 ] &&
  [ "$(git -C "$repo" diff --name-only "$loop_p" "$sha")" = src/lib/team-stub-9.ts ]; then
  record PASS "loop: solo's P holds only its spec, and its code arrives after"
else
  record FAIL "loop: solo's P holds only its spec, and its code arrives after" "$(git -C "$repo" log --stat --oneline -3 "$sha")"
fi
solo_case impossible "blocked"
solo_case tamper-config "blocked"
solo_case retry-fail "blocked"
solo_case review-block "blocked"
if [ "$(jq -s '.[0].blocking' <<<"$loop_records")" = 1 ] && [ -f "$tmp/loop-in/record-review-1/review-1.json" ]; then
  record PASS "loop: solo's blocking review is recorded for comparison"
else
  record FAIL "loop: solo's blocking review is recorded for comparison" "$loop_records"
fi

# A failed attempt's commit can hold anything, so nothing from it runs in a later job.
# attempt.yml can't run here, so these read it.
attempt_yml=$root/.github/workflows/attempt.yml
if ! grep -qE '(ref|REF): \$\{\{ *inputs\.head' "$attempt_yml"; then
  record PASS "workflow: no job checks out or exports the last attempt"
else
  record FAIL "workflow: no job checks out or exports the last attempt" "$(grep -nE 'inputs\.head' "$attempt_yml")"
fi
if [ "$(grep -c 'REF: ${{ inputs.p }}' "$attempt_yml")" -eq 2 ] && [ "$(grep -c 'REF: ' "$attempt_yml")" -eq 2 ]; then
  record PASS "workflow: both agents in an attempt start from P"
else
  record FAIL "workflow: both agents in an attempt start from P" "$(grep -n 'REF: ' "$attempt_yml")"
fi
if ! grep -q 'feedback-\$' "$attempt_yml" && grep -q 'FEEDBACK: \${{ inputs.feedback }}' "$attempt_yml" &&
  grep -q 'run: printenv FEEDBACK >team-feedback.txt' "$attempt_yml"; then
  record PASS "workflow: feedback reaches the Builder as an input, in one fixed file"
else
  record FAIL "workflow: feedback reaches the Builder as an input, in one fixed file" "$(grep -n -i feedback "$attempt_yml")"
fi
if [ "$(sed -n '/^  verdict:$/,$p' "$attempt_yml" | grep -cE '^      - ')" -eq 3 ] &&
  [ "$(sed -n '/^  verdict:$/,$p' "$attempt_yml" | grep -E '^      - ' | tail -1)" = "      - name: Decide" ]; then
  record PASS "workflow: the verdict comes from the job's last step"
else
  record FAIL "workflow: the verdict comes from the job's last step" "$(sed -n '/^  verdict:$/,$p' "$attempt_yml" | grep -E '^      - ')"
fi

team_yml=$root/.github/workflows/team.yml
if sed -n '/^  test:$/,/^    runs-on:/p' "$attempt_yml" | grep -q "needs.publish.result == 'success'"; then
  record PASS "workflow: the gate runs for solo, and only on what was published"
else
  record FAIL "workflow: the gate runs for solo, and only on what was published" "$(sed -n '/^  test:$/,/^    runs-on:/p' "$attempt_yml")"
fi
solo_minutes=$(RUN_ID=77 GOAL=x "$agent" prep solo | sed -n 's/^minutes=//p')
ceiling=$(sed -n "s/.*timeout-minutes: .*inputs.mode == 'solo' && \([0-9]*\) .*/\1/p" "$team_yml")
if [ -n "$ceiling" ] && [ "$ceiling" -gt "$solo_minutes" ]; then
  record PASS "workflow: the job's ceiling leaves room for solo's own limit"
else
  record FAIL "workflow: the job's ceiling leaves room for solo's own limit" "ceiling $ceiling, limit $solo_minutes"
fi

# The workflow's own shell, run for real. These come straight out of the YAML, so what's
# tested is what runs. gh is a stand-in that can't reach GitHub.
yaml_step() { # <workflow file> <first sed address> <last sed address> Prints a step's run block.
  sed -n "/$2/,/$3/p" "$1" | sed -n '/^        run: |$/,$p' | sed '1d;s/^          //'
}

# The gate's step. Only gate.sh's exit code may decide it.
gate_step=$(yaml_step "$attempt_yml" 'name: Run the gate from main' 'For the run record')
gate_step=$(sed '$d' <<<"$gate_step")
mkdir -p "$tmp/gate-step/gate/team"
cat >"$tmp/gate-step/gate/team/gate.sh" <<'EOF'
#!/bin/sh
echo "==> npm run lint"
if [ -n "${GATE_CHILD:-}" ]; then
  sleep 4 &
fi
exit "${GATE_EXIT:-0}"
EOF
chmod +x "$tmp/gate-step/gate/team/gate.sh"

gate_step_run() { # [VAR=value...] Sets $code, $out and $took.
  rm -rf "${tmp:?}/gate-step/temp"
  mkdir "$tmp/gate-step/temp"
  local started=$SECONDS
  code=0
  out=$(cd "$tmp/gate-step" && env RUNNER_TEMP="$tmp/gate-step/temp" ATTEMPT=1 P=p SHA=s "$@" bash -e -c "$gate_step" 2>&1) || code=$?
  took=$((SECONDS - started))
}

gate_step_run
if [ "$code" -eq 0 ] && [[ $out == *"==> npm run lint"* ]] && grep -q 'npm run lint' "$tmp/gate-step/temp/record/gate-1.log"; then
  record PASS "gate step: passes, prints the output, and keeps it for the record"
else
  record FAIL "gate step: passes, prints the output, and keeps it for the record" "exit $code: $out"
fi
gate_step_run GATE_EXIT=1
if [ "$code" -eq 1 ] && grep -q 'npm run lint' "$tmp/gate-step/temp/record/gate-1.log"; then
  record PASS "gate step: a failed gate fails the step, with its output kept"
else
  record FAIL "gate step: a failed gate fails the step, with its output kept" "exit $code: $out"
fi
gate_step_run GATE_CHILD=1
if [ "$code" -eq 0 ] && [ "$took" -lt 4 ]; then
  record PASS "gate step: a process PR code left running can't hold it up"
else
  record FAIL "gate step: a process PR code left running can't hold it up" "exit $code after ${took}s"
fi

# `finish`, which alone decides what merges.
finish_step=$(yaml_step "$team_yml" 'name: Post team-gate' 'The outcome is settled')
finish_step=$(sed '$d' <<<"$finish_step")
mkdir "$tmp/finish-bin"
cat >"$tmp/finish-bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >>"$FINISH_LOG"
case "$1 $2" in
  "api --method") exit "${POST_EXIT:-0}" ;;
  "pr merge") exit "${MERGE_EXIT:-0}" ;;
  "pr view")
    # Each look gets the next of PR_STATES, and the last one stays.
    echo look >>"$FINISH_LOG.looks"
    set -- ${PR_STATES:-OPEN}
    looks=$(wc -l <"$FINISH_LOG.looks")
    [ "$looks" -lt "$#" ] || looks=$#
    shift $((looks - 1))
    echo "$1"
    ;;
esac
EOF
printf '#!/bin/sh\n' >"$tmp/finish-bin/sleep"
chmod +x "$tmp/finish-bin/gh" "$tmp/finish-bin/sleep"

team_results="lead=success pin=success red=success build=success publish=success test=success review=success"

finish_case() { # <name> <wanted outcome> <wanted blocked_at> <wanted reason> <greens> [VAR=value...]
  local name=$1 outcome=$2 at=$3 reason=$4 greens=$5 got
  shift 5
  : >"$tmp/finish.log"
  : >"$tmp/finish.log.looks"
  : >"$tmp/finish-output"
  code=0
  env PATH="$tmp/finish-bin:$PATH" FINISH_LOG="$tmp/finish.log" GITHUB_OUTPUT="$tmp/finish-output" \
    GITHUB_STEP_SUMMARY="$tmp/finish-summary" GH_REPO=o/r BRANCH=team/run-1 RUN_ID=1 SCENARIO=x HEAD_SHA=abc \
    LEAD_AGENT= MODE= ATTEMPT_RESULT=success REASON= VERDICT= TEST_RESULT= RESULTS= "$@" \
    bash -eo pipefail -c "$finish_step" >/dev/null 2>&1 || code=$?
  got="$(sed -n 's/^outcome=//p' "$tmp/finish-output")|$(sed -n 's/^blocked_at=//p' "$tmp/finish-output")|$(sed -n 's/^reason=//p' "$tmp/finish-output")|$(grep -c 'conclusion=success' "$tmp/finish.log" || true)"
  if [ "$got" = "$outcome|$at|$reason|$greens" ]; then
    record PASS "$name"
  else
    record FAIL "$name" "exit $code: $got"
  fi
}

finish_case "finish: a passed gate and a clean review merge" MERGED "" "no blocking findings" 1 \
  TEST_RESULT=success VERDICT=pass 'REASON=no blocking findings' "RESULTS=$team_results verdict=pass"
finish_case "finish: pass without a passed test job can't merge" BLOCKED test "gate failed" 0 \
  TEST_RESULT=failure VERDICT=pass 'REASON=gate failed' "RESULTS=${team_results/test=success/test=failure} verdict=pass"
finish_case "finish: a blocking review stops at the verdict" BLOCKED verdict "blocking findings: 1" 0 \
  TEST_RESULT=success VERDICT=blocked 'REASON=blocking findings: 1' "RESULTS=$team_results verdict=blocked"
finish_case "finish: a gate that failed stops at test" BLOCKED test "gate failed" 0 \
  TEST_RESULT=failure VERDICT=blocked 'REASON=gate failed' "RESULTS=${team_results/test=success/test=failure} verdict=blocked"
finish_case "finish: solo never merges, however well it went" BLOCKED solo "no blocking findings" 0 \
  MODE=solo TEST_RESULT=success VERDICT=pass 'REASON=no blocking findings' \
  "RESULTS=lead=success pin=success red=success build=skipped publish=success test=success review=success verdict=pass"
if ! grep -q 'pr merge' "$tmp/finish.log" && grep -q 'pr close' "$tmp/finish.log" && grep -q 'conclusion=failure' "$tmp/finish.log"; then
  record PASS "finish: solo fails its check and closes its pull request"
else
  record FAIL "finish: solo fails its check and closes its pull request" "$(cat "$tmp/finish.log")"
fi
finish_case "finish: a solo refusal isn't named after the skipped Builder" BLOCKED solo "gate failed" 0 \
  MODE=solo TEST_RESULT=failure VERDICT=blocked 'REASON=gate failed' \
  "RESULTS=lead=success pin=success red=success build=skipped publish=success test=failure review=skipped verdict=blocked"
finish_case "finish: a solo run that never reached an attempt says where it stopped" BLOCKED red "stopped before any attempt" 0 \
  MODE=solo ATTEMPT_RESULT=skipped "RESULTS=lead=success pin=success red=failure  verdict="
finish_case "finish: the Lead's limit is the reason" BLOCKED lead "usage limit in lead" 0 \
  LEAD_AGENT=limit ATTEMPT_RESULT=skipped "RESULTS=lead=failure pin=skipped red=skipped  verdict="
finish_case "finish: stopping at red gives a reason" BLOCKED red "stopped before any attempt" 0 \
  ATTEMPT_RESULT=skipped "RESULTS=lead=success pin=success red=failure  verdict="
finish_case "finish: no verdict stops there, and says so" BLOCKED verdict "no verdict from the last attempt" 0 \
  TEST_RESULT=success "RESULTS=$team_results verdict="
finish_case "finish: a crash after a retry doesn't reuse the old reason" BLOCKED verdict "no verdict from the last attempt" 0 \
  TEST_RESULT=success VERDICT=retry 'REASON=blocking findings: 1' "RESULTS=$team_results verdict=retry"
finish_case "finish: a refused merge says so, and takes the check back" BLOCKED merge "merge refused" 1 \
  TEST_RESULT=success VERDICT=pass 'REASON=no blocking findings' MERGE_EXIT=1 "RESULTS=$team_results verdict=pass"
if grep -q 'conclusion=failure' "$tmp/finish.log" && [ "$(wc -l <"$tmp/finish.log.looks" | tr -d ' ')" -eq 3 ]; then
  record PASS "finish: it looks three times before calling a merge refused"
else
  record FAIL "finish: it looks three times before calling a merge refused" "$(cat "$tmp/finish.log")"
fi
finish_case "finish: a merge that landed late isn't recorded as blocked" MERGED "" "no blocking findings" 1 \
  TEST_RESULT=success VERDICT=pass 'REASON=no blocking findings' MERGE_EXIT=1 'PR_STATES=OPEN OPEN MERGED' \
  "RESULTS=$team_results verdict=pass"
finish_case "finish: a check that can't be posted stops the merge, and says so" BLOCKED merge "team-gate could not be posted" 1 \
  TEST_RESULT=success VERDICT=pass 'REASON=no blocking findings' POST_EXIT=1 "RESULTS=$team_results verdict=pass"
if ! grep -q 'pr merge' "$tmp/finish.log"; then
  record PASS "finish: no merge is tried without the check"
else
  record FAIL "finish: no merge is tried without the check" "$(cat "$tmp/finish.log")"
fi

# The Reviewer's workspace, from the real step, with stand-ins for gh and the runner.
review_step=$(yaml_step "$attempt_yml" 'name: Prepare the Reviewer' 'name: Reviewer .stub')
review_step=$(sed '$d' <<<"$review_step")
mkdir -p "$tmp/review-step/bin" "$tmp/review-step/temp/main/team/specs/9"
cp -R "$root/team/agent.sh" "$root/team/config.json" "$root/team/review.schema.json" "$root/team/prompts" "$tmp/review-step/temp/main/team/"
echo 'the spec' >"$tmp/review-step/temp/main/team/specs/9/spec.md"
printf '#!/bin/sh\necho "$*" >"$REVIEW_GH_LOG"\necho "the diff"\n' >"$tmp/review-step/bin/gh"
chmod +x "$tmp/review-step/bin/gh"
mkdir "$tmp/review-step/work"
code=0
out=$(cd "$tmp/review-step/work" && env PATH="$tmp/review-step/bin:$PATH" REVIEW_GH_LOG="$tmp/review-step/gh.log" \
  RUNNER_TEMP="$tmp/review-step/temp" GITHUB_OUTPUT="$tmp/review-step/output" GITHUB_REPOSITORY=o/r RUN_ID=9 \
  P=the-p SHA=the-sha GOAL=x FEEDBACK= bash -e -c "$review_step" 2>&1) || code=$?
if [ "$code" -eq 0 ] && [ "$(ls -A "$tmp/review-step/work" | tr '\n' ' ')" = "change.diff goal.md previous-findings.txt spec " ] &&
  [ "$(cat "$tmp/review-step/work/change.diff")" = "the diff" ] && grep -q 'compare/the-p...the-sha' "$tmp/review-step/gh.log"; then
  record PASS "review step: its inputs come from the commits, and there are exactly four"
else
  record FAIL "review step: its inputs come from the commits, and there are exactly four" "exit $code: $out"
fi

# What the shell above can't show.
if ! grep -q 'path: ${{ github.workspace }}' "$attempt_yml" "$team_yml"; then
  record PASS "workflow: no artifact lands in an agent's workspace"
else
  record FAIL "workflow: no artifact lands in an agent's workspace" "$(grep -n 'github.workspace' "$attempt_yml" "$team_yml")"
fi
# download-artifact drops the folder when a pattern matches one artifact, as after any
# failed gate. That emptied the Builder's feedback and lost solo's gate output.
if ! grep -qE 'merge-multiple|pattern: record-' "$team_yml" "$attempt_yml" &&
  grep -q 'gh run download .* --pattern "record-\*-$ATTEMPT"' "$attempt_yml" &&
  grep -q "gh run download .* --pattern 'record-\*'" "$team_yml"; then
  record PASS "workflow: each artifact is downloaded to its own directory"
else
  record FAIL "workflow: each artifact is downloaded to its own directory" "$(grep -nE 'merge-multiple|pattern|gh run download' "$team_yml" "$attempt_yml")"
fi
if sed -n '/^  verdict:$/,/^    steps:$/p' "$attempt_yml" | grep -q 'actions: read' &&
  [ "$(grep -cF 'permissions: { actions: read, contents: write }' "$team_yml")" -eq "$(jq .limits.attempts "$real_config")" ]; then
  record PASS "workflow: verdict can read artifacts, and each attempt's caller allows it"
else
  record FAIL "workflow: verdict can read artifacts, and each attempt's caller allows it" "$(grep -n 'permissions: {' "$team_yml")"
fi
if sed -n '/# The outcome is settled/,/download-artifact/p' "$team_yml" | grep -qF "ref: \${{ needs.pin.outputs.p || needs.lead.outputs.base || 'main' }}"; then
  record PASS "workflow: finish's scripts come from before anything merged"
else
  record FAIL "workflow: finish's scripts come from before anything merged" "$(sed -n '/# The outcome is settled/,/download-artifact/p' "$team_yml")"
fi
if [ "$(grep -cE '^  attempt-[0-9]+:$' "$team_yml")" -eq "$(jq .limits.attempts "$real_config")" ]; then
  record PASS "workflow: as many attempt jobs as limits.attempts"
else
  record FAIL "workflow: as many attempt jobs as limits.attempts" "$(grep -cE '^  attempt-[0-9]+:$' "$team_yml")"
fi
uploads=$(awk '/uses: actions\/upload-artifact/ { n = NR; u = 1 } u && /name: record-/ { print n; u = 0 }' "$attempt_yml" | wc -l | tr -d ' ')
safe=$(awk '/uses: actions\/upload-artifact/ { block = ""; u = 1 } u { block = block $0 "\n" } u && /retention-days/ { if (block ~ /name: record-/ && block ~ /continue-on-error: true/) print; u = 0 }' "$attempt_yml" | wc -l | tr -d ' ')
if [ "$uploads" -eq 2 ] && [ "$safe" -eq 2 ]; then
  record PASS "workflow: a failed record upload can't change a job's result"
else
  record FAIL "workflow: a failed record upload can't change a job's result" "$safe of $uploads"
fi

# The review stand-in has to feed `finish` the same file a real Reviewer does.
loop_scenario=review-block
loop_mode=team
attempt=2
: >"$tmp/loop-output"
rm -rf "${tmp:?}/loop-temp"
loop_stub "$tmp" review GITHUB_OUTPUT="$tmp/loop-output" RUNNER_TEMP="$tmp/loop-temp"
if [ "$(jq '.blocking | length' "$tmp/loop-temp/record/review-2.json")" -eq 1 ]; then
  record PASS "stub: a blocking review writes the file a real one would"
else
  record FAIL "stub: a blocking review writes the file a real one would" "$(cat "$tmp/loop-temp/record/review-2.json")"
fi

# A retry that lost the Reviewer's findings must fail, so the scenario proves delivery.
new_case
code=0
out=$(cd "$repo" && SCENARIO=retry-review RUN_ID=9 ATTEMPT=2 "$root/team/stub.sh" build 2>&1) || code=$?
expect_fail "stub: retry-review fails if the findings didn't arrive" "didn't reach attempt 2"

# So must a retry told only that the gate failed, which is what real runs were getting.
stub_gate_feedback() { # <feedback JSON> Sets $code.
  new_case
  printf '%s\n' "$1" >"$repo/team-feedback.txt"
  code=0
  (cd "$repo" && SCENARIO=retry-pass RUN_ID=9 ATTEMPT=2 "$root/team/stub.sh" build) || code=$?
}
stub_gate_feedback '{"source":"gate","step":"unknown","output":"","findings":"","withheld":true}'
if [ "$code" -eq 0 ] && [ -f "$repo/src/lib/team-stub-9-wrong.ts" ]; then
  record PASS "stub: retry-pass stays wrong if the gate's output didn't arrive"
else
  record FAIL "stub: retry-pass stays wrong if the gate's output didn't arrive" "exit $code"
fi
stub_gate_feedback '{"source":"gate","step":"npm run lint","output":"the failure","findings":"","withheld":false}'
if [ "$code" -eq 0 ] && [ -f "$repo/src/lib/team-stub-9.ts" ]; then
  record PASS "stub: retry-pass acts on the gate's output when it arrives"
else
  record FAIL "stub: retry-pass acts on the gate's output when it arrives" "exit $code"
fi

# The run record. It's public, so what fails the scan stays out, and it says so.
rec=$tmp/record-in
rec_spec=$tmp/record-spec
mkdir -p "$rec/record-gate-1" "$rec/record-gate-2" "$rec/record-review-2" "$rec_spec"
printf 'Run lint\n\033[31mbroken\033[0m\n' >"$rec/record-gate-1/gate-1.log"
echo 'all good' >"$rec/record-gate-2/gate-2.log"
echo '{"works":{"verdict":"pass","checked":"c"},"good":{"verdict":"pass","checked":"c"},"blocking":[],"planted":"x"}' >"$rec/record-review-2/review-2.json"
echo 'the criteria' >"$rec_spec/spec.md"
echo 'the test' >"$rec_spec/a.test.tsx"
echo 'not a spec file' >"$rec_spec/notes.txt"
attempt_records='{"attempt":1,"verdict":"retry","agents":{"build":{"turns":17},"review":null},"planted":"x"}
{"attempt":2,"verdict":"pass","agents":{"build":{"turns":9},"review":{"turns":4}}}
not json'
echo 'the criteria' >"$rec/spec.md"
echo 'the test' >"$rec/a.test.tsx"

record_run() { # [VAR=value...] Writes $tmp/record-out. Sets $code and $out.
  rm -rf "${tmp:?}/record-out"
  code=0
  out=$(env RUN_ID=77 GOAL='Add a link' OUTCOME=MERGED MODE=team SCENARIO= BLOCKED_AT= REASON='no blocking findings' \
    BASE=b P=p HEAD_SHA=h 'LEAD_STATS={"turns":21,"cost_usd":0.1}' STARTED_AT=2026-10-31T10:00:00Z \
    ATTEMPT_RECORDS="$attempt_records" "$@" \
    "$root/team/record.sh" write "$rec" "$tmp/record-out" "$rec_spec" 2>&1) || code=$?
}

record_is() { # <name> <jq filter that must be true of record.json>
  if [ "$code" -eq 0 ] && jq -e "$2" "$tmp/record-out/record.json" >/dev/null 2>&1; then
    record PASS "$1"
  else
    record FAIL "$1" "exit $code: $out $(cat "$tmp/record-out/record.json" 2>/dev/null)"
  fi
}

record_run MODE=solo
record_is "record: a solo run is labelled, and names its one agent" \
  '.mode == "solo" and .agents.solo.turns == 21 and (.agents | has("lead") | not)'
record_run
record_is "record: goal, outcome, reason and who spent what" \
  '.goal == "Add a link" and .outcome == "MERGED" and .reason == "no blocking findings" and .agents.lead.turns == 21 and .mode == "team"'
record_is "record: every attempt, in order, with its agents" \
  '.attempts_run == 2 and .attempts[0].verdict == "retry" and .attempts[0].agents.build.turns == 17 and .attempts[1].agents.review.turns == 4'
record_is "record: keeps only the fields an attempt should have" \
  '(.attempts[0] | has("planted") | not) and (.attempts[0] | keys) == ["agents", "attempt", "blocking", "jobs", "reason", "verdict"]'
record_is "record: duration, and the commits that pin the prompts and spec" \
  '.base == "b" and .p == "p" and .head == "h" and (.duration_seconds | type == "number") and .omitted == []'
if [ "$(cat "$tmp/record-out/gate-1.txt")" = $'Run lint\nbroken' ] && [ -f "$tmp/record-out/gate-2.txt" ] &&
  [ "$(jq -r .works.verdict "$tmp/record-out/review-2.json")" = pass ]; then
  record PASS "record: gate output and the Reviewer's JSON are kept"
else
  record FAIL "record: gate output and the Reviewer's JSON are kept" "$(ls "$tmp/record-out")"
fi

if [ "$(cat "$tmp/record-out/spec/spec.md")" = "the criteria" ] && [ -f "$tmp/record-out/spec/a.test.tsx" ]; then
  record PASS "record: the spec is kept, for when the branch is gone"
else
  record FAIL "record: the spec is kept, for when the branch is gone" "$(ls "$tmp/record-out")"
fi

if [ "$(ls "$tmp/record-out/spec" | tr '\n' ' ')" = "a.test.tsx spec.md " ]; then
  record PASS "record: only the spec and its tests are kept"
else
  record FAIL "record: only the spec and its tests are kept" "$(ls "$tmp/record-out/spec")"
fi

# PR code can upload an artifact, so nothing but expected paths may matter.
wanted_record=$(ls -R "$tmp/record-out")
mkdir -p "$rec/record-evil" "$rec/record-gate-9"
echo 'planted' >"$rec/gate-1.log"
echo 'planted' >"$rec/attempt-1.json"
echo 'planted' >"$rec/record-gate-1/extra.txt"
echo 'planted' >"$rec/record-gate-1/gate-2.log"
echo '{"works":"planted"}' >"$rec/record-evil/review-1.json"
echo 'planted' >"$rec/record-gate-9/gate-9.log"
echo 'planted' >"$rec/spec.md"
record_run
if [ "$(ls -R "$tmp/record-out")" = "$wanted_record" ] && ! grep -rq planted "$tmp/record-out"; then
  record PASS "record: extra files and artifacts have no effect"
else
  record FAIL "record: extra files and artifacts have no effect" "$(ls -R "$tmp/record-out")"
fi
if ! jq -e 'has("planted")' "$tmp/record-out/review-2.json" >/dev/null; then
  record PASS "record: a review keeps only its known fields"
else
  record FAIL "record: a review keeps only its known fields" "$(cat "$tmp/record-out/review-2.json")"
fi
echo 'not json' >"$rec/record-review-2/review-2.json"
record_run
if [ ! -e "$tmp/record-out/review-2.json" ]; then
  record_is "record: a review that isn't one is left out, and it says so" '.omitted[0] | test("review-2.json")'
else
  record FAIL "record: a review that isn't one is left out, and it says so" "$(cat "$tmp/record-out/review-2.json")"
fi
echo '{"works":{"verdict":"pass","checked":"c"},"good":{"verdict":"pass","checked":"c"},"blocking":[]}' >"$rec/record-review-2/review-2.json"

SHIM_MATCH='the criteria' record_run
if [ ! -e "$tmp/record-out/spec/spec.md" ] && [ -f "$tmp/record-out/spec/a.test.tsx" ]; then
  record_is "record: a spec file with a hit is left out, and it says so" '.omitted[0] | test("spec/spec.md")'
else
  record FAIL "record: a spec file with a hit is left out, and it says so" "$(ls "$tmp/record-out/spec" 2>/dev/null)"
fi
record_run 'LEAD_STATS=not json'
record_is "record: stats that aren't JSON still leave a record" '.agents.lead == null and .outcome == "MERGED"'
SHIM_MATCH=broken record_run
if [ ! -e "$tmp/record-out/gate-1.txt" ] && [ -f "$tmp/record-out/gate-2.txt" ]; then
  record_is "record: gate output with a hit is left out, and it says so" \
    '.outcome == "MERGED" and (.omitted | length == 1) and (.omitted[0] | test("gate-1.txt"))'
else
  record FAIL "record: gate output with a hit is left out, and it says so" "$(ls "$tmp/record-out")"
fi
SHIM_MATCH='"works"' record_run
if [ ! -e "$tmp/record-out/review-2.json" ]; then
  record_is "record: a review with a hit is left out, and it says so" '.omitted[0] | test("review-2.json")'
else
  record FAIL "record: a review with a hit is left out, and it says so" "$(ls "$tmp/record-out")"
fi
SHIM_MATCH=THE-SECRET record_run 'GOAL=fix THE-SECRET now'
record_is "record: a goal with a hit is left out, and it says so" \
  '.goal == null and (.omitted | length == 1) and (.omitted[0] | test("goal"))'
SHIM_EXIT=1 record_run
if ! grep -rqE 'Run lint|Add a link' "$tmp/record-out"; then
  record_is "record: with no working scanner, all free text is left out" \
    '.outcome == "MERGED" and .run_id == "77" and (has("goal") | not) and (.omitted | type == "number")'
else
  record FAIL "record: with no working scanner, all free text is left out" "$(cat "$tmp/record-out/record.json")"
fi
SHIM_MATCH='sneaked past' record_run 'BLOCKED_AT=sneaked past' 'SCENARIO=sneaked past'
record_is "record: a hit in the finished record keeps fixed fields, with a count" \
  '.outcome == "MERGED" and .omitted == 1 and (keys - ["attempts_run", "base", "head", "mode", "omitted", "outcome", "p", "run_id"] == [])'
if ! grep -q 'sneaked past' "$tmp/record-out/record.json"; then
  record PASS "record: nothing free-text reaches the fallback"
else
  record FAIL "record: nothing free-text reaches the fallback" "$(cat "$tmp/record-out/record.json")"
fi
mkdir "$tmp/record-empty"
rm -rf "${tmp:?}/record-out"
code=0
out=$(RUN_ID=77 OUTCOME=BLOCKED BLOCKED_AT=red "$root/team/record.sh" write "$tmp/record-empty" "$tmp/record-out" 2>&1) || code=$?
record_is "record: a run with no attempts still gets one" \
  '.outcome == "BLOCKED" and .blocked_at == "red" and .attempts == [] and .attempts_run == 0'
code=0
out=$(OUTCOME=MERGED "$root/team/record.sh" write "$rec" "$tmp/record-out" 2>&1) || code=$?
expect_fail "record: no run ID fails" "RUN_ID is required"
code=0
out=$("$root/team/record.sh" 2>&1) || code=$?
expect_fail "record.sh with no command fails" "usage:"

# Pushing a record, to a bare repo standing in for GitHub.
origin=$tmp/record-origin.git
git init -q --bare "$origin"
git -C "$base" push -q "$origin" HEAD:refs/heads/main

record_push() { # <run id> Clones as `finish` does, then pushes. Sets $code and $out.
  rm -rf "${tmp:?}/record-clone"
  git clone -q --depth=1 --branch main "file://$origin" "$tmp/record-clone"
  code=0
  out=$(RUN_ID=$1 "$root/team/record.sh" push "$tmp/record-out" "$tmp/record-clone" 2>&1) || code=$?
}

record_run
record_push 101
main_before=$(git -C "$origin" rev-parse main)
if [ "$code" -eq 0 ] && [ "$(git -C "$origin" ls-tree -r --name-only team-runs | cut -d/ -f1 | sort -u)" = runs ] &&
  ! git -C "$origin" merge-base main team-runs >/dev/null; then
  record PASS "push: the first record starts team-runs with no history from main"
else
  record FAIL "push: the first record starts team-runs with no history from main" "exit $code: $out"
fi
record_push 102
if [ "$code" -eq 0 ] && git -C "$origin" cat-file -e team-runs:runs/101/record.json &&
  git -C "$origin" cat-file -e team-runs:runs/102/gate-1.txt &&
  [ "$(git -C "$origin" rev-parse main)" = "$main_before" ]; then
  record PASS "push: later records add to team-runs, and main doesn't move"
else
  record FAIL "push: later records add to team-runs, and main doesn't move" "exit $code: $out"
fi
tip=$(git -C "$origin" rev-parse team-runs)
rm -rf "${tmp:?}/record-clone"
git clone -q --depth=1 --branch main "file://$origin" "$tmp/record-clone"
git -C "$tmp/record-clone" remote set-url origin "$tmp/no-such-remote.git"
code=0
out=$(RUN_ID=103 "$root/team/record.sh" push "$tmp/record-out" "$tmp/record-clone" 2>&1) || code=$?
if [ "$code" -ne 0 ] && [ "$(git -C "$origin" rev-parse team-runs)" = "$tip" ]; then
  record PASS "push: a failed push fails only this script, for the step to absorb"
else
  record FAIL "push: a failed push fails only this script, for the step to absorb" "exit $code: $out"
fi
code=0
out=$(RUN_ID=104 "$root/team/record.sh" push "$tmp/no-such-record" "$tmp/record-clone" 2>&1) || code=$?
expect_fail "push: no record fails" "no record in"

# proof.sh, against a stand-in for gh that dispatches nothing. Real runs are for a person
# or a supervising agent, and this only checks how it reads what they leave behind.
mkdir "$tmp/proof-bin"
cat >"$tmp/proof-bin/gh" <<'EOF'
#!/usr/bin/env bash
# Everything goes to files in $PROOF_STATE, and nothing here can reach GitHub.
count=$(cat "$PROOF_STATE/count")
case "$1 $2" in
  "repo view") echo fixture/repo ;;
  "workflow run")
    [ ! -e "$PROOF_STATE/refuse" ] || exit 1
    [ ! -e "$PROOF_STATE/hang" ] || exec sleep 30
    echo "$*" >>"$PROOF_STATE/dispatched"
    [ -e "$PROOF_STATE/no-run" ] || echo $((count + 1)) >"$PROOF_STATE/count"
    ;;
  "run list")
    # What the --jq in a poll leaves: nothing until a newer run shows up.
    case "$*" in
      *select*) [ "$count" -eq 100 ] || echo "$count" ;;
      *) echo "$count" ;;
    esac
    ;;
  "run view") [ -e "$PROOF_STATE/never-ends" ] && echo in_progress || echo completed ;;
  "pr view") cat "$PROOF_STATE/pr" ;;
  api*)
    case "$2" in
      *record.json*) cat "$PROOF_STATE/record" ;;
      *check-runs*) cat "$PROOF_STATE/gate" ;;
      *git/ref*) [ -e "$PROOF_STATE/branch-left" ] ;;
      *gate-1.txt*) [ ! -e "$PROOF_STATE/no-gate-output" ] ;;
    esac
    ;;
esac
EOF
chmod +x "$tmp/proof-bin/gh"
export PROOF_STATE=$tmp/proof-state
mkdir "$PROOF_STATE"

proof_run() { # <record JSON> <team-gate> <PR state> <pattern>
  echo 100 >"$PROOF_STATE/count"
  printf '%s\n' "$1" >"$PROOF_STATE/record"
  echo "$2" >"$PROOF_STATE/gate"
  echo "$3" >"$PROOF_STATE/pr"
  code=0
  out=$(PATH="$tmp/proof-bin:$PATH" PROOF_PAUSE=0 "$root/team/proof.sh" "$4" 2>&1) || code=$?
}

merged='{"mode":"team","outcome":"MERGED","blocked_at":"","attempts_run":2,"attempts":[{"jobs":{"test":"success"}}],"head":"abc"}'
blocked='{"mode":"team","outcome":"BLOCKED","blocked_at":"test","attempts_run":4,"attempts":[{"jobs":{"test":"failure"}}],"head":"abc"}'

proof_run "$merged" success MERGED '^retry-pass '
if [ "$code" -eq 0 ] && [[ $out == "PASS  retry-pass (team): MERGED -, attempts 2, run 101" ]] &&
  grep -qF 'workflow run team.yml --ref main -f goal=Proof scenario: retry-pass -f scenario=retry-pass -f mode=team' "$PROOF_STATE/dispatched"; then
  record PASS "proof: a merge that matches passes"
else
  record FAIL "proof: a merge that matches passes" "exit $code: $out"
fi
proof_run "$blocked" failure CLOSED '^retry-fail '
if [ "$code" -eq 0 ] && [[ $out == "PASS  retry-fail"* ]]; then
  record PASS "proof: a block that matches passes"
else
  record FAIL "proof: a block that matches passes" "exit $code: $out"
fi
proof_run "$merged" success MERGED '^retry-fail '
expect_fail "proof: the wrong outcome fails" "record says: team MERGED"
proof_run "$merged" failure MERGED '^retry-pass '
expect_fail "proof: a merge without a green check fails" "team-gate is failure"
proof_run "$merged" success CLOSED '^retry-pass '
expect_fail "proof: a merge that left the PR closed fails" "PR is CLOSED"
proof_run '' success MERGED '^retry-pass '
expect_fail "proof: no record fails" "record says"
touch "$PROOF_STATE/branch-left"
proof_run "$merged" success MERGED '^retry-pass '
expect_fail "proof: a leftover run branch fails" "run branch is still there"
rm -f "$PROOF_STATE/branch-left"
touch "$PROOF_STATE/no-gate-output"
proof_run "$merged" success MERGED '^retry-pass '
expect_fail "proof: a record with no gate output fails" "no gate output"
rm -f "$PROOF_STATE/no-gate-output"
touch "$PROOF_STATE/refuse"
proof_run "$merged" success MERGED '^retry-pass '
expect_fail "proof: a refused dispatch fails, and doesn't wait" "no run started"
rm -f "$PROOF_STATE/refuse"
touch "$PROOF_STATE/no-run"
proof_run "$merged" success MERGED '^retry-pass '
expect_fail "proof: a run that never appears fails" "no run started"
rm -f "$PROOF_STATE/no-run"
touch "$PROOF_STATE/never-ends"
proof_run "$merged" success MERGED '^retry-pass '
expect_fail "proof: a run that never ends fails" "still not finished"
rm -f "$PROOF_STATE/never-ends"
touch "$PROOF_STATE/hang"
started=$SECONDS
PROOF_GH_LIMIT=1 proof_run "$merged" success MERGED '^retry-pass '
expect_fail "proof: a gh call that hangs is stopped" "no run started"
if [ "$((SECONDS - started))" -lt 20 ]; then
  record PASS "proof: a hung gh call costs its time limit, and no more"
else
  record FAIL "proof: a hung gh call costs its time limit, and no more" "took $((SECONDS - started))s"
fi
rm -f "$PROOF_STATE/hang"
if ! grep -q 'timeout ' "$root/team/proof.sh" && ! grep -nE '(^|[^a-z_])command gh ' "$root/team/proof.sh" | grep -qv '^[0-9]*:  command gh "\$@" &$'; then
  record PASS "proof: every gh call goes through the limit, with nothing macOS lacks"
else
  record FAIL "proof: every gh call goes through the limit, with nothing macOS lacks" "$(grep -n 'command gh\|timeout ' "$root/team/proof.sh")"
fi

# Adding a scenario without a proof is the easy mistake.
missing=""
for scenario in $(sed -n '/^#   *SCENARIO=/,/^set -euo/p' "$root/team/stub.sh" | grep -oE '\b(pass|impossible|tamper-[a-z]+|secret|review-[a-z]+|retry-[a-z]+)\b' | sort -u); do
  grep -qE "^$scenario (team|solo) " "$root/team/proof.sh" || missing="$missing $scenario"
done
if [ -z "$missing" ] && grep -qE '^pass solo ' "$root/team/proof.sh"; then
  record PASS "proof: covers every stub scenario, and solo"
else
  record FAIL "proof: covers every stub scenario, and solo" "missing:$missing"
fi

# Installing gitleaks, with a stand-in for the download.
mkdir -p "$tmp/install/team" "$tmp/install/bin" "$tmp/install/pack"
cp "$root/team/scan.sh" "$tmp/install/team/"
echo fake >"$tmp/install/pack/gitleaks"
tar -czf "$tmp/install/fixture.tar.gz" -C "$tmp/install/pack" gitleaks
cat >"$tmp/install/bin/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >"$CURL_LOG"
cp "$CURL_FIXTURE" "$3"
EOF
chmod +x "$tmp/install/bin/curl"
wanted=$(sha256sum "$tmp/install/fixture.tar.gz" | cut -d' ' -f1)

install_case() { # <sha256> Sets $code and $out.
  rm -rf "$tmp/install/temp"
  mkdir "$tmp/install/temp"
  : >"$tmp/install/path"
  jq --arg sha "$1" '{gitleaks: {version: "9.9.9", sha256: $sha}}' "$real_config" >"$tmp/install/team/config.json"
  code=0
  out=$(PATH="$tmp/install/bin:$PATH" RUNNER_TEMP=$tmp/install/temp GITHUB_PATH=$tmp/install/path \
    CURL_LOG=$tmp/install/curl.log CURL_FIXTURE=$tmp/install/fixture.tar.gz \
    "$tmp/install/team/scan.sh" install 2>&1) || code=$?
}

install_case "$wanted"
if [ "$code" -eq 0 ] && [ -f "$tmp/install/temp/bin/gitleaks" ] &&
  grep -q "$tmp/install/temp/bin" "$tmp/install/path" &&
  grep -q 'v9.9.9/gitleaks_9.9.9_linux_x64.tar.gz' "$tmp/install/curl.log"; then
  record PASS "install: the pinned version, once its checksum matches"
else
  record FAIL "install: the pinned version, once its checksum matches" "exit $code: $out"
fi
install_case 0000000000000000000000000000000000000000000000000000000000000000
if [ "$code" -ne 0 ] && [ ! -e "$tmp/install/temp/bin/gitleaks" ] && [ ! -s "$tmp/install/path" ]; then
  record PASS "install: a bad checksum fails, and installs nothing"
else
  record FAIL "install: a bad checksum fails, and installs nothing" "exit $code: $out"
fi
if [ "$(jq -r .gitleaks.sha256 "$real_config" | wc -c | tr -d ' ')" -eq 65 ]; then
  record PASS "install: the real config pins a full checksum"
else
  record FAIL "install: the real config pins a full checksum" "$(jq -r .gitleaks.sha256 "$real_config")"
fi

echo
echo "$passed passed, $failed failed, $not_run not run"
[ "$failed" -eq 0 ]
