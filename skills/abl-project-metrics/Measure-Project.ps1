# Copyright 2026 Progress Software Corporation
# SPDX-License-Identifier: Apache-2.0

#requires -Version 5.1
<#
.SYNOPSIS
    Computes size and scope metrics for an OpenEdge ABL project, keeping
    production functional source clearly separated from test source.

.DESCRIPTION
    Scans configured project directories for ABL source files (.cls, .p, .w, .i)
    and reports counts, byte sizes, line counts, and test cases.  Production and
    test populations are reported separately.  Optional operational and generated
    categories are shown for awareness but are not mixed into functional code totals.

.PARAMETER ProjectRoot
    Root directory of the project.  Defaults to the current working directory.

.PARAMETER ProductionPaths
    Directories that contain functional/production ABL source.  Defaults to
    common ABL source folders; override for your project layout.

.PARAMETER TestPaths
    Directories that contain ABLUnit test source.  Defaults to src\test.

.PARAMETER OperationalPaths
    Directories with operational/batch scripts (e.g. one-off .p files).  Shown
    separately and not included in functional code totals.

.PARAMETER GeneratedPaths
    Directories with generated r-code or other build outputs.  Shown for
    awareness but not included in source totals.

.PARAMETER SourceExtensions
    ABL source file extensions to include in scans.

.PARAMETER OutputFormat
    Output style: text, json, or markdown.  Default is markdown.

.PARAMETER OutputFile
    Optional path to write output.  When omitted, output goes to the console.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$ProjectRoot = ".",

    [Parameter()]
    [string[]]$ProductionPaths = @(
        "src\WebHandler",
        "src\liminalis",
        "src\procs",
        "src\system"
    ),

    [Parameter()]
    [string[]]$TestPaths = @(
        "src\test"
    ),

    [Parameter()]
    [string[]]$OperationalPaths = @(
        "scripts"
    ),

    [Parameter()]
    [string[]]$GeneratedPaths = @(
        "build\rcode",
        "rcode"
    ),

    [Parameter()]
    [string[]]$SourceExtensions = @(".cls", ".p", ".w", ".i"),

    [Parameter()]
    [ValidateSet("text", "json", "markdown")]
    [string]$OutputFormat = "markdown",

    [Parameter()]
    [string]$OutputFile
)

function Resolve-RelativeToRoot {
    param([string]$Path, [string]$Root)
    if ($Path.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
        $rel = $Path.Substring($Root.Length)
        if ($rel.StartsWith('\') -or $rel.StartsWith('/')) {
            return $rel.Substring(1)
        }
        return $rel
    }
    return $Path
}

function Get-CategoryFiles {
    param(
        [string]$Root,
        [string[]]$Paths,
        [string[]]$Extensions
    )

    $collected = @()
    foreach ($segment in $Paths) {
        $full = Join-Path -Path $Root -ChildPath $segment -Resolve -ErrorAction SilentlyContinue
        if (-not $full) { continue }
        if (Test-Path -LiteralPath $full -PathType Container) {
            $collected += Get-ChildItem -LiteralPath $full -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in $Extensions }
        }
        elseif (Test-Path -LiteralPath $full -PathType Leaf) {
            $collected += Get-Item -LiteralPath $full
        }
    }
    return $collected | Sort-Object FullName -Unique
}

function Measure-AblFile {
    param(
        [System.IO.FileInfo]$File,
        [string]$Root
    )
    $lines = [System.IO.File]::ReadAllLines($File.FullName)
    $total = $lines.Count
    $nonBlank = 0
    $codeLines = 0
    $testAnnotations = 0
    $testSuiteAnnotations = 0
    $inBlockComment = $false
    foreach ($line in $lines) {
        $trim = $line.Trim()
        if ($trim.Length -eq 0) { continue }
        $nonBlank++

        if ($trim -match '^\s*@Test\.') {
            $testAnnotations++
        }
        if ($trim -match '^\s*@TestSuite\(') {
            $testSuiteAnnotations++
        }

        # Very light comment counting: // single-line and /* ... */ blocks.
        if ($inBlockComment) {
            if ($trim -like '* */*' -or $trim -match '\*/\s*$') {
                $inBlockComment = $false
            }
            continue
        }
        if ($trim.StartsWith('//')) {
            continue
        }
        if ($trim.StartsWith('/*')) {
            if (-not ($trim -match '\*/' -or $trim -like '* */*')) {
                $inBlockComment = $true
            }
            continue
        }
        $codeLines++
    }

    return [PSCustomObject]@{
        RelativePath = Resolve-RelativeToRoot -Path $File.FullName -Root $Root
        Extension    = $File.Extension.ToLowerInvariant()
        Bytes        = $File.Length
        TotalLines   = $total
        NonBlank     = $nonBlank
        CodeLines    = $codeLines
        TestMethods  = $testAnnotations
        TestSuites   = $testSuiteAnnotations
    }
}

function Measure-Category {
    param(
        [string]$Name,
        [string]$Root,
        [string[]]$Paths,
        [string[]]$Extensions
    )

    $files = Get-CategoryFiles -Root $Root -Paths $Paths -Extensions $Extensions
    $metrics = foreach ($file in $files) { Measure-AblFile -File $file -Root $Root }

    return [PSCustomObject]@{
        Name          = $Name
        Files         = $metrics
        FileCount     = @($metrics).Count
        Bytes         = ($metrics | Measure-Object -Property Bytes -Sum).Sum
        TotalLines    = ($metrics | Measure-Object -Property TotalLines -Sum).Sum
        NonBlankLines = ($metrics | Measure-Object -Property NonBlank -Sum).Sum
        CodeLines     = ($metrics | Measure-Object -Property CodeLines -Sum).Sum
        TestMethods   = ($metrics | Measure-Object -Property TestMethods -Sum).Sum
        TestSuites    = ($metrics | Measure-Object -Property TestSuites -Sum).Sum
    }
}

function Format-ByteSize {
    param([long]$Bytes)
    if ($Bytes -ge 1MB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    }
    if ($Bytes -ge 1KB) {
        return "{0:N2} KB" -f ($Bytes / 1KB)
    }
    return "$Bytes B"
}

function Format-PerExtension {
    param([array]$Metrics, [switch]$IncludeTests)
    $properties = @('Bytes', 'TotalLines', 'NonBlank', 'CodeLines')
    if ($IncludeTests) { $properties += 'TestMethods' }
    $grouped = $Metrics | Group-Object -Property Extension
    $rows = foreach ($g in $grouped | Sort-Object Name) {
        $s = $g.Group | Measure-Object -Property $properties -Sum
        $row = [ordered]@{
            Extension     = $g.Name
            Files         = $g.Count
            Bytes         = ($s | Where-Object { $_.Property -eq 'Bytes' }).Sum
            TotalLines    = ($s | Where-Object { $_.Property -eq 'TotalLines' }).Sum
            NonBlankLines = ($s | Where-Object { $_.Property -eq 'NonBlank' }).Sum
            CodeLines     = ($s | Where-Object { $_.Property -eq 'CodeLines' }).Sum
        }
        if ($IncludeTests) {
            $row['TestMethods'] = ($s | Where-Object { $_.Property -eq 'TestMethods' }).Sum
        }
        [PSCustomObject]$row
    }
    return $rows
}

$root = Resolve-Path -Path $ProjectRoot -ErrorAction SilentlyContinue
if (-not $root) {
    throw "Project root not found: $ProjectRoot"
}

$production  = Measure-Category -Name 'Production'  -Root $root -Paths $ProductionPaths  -Extensions $SourceExtensions
$test        = Measure-Category -Name 'Test'        -Root $root -Paths $TestPaths        -Extensions $SourceExtensions
$operational = Measure-Category -Name 'Operational' -Root $root -Paths $OperationalPaths -Extensions $SourceExtensions
$generated   = Measure-Category -Name 'Generated'   -Root $root -Paths $GeneratedPaths   -Extensions @('.r')

$totalSourceFiles = $production.FileCount + $test.FileCount
$totalSourceBytes = $production.Bytes + $test.Bytes
$totalSourceCode  = $production.CodeLines + $test.CodeLines

$output = ""

if ($OutputFormat -eq 'text') {
    $output = @"
Project metrics for: $root
Generated on: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

PRODUCTION SOURCE
  Files:          $($production.FileCount)
  Bytes:          $(Format-ByteSize $production.Bytes)
  Total lines:    $($production.TotalLines)
  Non-blank:      $($production.NonBlankLines)
  Code lines:     $($production.CodeLines)

TEST SOURCE
  Files:          $($test.FileCount)
  Bytes:          $(Format-ByteSize $test.Bytes)
  Total lines:    $($test.TotalLines)
  Non-blank:      $($test.NonBlankLines)
  Code lines:     $($test.CodeLines)
  @Test methods:  $($test.TestMethods)
  @TestSuite entries: $($test.TestSuites)

OPERATIONAL/BATCH
  Files:          $($operational.FileCount)
  Bytes:          $(Format-ByteSize $operational.Bytes)
  Total lines:    $($operational.TotalLines)

GENERATED R-CODE
  Files:          $($generated.FileCount)
  Bytes:          $(Format-ByteSize $generated.Bytes)

RATIOS
  Test files per production file: $(if($production.FileCount -gt 0){($test.FileCount / $production.FileCount).ToString('N2')}else{'N/A'})
  Test code lines per production code line: $(if($production.CodeLines -gt 0){($test.CodeLines / $production.CodeLines).ToString('N2')}else{'N/A'})
"@
}
elseif ($OutputFormat -eq 'json') {
    $payload = [PSCustomObject]@{
        projectRoot = $root
        generatedOn = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
        categories  = @($production, $test, $operational, $generated | ForEach-Object {
            [PSCustomObject]@{
                name = $_.Name
                fileCount = $_.FileCount
                bytes = $_.Bytes
                totalLines = $_.TotalLines
                nonBlankLines = $_.NonBlankLines
                codeLines = $_.CodeLines
                testMethods = $_.TestMethods
                testSuites = $_.TestSuites
            }
        })
    }
    $output = $payload | ConvertTo-Json -Depth 3
}
else {
    # markdown
    $prodExt = Format-PerExtension -Metrics $production.Files | ForEach-Object {
        "| $($_.Extension) | $($_.Files) | $(Format-ByteSize $_.Bytes) | $($_.TotalLines) | $($_.NonBlankLines) | $($_.CodeLines) |"
    }
    $testExt = Format-PerExtension -Metrics $test.Files -IncludeTests | ForEach-Object {
        "| $($_.Extension) | $($_.Files) | $(Format-ByteSize $_.Bytes) | $($_.TotalLines) | $($_.NonBlankLines) | $($_.CodeLines) | $($_.TestMethods) |"
    }

    $prodExtHeader = @"
| Extension | Files | Bytes | Total Lines | Non-Blank | Code Lines |
|-----------|-------|-------|-------------|-----------|------------|
"@
    $testExtHeader = @"
| Extension | Files | Bytes | Total Lines | Non-Blank | Code Lines | @Test Methods |
|-----------|-------|-------|-------------|-----------|------------|---------------|
"@

    $output = @"
# Project Metrics

Generated on: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Project root: $root

## Functional (Production) Source

| Metric | Value |
|--------|-------|
| Files | $($production.FileCount) |
| Bytes | $(Format-ByteSize $production.Bytes) |
| Total lines | $($production.TotalLines) |
| Non-blank lines | $($production.NonBlankLines) |
| Code lines | $($production.CodeLines) |

### By File Type

$prodExtHeader
$($prodExt -join "`n")

## Test Source

| Metric | Value |
|--------|-------|
| Files | $($test.FileCount) |
| Bytes | $(Format-ByteSize $test.Bytes) |
| Total lines | $($test.TotalLines) |
| Non-blank lines | $($test.NonBlankLines) |
| Code lines | $($test.CodeLines) |
| @Test methods | $($test.TestMethods) |
| @TestSuite entries | $($test.TestSuites) |

### By File Type

$testExtHeader
$($testExt -join "`n")

## Operational/Batch Scripts

| Metric | Value |
|--------|-------|
| Files | $($operational.FileCount) |
| Bytes | $(Format-ByteSize $operational.Bytes) |
| Total lines | $($operational.TotalLines) |

## Generated R-code

| Metric | Value |
|--------|-------|
| Files | $($generated.FileCount) |
| Bytes | $(Format-ByteSize $generated.Bytes) |

## Source Totals (Production + Test)

| Metric | Value |
|--------|-------|
| Files | $totalSourceFiles |
| Bytes | $(Format-ByteSize $totalSourceBytes) |
| Code lines | $totalSourceCode |

## Ratios

| Ratio | Value |
|-------|-------|
| Test files per production file | $(if($production.FileCount -gt 0){($test.FileCount / $production.FileCount).ToString('N2')}else{'N/A'}) |
| Test code lines per production code line | $(if($production.CodeLines -gt 0){($test.CodeLines / $production.CodeLines).ToString('N2')}else{'N/A'}) |
"@
}

if ($OutputFile) {
    $output | Set-Content -LiteralPath $OutputFile -Encoding UTF8
    Write-Host "Wrote $OutputFile"
}
else {
    Write-Output $output
}
