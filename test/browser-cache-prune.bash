#!/usr/bin/env bash
# Tests for the reference-aware browser cache prune in lib/common.sh.
#
# The bug this guards against: `rm -rf ms-playwright` in the safe tier deleted
# a pinned ~560 MB binary that does not rebuild on demand, so the next agent
# run re-downloaded it. These tests assert a pinned revision survives and only
# superseded ones go.
#
# Run: bash test/browser-cache-prune.bash   (exits non-zero on failure)

set -uo pipefail

# Resolve lib/common.sh relative to this script.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AM_TOOL=browser-cache-prune-test
# shellcheck source=/dev/null
. "$HERE/../lib/common.sh"

FAILS=0
pass(){ printf '  ok   %s\n' "$1"; }
fail(){ printf '  FAIL %s\n' "$1"; FAILS=$((FAILS + 1)); }

# Build a throwaway cache root that mimics a real ms-playwright layout:
#   <root>/.links/<sha>            -> path to a playwright-core package dir
#   <root>/<name>-<rev>/           -> a revision dir
new_fixture(){
  local root="$1"
  rm -rf "$root"; mkdir -p "$root/.links"
  local pkg="$root/fake-playwright-core"
  mkdir -p "$pkg"
  cat > "$pkg/browsers.json" <<'JSON'
{"browsers":[
 {"name":"chromium","revision":"1243","installByDefault":true,"browserVersion":"153.0.8010.12"},
 {"name":"chromium-headless-shell","revision":"1243","installByDefault":true},
 {"name":"firefox","revision":"1543","installByDefault":true}
]}
JSON
  printf '%s\n' "$pkg" > "$root/.links/deadbeef"
  local n
  for n in chromium-1243 chromium_headless_shell-1243 firefox-1543 \
           chromium-1234 chromium_headless_shell-1234 chromium-1233; do
    mkdir -p "$root/$n"; head -c 2048 /dev/zero > "$root/$n/blob"
  done
  # Distinct, explicit mtimes so "newest" is deterministic rather than a tie
  # broken by readdir order: 1234 is newer than 1233.
  touch -t 202409010000 "$root/chromium-1234"
  touch -t 202406010000 "$root/chromium_headless_shell-1234"
  touch -t 202401010000 "$root/chromium-1233"
}

# ── 1. pinned revisions survive; superseded ones are reaped ─────────────────
FIX=/tmp/am-browser-prune-test
new_fixture "$FIX"
out="$(AM_TOOL=t bash -c ". '$HERE/../lib/common.sh'; BROWSER_KEEP_NEWEST=0; am_browser_cache_prune '$FIX' 0 am_default_emit")"

for pinned in chromium-1243 chromium_headless_shell-1243 firefox-1543; do
  if [ -d "$FIX/$pinned" ]; then pass "pinned $pinned survived"; else fail "pinned $pinned was deleted"; fi
done
for stale in chromium-1234 chromium_headless_shell-1234; do
  if [ -d "$FIX/$stale" ]; then fail "superseded $stale should have been removed"; else pass "superseded $stale removed"; fi
done
# The json name uses hyphens, the dir uses underscores; a naive compare deletes
# the pinned shell. Assert the shell specifically is reported as pinned.
case "$out" in
  *"chromium_headless_shell r1243 kept — pinned"*) pass "hyphen/underscore name normalised" ;;
  *) fail "headless shell r1243 not recognised as pinned (name normalisation)"; printf '%s\n' "$out" ;;
esac

# ── 2. keep-newest margin protects an unreferenced revision ─────────────────
new_fixture "$FIX"
AM_TOOL=t bash -c ". '$HERE/../lib/common.sh'; BROWSER_KEEP_NEWEST=1; am_browser_cache_prune '$FIX' 0 am_default_emit" >/dev/null
# 1234 is the newest unreferenced revision (Sep mtime vs 1233's Jan), so the
# rollback margin must keep it while older unreferenced ones go.
if [ -d "$FIX/chromium-1234" ]; then pass "newest unreferenced revision kept (rollback margin)"; else fail "rollback margin not honoured"; fi
if [ -d "$FIX/chromium-1233" ]; then fail "older unreferenced revision should have been removed"; else pass "older unreferenced revision removed"; fi

# ── 3. dry run deletes nothing ──────────────────────────────────────────────
new_fixture "$FIX"
AM_TOOL=t bash -c ". '$HERE/../lib/common.sh'; BROWSER_KEEP_NEWEST=0; am_browser_cache_prune '$FIX' 1 am_default_emit" >/dev/null
if [ -d "$FIX/chromium-1234" ]; then pass "dry run removed nothing"; else fail "dry run deleted a revision"; fi

# ── 4. a dead .links pointer contributes no pins (deleted package) ──────────
new_fixture "$FIX"
printf '%s\n' "$FIX/gone-playwright-core" > "$FIX/.links/deadbeef2"
AM_TOOL=t bash -c ". '$HERE/../lib/common.sh'; BROWSER_KEEP_NEWEST=0; am_browser_cache_prune '$FIX' 1 am_default_emit" >/dev/null
# Still pinned by the live link, so nothing may be described as removable.
if [ -d "$FIX/chromium-1243" ]; then pass "live link still pins after a stale link is added"; else fail "stale link caused a pinned revision to be removed"; fi

# ── 5. missing cache root is a no-op, not an error ──────────────────────────
AM_TOOL=t bash -c ". '$HERE/../lib/common.sh'; am_browser_cache_prune '$FIX/does-not-exist' 0 am_default_emit" >/dev/null 2>&1 \
  && pass "missing cache root is a clean no-op" || fail "missing cache root errored"

rm -rf "$FIX"
printf '\n%s\n' "$([ "$FAILS" -eq 0 ] && echo 'all browser-cache-prune tests passed' || echo "$FAILS test(s) failed")"
exit "$([ "$FAILS" -eq 0 ] && echo 0 || echo 1)"
