---
name: audit-linux-path-compatibility
description: Analyze ABL source for Linux path compatibility blockers such as Windows-style separators, hard-coded absolute paths, and non-relative path usage in RUN/include/file I/O contexts.
license: Apache-2.0
allowed-tools: Read, Grep, Glob, Write, Bash, PowerShell
compatibility: Windows, PowerShell 5.1+, OpenEdge DLC
---

<!--
audit-linux-path-compatibility: Analyze ABL source for Linux path compatibility blockers such as Windows-style separators, hard-coded absolute paths, and non-relative path usage in RUN/include/file I/O contexts.

Copyright 2026 Progress Software Corporation
SPDX-License-Identifier: Apache-2.0
-->

## Use When
- You need to identify path usage in one or more code roots that may fail on Linux.
- You need to focus on `RUN`, include references, `INPUT FROM`/`OUTPUT TO`, `COPY-LOB`, `OS-DELETE`, `FILE-INFO:FILE-NAME`, and `SEARCH()`.
- You want an HTML report suitable for migration planning across repositories.

## Outputs
- `linux-path-compat-report.html`: interactive report with findings and summary counts.

## Required Outcome
- Scan requested roots and produce an HTML report.
- Exclude findings that appear inside comments (`/* ... */`, line-leading `*`, and `//` comments).
- Open the report automatically when run with `-OpenReport` (default behavior).

## Parameters
- `-Roots` (required): list of roots to scan (for example `src`, `app`, or `src/base,src/med10`).
- `-OutputDir` (optional): report output directory, default `docs`.
- `-ReportFileName` (optional): output file name, default `linux-path-compat-report.html`.
- `-NoOpenReport` (optional): suppress auto-open. By default the report opens after generation.

## Run
`<skill-dir>` = this skill's own folder (the directory containing this SKILL.md). Resolve it from where the skill was loaded — agents mount skills under different roots (`.claude/skills`, `.github/skills`, `.devin/skills`, ...). The scripts themselves are location-independent (they locate the workspace root on their own).

Preferred wrapper:
```cmd
<skill-dir>\run-audit.cmd -Roots src/base,src/med10 -OutputDir docs -ReportFileName linux-path-compat-report.html
```

Direct PowerShell:
```powershell
& "<skill-dir>/generate-linux-path-compat-report.ps1" -Roots @("src/base","src/med10") -OutputDir "docs"
```

## Notes
- The scanner evaluates only non-comment code.
- Findings prioritize path specs that are likely Linux blockers:
  - Drive-letter absolute paths (`C:\...`)
  - UNC paths (`\\server\share\...`)
  - Backslash separators in path specs
  - Absolute non-relative Unix-style paths (`/...`)

## Security & execution requirements

- **Execution capability**: This skill executes the bundled PowerShell script `generate-linux-path-compat-report.ps1` (an unsigned local script) via `run-audit.cmd`; it reads ABL source files and writes an HTML report. No database or network access.
- **Execution policy**: The invocation does not bypass PowerShell execution policy. The environment must permit local scripts (e.g. `RemoteSigned`, the Windows default). If execution is blocked by policy, stop and ask the user to adjust their policy consciously — never bypass it silently.
- **Safeguards**: the script is resolved only from the canonical skill directory (`<skill-dir>`) and verified with `Test-Path` before execution — missing script = stop. No PATH or current-directory fallback.

## Script integrity

Verify the bundled script(s) before first use: `Get-FileHash <file> -Algorithm SHA256` and compare to the values below. If a hash does not match, stop and review the file before executing. Hashes are regenerated whenever a bundled script changes (see the skills README).

| File | SHA-256 |
|---|---|
| `generate-linux-path-compat-report.ps1` | `F87E16AEA2667C118FF9882652E17B3BFBC4C1F1F24926A6B54543B5545E4804` |
| `run-audit.cmd` | `5920235352630304BEAF462DF1D41863C65ABCE04B6525C997FDF937B28E2D73` |
