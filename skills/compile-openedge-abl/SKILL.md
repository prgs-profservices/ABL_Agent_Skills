---
name: compile-openedge-abl
description: Compile or verify compilation of an OpenEdge ABL source file (.cls, .w, .i, or .p), including when building, changing, or checking ABL code.
license: Apache-2.0
allowed-tools: Read, Grep, Glob, Write, Bash, PowerShell
compatibility: Windows, PowerShell 5.1+, OpenEdge DLC
---

<!--
compile-openedge-abl: Compile or verify compilation of an OpenEdge ABL source file (.

Copyright 2026 Progress Software Corporation
SPDX-License-Identifier: Apache-2.0
-->

First, determine the openedge parameters to use for running a batch file. This skill will help determine the parameters to use.
Second, determine the DLC environment variable to use
Next, run the compilefile.ps1 file with the source file as a parameter. Add the remaining startup parameters to the command line.

Use the skill invocation's Base Directory as the directory that contains `compilefile.ps1`. The skill tool reports this Base Directory when the skill is invoked. Convert the `file:///...` URI to a local filesystem path if needed, then append `compilefile.ps1`.

Do not use file search to locate `compilefile.ps1`. Skill directories may be junctions, symlinks, or gitignored, and file search tools may skip them. The authoritative location is the Base Directory reported for this skill invocation.

Example command pattern, assuming the skill Base Directory is `C:\apps\MyApp\.devin\skills\compile-openedge-abl`:

```powershell
$skillDir = "C:\apps\MyApp\.devin\skills\compile-openedge-abl"
$scriptPath = Join-Path $skillDir "compilefile.ps1"
if (-not (Test-Path $scriptPath)) {
    throw "compilefile.ps1 was not found in the compile-openedge-abl skill Base Directory."
}
$env:DLC = "C:\Progress\OpenEdge"
powershell.exe -NoProfile -File $scriptPath src\web\helloworld.w other params here
```

## Security & execution requirements

- **Execution capability**: This skill executes the bundled PowerShell script `compilefile.ps1` (an unsigned local script); it only invokes the OpenEdge compiler for a single source file.
- **Execution policy**: The invocation does not bypass PowerShell execution policy. The environment must permit local scripts (e.g. `RemoteSigned`, the Windows default). If execution is blocked by policy, stop and ask the user to adjust their policy consciously — never bypass it silently. Prefer signed scripts where the environment supports them.
- **Safeguards**:
  - The script is resolved only from the skill's reported Base Directory and verified with `Test-Path` before execution (see above) — missing script = stop.
  - No PATH or current-directory fallback resolution of same-named scripts.
  - The source file path and startup parameters come from the user or `openedge-project.json`; treat them as untrusted input. Validate with an **allowlist**, not a denylist:
    - Source file: must exist, must have an ABL extension (`.p`, `.w`, `.i`, `.cls`), and its path must match `^[A-Za-z0-9_.\\/-]+$` and resolve inside the workspace.
    - Startup parameter tokens: option flags must match `^-[A-Za-z0-9]+$`; option values must match `^[A-Za-z0-9_.\\/:-]+$`. Reject anything else (quotes, newlines, redirection, `$`, parentheses, backticks, `%`).
    - Pass each value as a separate command token relying on PowerShell parameter binding; never build a raw command string or use `Invoke-Expression`.

## Reporting Results

If the compilation was successful, the response should say "Compilation successful for: <filename>". If the compilation was not successful, the response should say "Compilation failed for: <filename>".

When this skill is invoked at the user's explicit request, include the relevant compiler output in the chat response, especially failure diagnostics.

When this skill is invoked as an internal verification step while building or fixing code, use compiler output to guide fixes. In the final response, summarize the compile attempts and include detailed compiler output only if the final compile fails, user action is needed, or the user asked to see the output.

## Script integrity

Verify the bundled script(s) before first use: `Get-FileHash <file> -Algorithm SHA256` and compare to the values below. If a hash does not match, stop and review the file before executing. Hashes are regenerated whenever a bundled script changes (see the skills README).

| File | SHA-256 |
|---|---|
| `compilefile.p` | `C26475BE56A933AB76498108DA7BC05B1801AE6CF7A74BC740EEAD48517FDEED` |
| `compilefile.ps1` | `59929B232CF7697F5DAEA36D109C2E81D6436C9EC45859A3E5FD02A65F7AB808` |
