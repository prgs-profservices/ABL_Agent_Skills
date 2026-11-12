# Copyright 2026 Progress Software Corporation
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
    Analyzes an OpenEdge PROFILER v3 .out file and reports the hottest source lines
    by exclusive (self) CPU time.

.DESCRIPTION
    Parses two sections of the OpenEdge profiler output:
      Section 1 (Module)      - moduleId to class/method name mapping
      Section 3 (LineSummary) - per-line execution counts and timing
                                Format: moduleId lineNum execCount actualTime cumulativeTime
                                actualTime = exclusive self-time (no callees)
                                cumulativeTime = inclusive time (with callees)

    By default, test classes (test.*), ABLUnit framework (OpenEdge.*), and the
    profiling harness (scratch/profile_tests) are excluded.  Use -ShowTestCode
    to include them.

    When -ProjectRoot is supplied, the script reads the actual source line for each
    result and includes it in the output as a SourceLine column.

    Section transitions: Coverage (section 5) needs two consecutive "."s to exit;
    Statistics (section 6) is skipped for version 3.

    For a full-featured visual profiler experience, consider using the pro-peek
    VS Code extension to explore the raw profiler output in detail.

.PARAMETER ProfileFile
    Path to the .out file produced by the OpenEdge PROFILER.

.PARAMETER TopN
    Number of hottest entries to display.  Default: 30.

.PARAMETER Filter
    Optional substring include-filter on module/method name.
    e.g. "myapp" to show only a specific package.  Default: show all non-test code.

.PARAMETER SortBy
    "actual"     - sort by exclusive self-time (default, best for finding hot lines)
    "cumulative" - sort by inclusive time (best for finding slow call chains)

.PARAMETER ShowTestCode
    When specified, include test classes, ABLUnit framework, and profile harness
    entries that are excluded by default.

.PARAMETER ProjectRoot
    Root of the source tree (e.g. "C:\apps\MyApp").  When provided, the script
    reads the actual source line for each result and shows it as SourceLine.
    Looks for source files under <ProjectRoot>\src\.  Default: current directory.

.PARAMETER OutputJson
    When specified, emit results as a JSON array instead of a formatted table.
    Intended for AI-chat consumption: the caller formats the JSON into a Markdown
    table with clickable vscode://file/ links.

.EXAMPLE
    .\analyze-profile.ps1 .profile\20260623_154646.out -TopN 30 -ProjectRoot C:\apps\MyApp
    .\analyze-profile.ps1 .profile\20260623_154646.out -TopN 20 -SortBy cumulative -ProjectRoot .
    .\analyze-profile.ps1 .profile\20260623_154646.out -ShowTestCode -TopN 40
    .\analyze-profile.ps1 .profile\20260623_154646.out -TopN 15 -OutputJson -ProjectRoot C:\apps\MyApp
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$ProfileFile,

    [int]$TopN = 30,

    [string]$Filter = "",

    [ValidateSet("actual","cumulative")]
    [string]$SortBy = "actual",

    [switch]$ShowTestCode,

    [string]$ProjectRoot = ".",

    [switch]$OutputJson
)

if (-not (Test-Path $ProfileFile)) {
    Write-Error "File not found: $ProfileFile"
    exit 1
}

Write-Verbose "Reading $ProfileFile ..."

# ---------------------------------------------------------------------------
# Single-pass section-aware parse
# Sections (v3): 0=Description 1=Module 2=CallGraph 3=LineSummary 4=Tracing
#                5=Coverage(multi-dot) 6=Statistics(skipped) 7=CallTree 8=UserData
# ---------------------------------------------------------------------------
$moduleNames          = @{}   # moduleId -> display name
$moduleClassName      = @{}   # moduleId -> bare class name (for listing file lookup)
$classListingFile     = @{}   # className -> listingFile basename
$moduleListingStartLine = @{} # moduleId -> listing-file line where method starts (v3 LineNum)
$listingDir           = ""    # directory containing listing files (from profile header)
$lineSummary          = @{}   # "moduleId:lineNum" -> [execCount, actualTime, cumulativeTime]

$section  = 0
$lastLine = ""

foreach ($rawLine in [System.IO.File]::ReadLines($ProfileFile)) {
    $line = $rawLine.TrimEnd()

    if ($line -eq '.') {
        if ($section -ne 5) {
            # Normal advance
            $section++
            # Skip Statistics for version 3
            if ($section -eq 6) { $section++ }
        }
        elseif ($lastLine -eq '.') {
            # Two consecutive dots = exit Coverage
            $section++   # 6 = Statistics, skipped for v3
            $section++   # 7 = CallTree
        }
        $lastLine = $line
        continue
    }

    switch ($section) {
        0 {
            # Description line - extract listing directory from embedded JSON
            # Format: 3 <date> "desc" <time> "" {json}
            if ($line -match '\{.*"Directory"\s*:\s*"([^"]+)"') {
                $listingDir = $Matches[1].TrimEnd('\', '/')
            }
        }
        1 {
            # Module entry: moduleId "desc" "listingFile" crcVal lineNum ""
            $parts = $line -split '"'
            if ($parts.Count -ge 6) {
                $modId       = [int]$parts[0].Trim()
                $desc        = $parts[1]
                $listingFile = $parts[3]
                # "methodName className className" -> className::methodName
                # (extension removes duplicate third token when [1]==[2])
                $np = $desc -split ' '
                if ($np.Count -eq 3 -and $np[1] -eq $np[2]) {
                    $name      = "$($np[1])::$($np[0])"
                    $className = $np[1]
                } else {
                    $name      = $desc
                    $className = $desc   # class-level entry
                }
                $moduleNames[$modId]     = $name
                $moduleClassName[$modId] = $className
                # Class entries have a non-empty listing file
                if ($listingFile -ne '' -and -not $classListingFile.ContainsKey($className)) {
                    $classListingFile[$className] = $listingFile
                }
                # Store listing-file start line for method entries (v3 LineNum field)
                # This is used to compute the offset to the source file line number.
                $nums = $parts[4].Trim() -split '\s+'
                if ($nums.Count -ge 2) {
                    $moduleListingStartLine[$modId] = [int]$nums[1]
                }
            }
        }
        3 {
            # LineSummary: moduleId lineNum execCount actualTime cumulativeTime
            $parts = $line -split '\s+'
            if ($parts.Count -ge 5) {
                $modId   = [int]$parts[0]
                $lineNum = [int]$parts[1]
                $execCnt = [int]$parts[2]
                $actual  = [double]$parts[3]
                $cumul   = [double]$parts[4]

                if ($lineNum -lt 0) { $lastLine = $line; continue }

                $key = "$modId`:$lineNum"
                if ($lineSummary.ContainsKey($key)) {
                    $lineSummary[$key][0] += $execCnt
                    $lineSummary[$key][1] += $actual
                    $lineSummary[$key][2] += $cumul
                } else {
                    $lineSummary[$key] = @($execCnt, $actual, $cumul)
                }
            }
        }
    }

    $lastLine = $line
}

Write-Verbose "Modules indexed:      $($moduleNames.Count)"
Write-Verbose "LineSummary entries:  $($lineSummary.Count)"
Write-Verbose "Listing directory:    $(if ($listingDir) { $listingDir } else { `"(none)`" })"

# ---------------------------------------------------------------------------
# Source line lookup helpers
# Priority: listing file (exact profiler line mapping, include-expanded)
#           -> source file (dotted class name -> src/ path, may have offset from includes)
# Files are cached by absolute path to avoid re-reading.
# Listing file format per line: <9-char right-justified line num>   <source code>
# ---------------------------------------------------------------------------
$fileLineCache = @{}   # absolutePath -> string[]

function Get-CachedLines {
    param([string]$AbsPath, [hashtable]$Cache)
    if (-not $Cache.ContainsKey($AbsPath)) {
        $Cache[$AbsPath] = if (Test-Path $AbsPath) { [System.IO.File]::ReadAllLines($AbsPath) } else { $null }
    }
    return $Cache[$AbsPath]
}

function Resolve-SourcePath {
    param([string]$ClassName, [string]$Root)
    if ($ClassName -match '^[A-Za-z]:\\' -or $ClassName -match '^/') { return $ClassName }
    $relPath = $ClassName -replace '\.', [System.IO.Path]::DirectorySeparatorChar
    foreach ($ext in @('.cls', '.p', '.w')) {
        foreach ($base in @("$Root\src\$relPath$ext", "$Root\$relPath$ext")) {
            if (Test-Path $base) { return $base }
        }
    }
    return $null
}

function Get-SourceLine {
    param(
        [int]$ModId, [int]$LineNum, [string]$Root,
        [hashtable]$Cache,
        [hashtable]$ModNames, [hashtable]$ModClassNames,
        [hashtable]$ClassListings, [string]$LDir
    )
    if ($LineNum -le 0) { return '' }

    $modName   = if ($ModNames.ContainsKey($ModId)) { $ModNames[$ModId] } else { '' }
    $className = if ($ModClassNames.ContainsKey($ModId)) { $ModClassNames[$ModId] } else { ($modName -split '::')[0] }

    # 1. Prefer listing file: line numbers match exactly, include expansions intact
    if ($LDir -ne '' -and $ClassListings.ContainsKey($className)) {
        $listingPath = Join-Path $LDir $ClassListings[$className]
        $lines = Get-CachedLines -AbsPath $listingPath -Cache $Cache
        if ($null -ne $lines -and $LineNum -le $lines.Count) {
            # Strip the embedded line-number prefix: "<9-char num>   "
            $raw = $lines[$LineNum - 1] -replace '^\s*\d+\s{3}', ''
            return $raw.Trim()
        }
    }

    # 2. Fall back to original source file (may be offset by include expansions)
    $srcPath = Resolve-SourcePath -ClassName $className -Root $Root
    if ($null -ne $srcPath) {
        $lines = Get-CachedLines -AbsPath $srcPath -Cache $Cache
        if ($null -ne $lines -and $LineNum -le $lines.Count) {
            return $lines[$LineNum - 1].Trim()
        }
    }

    return ''
}

$resolvedRoot = (Resolve-Path $ProjectRoot -ErrorAction SilentlyContinue).Path
if (-not $resolvedRoot) { $resolvedRoot = $ProjectRoot }

# ---------------------------------------------------------------------------
# Exact source line mapping via diff
#
# Strategy: strip the embedded line-number prefix from the listing file, write
# to a temp file, then run "git diff --no-index --unified=0" against the real
# source.  Parse the @@ hunk headers to build a cumulative offset table:
#
#   @@ -lstLine,lstCount +srcLine,srcCount @@
#   => listing lines [lstLine .. lstLine+lstCount-1] are expansions of srcCount
#      source lines starting at srcLine.
#
# For any listing line N:
#   offset(N) = sum of (lstCount - srcCount) for all hunks where lstLine <= N
#   source_line = N - offset(N)
#
# The table is built once per class and cached.  Falls back to 0 offset when
# git is unavailable or no listing file exists.
# ---------------------------------------------------------------------------
$classOffsetTable    = @{}   # className -> int[] indexed by listing line (1-based), value = source line

function Get-ListingOffsetTable {
    param(
        [string]$ClassName,
        [hashtable]$ClassListings, [string]$LDir,
        [hashtable]$TableCache, [hashtable]$FileCache,
        [string]$Root
    )
    if ($TableCache.ContainsKey($ClassName)) { return $TableCache[$ClassName] }

    $TableCache[$ClassName] = $null   # mark as attempted

    if ($LDir -eq '' -or -not $ClassListings.ContainsKey($ClassName)) { return $null }
    $listingPath = Join-Path $LDir $ClassListings[$ClassName]
    if (-not (Test-Path $listingPath)) { return $null }

    $srcPath = Resolve-SourcePath -ClassName $ClassName -Root $Root
    if ($null -eq $srcPath -or -not (Test-Path $srcPath)) { return $null }

    # Write stripped listing to a temp file
    $tmpFile = [System.IO.Path]::GetTempFileName()
    try {
        $listingLines = Get-CachedLines -AbsPath $listingPath -Cache $FileCache
        if ($null -eq $listingLines) { return $null }
        $stripped = $listingLines | ForEach-Object { $_ -replace '^\s*\d+\s{3}', '' }
        [System.IO.File]::WriteAllLines($tmpFile, $stripped, [System.Text.Encoding]::UTF8)

        # Run git diff to get unified hunk headers
        $diffOut = & git diff --no-index --unified=0 $tmpFile $srcPath 2>$null
        if ($null -eq $diffOut) { return $null }

        # Parse @@ -lstStart,lstCount +srcStart,srcCount @@ lines
        # Build hunks list sorted by lstStart
        $hunks = [System.Collections.Generic.List[object]]::new()
        foreach ($diffLine in $diffOut) {
            if ($diffLine -match '^@@\s+-(\d+)(?:,(\d+))?\s+\+(\d+)(?:,(\d+))?\s+@@') {
                $lstStart  = [int]$Matches[1]
                $lstCount  = if ($Matches[2]) { [int]$Matches[2] } else { 1 }
                $srcStart  = [int]$Matches[3]
                $srcCount  = if ($Matches[4]) { [int]$Matches[4] } else { 1 }
                $hunks.Add([PSCustomObject]@{ LstStart=$lstStart; LstCount=$lstCount; SrcStart=$srcStart; SrcCount=$srcCount })
            }
        }

        # Build per-listing-line source-line lookup array
        # Size = number of listing lines
        $tableSize = $listingLines.Count
        $table = New-Object int[] ($tableSize + 1)   # 1-based; index 0 unused

        $hunkIdx  = 0
        $cumOffset = 0   # sum of (lstCount - srcCount) for all hunks processed so far

        for ($lstLine = 1; $lstLine -le $tableSize; $lstLine++) {
            # Apply any hunks that START at or before this line
            while ($hunkIdx -lt $hunks.Count -and $hunks[$hunkIdx].LstStart -le $lstLine) {
                $cumOffset += ($hunks[$hunkIdx].LstCount - $hunks[$hunkIdx].SrcCount)
                $hunkIdx++
            }
            $table[$lstLine] = $lstLine - $cumOffset
        }

        $TableCache[$ClassName] = $table
        return $table
    } finally {
        Remove-Item $tmpFile -ErrorAction SilentlyContinue
    }
}

function Get-SourceLineNum {
    param(
        [int]$ModId, [int]$ListingLineNum,
        [hashtable]$ModClassNames,
        [hashtable]$ClassListings, [string]$LDir,
        [hashtable]$TableCache, [hashtable]$FileCache,
        [string]$Root
    )
    if ($ListingLineNum -le 0) { return 0 }

    $className = if ($ModClassNames.ContainsKey($ModId)) { $ModClassNames[$ModId] } else { '' }
    if ($className -eq '') { return 0 }

    $table = Get-ListingOffsetTable -ClassName $className `
                 -ClassListings $ClassListings -LDir $LDir `
                 -TableCache $TableCache -FileCache $FileCache -Root $Root

    if ($null -eq $table -or $ListingLineNum -ge $table.Length) { return 0 }
    $srcLine = $table[$ListingLineNum]
    if ($srcLine -gt 0) { return $srcLine }   # 0 or negative = inside an include expansion zone
    return 0
}

# ---------------------------------------------------------------------------
# Build raw result objects (fast ? no git diff, no file I/O beyond listing)
# Source line enrichment runs only for the final top-N rows below.
# ---------------------------------------------------------------------------
$results = foreach ($key in $lineSummary.Keys) {
    $kparts  = $key -split ':'
    $modId   = [int]$kparts[0]
    $lineNum = [int]$kparts[1]
    $name    = if ($moduleNames.ContainsKey($modId)) { $moduleNames[$modId] } else { "module_$modId" }
    $execCnt = $lineSummary[$key][0]
    $actual  = $lineSummary[$key][1]
    $cumul   = $lineSummary[$key][2]
    $avgMs   = if ($execCnt -gt 0) { ($actual / $execCnt * 1000) } else { 0 }

    [PSCustomObject]@{
        Module    = $name
        ModId     = $modId
        LstLine   = $lineNum
        ActualSec = [math]::Round($actual, 6)
        CumulSec  = [math]::Round($cumul,  6)
        ExecCount = $execCnt
        AvgMs     = [math]::Round($avgMs,  4)
    }
}

# ---------------------------------------------------------------------------
# Filter, sort, select top N
# ---------------------------------------------------------------------------

# Default exclusions: test classes, ABLUnit framework, profiling harness
if (-not $ShowTestCode) {
    $results = $results | Where-Object {
        $_.Module -notlike 'test.*'          -and   # test classes
        $_.Module -notlike 'OpenEdge.*'      -and   # ABLUnit / OE framework
        $_.Module -notlike 'scratch*'        -and   # scratch programs
        $_.Module -notlike '*profile_tests*'         # profiling harness (any path form)
    }
}

if ($Filter -ne '') {
    $results = $results | Where-Object { $_.Module -like "*$Filter*" }
}

$sortProp = if ($SortBy -eq 'cumulative') { 'CumulSec' } else { 'ActualSec' }
$top      = $results | Sort-Object -Property $sortProp -Descending | Select-Object -First $TopN

# ---------------------------------------------------------------------------
# Enrich top-N rows with source code and exact source line (git diff runs here,
# once per unique class, only for the rows we are about to display)
# ---------------------------------------------------------------------------
$top = foreach ($row in $top) {
    $modId   = $row.ModId
    $lineNum = $row.LstLine

    $className = if ($moduleClassName.ContainsKey($modId)) { $moduleClassName[$modId] } else { ($row.Module -split '::')[0] }
    $srcPath   = Resolve-SourcePath -ClassName $className -Root $resolvedRoot

    $codeText = Get-SourceLine -ModId $modId -LineNum $lineNum -Root $resolvedRoot `
                               -Cache $fileLineCache `
                               -ModNames $moduleNames -ModClassNames $moduleClassName `
                               -ClassListings $classListingFile -LDir $listingDir
    if ($codeText.Length -gt 55) { $codeText = $codeText.Substring(0, 52) + '...' }

    $srcLineNum = Get-SourceLineNum -ModId $modId -ListingLineNum $lineNum `
                      -ModClassNames $moduleClassName `
                      -ClassListings $classListingFile -LDir $listingDir `
                      -TableCache $classOffsetTable -FileCache $fileLineCache `
                      -Root $resolvedRoot

    [PSCustomObject]@{
        Module     = $row.Module
        LstLine    = $lineNum
        SrcLine    = $srcLineNum
        ActualSec  = $row.ActualSec
        CumulSec   = $row.CumulSec
        ExecCount  = $row.ExecCount
        AvgMs      = $row.AvgMs
        SourceCode = $codeText
        SrcPath    = $srcPath
    }
}
if ($OutputJson) {
    # ---------------------------------------------------------------------------
    # JSON output ? for AI chat consumption.  The caller (Cascade) formats this
    # into a Markdown table with clickable vscode://file/ links.
    # ---------------------------------------------------------------------------
    $jsonRows = $top | ForEach-Object {
        $fwdPath = if ($null -ne $_.SrcPath) { $_.SrcPath -replace '\\', '/' } else { $null }
        $uri     = if ($null -ne $fwdPath -and $_.SrcLine -gt 0) { "vscode://file/$fwdPath`:$($_.SrcLine)" } `
                   elseif ($null -ne $fwdPath)                   { "vscode://file/$fwdPath" } `
                   else                                          { $null }
        [ordered]@{
            Module     = $_.Module
            LstLine    = $_.LstLine
            SrcLine    = $_.SrcLine
            ActualSec  = $_.ActualSec
            CumulSec   = $_.CumulSec
            ExecCount  = $_.ExecCount
            AvgMs      = $_.AvgMs
            SourceCode = $_.SourceCode
            Uri        = $uri
        }
    }
    $jsonRows | ConvertTo-Json -Depth 3
} else {
    # ---------------------------------------------------------------------------
    # Formatted table + clickable URIs for direct terminal use
    # ---------------------------------------------------------------------------
    $filterLabel = if ($Filter) { $Filter } else { '(none)' }
    $exclLabel   = if ($ShowTestCode) { 'all' } else { 'prod only' }

    Write-Host ""
    Write-Host "Top $TopN hottest lines  [sort=$SortBy  filter=$filterLabel  scope=$exclLabel]" -ForegroundColor Yellow
    Write-Host ("-" * 130)
    $top | Format-Table -AutoSize Module, LstLine, SrcLine, ActualSec, CumulSec, ExecCount, AvgMs, SourceCode

    Write-Host "File links (Ctrl+click to open in editor):" -ForegroundColor Cyan
    $iRank = 0
    foreach ($row in $top) {
        $iRank++
        if ($null -ne $row.SrcPath) {
            $fwdPath = $row.SrcPath -replace '\\', '/'
            $uri     = if ($row.SrcLine -gt 0) { "vscode://file/$fwdPath``:$($row.SrcLine)" } `
                       else                    { "vscode://file/$fwdPath" }
            Write-Host ("  #{0,-3} {1}" -f $iRank, $uri) -ForegroundColor DarkCyan
        } else {
            Write-Host ("  #{0,-3} (source not found)  {1}" -f $iRank, $row.Module)
        }
    }
}
