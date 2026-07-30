# Cursor multi-root search notes

Metra often opens many sibling folders in one workspace. Content search tools then return the **same file path once per mounted root** that can see it (search echo). That burns agent tokens.

## Agent mitigation (required)

After routing to one project, always pass an absolute `path` to Grep/Glob (that project's folder, or `C:\Projects\_meta` for orchestration work). Prefer `.\meta.ps1 routing` / `ctx` for "which project?" asks.

## Operator / workspace options

| Approach | Effect | Cost |
|----------|--------|------|
| Path-scoped agent search (above) | Stops most echo without changing the IDE | None |
| Smaller Metra-only workspace session | Fewer mounts = less echo | Open fewer folders when doing `_meta`-only work |
| Trim `workspace.alwaysInclude` in `meta.config.json` | Fewer always-mounted hubs | May need manual open for unpinned projects |
| `.cursorindexingignore` | Reduces index noise; may not stop Grep echo across roots | Experiment per machine |

Do **not** auto-run `.\meta.ps1 workspace` on chat start - rewriting the workspace file can reload Cursor mid-session.

See [Integrations.md](Integrations.md) for sessionStart snapshot hooks. Broader routing cadence: [Context-Routing.md](Context-Routing.md).
