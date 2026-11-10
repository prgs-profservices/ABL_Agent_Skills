---
name: test-with-ablunit
description: Test ABL programs (.w, .cls, .p) by running ABLUnit tests.
license: Apache-2.0
allowed-tools: Read, Grep, Glob, Write, Bash, PowerShell
compatibility: Windows, PowerShell 5.1+, OpenEdge DLC
---

<!--
test-with-ablunit: Test ABL programs (.

Copyright 2026 Progress Software Corporation
SPDX-License-Identifier: Apache-2.0
-->

## Quick Start

Run ABLUnit tests in a single command using the provided `runtest.ps1` script.

`<skill-dir>` below means this skill's own folder (the directory containing this SKILL.md). Agents mount skills under different roots (`.claude/skills`, `.github/skills`, `.devin/skills`, ...), so resolve `<skill-dir>` from where this skill was loaded — do not hardcode a root.

Resolve the script **only** from `<skill-dir>` and fail closed if it is missing — never search PATH or the current directory for a same-named script:

```powershell
$scriptPath = Join-Path "<skill-dir>" "runtest.ps1"
if (-not (Test-Path $scriptPath)) {
    throw "runtest.ps1 not found in the test-with-ablunit skill directory - refusing to run an unverified script."
}
powershell.exe -NoProfile -File $scriptPath "test/path/test_ClassName.cls" "-pf dbconn.pf -basekey ini"
```

## Security & execution requirements

- **Execution capability**: This skill executes the bundled PowerShell script `runtest.ps1` (an unsigned local script) to run the ABLUnit test runner locally.
- **Execution policy**: The invocation does not bypass PowerShell execution policy. The environment must permit local scripts (e.g. `RemoteSigned`, the Windows default). If execution is blocked by policy, stop and ask the user to adjust their policy consciously — never bypass it silently.
- **Safeguards**:
  - The script is resolved only from the canonical skill directory (`<skill-dir>`) and verified with `Test-Path` before execution — missing script = stop.
  - No PATH or current-directory fallback resolution of same-named scripts.
  - The test path and startup parameters passed to the script come from the user or from `openedge-project.json`; treat them as untrusted input. Validate with an **allowlist**, not a denylist:
    - Test path: must match `^[A-Za-z0-9_.\\/-]+$` and resolve to a location inside the workspace.
    - Startup parameter tokens: option flags must match `^-[A-Za-z0-9]+$`; option values must match `^[A-Za-z0-9_.\\/:-]+$`. Reject anything else (quotes, newlines, redirection, `$`, parentheses, backticks, `%`).
    - Pass arguments as separate tokens relying on PowerShell parameter binding; never build a command with string concatenation or `Invoke-Expression`.
- **Local files read** (full list): `openedge-project.json` in the workspace root; the VS Code `settings.json` resolved via the `resolve-vscode-settings-path` skill (only when `DLC` is not set); and `ABLUnitCore.p` inside the `kherring.ablunit-test-runner` extension folder under `%USERPROFILE%\.vscode\extensions\`. The skill reads nothing else outside the workspace and transmits nothing externally.

## Dependencies

- **ABLUnit test runner VS Code extension** (`kherring.ablunit-test-runner`): the script locates `ABLUnitCore.p` inside this extension under `%USERPROFILE%\.vscode\extensions\`. On agents without VS Code, install the extension files or set the script's ABLUnitCore.p lookup path accordingly.
- **DLC**: set the `DLC` environment variable up front to skip the VS Code settings auto-detection (recommended on non-VS Code agents).

The script automatically:
1. Detects DLC path from VS Code settings matching the project's OpenEdge version (skipped when `DLC` is already set)
2. Extracts and sets PROPATH from openedge-project.json
3. Locates ABLUnitCore.p
4. Creates ablunit.json configuration
5. Runs the test and writes results to `ablunit/results.xml`

## Step-by-Step Process

### Step 1: Find the Test File

Use the **find-ablunit-tests** skill to locate the test file for the given source file or validate the provided test file path.

### Step 2: Convert to PROPATH-Relative Path

**CRITICAL**: Remove the PROPATH prefix from the workspace file path.

- Read `openedge-project.json` -> find `buildPath` with `"type": "source"`
- Common prefix: `src/`
- Workspace: `src/test/system/test_DateUtils.cls` -> Test path: `test/system/test_DateUtils.cls`

### Step 3: Build Startup Parameters

Check if `dbconn.pf` exists in workspace root:
- **If exists**: Use `-pf dbconn.pf`
- **If not**: Extract from `openedge-project.json` -> `dbConnections` array

Get `extraParameters` from `openedge-project.json` (e.g., `-basekey ini`).

Combine: `"-pf dbconn.pf -basekey ini"`

### Step 4: Execute Test

Run the simplified command from Quick Start section above, substituting:
- `test/path/test_ClassName.cls` -> your PROPATH-relative test path
- Startup params from Step 3

The script handles all setup automatically including DLC detection.

### Step 5: Display Results

Parse `ablunit/results.xml` and format output:

Use these colored status emoji in chat output. The skill source stores them as ASCII-safe HTML entities; when displaying results to the user, output the actual rendered emoji, not the entity text.

- `&#9989;` renders as green check for Success
- `&#10060;` renders as red X for Failure
- `&#9888;&#65039;` renders as warning sign for Error

Example chat output should look like this with rendered status emoji:

```text
test/system/test_DateUtils.cls
  green check test_GetDateFromJS (0s)
  green check test_GetDateTimeFromJS (0.001s)
  red X test_InvalidFormat (0.002s)

red X 2 passed, 1 failed (3 total) in 0.003s
```

Replace the words `green check`, `red X`, and `warning sign` in the example with the rendered status emoji in your chat response.

## Common Errors

**DLC not set**: The script will fail immediately. Ensure the first part of the Quick Start command successfully extracts the DLC path.

**Class name mismatch (12629)**: Test path still contains PROPATH prefix (e.g., `src/test/...`). Remove the `src/` prefix.

**Test file not found**: Verify the test path is correct and PROPATH-relative.

## Script integrity

Verify the bundled script(s) before first use: `Get-FileHash <file> -Algorithm SHA256` and compare to the values below. If a hash does not match, stop and review the file before executing. Hashes are regenerated whenever a bundled script changes (see the skills README).

| File | SHA-256 |
|---|---|
| `runtest.ps1` | `9AAD2D552083A2889EB3D87ED38770A343DF67B31A2BA7B18687B1233B1CD1BC` |
