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
| **Reclaim** | `am_reclaim_caches <dry> <emit_fn>` — the safe tier, identical on both platforms, with a per-platform tail |
| **Tools** | `bin/worktree-audit` — genuinely platform-independent, so it lives here and both repos vendor it rather than forking copies that drift |
| **Delegation** | `am_suggest_session_cleanup` — defers agent-transcript cleanup to `agent-session-kill` rather than half-reimplementing it |

## Design rule

Everything here is **safe by construction or read-only.** The reclaim helper only
touches package-manager caches that the owning tool rebuilds on demand — `pnpm`/`uv`
prune only *unreferenced* packages, npm's `_cacache` is a re-download cache, installed
`node_modules` are never touched. Anything requiring *evidence* before deletion stays
in the consuming tool, where the platform-specific proof lives.

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
