# Code intelligence


> **Code symbol, caller, or blast radius → CodeGraph.
> What routes / env vars / libraries exist → `.codesight/`.
> grep and read last.**

Two indexes with disjoint jobs. Neither replaces reading the code; both replace
*guessing which file to read*.

| Index | Answers | State | Local setup |
|---|---|---|---|
| **CodeGraph** | where a symbol is, what calls it, what breaks if it changes | `.codegraph/` — 1.6 MB SQLite, **gitignored** | `codegraph init .` |
| **codesight** | the route / library / env-var inventory | `.codesight/` — 32 KB markdown, **committed** | none |

codesight's output is a deterministic AST scan, so it diffs line by line and every
runtime reads it with zero setup. CodeGraph's index is neither deterministic nor
small. **Commit the inventory, never the graph.**

`.mcp.json` registers `codegraph serve --mcp`; `.claude/settings.json` runs
`codegraph prompt-hook` on `UserPromptSubmit`, injecting matching symbols *before*
a search strategy is chosen. Both are guarded — with `codegraph` off `PATH` the
hook prints nothing and exits 0, so a clone without it gets a working session.

**Subagents must use the CLI, not the MCP tool.** Project MCP servers are not
reliably inherited by `Task`-spawned subagents, so a subagent calling
`mcp__codegraph__codegraph_explore` errors with "no such tool". Use
`rtk codegraph explore "<query>"` — every agent has `Bash`.

`codegraph.json` excludes `venv/`, `data/`, `__pycache__/` and the empty
`AI_detect/`. The `venv/` entry is load-bearing: `fall_detection_web/venv/` holds
all of torch and ultralytics, which would swamp 6,600 lines of app code.
`.codesightignore` mirrors that list — change one, change the other.

## Validation ladder

Run cold, in order — the first failure is the earliest cause.

```bash
rtk codegraph --version                              # CLI present (1.5.0 here)
rtk git check-ignore .codegraph                      # index ignored
rtk codegraph explore "capture_rtsp_snapshot"        # MUST name fall_detection_web/monitor.py:93
rtk head -5 .codesight/routes.md                     # inventory arrived with the clone
```

The third line is the only rung that proves the index is *correct* rather than
merely *present*. A graph that answers with the wrong file is worse than no graph.
After a large refactor, rebuild with `rtk codegraph index .`.

## Regenerating the inventory

```bash
rtk npx --yes codesight@1.19.0 .     # then commit the .codesight/ diff
```

**Keep the version pinned** — an unpinned `npx codesight` lets a new release rewrite
committed AI context with no diff review. Bump deliberately, as its own commit.

Never pass `--init` (it overwrites this file and writes an unused `.cursorrules`)
or `--hook` (this repo has no pre-commit hook and does not want one yet).

