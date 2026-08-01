#!/usr/bin/env bash
# Regression test for bin/worktree-audit root selection.
#
# Desired contract:
#   * WORKTREE_ROOTS set to an existing isolated root -> scan only that root.
#   * WORKTREE_ROOTS set to a nonexistent path -> no scan / no results.
#   * Positional roots override both WORKTREE_ROOTS and defaults.
#
# Regression guarded: when no positional roots are passed, WORKTREE_ROOTS used to
# be additive with the default roots ($HOME/workspace, projects, src, code), so a
# constrained env root still scanned the fake $HOME/workspace and reported its
# worktrees.

set -euo pipefail

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AM_LIB="$REPO_ROOT/lib/common.sh"
WORKTREE_AUDIT="$REPO_ROOT/bin/worktree-audit"

FAKE_HOME=$(mktemp -d /tmp/wtroots_home.XXXXXX)
ISOLATED_ROOT=$(mktemp -d /tmp/wtroots_iso.XXXXXX)
OUT1=$(mktemp /tmp/wtroots_out1.XXXXXX)
OUT2=$(mktemp /tmp/wtroots_out2.XXXXXX)
OUT3=$(mktemp /tmp/wtroots_out3.XXXXXX)

cleanup() {
  rm -rf "$FAKE_HOME" "$ISOLATED_ROOT" "$OUT1" "$OUT2" "$OUT3"
}
trap cleanup EXIT

# Build a repo with one clean, merged linked worktree at $2 on branch $3.
make_repo_with_worktree() {
  local repo_dir="$1" wt_dir="$2" branch="$3" marker="$4"
  mkdir -p "$repo_dir"
  cd "$repo_dir"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  printf 'main\n' > main.txt
  git add main.txt
  git commit -q -m 'init'
  git branch -M main
  git checkout -q -b "$branch"
  printf '%s\n' "$marker" > "$marker.txt"
  git add "$marker.txt"
  git commit -q -m 'feature'
  git checkout -q main
  git merge -q --no-ff "$branch" -m 'merge'
  git worktree add -q "$wt_dir" "$branch"
}

CONTROL_REPO="$FAKE_HOME/workspace/control-repo"
CONTROL_WT="$FAKE_HOME/workspace/control-wt"
EXPECTED_REPO="$ISOLATED_ROOT/expected-repo"
EXPECTED_WT="$ISOLATED_ROOT/expected-wt"

make_repo_with_worktree "$CONTROL_REPO" "$CONTROL_WT" control-branch controlmarker
make_repo_with_worktree "$EXPECTED_REPO" "$EXPECTED_WT" expected-branch expectedmarker

run_audit() {
  local wt_roots="$1" out="$2"
  shift 2
  HOME="$FAKE_HOME" AM_LIB="$AM_LIB" WORKTREE_ROOTS="$wt_roots" "$WORKTREE_AUDIT" "$@" > "$out" 2>&1
}

show() {
  cat "$1"
}

failed=0

echo "== Case 1: WORKTREE_ROOTS points to existing isolated root =="
run_audit "$ISOLATED_ROOT" "$OUT1"
if ! grep -qF "expected-wt" "$OUT1"; then
  echo "FAIL: expected isolated worktree was not found (fixture sanity)"
  show "$OUT1"
  failed=1
elif grep -qF "control-wt" "$OUT1"; then
  echo "FAIL: control worktree under fake \$HOME/workspace leaked into scan"
  show "$OUT1"
  failed=1
else
  echo "ok"
fi

echo "== Case 2: WORKTREE_ROOTS points to a nonexistent path =="
run_audit "$ISOLATED_ROOT/this-does-not-exist" "$OUT2"
if ! grep -qF "No repos with linked worktrees under: $ISOLATED_ROOT/this-does-not-exist" "$OUT2"; then
  echo "FAIL: nonexistent WORKTREE_ROOTS did not report an empty scan"
  show "$OUT2"
  failed=1
elif grep -qF '══' "$OUT2"; then
  echo "FAIL: nonexistent WORKTREE_ROOTS still produced a repo header"
  show "$OUT2"
  failed=1
else
  echo "ok"
fi

echo "== Case 3: Positional root overrides WORKTREE_ROOTS =="
run_audit "$FAKE_HOME/workspace" "$OUT3" "$ISOLATED_ROOT"
if ! grep -qF "expected-wt" "$OUT3"; then
  echo "FAIL: positional isolated worktree was not found"
  show "$OUT3"
  failed=1
elif grep -qF "control-wt" "$OUT3"; then
  echo "FAIL: env-based control root leaked despite positional override"
  show "$OUT3"
  failed=1
else
  echo "ok"
fi

if [ "$failed" -ne 0 ]; then
  exit 1
fi

echo "PASS"
