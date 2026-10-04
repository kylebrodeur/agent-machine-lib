# agent-machine-lib

Shared bash primitives for keeping a machine alive when it runs fleets of AI coding agents.

Ships one shared library and one shared *tool*. Extracted from [`mac-optimize`](https://github.com/kylebrodeur/mac-optimize) and
[`wsl-optimize`](https://github.com/kylebrodeur/wsl-optimize) once the two started
duplicating each other. One file, `lib/common.sh`, no dependencies.

## What's in it

| Group | Functions |
|---|---|
| **Platform** | `am_detect_platform` sets `AM_PLATFORM` to `macos` \| `wsl2` \| `linux`; `am_is_macos`, `am_is_wsl` |
| **Output** | `am_hdr` `am_ok` `am_no` `am_warn` `am_info` `am_dim` `am_row` `am_act` — colour only when stdout is a TTY, so logs stay clean |
| **Sizes** | `am_du_kb` `am_mib` `am_free_kb` `am_mtime` `am_idle_days` (BSD and GNU `stat` take different flags and reject each other's; `find -printf` is GNU-only and silently returns nothing on macOS) (POSIX `df -Pk`; BSD and GNU `df` agree on nothing else) |
| **Guards** | `am_in_use` (lsof; treats "no lsof" as in-use — a deletion guard must not guess), `am_allowlisted`, `am_stale_entries` (age gate **and** keep-newest-N) |
| **Browsers** | `am_browser_cache_prune` (superseded browser revisions only — never one an installed `playwright-core` pins), `am_browser_cache_refs`, `am_browsers_json_revisions` |
| **Reclaim** | `am_reclaim_caches <dry> <emit_fn>` — the safe tier, identical on both platforms, with a per-platform tail |
| **Tools** | `bin/worktree-audit` — genuinely platform-independent, so it lives here and both repos vendor it rather than forking copies that drift. `bin/browser-guard` — the same argument: one shared browser directory instead of a ~560 MB download per repo. |
| **Delegation** | `am_suggest_session_cleanup` — defers agent-transcript cleanup to `agent-session-kill` rather than half-reimplementing it |

## Design rule

Everything here is **safe by construction or read-only.** The reclaim helper only
touches package-manager caches that the owning tool rebuilds on demand — `pnpm`/`uv`
prune only *unreferenced* packages, npm's `_cacache` is a re-download cache, installed
`node_modules` are never touched. Anything requiring *evidence* before deletion stays
in the consuming tool, where the platform-specific proof lives.

**Browser caches are the exception, and are why this rule is written down.** A
Playwright browser is a pinned *binary*, not a rebuildable cache: deleting it costs
back every byte it reclaims, because the next run re-downloads it. An earlier
version of this file did `rm -rf ms-playwright` anyway, and a weekly reclaim plus
the resulting re-downloads became a standing cost. `am_browser_cache_prune` now
deletes only *superseded* revisions — never one an installed `playwright-core`
pins (read from its `.links` map), never one in use, and it keeps newest-N as a
rollback margin. `bin/browser-guard` goes further and makes one directory serve
every repo, so the bytes exist once.

## Use

Vendored, not submoduled — consumers promise zero dependencies, so the file is
committed into each repo and refreshed deliberately:

```bash
make vendor-lib     # in mac-optimize / wsl-optimize
```

Then:

```bash
AM_TOOL=mytool
. "$(dirname "$0")/../lib/common.sh"

am_hdr "Caches"
am_reclaim_caches 0 my_emit_fn
```

Browser hygiene (one shared browser for every repo):

```bash
browser-guard status        # what is shared, pinned, reclaimable
browser-guard adopt         # materialise every revision the repos pin
browser-guard env           # the shell exports that wire it up
browser-guard gc --dry-run  # superseded revisions, agent-browser orphans
```

## The family

Part of a small family of tools for keeping machines healthy when they run fleets of AI coding agents:

| Repo | What |
|---|---|
| **agent-machine-lib** (this) | The shared bash primitives — platform detection, deletion guards, safe-tier cache reclaim — plus the shared `worktree-audit` tool. Vendored into the two optimize repos. |
| [`mac-optimize`](https://github.com/kylebrodeur/mac-optimize) | macOS disk/memory/shell hygiene — safe reclaim, git-worktree audit, Codex-session backup, and launchd watchers. |
| [`wsl-optimize`](https://github.com/kylebrodeur/wsl-optimize) | The WSL2 sibling — OOM forensics, cgroup bounds, and `vhdx` compaction. |
| [`agent-session-kill`](https://github.com/kylebrodeur/agent-session-kill) | Node/npm TUI that cleans agent session remnants; the optimize tools delegate transcript cleanup to it. |

## License

MIT © 2026 Kyle Brodeur
