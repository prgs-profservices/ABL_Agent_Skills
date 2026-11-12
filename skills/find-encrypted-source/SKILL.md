---
name: find-encrypted-source
description: Scan ABL source files in the project to identify which ones are XCODE-encrypted (start with byte 0x13), and write results to a CSV in the docs/ folder.
license: Apache-2.0
allowed-tools: Read, Grep, Glob, Write, Bash, PowerShell
compatibility: Windows, PowerShell 5.1+, OpenEdge DLC
---

<!--
find-encrypted-source: Scan ABL source files in the project to identify which ones are XCODE-encrypted (start with byte 0x13), and write results to a CSV in the docs/ folder.

Copyright 2026 Progress Software Corporation
SPDX-License-Identifier: Apache-2.0
-->

## Canonical Script

A ready-to-run PowerShell implementation of this skill lives in this skill's own folder:

```
<skill-dir>/scan-encrypted.ps1
```

`<skill-dir>` is the directory containing this SKILL.md; resolve it from where the skill was loaded rather than hardcoding a root like `.github/skills` or `.claude/skills`. The script resolves the workspace root itself (three levels up from its own location, i.e. `<skills-root>/find-encrypted-source` → workspace).

When this skill is invoked, **run the existing script** rather than constructing a new one. Resolve the script **only** from `<skill-dir>` and fail closed if it is missing — never search PATH or the current directory for a same-named script:

```powershell
$scriptPath = Join-Path "<skill-dir>" "scan-encrypted.ps1"
if (-not (Test-Path $scriptPath)) {
    throw "scan-encrypted.ps1 not found in the find-encrypted-source skill directory - refusing to run an unverified script."
}
powershell -NoProfile -File $scriptPath
```

The script reads `openedge-project.json` automatically and writes output to `docs/encrypted-source-scan.csv`.

## Security & execution requirements

- **Execution capability**: This skill executes the bundled PowerShell script `scan-encrypted.ps1` (an unsigned local script); it only reads files and writes a CSV report.
- **Execution policy**: The invocation does not bypass PowerShell execution policy. The environment must permit local scripts (e.g. `RemoteSigned`, the Windows default). If execution is blocked by policy, stop and ask the user to adjust their policy consciously — never bypass it silently.
- **Safeguards**:
  - The script is resolved only from the canonical skill directory (`<skill-dir>`) and verified with `Test-Path` before execution — missing script = stop.
  - No PATH or current-directory fallback resolution of same-named scripts.
  - The scan is read-only for source files; the only write is the CSV report under `docs/`.

---

## Overview

XCODE-encrypted ABL source files cannot be read, edited, or analyzed as plain text. They start with the byte `0x13` (ASCII DC3 / XOFF), which OpenEdge uses as a file signature for encrypted source. This skill scans all compilable ABL source files in the project (as defined by `openedge-project.json`) and produces a CSV report of which files are encrypted, so the team can understand the extent of third-party locked source in the codebase.

## When to Use

Use this skill when you need to:
- Audit how much of the codebase is XCODE-encrypted vs open source
- Identify encrypted files before attempting to compile, analyze, or review them
- Plan migration or modernization work that requires access to source
- Understand which modules came from a third-party vendor with source protection

## Inputs

- **Workspace root** — the project root (the directory containing `openedge-project.json`)
- **Output filename** — optional; defaults to `docs/encrypted-source-scan.csv`

## Process

### Step 1: Determine source directories

Invoke the **get-source-directories** skill to read `openedge-project.json` and produce the list of source directories and glob patterns to scan.

### Step 2: Collect ABL source files

For each source path returned in Step 1, collect all files matching ABL extensions: `*.p`, `*.w`, `*.i`, `*.cls`.

Respect the `includes` and `excludes` glob filters from the source directory entries.

Use PowerShell to enumerate:

```powershell
$srcRoot = "<workspace-root>"

# One entry per source path from get-source-directories.
# Example using the includes patterns from openedge-project.json:
$sourcePaths = @(
    @{ Base = "src\med10"; Includes = @("ar/**","pt/**") },
    @{ Base = "src\cust";  Includes = @("ar/**","pt/**","adm2/**") },
    @{ Base = "src\base";  Includes = @("ar/**","pt/**","adm2/**","rules/**") }
    # ... add all entries from get-source-directories output
)

$files = @()
foreach ($sp in $sourcePaths) {
    $dir = Join-Path $srcRoot $sp.Base
    if ($sp.Includes.Count -eq 0) {
        $files += Get-ChildItem $dir -Recurse -Include "*.p","*.w","*.i","*.cls"
    } else {
        foreach ($inc in $sp.Includes) {
            # Convert glob (e.g. "pt/**") to a subdirectory path
            $subDir = Join-Path $dir ($inc -replace '/\*\*$','')
            if (Test-Path $subDir) {
                $files += Get-ChildItem $subDir -Recurse -Include "*.p","*.w","*.i","*.cls"
            }
        }
    }
}
```

### Step 3: Detect encrypted files

For each file, read the first byte. A file is XCODE-encrypted if and only if byte `[0]` equals `0x13` (decimal 19).

```powershell
function Test-XcodeEncrypted($path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    return ($bytes.Length -gt 0 -and $bytes[0] -eq 0x13)
}
```

Do **not** use text-based parsing or ratio heuristics — the single byte check is definitive and fast.

### Step 4: Build results

For each file, record:

| Column | Value |
|---|---|
| `RelativePath` | File path relative to workspace root, using forward slashes |
| `Directory` | Parent directory name (e.g. `pt`, `ar`) |
| `SourceTree` | Top-level source tree (e.g. `src/base`, `src/cust`) |
| `Extension` | File extension (`.p`, `.w`, `.i`, `.cls`) |
| `Encrypted` | `TRUE` or `FALSE` |
| `SizeBytes` | File size in bytes |

### Step 5: Write CSV output

Write the results to `docs/encrypted-source-scan.csv` in the workspace root.

```powershell
$results | Export-Csv -Path (Join-Path $srcRoot "docs\encrypted-source-scan.csv") `
           -NoTypeInformation -Encoding UTF8
```

Also print a summary to the terminal:

```
Total ABL files scanned : 776
Encrypted (XCODE)       : 572  (73.7%)
Plain text              : 204  (26.3%)

Results written to: docs/encrypted-source-scan.csv
```

### Step 6: Report to user

After writing the file, tell the user:
- The total count of files scanned
- How many are encrypted and what percentage
- Which source trees / directories have the highest concentration of encrypted files
- The path to the CSV output file

## Output Format

The CSV file has these columns (with header row):

```
RelativePath,Directory,SourceTree,Extension,Encrypted,SizeBytes
src/base/pt/menu4.p,pt,src/base,.p,TRUE,23617
src/base/pt/xcomp.p,pt,src/base,.p,FALSE,18432
```

## Notes

- The `0x13` magic byte is consistent across XCODE versions.
- Files encrypted with older vs newer XCODE keys have the same magic byte — the key itself is not detectable from the file.
- `.i` include files can also be encrypted, not just `.p` and `.w`.
- Encrypted files should be excluded from any code review, XREF, or linting workflow. Use the CSV output to build exclusion lists.
- If your project has an XCODE key helper (e.g. a `set-xcode-key.p` utility), run it before compiling encrypted source.

## Script integrity

Verify the bundled script(s) before first use: `Get-FileHash <file> -Algorithm SHA256` and compare to the values below. If a hash does not match, stop and review the file before executing. Hashes are regenerated whenever a bundled script changes (see the skills README).

| File | SHA-256 |
|---|---|
| `scan-encrypted.ps1` | `F4BEA817F44D8D8BC812B3A17993C3EF8C96A00D5577F560D7A92967C718E8F6` |
