#!/usr/bin/env bash
# Trusted. The one place gitleaks is installed and run, and an agent's tree is
# staged. Run it from a checkout no agent has touched.
#
#   scan.sh install                 The pinned, checksummed gitleaks, on GITHUB_PATH.
#   scan.sh stage <tree> [only]     Stage a tree in this checkout, scan the change, then
#                                   keep only the paths under [only] staged.
#   scan.sh commit-on <parent> <message>
#                                   Commit what's staged on <parent>, and print the SHA.
#   scan.sh commits <repo> <range>  Scan a range of commits.
#   scan.sh text <in> <out> <max>   Clean free text for a public record or an agent.
#                                   Non-zero, and no <out>, unless the scan is clean.
set -euo pipefail

team=$(cd "$(dirname "$0")" && pwd -P)
rules=$team/gitleaks.toml

fail() {
  echo "SCAN FAIL: $*" >&2
  exit 1
}

# gitleaks:allow comments are ignored, and .gitleaks* files are frozen, so a change
# can't exempt itself.
scan() {
  [ -f "$rules" ] || fail "no gitleaks rules at $rules"
  gitleaks "$1" --no-banner --redact --ignore-gitleaks-allow --config "$rules" "${@:2}"
}

install() {
  local version sha256 tarball=$RUNNER_TEMP/gitleaks.tar.gz
  version=$(jq -er .gitleaks.version "$team/config.json")
  sha256=$(jq -er .gitleaks.sha256 "$team/config.json")
  curl -fsSL -o "$tarball" \
    "https://github.com/gitleaks/gitleaks/releases/download/v$version/gitleaks_${version}_linux_x64.tar.gz"
  echo "$sha256  $tarball" | sha256sum -c -
  mkdir -p "$RUNNER_TEMP/bin"
  tar -xzf "$tarball" -C "$RUNNER_TEMP/bin" gitleaks
  echo "$RUNNER_TEMP/bin" >>"$GITHUB_PATH"
}

stage() {
  local tree=${1:-} only=${2:-} dir
  [ -d "$tree" ] || fail "no tree: $tree"
  [ -z "$(find "$tree" -name .git -print -quit)" ] || fail "the tree holds a .git"

  # Claude Code's sandbox leaves an empty file for each path it protects. Only those
  # go: empty, new and on the list. One with content is still refused downstream.
  local path
  while IFS= read -r path; do
    if [ -f "$tree/$path" ] && [ ! -s "$tree/$path" ] &&
      ! git ls-files --error-unmatch -- "$path" >/dev/null 2>&1; then
      rm -f "$tree/$path"
    fi
  done < <(jq -er '.sandbox_placeholders[]' "$team/config.json")

  # Tracked files, then new ones. Only this checkout's .gitignore decides what's
  # ignored, so one an agent wrote can't hide anything. Exec bits stay as they are,
  # because an artifact doesn't keep them.
  git -c core.fileMode=false --work-tree="$tree" add -u
  git --work-tree="$tree" ls-files -z --others --exclude-from=.gitignore |
    git -c advice.addEmptyPathspec=false --work-tree="$tree" \
      add --force --pathspec-file-nul --pathspec-from-file=-

  # This repo is public, so this comes before any push. A text diff, scanned from
  # outside the checkout, so nothing in the tree can exempt the change.
  dir=$(mktemp -d)
  git diff --cached --text -U0 >"$dir/candidate.diff"
  (cd "$dir" && scan dir .)
  rm -rf "$dir"

  if [ -n "$only" ]; then
    git reset -q -- ":(exclude)$only"
  fi
}

# A retry stages over P, because this job runs scripts from its checkout and a failed
# attempt's commit could hold any scripts. The new commit still goes on the last one,
# so the branch only moves forward, with no earlier attempt ever on disk here. A tree
# that matches the last attempt is what failed already, so it ends the run.
commit_on() {
  local parent=${1:-} message=${2:-} tree
  [ -n "$parent" ] && [ -n "$message" ] || fail "commit-on needs <parent> <message>"
  ! git diff --cached --quiet || fail "the change is empty"
  tree=$(git write-tree)
  [ "$tree" != "$(git rev-parse "$parent^{tree}")" ] || fail "the tree matches the last attempt"
  git commit-tree "$tree" -p "$parent" -m "$message"
}

# --text so a -diff attribute can't hide a file from `git log -p`.
commits() {
  scan git --log-opts="--text ${2:?a commit range is required}" "${1:?a repo is required}"
}

# Strip, then scan, then trim. Stripping can join up a split secret, and trimming can
# cut one in half, so the scan has to see what's left after one and before the other.
# <out> stays outside the scanned directory, so nothing in the text can exempt it.
text() {
  local in=${1:-} out=${2:-} max=${3:-} dir code=0
  [ -f "$in" ] || fail "no file: $in"
  [ -n "$out" ] && [[ $max =~ ^[0-9]+$ ]] || fail "text needs <in> <out> <max-bytes>"
  dir=$(mktemp -d)
  mkdir "$dir/scan"
  LC_ALL=C sed $'s/\033\\[[0-9;?]*[A-Za-z]//g' "$in" |
    LC_ALL=C tr -d '\000-\010\013-\037\177' >"$dir/clean"
  # gitleaks `dir` skips a file whose start looks like an application type, such as a
  # log that opens with %PDF-. Some of those marks sit deep in a file, so this fixed
  # line runs past them all, and what's scanned can only read as text.
  { printf 'team scan %040000d\n' 0; cat "$dir/clean"; } >"$dir/scan/candidate.diff"
  (cd "$dir/scan" && scan dir .) || code=$?
  [ "$code" -ne 0 ] || tail -c "$max" "$dir/clean" >"$out"
  rm -rf "${dir:?}"
  return "$code"
}

command=${1:-}
[ "$#" -eq 0 ] || shift
case "$command" in
  install) install ;;
  stage) stage "$@" ;;
  commit-on) commit_on "$@" ;;
  commits) commits "$@" ;;
  text) text "$@" ;;
  *) fail "usage: scan.sh install | stage <tree> [only] | commit-on <parent> <message> | commits <repo> <range> | text <in> <out> <max>" ;;
esac
