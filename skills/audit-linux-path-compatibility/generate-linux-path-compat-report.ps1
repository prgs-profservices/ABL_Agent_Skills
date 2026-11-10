# Copyright 2026 Progress Software Corporation
# SPDX-License-Identifier: Apache-2.0

param(
  [Parameter(Mandatory = $true)]
  [string[]]$Roots,
  [string]$OutputDir = 'docs',
  [string]$ReportFileName = 'linux-path-compat-report.html',
  [switch]$NoOpenReport
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$workspace = Resolve-Path (Join-Path $scriptDir '..\..\..') | Select-Object -ExpandProperty Path
Set-Location $workspace

$resolvedOutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) {
  $OutputDir
} else {
  Join-Path $workspace $OutputDir
}

if (-not (Test-Path $resolvedOutputDir)) {
  New-Item -ItemType Directory -Path $resolvedOutputDir -Force | Out-Null
}

$templatePath = Join-Path $scriptDir 'templates/linux-path-compat-template.html'
if (-not (Test-Path $templatePath)) {
  throw "Template not found: $templatePath"
}

$filePatterns = @('.p', '.w', '.i', '.cls')

function Encode-Html {
  param([string]$Text)
  [System.Net.WebUtility]::HtmlEncode([string]$Text)
}

function Convert-ToRelativePath {
  param(
    [string]$Path,
    [string]$Root
  )

  $normalizedRoot = $Root.TrimEnd('\', '/')
  if ($Path.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $Path.Substring($normalizedRoot.Length + 1) -replace '\\', '/'
  }

  return $Path -replace '\\', '/'
}

function Get-Category {
  param([string]$Line)

  $u = $Line.ToUpperInvariant()
  if ($u -match '^\s*RUN\b') { return 'RUN statement' }
  if ($u -match '\{[^}]*\.I\b') { return 'Include usage' }
  if ($u -match '\bINPUT\s+FROM\b|\bOUTPUT\s+TO\b|\bCOPY-LOB\s+FROM\s+FILE\b|\bCOPY-LOB\s+TO\s+FILE\b|\bOS-DELETE\b') { return 'File read/write' }
  if ($u -match '\bFILE-INFO:FILE-NAME\b|\bSEARCH\s*\(') { return 'File-spec operation' }
  if ($u -match '&GLOBAL-DEFINE|&SCOPED-DEFINE') { return 'Macro-defined path' }
  return 'Other path usage'
}

function Get-RiskInfo {
  param([string]$PathSpec)

  $p = [string]$PathSpec

  if ([string]::IsNullOrWhiteSpace($p)) {
    return [pscustomobject]@{ Risk = ''; Severity = ''; Reason = '' }
  }

  if ($p -match '^[A-Za-z]:[\\/]') {
    return [pscustomobject]@{
      Risk = 'Windows absolute path'
      Severity = 'High'
      Reason = 'Drive-letter absolute path is Windows-specific and non-relative.'
    }
  }

  if ($p -match '^\\\\') {
    return [pscustomobject]@{
      Risk = 'UNC path'
      Severity = 'High'
      Reason = 'UNC share path is Windows-specific and will not map directly on Linux.'
    }
  }

  if ($p -match '\\') {
    return [pscustomobject]@{
      Risk = 'Backslash path separator'
      Severity = 'Medium'
      Reason = 'Backslash separator may break on Linux if treated as literal path text.'
    }
  }

  if ($p -match '^/') {
    return [pscustomobject]@{
      Risk = 'Absolute path'
      Severity = 'Medium'
      Reason = 'Absolute path is non-relative and may not exist in deployment environment.'
    }
  }

  return [pscustomobject]@{ Risk = ''; Severity = ''; Reason = '' }
}

function Get-CodeOnlyLine {
  param(
    [string]$Line,
    [ref]$InBlockComment
  )

  $text = [string]$Line

  if (-not $InBlockComment.Value) {
    $trimLeading = $text.TrimStart()
    if ($trimLeading -match '^\*') {
      return ''
    }
  }

  $sb = New-Object System.Text.StringBuilder
  $inSingle = $false
  $inDouble = $false
  $idx = 0

  while ($idx -lt $text.Length) {
    if ($InBlockComment.Value) {
      if ($idx + 1 -lt $text.Length -and $text[$idx] -eq '*' -and $text[$idx + 1] -eq '/') {
        $InBlockComment.Value = $false
        $idx += 2
        continue
      }

      $idx++
      continue
    }

    if (-not $inSingle -and -not $inDouble -and $idx + 1 -lt $text.Length -and $text[$idx] -eq '/' -and $text[$idx + 1] -eq '/') {
      break
    }

    if (-not $inSingle -and -not $inDouble -and $idx + 1 -lt $text.Length -and $text[$idx] -eq '/' -and $text[$idx + 1] -eq '*') {
      $InBlockComment.Value = $true
      $idx += 2
      continue
    }

    $ch = $text[$idx]

    if ($ch -eq '''') {
      if (-not $inDouble) {
        $inSingle = -not $inSingle
      }
      [void]$sb.Append($ch)
      $idx++
      continue
    }

    if ($ch -eq '"') {
      if (-not $inSingle) {
        $inDouble = -not $inDouble
      }
      [void]$sb.Append($ch)
      $idx++
      continue
    }

    [void]$sb.Append($ch)
    $idx++
  }

  return $sb.ToString()
}

$scanRoots = @()
foreach ($root in $Roots) {
  $resolvedRoot = if ([System.IO.Path]::IsPathRooted($root)) {
    $root
  } else {
    Join-Path $workspace $root
  }

  if (Test-Path $resolvedRoot) {
    $scanRoots += (Resolve-Path $resolvedRoot | Select-Object -ExpandProperty Path)
  }
}

if ($scanRoots.Count -eq 0) {
  throw 'No valid roots to scan. Provide one or more existing paths via -Roots.'
}

$files = foreach ($root in $scanRoots) {
  if (Test-Path $root -PathType Container) {
    Get-ChildItem -Path $root -Recurse -File | Where-Object { $filePatterns -contains $_.Extension.ToLowerInvariant() }
  } elseif (Test-Path $root -PathType Leaf) {
    $item = Get-Item $root
    if ($filePatterns -contains $item.Extension.ToLowerInvariant()) { $item }
  }
}

$files = $files | Sort-Object FullName -Unique

$targetLinePattern = '(?i)^\s*RUN\b|\{[^}]*\.i[^}]*\}|\bINPUT\s+FROM\b|\bOUTPUT\s+TO\b|\bCOPY-LOB\s+FROM\s+FILE\b|\bCOPY-LOB\s+TO\s+FILE\b|\bOS-DELETE\b|\bFILE-INFO:FILE-NAME\b|\bSEARCH\s*\('
$quotedPattern = '(?:"([^"\r\n]+)"|''([^''\r\n]+)'')'
$includePattern = '\{([^}\r\n]+)\}'
$runTokenPattern = '(?i)^\s*RUN\s+([^\s\(,]+)'

$rows = New-Object System.Collections.Generic.List[object]

foreach ($file in $files) {
  $rel = Convert-ToRelativePath -Path $file.FullName -Root $workspace
  $lines = Get-Content -Path $file.FullName
  $inBlockComment = $false

  for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
    $rawLine = [string]$lines[$lineIndex]
    $codeLine = Get-CodeOnlyLine -Line $rawLine -InBlockComment ([ref]$inBlockComment)

    if ([string]::IsNullOrWhiteSpace($codeLine)) { continue }
    if (-not ($codeLine -match $targetLinePattern)) { continue }

    $category = Get-Category -Line $codeLine
    $pathSpecs = New-Object System.Collections.Generic.List[string]

    $quotedMatches = [regex]::Matches($codeLine, $quotedPattern)
    foreach ($match in $quotedMatches) {
      $candidate = if ($match.Groups[1].Success) { $match.Groups[1].Value } else { $match.Groups[2].Value }
      if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
      if ($candidate -match '[\\/]' -or $candidate -match '^[A-Za-z]:') {
        $pathSpecs.Add($candidate) | Out-Null
      }
    }

    $includeMatches = [regex]::Matches($codeLine, $includePattern)
    foreach ($match in $includeMatches) {
      $inner = $match.Groups[1].Value.Trim()
      if ([string]::IsNullOrWhiteSpace($inner)) { continue }
      if ($inner -match '^&') { continue }
      if ($inner -match '[\\/]' -or $inner -match '^[A-Za-z]:') {
        $pathSpecs.Add($inner) | Out-Null
      }
    }

    if ($codeLine -match $runTokenPattern) {
      $runTarget = $Matches[1].Trim().TrimEnd('.').Trim()
      if ($runTarget -and $runTarget -notmatch '^(VALUE|SEARCH)\s*\(' -and $runTarget -match '[\\/]|^[A-Za-z]:') {
        $pathSpecs.Add($runTarget) | Out-Null
      }
    }

    foreach ($pathSpec in ($pathSpecs | Select-Object -Unique)) {
      $risk = Get-RiskInfo -PathSpec $pathSpec
      if ([string]::IsNullOrWhiteSpace($risk.Risk)) { continue }

      $rows.Add([pscustomobject]@{
        File = $rel
        Line = $lineIndex + 1
        Category = $category
        PathSpec = $pathSpec
        Risk = $risk.Risk
        Severity = $risk.Severity
        Reason = $risk.Reason
        Usage = $codeLine.Trim()
      }) | Out-Null
    }
  }
}

$rows = $rows | Sort-Object File, Line, PathSpec -Unique
$totalFindings = ($rows | Measure-Object).Count
$affectedFiles = ($rows | Select-Object -ExpandProperty File -Unique | Measure-Object).Count

$byRisk = if ($totalFindings -gt 0) { $rows | Group-Object Risk | Sort-Object Name } else { @() }
$byCategory = if ($totalFindings -gt 0) { $rows | Group-Object Category | Sort-Object Name } else { @() }

$summaryCards = "<div class='card'><h3>Total Findings</h3><div class='value'>$totalFindings</div></div>" +
                "<div class='card'><h3>Files Affected</h3><div class='value'>$affectedFiles</div></div>"
foreach ($group in $byRisk) {
  $summaryCards += "<div class='card'><h3>$(Encode-Html $group.Name)</h3><div class='value'>$($group.Count)</div></div>"
}

$categorySummary = if ($byCategory.Count -eq 0) {
  '<li>No category findings.</li>'
} else {
  ($byCategory | ForEach-Object { "<li><strong>$(Encode-Html $_.Name)</strong>: $($_.Count)</li>" }) -join ''
}

$rowsHtml = if ($totalFindings -eq 0) {
  "<tr><td colspan='8'>No Linux path compatibility findings in scoped patterns.</td></tr>"
} else {
  ($rows | ForEach-Object {
    $severityClass = $_.Severity.ToLowerInvariant()
    "<tr class='sev-$severityClass'><td>$(Encode-Html $_.File)</td><td>$($_.Line)</td><td>$(Encode-Html $_.Category)</td><td>$(Encode-Html $_.Risk)</td><td>$($_.Severity)</td><td><code>$(Encode-Html $_.PathSpec)</code></td><td>$(Encode-Html $_.Reason)</td><td><code>$(Encode-Html $_.Usage)</code></td></tr>"
  }) -join "`n"
}

$template = Get-Content -Path $templatePath -Raw
$scopeDisplay = ($scanRoots | ForEach-Object { Convert-ToRelativePath -Path $_ -Root $workspace }) -join ', '
$generatedAt = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

$html = $template.Replace('{{WORKSPACE}}', (Encode-Html $workspace))
$html = $html.Replace('{{GENERATED_AT}}', $generatedAt)
$html = $html.Replace('{{SCOPE_DISPLAY}}', (Encode-Html $scopeDisplay))
$html = $html.Replace('{{SUMMARY_CARDS}}', $summaryCards)
$html = $html.Replace('{{CATEGORY_SUMMARY}}', $categorySummary)
$html = $html.Replace('{{ROWS_HTML}}', $rowsHtml)

$outPath = Join-Path $resolvedOutputDir $ReportFileName
if ($PSVersionTable.PSVersion.Major -ge 7) {
  $html | Out-File -FilePath $outPath -Encoding utf8NoBOM
} else {
  [System.IO.File]::WriteAllText($outPath, $html, (New-Object System.Text.UTF8Encoding($false)))
}

if (-not $NoOpenReport) {
  Start-Process $outPath
}

Write-Output "REPORT_PATH=$outPath"
Write-Output "TOTAL_FINDINGS=$totalFindings"
Write-Output "FILES_AFFECTED=$affectedFiles"
Write-Output "COMMENT_FILTER=enabled"
