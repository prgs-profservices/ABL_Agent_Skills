---
name: audit-abl-memory-leaks
description: Analyze OpenEdge ABL source for potential memory/resource leak patterns and generate an interactive HTML report with risk-ranked findings.
license: Apache-2.0
allowed-tools: Read, Grep, Glob, Write, Bash, PowerShell
compatibility: Windows, PowerShell 5.1+, OpenEdge DLC
---

<!--
audit-abl-memory-leaks: Analyze OpenEdge ABL source for potential memory/resource leak patterns and generate an interactive HTML report with risk-ranked findings.

Copyright 2026 Progress Software Corporation
SPDX-License-Identifier: Apache-2.0
-->

## Use When
- You want a first-pass static analysis for probable memory/resource leaks in ABL code.
- You want thorough coverage of the known ABL leak-prone constructs (handles, `MEMPTR`, widgets, streams, COM objects, class instances, async requests, `LONGCHAR`/`UNKNOWN`, static temp-tables).
- You want widget-related findings to account for `CREATE WIDGET-POOL` context.

## Outputs
- `abl-memory-leak-report.html`: interactive report of potential leak findings.

## Detection Categories
- **MEMPTR allocation without release**: `SET-SIZE(x) = n` with no later `SET-SIZE(x) = 0`.
- **MEMPTR incorrect release (KB 000215510)**: `SET-POINTER-VALUE(x) = 0` does NOT free the underlying allocation (unlike `SET-SIZE(x) = 0`); flagged as High severity.
- **Dynamic handle-based object lifecycle**: `CREATE BUFFER/TEMP-TABLE/DATASET/DATA-SOURCE/SOCKET/SERVER/SERVER-SOCKET/CLIENT-PRINCIPAL/SAX-READER/SAX-WRITER/SAX-ATTRIBUTES/X-DOCUMENT/X-NODEREF/CALL` without a matching `DELETE OBJECT`/`DELETE WIDGET`/`DELETE PROCEDURE`. Includes the KB 000185865 caveat: reassigning a handle variable between `CREATE` and `DELETE OBJECT` loses the original reference and leaks it.
- **Widget pools**: `CREATE WIDGET-POOL` presence is tracked so dynamic-widget findings in the same file are down-ranked (pool deletion frees all pooled widgets at once).
- **Event subscription lifecycle**: `SUBSCRIBE` without a corresponding `UNSUBSCRIBE`.
- **Stream/file I/O lifecycle**: `INPUT FROM`/`OUTPUT TO` without `INPUT CLOSE`/`OUTPUT CLOSE`.
- **COM/ActiveX objects**: `CREATE "ProgID" hVar` without `RELEASE OBJECT`/`DELETE OBJECT` — these are never garbage collected.
- **Class instance lifecycle (`NEW`)**: instances assigned via `NEW` with no `DELETE OBJECT` in scope. Flagged Low/informational since ABL GC normally reclaims unreferenced instances, but call out cases GC does not reach (KB 000185865 handle reassignment; KB 000281107 classes with bound `REFERENCE-ONLY` datasets; static members; circular references; long-running/AppServer sessions).
- **Asynchronous AppServer requests**: `RUN ... ASYNCHRONOUS SET hRequest` without a later `DELETE OBJECT hRequest`.
- **`LONGCHAR` compared directly to `UNKNOWN` (KB 000213596)**: a function/method/property call result compared inline to `?` can leak the implicit temporary `LONGCHAR` value on affected releases; recommend assigning to a variable first.
- **Static temp-table defined in a class body (KB 000172688)**: combined with `DELETE OBJECT` of the class instance, has historically left undeleted temp-table/buffer objects on older OpenEdge releases.
- Excludes commented-out code from all pattern matching.

## Required Outcome
- Scan requested roots and produce a report with line-level findings for every category above.
- Exclude commented-out code from pattern matching.
- Include widget-pool context so widget findings can be down-ranked when `CREATE WIDGET-POOL` exists in the file.
- Each finding includes severity, confidence, rationale (with KB/doc citation where applicable), and prevention guidance.

## Parameters
- `-Roots` (required): list of roots to scan (for example `src` or `src/base,src/med10`).
- `-OutputDir` (optional): report output directory, default `docs`.
- `-ReportFileName` (optional): output file name, default `abl-memory-leak-report.html`.
- `-NoOpenReport` (optional): suppress auto-open; by default report opens.

## Run
`<skill-dir>` = this skill's own folder (the directory containing this SKILL.md). Resolve it from where the skill was loaded — agents mount skills under different roots (`.claude/skills`, `.github/skills`, `.devin/skills`, ...). The scripts themselves are location-independent (they locate the workspace root on their own).

Preferred wrapper:
```cmd
<skill-dir>\run-audit.cmd -Roots src -OutputDir docs -ReportFileName abl-memory-leak-report.html
```

Direct PowerShell:
```powershell
& "<skill-dir>/generate-memory-leak-report.ps1" -Roots @("src") -OutputDir "docs"
```

## Prevention Guidance (summary; full rationale is in each report finding)
- Always pair `SET-SIZE(x) = n` with `SET-SIZE(x) = 0`; never use `SET-POINTER-VALUE(x) = 0` to free memory (KB 000215510).
- Always pair `CREATE` (buffer/temp-table/dataset/socket/server/etc.) with `DELETE OBJECT`/`DELETE WIDGET`/`DELETE PROCEDURE`; never reassign a handle variable before deleting what it originally referenced (KB 000185865).
- Prefer `CREATE WIDGET-POOL` + `DELETE WIDGET-POOL` for dynamic UI widgets to guarantee bulk cleanup.
- Always pair `SUBSCRIBE` with `UNSUBSCRIBE`, especially for static/long-lived publishers.
- Always pair `INPUT FROM`/`OUTPUT TO` with `INPUT CLOSE`/`OUTPUT CLOSE`.
- Always pair COM/ActiveX `CREATE "ProgID"` with `RELEASE OBJECT` (COM objects are never garbage collected).
- Explicitly `DELETE OBJECT` class instances held by `STATIC` members, stored in temp-tables/collections, part of circular references, or living in long-running/AppServer sessions — don't rely on GC in these cases (KB 000185865, KB 000281107).
- Always `DELETE OBJECT` an asynchronous request handle after `WAIT-FOR`/completion of a `RUN ... ASYNCHRONOUS SET` call.
- Assign `LONGCHAR`-returning calls to a variable before comparing to `?` (KB 000213596).
- Avoid `DEFINE TEMP-TABLE` directly in a class body when the class instance is explicitly `DELETE OBJECT`ed; verify target OE version against KB 000172688.

## Notes
- This is a static heuristic audit, not a profiler.
- Findings are "potential leak risks" and should be validated in runtime load tests.
- The report includes confidence and rationale to help triage false positives quickly.
- For deeper runtime confirmation, use client startup parameter `-clientlog`/`DynObjects` logging as described in the OpenEdge KnowledgeBase article "Identifying and Troubleshooting Memory Leaks".

## Security & execution requirements

- **Execution capability**: This skill executes the bundled PowerShell script `generate-memory-leak-report.ps1` (an unsigned local script) via `run-audit.cmd`; it reads ABL source files and writes an HTML report. No database or network access.
- **Execution policy**: The invocation does not bypass PowerShell execution policy. The environment must permit local scripts (e.g. `RemoteSigned`, the Windows default). If execution is blocked by policy, stop and ask the user to adjust their policy consciously — never bypass it silently.
- **Safeguards**: the script is resolved only from the canonical skill directory (`<skill-dir>`) and verified with `Test-Path` before execution — missing script = stop. No PATH or current-directory fallback.

## Script integrity

Verify the bundled script(s) before first use: `Get-FileHash <file> -Algorithm SHA256` and compare to the values below. If a hash does not match, stop and review the file before executing. Hashes are regenerated whenever a bundled script changes (see the skills README).

| File | SHA-256 |
|---|---|
| `generate-memory-leak-report.ps1` | `166C8B2AA5126262E3C26E6B427530608010DDF039D7C2CCC977629AB3753362` |
| `run-audit.cmd` | `D627CE4D58181FCC9A7026223E68A7FEFEAA0AC6F67EE7965B44D0B0B5D97AFF` |
