# Copyright 2026 Progress Software Corporation
# SPDX-License-Identifier: Apache-2.0

# Resolve workspace root: this script lives at <skills-root>/find-encrypted-source/
# (e.g. .claude/skills, .github/skills, .devin/skills) — three levels below the workspace.
$srcRoot = (Get-Item $PSScriptRoot).Parent.Parent.Parent.FullName
if (-not (Test-Path (Join-Path $srcRoot "openedge-project.json"))) {
    # Fallback: walk up from the current directory to find the project root
    $probe = (Get-Location).Path
    while ($probe -and -not (Test-Path (Join-Path $probe "openedge-project.json"))) {
        $parent = Split-Path -Parent $probe
        if (-not $parent -or $parent -eq $probe) { break }
        $probe = $parent
    }
    if (Test-Path (Join-Path $probe "openedge-project.json")) { $srcRoot = $probe }
}
$outFile  = Join-Path $srcRoot "docs\encrypted-source-scan.csv"
$docsDir  = Split-Path -Parent $outFile
if (-not (Test-Path $docsDir)) { New-Item -ItemType Directory -Path $docsDir -Force | Out-Null }

# ── Step 1: Read source directories from openedge-project.json ───────────────
$project = Get-Content (Join-Path $srcRoot "openedge-project.json") -Raw | ConvertFrom-Json
$sourcePaths = $project.buildPath | Where-Object { $_.type -eq "source" }

# ── Step 2: Collect ABL source files ─────────────────────────────────────────
$files = @()
foreach ($sp in $sourcePaths) {
    $baseDir  = Join-Path $srcRoot ($sp.path -replace '/', '\')
    $includes = if ($sp.includes) { $sp.includes -split ',' | ForEach-Object { $_.Trim() } } else { @() }

    if ($includes.Count -eq 0) {
        $files += Get-ChildItem $baseDir -Recurse -Include "*.p","*.w","*.i","*.cls" |
                  Select-Object *, @{N="SourceTree";E={$sp.path}}
    } else {
        foreach ($inc in $includes) {
            $subPath = $inc -replace '/\*\*$','' -replace '/','\'
            $subDir  = Join-Path $baseDir $subPath
            if (Test-Path $subDir) {
                $files += Get-ChildItem $subDir -Recurse -Include "*.p","*.w","*.i","*.cls" |
                          Select-Object *, @{N="SourceTree";E={$sp.path}}
            }
        }
    }
}

# ── Step 3 & 4: Detect encrypted files and build results ─────────────────────
$results = @()
$totalScanned = 0
foreach ($f in $files) {
    $allBytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $encrypted = ($allBytes.Length -gt 0 -and $allBytes[0] -eq 0x13)
    $relPath   = $f.FullName.Substring($srcRoot.Length + 1) -replace '\\','/'

    if ($encrypted) {
        $results += [pscustomobject]@{
            RelativePath = $relPath
            Directory    = $f.Directory.Name
            SourceTree   = $f.SourceTree
            Extension    = $f.Extension
            SizeBytes    = $allBytes.Length
        }
    }
    $totalScanned++
}

# ── Step 5: Write CSV ─────────────────────────────────────────────────────────
$results | Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8

# ── Step 6: Print summary ─────────────────────────────────────────────────────
$encCount   = $results.Count
$plainCount = $totalScanned - $encCount
$pct        = if ($totalScanned -gt 0) { [math]::Round($encCount / $totalScanned * 100, 1) } else { 0 }

""
"Total ABL files scanned : $totalScanned"
"Encrypted (XCODE)       : $encCount  ($pct%)"
"Plain text              : $plainCount"
""

"Top directories by encrypted file count:"
$results |
    Group-Object SourceTree, Directory | Sort-Object Count -Descending |
    Select-Object -First 10 |
    ForEach-Object { "  $($_.Count.ToString().PadLeft(4))  $($_.Name)" }

""
"Results written to: $outFile"
