---
name: abl-project-metrics
description: Compute project size and scope metrics for an OpenEdge ABL project, keeping production functional source separate from test source.
license: Apache-2.0
allowed-tools: Read, Grep, Glob, Write, Bash, PowerShell
compatibility: Windows, PowerShell 5.1+, OpenEdge DLC
---

<!--
abl-project-metrics: Compute project size and scope metrics for an OpenEdge ABL project, keeping production functional source separate from test source.

Copyright 2026 Progress Software Corporation
SPDX-License-Identifier: Apache-2.0
-->

## Quick Start

Run `Measure-Project.ps1` from this skill's own folder against the active workspace.

Resolve the script **only** from `<skill-dir>` and fail closed if it is missing — never search PATH or the current directory for a same-named script:

```powershell
$scriptPath = Join-Path "<skill-dir>" "Measure-Project.ps1"
if (-not (Test-Path $scriptPath)) {
    throw "Measure-Project.ps1 not found in the abl-project-metrics skill directory - refusing to run an unverified script."
}
powershell.exe -NoProfile -File $scriptPath
```

`<skill-dir>` below means the folder that contains this `SKILL.md`. Agents mount skills under different roots (`.claude/skills`, `.github/skills`, `.devin/skills`, ...), so resolve `<skill-dir>` from where the skill was loaded.

## What It Measures

- **Production source** ? functional ABL code (`.cls`, `.p`, `.w`, `.i`)
- **Test source** ? ABLUnit test classes and supporting test code
- **Operational scripts** ? one-off `.p` batch utilities (shown separately)
- **Generated r-code** ? compiled `.r` outputs (shown for awareness, not mixed into source totals)

For each population the script reports:

- File count
- Byte size
- Total lines
- Non-blank lines
- Code lines (non-blank, not single-line `//` comment or inside `/* ... */` block)
- `@Test.` methods and `@TestSuite` entries (for test code)

It also reports per-extension breakdowns and useful ratios such as test files per production file and test code lines per production code line.

## Step-by-Step Process

1. Resolve the skill base directory (`<skill-dir>`).
2. Run `Measure-Project.ps1` with the project root. Defaults to the current directory.
3. Review the markdown output in the console, or use `-OutputFile` and `-OutputFormat` to save JSON or text.

## Parameters

```powershell
powershell.exe -NoProfile -File $scriptPath `
    -ProjectRoot "C:\apps\Liminalis" `
    -OutputFormat markdown `
    -OutputFile "C:\temp\abl-project-metrics.md"
```

| Parameter | Default | Notes |
|-----------|---------|-------|
| `ProjectRoot` | `.` | Project root to measure. |
| `ProductionPaths` | `src\WebHandler`, `src\liminalis`, `src\procs`, `src\system` | Default ABL source folders; override for your project layout. |
| `TestPaths` | `src\test` | Folders containing ABLUnit tests. |
| `OperationalPaths` | `scripts` | One-off operational `.p` scripts. |
| `GeneratedPaths` | `build\rcode`, `rcode` | Generated `.r` code directories. |
| `SourceExtensions` | `.cls`, `.p`, `.w`, `.i` | Source file extensions to include. |
| `OutputFormat` | `markdown` | `text`, `json`, or `markdown`. |
| `OutputFile` | none | Optional file to write; otherwise prints to console. |

## Security & execution requirements

- **Execution capability**: This skill executes the bundled PowerShell script `Measure-Project.ps1` (an unsigned local script); it is read-only apart from the optional metrics output file.
- **Execution policy**: The invocation does not bypass PowerShell execution policy. The environment must permit local scripts (e.g. `RemoteSigned`, the Windows default). If execution is blocked by policy, stop and ask the user to adjust their policy consciously — never bypass it silently.
- **Safeguards**:
  - The script is resolved only from the canonical skill directory (`<skill-dir>`) and verified with `Test-Path` before execution — missing script = stop.
  - No PATH or current-directory fallback resolution of same-named scripts.
  - `-ProjectRoot` and `-OutputFile` are user-supplied paths; normalize them and reject paths containing shell metacharacters.

## Reporting Results

If `OutputFile` is supplied, the script reports the written file path. Otherwise it prints the metrics table directly. When running for the user, present the key numbers and ratios in a concise summary.

## Script integrity

Verify the bundled script(s) before first use: `Get-FileHash <file> -Algorithm SHA256` and compare to the values below. If a hash does not match, stop and review the file before executing. Hashes are regenerated whenever a bundled script changes (see the skills README).

| File | SHA-256 |
|---|---|
| `Measure-Project.ps1` | `765A4A8231BE405DB5CFAE99FE2306F4A8828434674507EBF6A8B4BE99A279FE` |
