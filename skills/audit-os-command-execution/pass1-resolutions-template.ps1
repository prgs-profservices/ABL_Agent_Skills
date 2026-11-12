# Copyright 2026 Progress Software Corporation
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
AI Pass 1 resolution script template — apply context-traced token and platform
resolutions to the OS-command inventory CSV, then rebuild the unresolved CSV.

.DESCRIPTION
This script is a TEMPLATE. Copy it, fill in the Resolve-Row calls below based
on source tracing of blank-token rows, then run it once. Delete the copy after
it runs successfully — it is a one-time run artifact, not a permanent file.

Usage:
  & "devops\apply-pass1-resolutions.ps1"

See the audit-os-command-execution skill's SKILL.md for the full workflow.
#>
param(
  [string]$CsvPath           = 'docs\os-command-inventory-latest.csv',
  [string]$UnresolvedCsvPath = 'docs\os-command-unresolved-latest.csv'
)

$ErrorActionPreference = 'Stop'

# ── Resolve workspace ──────────────────────────────────────────────────────────
$workspace = $PSScriptRoot
while ($workspace -and -not (Test-Path (Join-Path $workspace 'openedge-project.json'))) {
  $parent = Split-Path -Parent $workspace
  if (-not $parent -or $parent -eq $workspace) { break }
  $workspace = $parent
}
Set-Location $workspace

$invPath   = if ([System.IO.Path]::IsPathRooted($CsvPath)) { $CsvPath } else { Join-Path $workspace $CsvPath }
$unresPpath = if ([System.IO.Path]::IsPathRooted($UnresolvedCsvPath)) { $UnresolvedCsvPath } else { Join-Path $workspace $UnresolvedCsvPath }

Write-Host "Loading inventory: $invPath" -ForegroundColor Cyan
$inv = Import-Csv $invPath

# ── Resolve-Row helper ─────────────────────────────────────────────────────────
# Matches rows by relative file path (forward slashes) and line number.
# Parameters:
#   $inv       — the imported CSV array
#   $relPath   — workspace-relative path with backslashes (e.g. 'src\base\foo.p')
#   $lineNum   — line number as string or int
#   $token     — resolved command token (blank string to leave opaque)
#   $opaque    — 'True' if command cannot be determined; 'False' otherwise
#   $platform  — 'linux' | 'windows' | 'both' | 'unknown'
#   $rhel      — RHEL 9.6 concern text
#   $conf      — TokenConfidence (0-100 integer as string)
#   $score     — ConfidenceScore (0-100 integer as string)
#   $expl      — ConfidenceExplanation (brief evidence summary)
function Resolve-Row($inv, $relPath, $lineNum, $token, $opaque, $platform, $rhel, $conf, $score, $expl) {
  $fwd  = $relPath.Replace('\', '/')
  $rows = @($inv | Where-Object { ([string]$_.File).Replace('\','/') -eq $fwd -and [string]$_.Line -eq [string]$lineNum })
  if ($rows.Count -eq 0) { Write-Warning "No match: $fwd line $lineNum"; return 0 }
  foreach ($r in $rows) {
    $r.CommandToken          = $token
    $r.CommandSource         = 'ai-context'
    $r.OpaqueValue           = $opaque
    $r.PlatformClassification = $platform
    $r.RHEL96Concern         = $rhel
    $r.TokenConfidence       = $conf
    $r.ConfidenceScore       = $score
    $r.ConfidenceExplanation = $expl
  }
  return $rows.Count
}

$n = 0

# ==============================================================================
# BLANK-TOKEN RESOLUTIONS
# Add one Resolve-Row call per blank-token row. Trace: full statement, local
# variable assignments, preprocessor constants ({& }), include files, opsys
# branches. Output one call per distinct file+line.
# ==============================================================================

# EXAMPLE — replace with real resolutions:
# $n += Resolve-Row $inv 'src\base\foo.p' '42' `
#     'geocode' 'False' 'linux' `
#     'Vertex geocode binary at /data4/vertex/c — verify installed on RHEL 9.6.' `
#     '90' '90' `
#     '{&vertexCCode}/geocode traced to /data4/vertex/c/geocode via vertexScopDefs.i.'

Write-Host "Blank-token resolutions: $n rows updated" -ForegroundColor Yellow

# ==============================================================================
# BATCH PLATFORM CONFIRMATIONS
# For low-confidence rows (TokenConfidence < 75) that have valid tokens but
# unknown platform, list them in $platformMap: token => [platform, confidence]
# ==============================================================================

$platformMap = @{
  # EXAMPLES — replace or extend with tokens from this run's unresolved CSV:
  # 'printform'   = @('linux', 85)
  # 'sendmail'    = @('linux', 80)
  # 'cvs'         = @('both',  90)
  # 'cvpmftp.exe' = @('windows', 95)
}

$batchN = 0
foreach ($row in $inv) {
  $tok  = ([string]$row.CommandToken).Trim().ToLowerInvariant()
  $conf = [int]$row.TokenConfidence
  if ([string]::IsNullOrWhiteSpace($tok)) { continue }
  if ($conf -ge 75)                       { continue }
  if ($platformMap.ContainsKey($tok)) {
    $tgt = $platformMap[$tok]
    $row.PlatformClassification = $tgt[0]
    $row.TokenConfidence        = $tgt[1]
    $row.ConfidenceScore        = $tgt[1]
    $row.ConfidenceExplanation  = 'Platform confirmed by AI context analysis'
    $batchN++
  }
}
Write-Host "Batch platform confirms: $batchN rows updated" -ForegroundColor Yellow

# ==============================================================================
# SAVE
# ==============================================================================

$inv | Export-Csv $invPath -NoTypeInformation -Encoding utf8

# Rebuild unresolved CSV
$newUnresolved = @($inv | Where-Object {
  [string]::IsNullOrWhiteSpace([string]$_.CommandToken) -or [int]$_.TokenConfidence -lt 75
} | Sort-Object File, Line)

$newUnresolved | Select-Object File,Line,Type,CommandToken,Statement,CommandSource,PlatformClassification,TokenConfidence,ConfidenceScore,ConfidenceExplanation |
  Export-Csv $unresPpath -NoTypeInformation -Encoding utf8

# Export unknown-platform rows separately for AI Pass 2
$unknownRows = @($inv | Where-Object { $_.PlatformClassification -eq 'unknown' })
$pass2Path   = Join-Path (Split-Path $invPath) 'ai-pass2-unknown-platforms.csv'
$unknownRows | Select-Object File,Line,Type,CommandToken,Statement,CommandSource,PlatformClassification,RHEL96Concern,OpenEdgeBuiltIn,TokenConfidence,ConfidenceScore,ConfidenceExplanation |
  Export-Csv $pass2Path -NoTypeInformation -Encoding utf8

Write-Host ""
Write-Host "=== Pass 1 Complete ===" -ForegroundColor Green
Write-Host "  Blank-token fixes : $n" -ForegroundColor Green
Write-Host "  Platform confirms : $batchN" -ForegroundColor Green
Write-Host "  Still unresolved  : $($newUnresolved.Count)" -ForegroundColor Green
Write-Host "  Unknown platform  : $($unknownRows.Count)  (saved to $(Split-Path $pass2Path -Leaf))" -ForegroundColor Green
Write-Host ""
Write-Host "Next: AI Pass 2 on $pass2Path, then run -Mode report-only" -ForegroundColor Yellow
Write-Host "Then: delete this script - it is a one-time run artifact." -ForegroundColor DarkYellow
