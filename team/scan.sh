#!/usr/bin/env bash
# Trusted. The one place gitleaks is installed and run, and an agent's tree is
# staged. Run it from a checkout no agent has touched.
#
#   scan.sh install                 The pinned, checksummed gitleaks, on GITHUB_PATH.
#   scan.sh stage <tree>            Stage a tree in this checkout, then scan the change.
#   scan.sh commits <repo> <range>  Scan a range of commits.
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
  local tree=${1:-} dir
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
}

# --text so a -diff attribute can't hide a file from `git log -p`.
commits() {
  scan git --log-opts="--text ${2:?a commit range is required}" "${1:?a repo is required}"
}

command=${1:-}
[ "$#" -eq 0 ] || shift
case "$command" in
  install) install ;;
  stage) stage "$@" ;;
  commits) commits "$@" ;;
  *) fail "usage: scan.sh install | scan.sh stage <tree> | scan.sh commits <repo> <range>" ;;
esac
