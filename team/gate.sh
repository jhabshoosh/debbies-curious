#!/usr/bin/env bash
# The gate: frozen-path checks, then gitleaks, then project commands.
#
#   gate.sh <candidate-repo> <P> <candidate-sha> <config.json>
#
# Run main's copy of this script and config, never the candidate's. Project
# commands are the first thing to execute candidate code, so a tampered
# package.json is refused before `npm ci` can run it. Only exit 0 passes.
#
# The candidate's files and their contents are rechecked after each project
# command, against what only this process holds, so a test that edits a spec or
# plants a config file at runtime is caught. Git's own view isn't trusted, because
# PR code can make it look away. Tampering at runtime with the test framework, or
# undoing a change before the command ends, isn't caught: PR code shares this
# runner with the gate.
set -euo pipefail

fail() {
  echo "GATE FAIL: $*" >&2
  exit 1
}

# A digest of $files in <dir>.
digest() {
  (cd "$1" && printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 sha256sum -- | sha256sum)
}

# Every path in the checkout that .gitignore at the candidate doesn't cover. That
# file is frozen, and a nested one or git's excludes have no say here.
listing() {
  git -C "$repo" ls-files --cached --others --exclude-from=<(printf '%s\n' "$ignored") |
    LC_ALL=C sort -u
}

# True if <path> matches an entry in <list-file>. Entries are globs, and an
# entry also covers everything below it. In `case`, `*` matches across `/`.
matches() {
  local pattern
  while IFS= read -r pattern; do
    # shellcheck disable=SC2254 # Entries are meant to be globs.
    case "$2" in
      $pattern | $pattern/*) return 0 ;;
    esac
  done <"$1"
  return 1
}

[ "$#" -eq 4 ] || fail "usage: gate.sh <candidate-repo> <P> <candidate-sha> <config.json>"
for arg in "$@"; do
  [ -n "$arg" ] || fail "an input is empty"
done
p=$2
sha=$3
config=$4

for tool in git jq gitleaks; do
  command -v "$tool" >/dev/null || fail "$tool is not installed"
done

[[ $p =~ ^[0-9a-f]{40}$ ]] || fail "P is not a full commit SHA: $p"
[[ $sha =~ ^[0-9a-f]{40}$ ]] || fail "candidate is not a full commit SHA: $sha"
[ -f "$config" ] || fail "config not found: $config"
repo=$(cd "$1" && git rev-parse --show-toplevel) || fail "not a git checkout: $1"

for dir in "$(dirname "$0")" "$(dirname "$config")"; do
  case "$(cd "$dir" && pwd -P)/" in
    "$repo"/*) fail "gate and config must come from main, not the candidate" ;;
  esac
done

[ "$(git -C "$repo" rev-parse HEAD)" = "$sha" ] || fail "checkout is not at the candidate $sha"
[ -z "$(git -C "$repo" status --porcelain)" ] || fail "checkout has uncommitted changes"
git -C "$repo" merge-base --is-ancestor "$p" "$sha" || fail "candidate does not descend from P"
git -C "$repo" rev-parse --verify --quiet "$p^" >/dev/null || fail "P has no parent commit"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

jq -er '.frozen_paths[]' "$config" >"$tmp/frozen" || fail "config has no frozen_paths"
jq -er '.test_paths[]' "$config" >"$tmp/tests" || fail "config has no test_paths"
jq -er '.allowed_paths[]' "$config" >"$tmp/allowed" || fail "config has no allowed_paths"
max_bytes=$(jq -er '.limits.diff_max_bytes' "$config") || fail "config has no diff_max_bytes"
max_line=$(jq -er '.limits.diff_max_line' "$config") || fail "config has no diff_max_line"
jq -er '.install' "$config" >"$tmp/commands" || fail "config has no install"
jq -er '.commands[]' "$config" >>"$tmp/commands" || fail "config has no commands"

echo "==> frozen paths"
git -C "$repo" diff --name-status --no-renames -z "$p" "$sha" >"$tmp/changes"
[ -s "$tmp/changes" ] || fail "no change between P and the candidate"

bad=0
while IFS= read -r -d '' status && IFS= read -r -d '' path; do
  if matches "$tmp/frozen" "$path"; then
    echo "frozen path changed: $path" >&2
    bad=1
  elif [ "$status" != A ] && matches "$tmp/tests" "$path"; then
    echo "existing test changed: $path" >&2
    bad=1
  elif ! matches "$tmp/allowed" "$path"; then
    echo "path not allowed: $path" >&2
    bad=1
  fi
done <"$tmp/changes"
[ "$bad" -eq 0 ] || fail "frozen-path check"

# A symlink could point anywhere, and a gitlink hides its content from the Reviewer.
git -C "$repo" diff --raw --no-renames "$p" "$sha" >"$tmp/raw"
! grep -E '^:[0-9]+ (120000|160000) ' "$tmp/raw" >&2 || fail "the change adds a symlink or a gitlink"

# What one review has to carry. Padding is how a change hides from a reviewer.
echo "==> diff limits"
git -C "$repo" diff --text "$p" "$sha" >"$tmp/diff"
[ "$(wc -c <"$tmp/diff")" -le "$max_bytes" ] || fail "diff is over $max_bytes bytes"
longest=$(LC_ALL=C awk 'length($0) > max { max = length($0) } END { print max + 0 }' "$tmp/diff")
[ "$longest" -le "$max_line" ] || fail "diff has a line over $max_line characters"

# P^ so the scan also covers the Lead's commit.
echo "==> gitleaks"
"$(dirname "$0")/scan.sh" commits "$repo" "$p^..$sha" ||
  fail "gitleaks found a secret or could not run"

mkdir "$tmp/pristine"
git -C "$repo" archive "$sha" | tar -x -C "$tmp/pristine"
files=$(cd "$tmp/pristine" && find . -type f | sed 's|^\./||' | LC_ALL=C sort -u)
pristine=$(digest "$tmp/pristine")
ignored=$(cat "$tmp/pristine/.gitignore")
rm -rf "$tmp/pristine"

while IFS= read -r cmd; do
  echo "==> $cmd"
  (cd "$repo" && bash -euo pipefail -c "$cmd") </dev/null || fail "project command failed: $cmd"
  [ "$(digest "$repo")" = "$pristine" ] && [ "$(listing)" = "$files" ] ||
    fail "project command changed the checkout: $cmd"
done <"$tmp/commands"

echo "GATE PASS: $sha"
