---
name: purge-junk-files
description: Clean up an ABL codebase by identifying and removing old backup copies, version-suffixed files, and temporary junk files.
license: Apache-2.0
allowed-tools: Read, Grep, Glob, Write, Bash, PowerShell
compatibility: Windows, PowerShell 5.1+, OpenEdge DLC
---

<!--
purge-junk-files: Clean up an ABL codebase by identifying and removing old backup copies, version-suffixed files, and temporary junk files.

Copyright 2026 Progress Software Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Purge Junk Files

> **Purpose:** Clean up an ABL codebase by removing old backup copies and temporary files.

> **⚠️ File-delete capability:** This skill **permanently deletes files** (`Remove-Item -Force`). Actual deletion requires the explicit `-Confirm` switch; without it the script runs in preview mode and deletes nothing. Always review the preview log before confirming.

## Overview

This skill removes backup files and junk accumulation from **ABL projects**, helping to:
- Reduce repository bloat in OpenEdge distributions
- Remove stale `.bak` files and version suffixes that accumulate in development
- Clean up temporary files before commits
- Improve repository hygiene for ABL codebases

**Important:** All examples in this documentation use generic directory and project names (not specific to any single client or organization). You should adapt paths and patterns to match your specific ABL project structure.

**Path convention:** `<skill-dir>` in the commands below means this skill's own folder (the directory containing this SKILL.md). Agents mount skills under different roots (`.claude/skills`, `.github/skills`, `.devin/skills`, ...), so resolve `<skill-dir>` from where the skill was loaded — do not hardcode a root.

Customization supports:
- **Pattern configuration** — Edit `patterns.json` to define which files to delete
- **Command-line options** — Override patterns for one-time runs
- **Dry-run preview** — Test before executing (highly recommended)
- **Comprehensive logging** — All operations logged with timestamps

## When to Use

This skill is designed for **ABL projects** where you need to:
- Clean up backup copies of ABL source files (`.bak`, `.old`, `.backup`, etc.)
- Remove duplicate ABL files with version suffixes (e.g., `myprogram.283091287.p`, `report.20250315.w`)
- Remove temporary files before committing to version control
- Prepare an ABL codebase distribution or archive

## Prerequisites

- PowerShell 5.1+ (Windows) or bash (Linux/macOS)
- Read/write access to the target directory
- Understanding of which file patterns can be safely removed

## Key Concepts

### File Patterns to Remove (ABL Codebase)

Common patterns in ABL projects that should be identified and removed:

- Backup suffixes: (`.bak`, `.old`, `.backup`, `.orip`, `.orig`) — manual backups of `.p`, `.w`, `.i`, `.cls` files
- Version suffixes: (`.20YYMMDD.*` — numbered backups like `myprogram.20250315.p` or `report.283091287.w`)
- Temporary files: (`.tmp`, `.temp`, `.shold`)
- Other patterns specific to your ABL project

### Pattern Configuration

Different ABL projects may accumulate different types of junk files. The skill supports three-tier pattern customization so you can adapt it to your specific project:

#### 1. Configuration File (`patterns.json`)

Located at: `<skill-dir>/patterns.json`

Edit this file to customize patterns once for your project:

```json
{
  "patterns": [
    "*.bak",
    "*.old",
    "*.[0-9]*.*"
  ]
}
```

**Advantages:**
- Reusable across team members
- Clear documentation of what gets deleted
- Single source of truth for your project

#### 2. Command-Line Parameter

Pass patterns directly when running the script:

```powershell
<skill-dir>\purge-junk-files.ps1 `
  -TargetDir "./src" `
  -Patterns @("*.bak", "*.old")
```

**Advantages:**
- One-time customization
- No file modifications needed
- Good for testing patterns

#### 3. Built-in Defaults

If no patterns are provided, the script uses these defaults (same as `patterns.json` defaults):
- `*.bak`, `*.old`, `*.backup`, `*.orig`, `*.tmp`, `*.[0-9]*.*`, `* - Copy.*`, `* - Copy (*.*`, `*-OLD.*`

**Priority order:**
1. `-Patterns` parameter (if provided)
2. `patterns.json` (if exists and readable)
3. Built-in defaults (fallback)

### Safety Considerations

- ✅ **Deletion requires explicit confirmation** — Files are only deleted when `-Confirm` is passed; otherwise the script runs in preview mode and exits without deleting
- ✅ **Logging enabled** — All deletions logged to `cleanup-reports/` with timestamps
- ✅ **Dry-run mode supported** — Preview deletions before executing (`-DryRun`)
- ✅ **Traversal limits** — Recursion is bounded by `-MaxDepth` (default 10, range 1–50) and `-MaxFiles` (default 100000, range 1–500000); the scan aborts instead of deleting when limits are exceeded
- ✅ **Scope warnings** — The script warns when `TargetDir` is outside the current location, a drive root, or the user home directory
- ✅ **Pattern validation** — Overly broad patterns (`*`, `*.*`, `*.*.*`) are rejected; explicitly configured patterns reduce risk
- ✅ **Error resilience** — Skips locked/protected files; continues processing
- ⚠️ **No automatic rollback** — Use version control (`git`, etc.) for recovery if needed

## Workflow

### Step 1: Identify Target Directory

Specify the root directory to scan (e.g., `./src`, `./source`, or specific subdirectory). This is project-specific.

### Step 2: Define Removal Patterns

Choose how to customize patterns:
- **Use defaults** — Built-in patterns work for most codebases
- **Edit `patterns.json`** — Customize once, then reuse for this project
- **Use `-Patterns` parameter** — One-time customization for specific runs

### Step 3: Run in Dry-Run Mode

ALWAYS test first without deleting:
```powershell
<skill-dir>\purge-junk-files.ps1 -TargetDir "./src" -DryRun
```

Review the log to ensure safe patterns.

### Step 4: Execute Cleanup

Once satisfied with dry-run results, execute with the explicit confirmation switch:
```powershell
<skill-dir>\purge-junk-files.ps1 -TargetDir "./src" -Confirm
```

Without `-Confirm` the script only previews and deletes nothing (exit code 1).

### Step 5: Verify Results

Confirm:
- Intended files were removed
- No critical files were deleted
- Repository state is clean
- Log file captured all operations

## Usage Example

### Basic Usage (Generic Project)

```powershell
# Navigate to your project root
cd "C:\MyProjects\MyProject"

# Remove junk files from source directory (dry-run first!)
<skill-dir>\purge-junk-files.ps1 -TargetDir "./src" -DryRun

# Review the log
Get-Content "./cleanup-reports/purge-junk-files-*.log" | Select-Object -Last 30

# If satisfied, execute the cleanup (requires -Confirm)
<skill-dir>\purge-junk-files.ps1 -TargetDir "./src" -Confirm
```

### Dry-Run Mode (RECOMMENDED - Always Test First)

```powershell
# Preview what would be deleted WITHOUT actually deleting anything
<skill-dir>\purge-junk-files.ps1 -TargetDir "./MySourceFolder" -DryRun

# View the log file to see all files that would be deleted
$latestLog = Get-ChildItem "./cleanup-reports/purge-junk-files-*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Get-Content $latestLog

# If you're satisfied with the results, run with -Confirm (and without -DryRun)
<skill-dir>\purge-junk-files.ps1 -TargetDir "./MySourceFolder" -Confirm
```

### Customize Patterns

#### Option 1: Edit `patterns.json` (Recommended for repeated use)

Open `<skill-dir>/patterns.json` and modify the patterns array:

```json
{
  "patterns": [
    "*.bak",
    "*.old",
    "*.backup",
    "*.[0-9]*.*",
    "*.shold",
    "*~"
  ]
}
```

Then run without specifying patterns (preview first, then confirm):
```powershell
<skill-dir>\purge-junk-files.ps1 -TargetDir "./src" -DryRun
<skill-dir>\purge-junk-files.ps1 -TargetDir "./src" -Confirm
```

#### Option 2: Pass Patterns via Command Line

```powershell
# Remove only .bak files
<skill-dir>\purge-junk-files.ps1 `
  -TargetDir "./src" `
  -Patterns @("*.bak") `
  -Confirm

# Remove multiple specific patterns
<skill-dir>\purge-junk-files.ps1 `
  -TargetDir "./src" `
  -Patterns @("*.bak", "*.old", "*.[0-9]*.*") `
  -Confirm
```

### Advanced Usage

```powershell
# Exclude certain directories from processing
<skill-dir>\purge-junk-files.ps1 `
  -TargetDir "./src" `
  -Exclude @(".git", "build", "dist") `
  -DryRun

# Process multiple folders
<skill-dir>\purge-junk-files.ps1 -TargetDir "./src/core" -DryRun
<skill-dir>\purge-junk-files.ps1 -TargetDir "./src/utils" -DryRun
<skill-dir>\purge-junk-files.ps1 -TargetDir "./src/vendor" -DryRun

# View recent operation logs
ls cleanup-reports/purge-junk-files-*.log | Sort-Object LastWriteTime -Descending | Select-Object -First 5
```

## Default Patterns

The script uses these built-in default patterns (can be customized in `patterns.json` or via command line):

| Pattern | Examples |
|---------|----------|
| `*.bak` | file.bak, program.p.bak |
| `*.old` | script.w.old, code.cls.old |
| `*.backup` | data.backup |
| `*.orig` | original.orig |
| `*.tmp` | temporary.tmp |
| `*.[0-9][0-9]*.*` | myprogram.283091287.p, report.12345.w, script.20180101.p |
| `* - Copy.*` | ackfm - Copy.p, report - Copy.w |
| `* - Copy (*.*` | ackfm - Copy (2).p, report - Copy (3).w |
| `Copy of *.*` | Copy of foo.p, Copy of report.w |
| `*-OLD.*` | createbol2-OLD.p, report-old.w (case-insensitive) |

### File-Level Exclusions

The `exclude` key in `patterns.json` lists filename patterns that are **never** deleted, regardless of what the `patterns` list matches. This prevents false positives:

```json
{
  "patterns": [ "*.[0-9][0-9]*.*", "*.bak", ... ],
  "exclude": [
    "*.doc",
    "*.xlsx"
  ]
}
```

File exclusions are matched case-insensitively against the filename only (not the full path). There is no command-line equivalent — file exclusions can only be set in `patterns.json`.

> **Default:** `*.doc` is excluded out-of-the-box to protect documents whose names may contain version numbers (e.g., `8.1d-01 Job Processing Guide.doc`).

### Pattern Matching

- **Wildcards:** `*.bak`, `file.*`, `*test*` (standard Windows wildcard syntax)
- **Numeric sequence patterns:** `*.[0-9][0-9]*.*` requires at least two consecutive digits in a dot-separated segment, so `prog.283091287.p` and `prog.20250315.p` match but `prog.8.1d.p` does not
- **Character ranges:** `[0-9]` for digits, `[a-z]` for letters

## Implementation Details

### Logging

All operations are logged to the `cleanup-reports/` directory with timestamped filenames:

```
cleanup-reports/purge-junk-files-<YYYYMMDD-HHMMSS>.log
```

**Log Format:**
- Timestamp of operation
- File path deleted or action taken
- Result status (OK, SKIPPED, ERROR)
- Dry-run indicators (if applicable)

**Example log entry:**
```
[2026-03-16 14:32:15] DELETE: src/base/program.p.bak | OK
[2026-03-16 14:32:15] DELETE: src/med10/script.w.20250101 | OK
[2026-03-16 14:32:16] ERROR: src/cust/locked.p.old (file locked) | SKIPPED
```

### Folder Creation

The skill automatically creates `cleanup-reports/` if it does not exist:

```powershell
$logsDir = Join-Path (Get-Location) "cleanup-reports"
if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}
```

### Dry-Run Mode and Confirmation Gate

**Purpose:** Preview all deletions without actually removing files.

**Usage:**
```powershell
# With -DryRun flag
<skill-dir>\purge-junk-files.ps1 -TargetDir "./src" -DryRun
```

**Behavior:**
- Scans for matching patterns
- Logs all files that *would* be deleted
- No files are actually removed
- Log file clearly marked as "PREVIEW"
- User can review log and confirm it's safe to run

**Confirmation gate:** Actual deletion requires the `-Confirm` switch. Running without `-DryRun` but also without `-Confirm` behaves exactly like a dry run (preview only, exit code 1). Only `-Confirm` without `-DryRun` deletes files.

### Traversal Limits and Scope Warnings

- **`-MaxDepth`** (default 10): limits recursion depth below `TargetDir` to prevent runaway traversal of deep trees.
- **`-MaxFiles`** (default 100000): if the scanned tree contains more files, the script aborts without deleting anything; raise the limit explicitly if intentional.
- **Scope warnings**: the script emits prominent warnings when `TargetDir` resolves outside the current location, or is a drive root / user home directory. Treat these as a strong signal to narrow the target.

### Script Location

```
<skill-dir>/purge-junk-files.ps1
```

The script is self-contained and includes complete parameter validation, error handling, and logging.

### File Deletion Mechanism

- **PowerShell:** `Remove-Item -Path $filePath -Force`
- Files are deleted individually with error handling per file
- Locked/in-use files are caught and logged without halting the process
- Recursive directory traversal ensures all subdirectories are processed

### Error Handling

- Skips locked or in-use files and logs the error
- Continues processing remaining files (non-fatal errors)
- Reports summary: files deleted, skipped, errors
- Non-fatal errors do not halt execution
- Errors are tagged with timestamp in log

### Pattern Matching Logic

The script identifies junk files by:

1. **Extension matching** — `*.bak`, `*.old`, `*.backup`, etc.
2. **Wildcard patterns** — `file.*`, `*temp*`, etc.
3. **Numeric suffix patterns** — `*.[0-9][0-9]*.*` matches files with at least two consecutive digits in a dot-separated segment (sequential backup numbers, dates, etc.)
4. **File exclusions** — `exclude` list in `patterns.json` protects specific file types from deletion regardless of pattern matches
5. **Custom patterns** — User can override with `-Patterns` parameter

### Operation Summary

After completion, the log file includes:

```
======== Summary ========
Total files processed:     1,245
Files deleted/would delete:  287
Files skipped:               958
Errors encountered:            3
Completed: 2026-03-16 14:37:22
```

For dry-run mode, the footer includes:
```
*** DRY RUN MODE - NO FILES WERE ACTUALLY DELETED ***
Review this log and re-run without -DryRun flag to execute.
```

## Troubleshooting

### Issue: "Target directory not found"

- **Check:** Ensure the path is correct and relative to your current working directory
- **Solution:** Use absolute path or `cd` to the workspace root first

### Issue: Files Not Being Deleted

- **Check:** Run with `-DryRun` first to see what patterns match
- **Check:** Verify patterns are correct and match your filenames
- **Check:** Confirm file permissions allow deletion
- **Check:** Review the log file for specific errors

### Issue: "Access to the path is denied"

- **Cause:** File is locked by another process (editor, compiler, etc.)
- **Solution:** Close the file in the editor and try again
- **Note:** Script logs these as errors and continues with other files

### Issue: Deleted Files That Shouldn't Have Been

- **Prevention:** ALWAYS run with `-DryRun` first and review the log!
- **Recovery:** Use version control (`git checkout`) to restore deleted files
- **Prevention:** Use custom `-Patterns` if you need more control

## Getting Help

### View Script Parameters and Documentation

```powershell
Get-Help -Full <skill-dir>\purge-junk-files.ps1
```

### Customize Patterns for Your Project

Edit the patterns configuration file:
```powershell
# Open in your editor
notepad <skill-dir>\patterns.json
```

Add or remove patterns as needed, then save. The script will automatically load your customized patterns.

### Check Recent Logs

```powershell
# List last 5 operation logs
ls cleanup-reports/purge-junk-files-*.log | Sort-Object LastWriteTime -Descending | Select-Object -First 5 | Select-Object Name, LastWriteTime

# View latest log
$latest = ls cleanup-reports/purge-junk-files-*.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Get-Content $latest.FullName | Select-Object -Last 50
```

## References

- [PowerShell Remove-Item documentation](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/remove-item)
- [Linux rm command documentation](https://man7.org/linux/man-pages/man1/rm.1.html)

## Notes

- This skill should be idempotent (safe to run multiple times)
- Consider integrating with version control workflows
- Document all patterns being removed for team awareness

---

**Status:** Complete
**Last Updated:** March 16, 2026
**Script Location:** [purge-junk-files.ps1](purge-junk-files.ps1)

## Script integrity

Verify the bundled script(s) before first use: `Get-FileHash <file> -Algorithm SHA256` and compare to the values below. If a hash does not match, stop and review the file before executing. Hashes are regenerated whenever a bundled script changes (see the skills README).

| File | SHA-256 |
|---|---|
| `purge-junk-files.ps1` | `5242FE08FC9F5B544A9904F43263FE44951F452281A642BE2EDCC8738A415C92` |
