# OpenEdge ABL Skills

A collection of agent skills for working with OpenEdge ABL codebases. They are written to be **IDE/agent-portable**: the same skill files work in VS Code Copilot, Claude Code, Devin, Windsurf, and other agents that support the SKILL.md convention.

## Installation

Clone this repository and copy the skill folders into whatever skills directory your agent uses:

| Agent | Skills directory |
|---|---|
| Claude Code | `.claude/skills/` |
| VS Code Copilot | `.github/skills/` |
| Devin | `.devin/skills/` |

Copy each skill **as a whole folder** (SKILL.md plus its scripts/templates). Skills reference their own files via the skill's folder (`<skill-dir>` in the docs), never via a hardcoded root, so they work from any of the locations above.

**Cross-skill dependency:** `audit-os-command-execution` reads the Progress logo from the sibling folder `analyze-abl-dependencies/templates/`. Copy those two skills together (the report still generates without the logo).

Many skills reference each other by name (e.g. `get-project-dlc`, `determine-oe-params`, `find-ablunit-tests`, `detect-editor`, `load-openedge-schema`, `get-source-directories`, `get-workspace-propath`, `make-project-ini`, `modernize-variables`, `test-with-ablunit`). For full functionality, copy the whole set.

## Requirements common to most skills

- **Windows + PowerShell 5.1+** — all helper scripts are PowerShell/cmd. (Several SKILL.md docs describe Linux equivalents, but the bundled scripts target Windows.)
- **OpenEdge 12.x installation** — the `DLC` environment variable (or VS Code `abl.configuration.runtimes` settings) must point at it. Setting `DLC` explicitly is the most portable option.
- **`openedge-project.json` in the workspace root** — used to derive PROPATH, database connections, source directories, and OpenEdge version.

## Per-skill external dependencies

| Skill | Extra dependencies beyond the common ones |
|---|---|
| `test-with-ablunit` | VS Code extension **`kherring.ablunit-test-runner`** (script locates `ABLUnitCore.p` under `%USERPROFILE%\.vscode\extensions\`). Without VS Code, provide those extension files another way. |
| `get-project-dlc`, `resolve-vscode-settings-path` | VS Code user `settings.json` (`abl.configuration.runtimes`). Falls back to the `DLC` env var / defaults on other agents. |
| `load-openedge-schema` | **OpenEdge DevOps Framework (OEDF)**: `$DLC/bin/progradle` and Gradle plugin `progress.openedge.abl-base` (default version 2.3.0). First run needs network access to download the plugin. |
| `markdown-to-word` | **Python 3** + **`python-docx`** package (`pip install python-docx==1.1.2` — pinned, reviewed version). |
| `audit-os-command-execution` | PowerShell module **`ImportExcel`** (only for `-Mode command-summary` / the .xlsx workbook). Logo shared from `analyze-abl-dependencies` (optional). |
| `analyze-oe-profile` | **git** on PATH (optional — used for include-aware line mapping; degrades gracefully). |
| `modernize-variables`, ABL coding skills | **`openedge-abl-mcp-server` MCP** for authoritative ABL syntax lookups (recommended, not strictly required). |
| `create-ablunit-tests` | Project coding-standards file if present (`CLAUDE.md`, `AGENTS.md`, or `.github/copilot-instructions.md`). |
| `detect-editor` | `code` or `devin` CLI on PATH (only used to open files; skills work without it). |
| `create-openedge-database`, `dump-database-df`, `compile-*`, `run-openedge-program` | OpenEdge utilities from `$DLC/bin` (`prostrct`, `procopy`, `_progres`, `prowin`). |

## Safety notes

- `purge-junk-files` **deletes files**. Deletion requires the explicit `-Confirm` switch; always run with `-DryRun` first and review the log. Recover mistakes via version control.
- `drop-openedge-db-field` and `load-openedge-schema` change database schemas. The skills require explicit user confirmation before applying a .df — keep it that way.
- `load-schema.ps1` passes `-U/-P` database credentials on the command line when you supply them; prefer a `.pf` parameter file so credentials do not appear in process listings or logs.

## Script integrity hashes

Every skill that bundles an executable script documents its SHA-256 hash in a **Script integrity** section at the end of its SKILL.md. Agents and reviewers should verify hashes before first execution (`Get-FileHash <file> -Algorithm SHA256`) and stop on mismatch.

When a bundled script changes, regenerate its hash and update the table in the skill's SKILL.md:

```powershell
Get-ChildItem <skill-dir> -Include *.ps1,*.cmd,*.py,*.p -File | Get-FileHash -Algorithm SHA256
```
