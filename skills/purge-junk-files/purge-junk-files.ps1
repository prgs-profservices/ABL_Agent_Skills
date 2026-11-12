# Copyright 2026 Progress Software Corporation
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
    Purge junk files and backups from an ABL codebase. See SKILL.md for full docs.
.DESCRIPTION
    Deletes files matching junk patterns under -TargetDir. Deletion requires -Confirm;
    without it (or with -DryRun) the script only previews. Traversal is bounded by
    -MaxDepth (default 10) and -MaxFiles (default 100000). All runs are logged to
    cleanup-reports/. Patterns come from -Patterns, patterns.json, or built-in defaults.
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TargetDir,

    [string[]]$Patterns,

    [switch]$DryRun,

    [string[]]$Exclude = @(),

    [string]$LogPath,

    [switch]$Confirm,

    [ValidateRange(1, 50)]
    [int]$MaxDepth = 10,

    [ValidateRange(1, 500000)]
    [int]$MaxFiles = 100000
)

$ErrorActionPreference = 'Stop'

# If patterns not provided, try to load from patterns.json
$ExcludeFilePatterns = @()
if (-not $Patterns) {
    $patternsJsonPath = Join-Path $PSScriptRoot "patterns.json"
    if (Test-Path $patternsJsonPath) {
        try {
            $patternsConfig = Get-Content $patternsJsonPath -Raw | ConvertFrom-Json
            if ($patternsConfig.patterns -and $patternsConfig.patterns.Count -gt 0) {
                $Patterns = @($patternsConfig.patterns)
                Write-Verbose "Loaded patterns from patterns.json: $($Patterns -join ', ')"
            }
            if ($patternsConfig.exclude -and $patternsConfig.exclude.Count -gt 0) {
                $ExcludeFilePatterns = @($patternsConfig.exclude)
                Write-Verbose "Loaded file excludes from patterns.json: $($ExcludeFilePatterns -join ', ')"
            }
        }
        catch {
            Write-Verbose "Could not parse patterns.json, using built-in defaults: $_"
        }
    }
}

# Use built-in defaults if no patterns found
if (-not $Patterns) {
    $Patterns = @(
        "*.bak",
        "*.old",
        "*.backup",
        "*.orig",
        "*.tmp",
        "*.[0-9][0-9]*.*",
        "* - Copy.*",
        "* - Copy (*.*",
        "*-OLD.*"
    )
}

# Ensure target directory exists
if (-not (Test-Path $TargetDir)) {
    Write-Error "Target directory not found: $TargetDir"
    exit 1
}

$TargetDir = (Resolve-Path $TargetDir).Path

# --- Scope safety checks ---
$script:warnings = @()
$cwd = (Get-Location).Path.TrimEnd('\', '/')
$targetNormalized = $TargetDir.TrimEnd('\', '/')

if (-not ($targetNormalized.StartsWith($cwd, [System.StringComparison]::OrdinalIgnoreCase))) {
    $script:warnings += "Target directory '$TargetDir' is OUTSIDE the current location '$cwd'. Deletion requires -Confirm and should be reviewed carefully."
}
if ($targetNormalized -match '^[A-Za-z]:$' -or $targetNormalized -ieq [Environment]::GetFolderPath('UserProfile').TrimEnd('\', '/')) {
    $script:warnings += "Target directory '$TargetDir' is a drive root or user home directory. This is almost certainly too broad."
}

# Deletion gate: actual deletion requires explicit -Confirm. Without it, behave like a dry run.
$effectiveDryRun = $DryRun
if (-not $DryRun -and -not $Confirm) {
    $effectiveDryRun = $true
    $script:warnings += "No -Confirm switch supplied: running in preview mode only. Re-run with -Confirm to actually delete files."
}

# Reject overly broad patterns that could match everything
$broadPatterns = @('*', '*.*', '*.*.*')
$detectedBroad = $Patterns | Where-Object { $_ -in $broadPatterns }
if ($detectedBroad) {
    Write-Error "Pattern '$($detectedBroad -join ', ')' is too broad and could match all files. Use specific extensions (e.g., '*.bak', '*.tmp') instead."
    exit 1
}

# Create cleanup-reports directory if it doesn't exist
$candidateLogsDir = Join-Path $TargetDir "..\..\cleanup-reports"
$resolvedLogsDir = Resolve-Path $candidateLogsDir -ErrorAction SilentlyContinue
if ($resolvedLogsDir) {
    $logsDir = $resolvedLogsDir.Path
} else {
    $logsDir = Join-Path (Get-Location) "cleanup-reports"
}

if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}

# Set log file path
if (-not $LogPath) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $logFileName = "purge-junk-files-$timestamp.log"
    $LogPath = Join-Path $logsDir $logFileName
}

# Initialize counters and collections
$filesDeleted = 0
$errorsEncountered = 0
$allFiles = @()
$deletedFiles = @()
$errorFiles = @()

# Start logging
$logContent = @()
$logContent += "======== Purge Junk Files Log ========"
$logContent += "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$logContent += "Mode: $(if ($effectiveDryRun) { if ($DryRun) { 'DRY RUN (preview only)' } else { 'PREVIEW (no -Confirm supplied; nothing deleted)' } } else { 'EXECUTE (files will be deleted)' })"
$logContent += "Limits: MaxDepth=$MaxDepth, MaxFiles=$MaxFiles"
foreach ($w in $script:warnings) { $logContent += "WARNING: $w" }
$logContent += "Target Directory: $TargetDir"
$logContent += "Log File: $LogPath"
$logContent += "Patterns: $($Patterns -join ', ')"
if ($Exclude.Count -gt 0) { $logContent += "Excluded Dirs: $($Exclude -join ', ')" }
if ($ExcludeFilePatterns.Count -gt 0) { $logContent += "Excluded File Patterns: $($ExcludeFilePatterns -join ', ')" }
$logContent += ""
$logContent += "Processing files..."
$logContent += ""

function Test-ExcludedPath {
    param([string]$Path)
    foreach ($excludePattern in $Exclude) {
        if ($Path -like "*\$excludePattern\*" -or $Path -like "*/$excludePattern/*") {
            return $true
        }
    }
    return $false
}

function Test-PatternMatch {
    param([string]$FileName, [string[]]$Patterns)

    foreach ($pattern in $Patterns) {
        if ($FileName -like $pattern) {
            return $true
        }
        # Regex fallback for patterns like *.283091287.p
        try {
            $regexPattern = $pattern `
                -replace '\.', '\.' `
                -replace '\*', '.*' `
                -replace '\[', '{' `
                -replace '\]', '}'

            if ($FileName -match "^$regexPattern$") {
                return $true
            }
        }
        catch {
            # Silently skip invalid regex
        }
    }

    return $false
}

# Scan for matching files (depth-limited)
try {
    $allFiles = Get-ChildItem -Path $TargetDir -Recurse -Depth $MaxDepth -File -ErrorAction Continue |
        Where-Object { -not (Test-ExcludedPath $_.FullName) }

    $logContent += "Total files scanned: $($allFiles.Count)"
}
catch {
    $logContent += "ERROR: Failed to scan target directory: $_"
    $errorsEncountered++
}

# Enforce MaxFiles outside the try/catch so the abort cannot be swallowed by the catch block
if ($allFiles.Count -gt $MaxFiles) {
    $logContent += "ERROR: Scanned file count ($($allFiles.Count)) exceeds MaxFiles limit ($MaxFiles). Aborting. Raise -MaxFiles explicitly if this is intentional."
    $logContent | Out-File -FilePath $LogPath -Encoding UTF8 -ErrorAction SilentlyContinue
    Write-Host "ABORTED: Scanned file count ($($allFiles.Count)) exceeds MaxFiles limit ($MaxFiles). Nothing was deleted. Raise -MaxFiles explicitly if this is intentional."
    exit 1
}

# Process matching files
foreach ($file in $allFiles) {
    $isExcluded = $false
    foreach ($xp in $ExcludeFilePatterns) { if ($file.Name -like $xp) { $isExcluded = $true; break } }
    if (-not $isExcluded -and (Test-PatternMatch $file.Name $Patterns)) {
        $fileRel = $file.FullName.Replace("$TargetDir\", "").Replace("$TargetDir/", "")

        if ($effectiveDryRun) {
            $logContent += "[PREVIEW] WOULD DELETE: $fileRel | Size: $($file.Length) bytes"
            $deletedFiles += $fileRel
            $filesDeleted++
        }
        else {
            try {
                $fileRel = $file.FullName.Replace("$TargetDir\", "").Replace("$TargetDir/", "")
                Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                $logContent += "[$(Get-Date -Format 'HH:mm:ss')] DELETE OK: $fileRel"
                $deletedFiles += $fileRel
                $filesDeleted++
            }
            catch {
                $logContent += "[$(Get-Date -Format 'HH:mm:ss')] DELETE ERROR: $fileRel | $_"
                $errorFiles += $fileRel
                $errorsEncountered++
            }
        }
    }
}

# Finalize log
$logContent += ""
$logContent += "======== Summary ========"
$logContent += "Total files processed: $($allFiles.Count)"
$logContent += "Files deleted/would delete: $filesDeleted"
$logContent += "Files skipped: $($allFiles.Count - $filesDeleted)"
$logContent += "Errors encountered: $errorsEncountered"
$logContent += "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

if ($effectiveDryRun) {
    $logContent += ""
    $logContent += "*** PREVIEW MODE - NO FILES WERE ACTUALLY DELETED ***"
    if ($DryRun) {
        $logContent += "Review this log and re-run with -Confirm (and without -DryRun) to execute."
    } else {
        $logContent += "Review this log and re-run with -Confirm to execute."
    }
}

$logContent += "===================="
$logContent += ""

# Write log file
try {
    $logContent | Out-File -FilePath $LogPath -Encoding UTF8 -ErrorAction Stop
}
catch {
    Write-Error "Failed to write log file: $_"
}

# Display summary to console
Write-Host ""
Write-Host "======== Purge Junk Files Summary ========"
Write-Host "Mode: $(if ($effectiveDryRun) { 'PREVIEW' } else { 'EXECUTE' })"
Write-Host "Target: $TargetDir"
Write-Host "Files scanned: $($allFiles.Count)"
Write-Host "Files deleted/preview-deleted: $filesDeleted"
Write-Host "Errors: $errorsEncountered"
Write-Host "Log file: $LogPath"
foreach ($w in $script:warnings) { Write-Warning $w }
Write-Host "=========================================="
Write-Host ""

if ($effectiveDryRun) {
    Write-Host "PREVIEW COMPLETE - No files were deleted."
    Write-Host "Review the log above and run again with -Confirm to execute."
    if (-not $DryRun -and -not $Confirm) { exit 1 }
}
else {
    Write-Host "Cleanup complete."
}

exit 0
