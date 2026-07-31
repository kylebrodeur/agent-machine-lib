# agent-machine-lib

Shared bash primitives for keeping a machine alive when it runs fleets of AI coding agents.

Extracted from [`mac-optimize`](https://github.com/kylebrodeur/mac-optimize) and
[`wsl-optimize`](https://github.com/kylebrodeur/wsl-optimize) once the two started
duplicating each other. One file, `lib/common.sh`, no dependencies.

## What's in it

| Group | Functions |
|---|---|
| **Platform** | `am_detect_platform` sets `AM_PLATFORM` to `macos` \| `wsl2` \| `linux`; `am_is_macos`, `am_is_wsl` |
| **Output** | `am_hdr` `am_ok` `am_no` `am_warn` `am_info` `am_dim` `am_row` `am_act` — colour only when stdout is a TTY, so logs stay clean |
| **Sizes** | `am_du_kb` `am_mib` `am_free_kb` (POSIX `df -Pk`; BSD and GNU `df` agree on nothing else) |
| **Guards** | `am_in_use` (lsof; treats "no lsof" as in-use — a deletion guard must not guess), `am_allowlisted`, `am_stale_entries` (age gate **and** keep-newest-N) |
| **Reclaim** | `am_reclaim_caches <dry> <emit_fn>` — the safe tier, identical on both platforms, with a per-platform tail |
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

## License

MIT © 2026 Kyle Brodeur
