# Browser-guard — design spec

**Date:** 2026-10-04
**Status:** Draft for review. Root cause found — integration target changed to the `agent-machine-lib` family.
**Author:** session with Kyle

## Headline

The re-download loop is **caused by Kyle's own tooling**. `mac-reclaim` (a
launchd job, weekly Sunday 11:00) calls `am_reclaim_caches`, which contains:

```sh
# agent-machine-lib/lib/common.sh:150  (vendored into mac-optimize + wsl-optimize)
d="$HOME/Library/Caches/ms-playwright"; [ -d "$d" ] && _try "playwright cache" rm -rf "$d"
```

That is a blind delete of Playwright's browser cache. Playwright then fails with
`Executable doesn't exist at .../chrome-headless-shell`, and the next agent run
re-runs `npx playwright install chromium` — ~560 MB, over and over.

### Evidence (this machine, 2026-10-04)

| Observation | Value |
|---|---|
| Today | **Sunday** 2026-10-04 |
| `mac-reclaim` last run | **11:00:37**, "freed 1010MB, 21GB free" (free space 11 GB → 21 GB) |
| `ms-playwright/chromium-1243` re-created | **11:05:23** |
| `ms-playwright/chromium-1234` re-created | **11:14:48** |
| launchd jobs installed | `com.mac-optimize.mac-reclaim` (+ diskguard, memguard, codex-backup) |
| Schedule | `StartCalendarInterval` → Sunday, 11:00 |

The 1010 MB "reclaimed" at 11:00 and the browser dirs re-created minutes later
*are the same megabytes.* The tool is paying 560 MB to reclaim 560 MB.

### Why this violates the family's own stated design rule

`agent-machine-lib` documents its safe tier as "caches tools rebuild on demand …
safe *by construction*". The shared tier's other entries honour that: `pnpm store
prune` (unreferenced only), `npm cache verify`, `uv cache prune` — all
*purpose-built* pruners.

Playwright's cache is **not** that. It is a ~560 MB pinned binary that does
**not** rebuild on demand: it hard-fails and demands an explicit
`playwright install`. Blindly `rm -rf`-ing it is the one entry in the safe tier
that breaks the rule the file claims to follow.

## Empirical findings (tested, not assumed)

| # | Question | Result |
|---|---|---|
| 1 | Playwright drive system Chrome? | Yes — `channel:"chrome"` → 154.0.8037.93 |
| 2 | Playwright use agent-browser's Chrome? | Yes — `executablePath` → 153.0.8010.47 |
| 3 | Is Playwright's bundled chromium the same product? | **Yes** — both *Chrome for Testing* 153.x, identical layout |
| 4 | `npm i playwright` auto-download? | **No** |
| 5 | `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1` stops `playwright install`? | **No** — both runs downloaded 580 MB; it only gates the npm postinstall hook |
| 6 | `playwright install` when browser already present? | **No-op** (1 s) — this is why the shared dir suffices |
| 7 | `PLAYWRIGHT_DOWNLOAD_HOST` as a choke? | Effective — dead port ⇒ install fails, 4 KB written |
| 8 | PATH shim intercepts `npx playwright` in a repo? | **No** — `npx` uses `node_modules/.bin/playwright` |
| 9 | PATH shim intercepts bare `playwright`? | Yes |
| 10 | Custom `PLAYWRIGHT_BROWSERS_PATH` ⇒ ms-playwright untouched? | **Yes** — installs went to the custom path |

Finding **10** is the key lever: point `PLAYWRIGHT_BROWSERS_PATH` at a shared
dir and `ms-playwright` is never populated — so the existing `rm -rf` there
becomes harmless *and* the per-repo vendoring stops.

## Design — family-conformant

### A. Fix the reclaim (the actual bug) — `agent-machine-lib/lib/common.sh`

Replace the blind `rm -rf ms-playwright` with a **reference-aware prune** built
from primitives the lib already has (`am_stale_entries` already implements "age
gate **and** keep-newest-N"):

- Enumerate `<cache>/<browser>-<revision>` dirs.
- Never delete the revision(s) an installed `playwright-core/browsers.json` pins.
- Keep newest-N as rollback margin; delete the rest.
- Same treatment for `puppeteer`/Chrome-for-Testing caches.

Net effect: superseded revisions are still reclaimed (the tool keeps doing its
job) but the pinned, in-use browser survives — so nothing re-downloads.

This is a one-file change; both siblings inherit it via `make vendor-lib`.

### B. One shared browser — the shared dir

`BROWSER_GUARD_ROOT` default `~/.cache/browsers` (**must** be outside
`ms-playwright`, or the weekly job eats it). Set:

- `PLAYWRIGHT_BROWSERS_PATH=$BROWSER_GUARD_ROOT`
- `PUPPETEER_CACHE_DIR=$BROWSER_GUARD_ROOT`, `PUPPETEER_SKIP_DOWNLOAD=1`

Revision dirs are symlinks to a real Chrome for Testing (agent-browser's, per
Kyle's preference), so bytes exist once.

**Headless-shell gap.** Playwright's default headless needs a *second* binary,
`chrome-headless-shell` (~200 MB), which agent-browser does not ship. Verified:
a shared dir with only the full browser fails to launch. Two options (decision
1 below).

### C. Guard tool — `browser-guard`

Shared tool in `agent-machine-lib/bin/`, vendored into both optimize repos
(precedent: `worktree-audit` already lives there and is vendored).

| Subcommand | Job |
|---|---|
| `adopt` | scan repos → collect pinned revisions → materialize one dir each in the shared root |
| `check` | assert the shared root satisfies every pinned revision; non-zero + exact fix on drift |
| `gc` | report/delete superseded dirs (the Layer-A logic, callable standalone) |
| `status` | human summary + bytes |

The `playwright` PATH shim is **demoted** to convenience (finding 8 — it cannot
stop `npx` inside a repo). Real prevention is the env wiring + idempotency.

### D. Consumer fixes

- `uofd-graphics-publishing`: 6 places document
  `PLAYWRIGHT_BROWSERS_PATH=0 npx playwright install chromium` — the flag means
  *vendor into `node_modules`* (confirmed at `coreBundle.js:33120-33122`), the
  per-repo 550 MB duplication. Replace with the shared setting.
- `folia-app`: drop the hardcoded
  `PLAYWRIGHT_BROWSERS_PATH=.../.local-browsers` test command.
- Delete both vendored `.local-browsers` trees (1.1 GB).

## Immediate reclaim (~2.4 GB)

Superseded agent-browser 151/152 (**728 MB**), the duplicate Playwright revision
pair (**~567 MB**), both vendored `.local-browsers` (**1.1 GB**).

## Open decisions

1. **Headless-shell** — ship the shell in the shared dir (works with default
   launch, +200 MB/revision) vs require `channel:"chromium"` (no shell, needs a
   consumer config change) vs both.
2. **Shared root** — `~/.cache/browsers` (neutral, recommended) vs reuse
   `~/.agent-browser/browsers`.
3. **Landing** — change `agent-machine-lib` + the two public optimize repos now,
   or prototype standalone first.

## Scope

- **In:** the `am_reclaim_caches` fix, the shared-dir wiring, `browser-guard`, the
  consumer docs/commands, the immediate reclaim.
- **Out:** replacing Playwright with agent-browser in any test suite; the
  `PLAYWRIGHT_DOWNLOAD_HOST` choke (a separate hardening decision).
