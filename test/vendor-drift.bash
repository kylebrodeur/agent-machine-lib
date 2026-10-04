#!/usr/bin/env bash
# Vendor-drift guard: the vendored copies of lib/common.sh in the consumer repos
# must match this repo, and none may reintroduce the blind browser-cache delete.
#
# Why: consumers vendor (not submodule) this file, so a stale copy silently
# keeps the old `rm -rf ms-playwright` behaviour — deleting a pinned browser
# whose bytes the next test run has to download again.
#
# Run: bash test/vendor-drift.bash

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
FAILS=0
pass(){ printf '  ok   %s\n' "$1"; }
fail(){ printf '  FAIL %s\n' "$1"; FAILS=$((FAILS + 1)); }

# Detects an actual reclaim action on the Playwright cache (assignment + delete
# on one logical line), not the prose in the comments that explains why it was
# removed. Written as a pattern so a reintroduction fails CI.
_has_blind_delete(){
  grep -qE '(^|[[:space:]])(d|dir)=.*ms-playwright.*(&&|;).*(rm -rf|rm -r )' "$1"
}

# 1. The library itself must not contain the destructive pattern.
if _has_blind_delete "$REPO/lib/common.sh"; then
  fail "lib/common.sh still deletes the whole Playwright cache"
else
  pass "lib/common.sh does not rm -rf the Playwright cache"
fi

# 2. Consumers must match, byte for byte, and carry the same guarantee.
CONSUMER_ROOT="${CONSUMER_ROOT:-$(dirname "$REPO")}"
found_consumer=0
for name in mac-optimize wsl-optimize; do
  vend="$CONSUMER_ROOT/$name/lib/common.sh"
  [ -f "$vend" ] || { printf '  skip %s (not checked out)\n' "$name"; continue; }
  found_consumer=1
  if cmp -s "$REPO/lib/common.sh" "$vend"; then
    pass "$name vendors current common.sh"
  else
    fail "$name has a DRIFTED common.sh — run: make vendor-lib (in $name)"
  fi
  if _has_blind_delete "$vend"; then
    fail "$name reintroduced the blind ms-playwright delete"
  else
    pass "$name has no blind ms-playwright delete"
  fi
done

# 3. The shared tool must be executable wherever it is vendored.
for name in mac-optimize wsl-optimize; do
  g="$CONSUMER_ROOT/$name/bin/browser-guard"
  [ -f "$g" ] || continue
  [ -x "$g" ] && pass "$name/bin/browser-guard is executable" \
              || fail "$name/bin/browser-guard is not executable"
done

if [ "$found_consumer" -eq 0 ]; then
  printf '  note no consumer checkouts found under %s\n' "$CONSUMER_ROOT"
fi

printf '\n%s\n' "$([ "$FAILS" -eq 0 ] && echo 'vendor-drift guard passed' || echo "$FAILS check(s) failed")"
exit "$([ "$FAILS" -eq 0 ] && echo 0 || echo 1)"
