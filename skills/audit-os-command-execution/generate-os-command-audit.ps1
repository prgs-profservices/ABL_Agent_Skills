# Copyright 2026 Progress Software Corporation
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
Generate an OpenEdge ABL OS-command inventory and produce a final OS-command compatibility audit report for the target platform after AI review.

.DESCRIPTION
This script scans requested ABL roots for OS command execution sites, writes the inventory and unresolved-review CSVs,
persists audit context metadata, and generates the final HTML report only during the final reporting step.

.AUTHOR
GitHub Copilot (GPT-5.4)

.PROMPTER
S.E. Southwell - Progress
#>
param(
  [string[]]$Roots = @('.'),
  [string]$OutputDir = 'docs',
  # Extraction mode should not generate HTML. The final HTML is generated in report-only mode.
  [ValidateSet('full','confidence','export','report-only','command-summary','ingest-decisions')]
  [string]$Mode = 'full',
  [string]$DecisionsXlsxPath = '',  # for ingest-decisions: path to the returned client workbook
  [string]$CsvPath = '',
  [switch]$IncludeComments,
  # Binary target platform — determines which commands are concerns and which are suppressed.
  # Defaults to 'linux' to preserve existing behaviour for all current invocations.
  [ValidateSet('linux','windows')]
  [string]$TargetPlatform = 'linux',
  # Display label for the target — used in report title, concern column header, and Excel.
  # Free text; no programmatic meaning. Defaults to platform-appropriate label when not specified.
  [string]$TargetPlatformLabel = '',
  # OpenEdge client windowing mode — determines whether TTY-gated or GUI-gated blocks are live or dead code.
  # gui  = prowin/GUI client (default); tty = _progres character-mode client; any = don't suppress either mode.
  # Note: TTY is NOT synonymous with Unix. Both gui and tty sessions can run on Windows or Linux.
  [ValidateSet('gui','tty','any')]
  [string]$WindowSystem = 'gui'
)

# Auto-derive TargetPlatformLabel when not explicitly provided
if ([string]::IsNullOrWhiteSpace($TargetPlatformLabel)) {
  $TargetPlatformLabel = if ($TargetPlatform -eq 'windows') { 'Windows Server' } else { 'RHEL 9.6' }
}

$ErrorActionPreference = 'Stop'

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

<#
.SYNOPSIS
Creates a properly-structured audit row object for consistent handling throughout the pipeline.

.PARAMETER File
Relative file path from workspace root

.PARAMETER Line
Line number in source file

.PARAMETER Type
Statement type (OS-COMMAND, UNIX SILENT, DOS SILENT, INPUT THROUGH, OUTPUT THROUGH)

.PARAMETER CommandToken
Primary command token extracted from statement

.PARAMETER GatedNearby
Whether statement appears to be gated by opsys check

.PARAMETER GatedFor
Which OS the surrounding OPSYS gate targets: unix, windows, vms, uncertain, or empty if not gated

.PARAMETER CommentLikely
Whether the statement appears to be commented out

.PARAMETER Statement
Full statement text (multi-line joined)

.PARAMETER OpaqueValue
Whether command source is opaque (VALUE() without resolution)

.PARAMETER CommandSource
Source of token extraction (literal, env-path, abs-path, search-literal, var-assignment, opaque, etc.)

.PARAMETER OpenEdgeBuiltIn
Whether command is an OpenEdge utility

.PARAMETER RHEL96Concern
Migration concern notes for RHEL 9.6

.PARAMETER TokenConfidence
Confidence in token extraction (0-100 integer)

.NOTES
Returns a PSCustomObject with normalized property names and types suitable for
export to CSV or JSON, as well as filtering/sorting in downstream stages.
#>
function New-AuditRow {
  param(
    [string]$File,
    [int]$Line,
    [string]$Type,
    [string]$CommandToken,
    [bool]$GatedNearby,
    [string]$GatedFor = '',
    [bool]$CommentLikely,
    [string]$Statement,
    [bool]$OpaqueValue,
    [string]$CommandSource,
    [bool]$OpenEdgeBuiltIn,
    [string]$RHEL96Concern,
    [string]$PlatformClassification = 'unknown',
    [int]$TokenConfidence = 50
  )

  # Validate parameter ranges
  if ($TokenConfidence -lt 0 -or $TokenConfidence -gt 100) {
    throw "TokenConfidence must be 0-100; got $TokenConfidence"
  }

  # The base confidence is driven by token extraction and can be refined later.
  $compositeConfidence = $TokenConfidence

  # If no command token, composite confidence is 0.
  if ([string]::IsNullOrWhiteSpace($CommandToken)) {
    $compositeConfidence = 0
  }

  # Generate brief confidence explanation
  if ([string]::IsNullOrWhiteSpace($CommandToken)) {
    $confidenceExplanation = "Cannot determine command token - no basis for confidence"
  } else {
    $confidenceExplanation = if ($TokenConfidence -lt 60) {
      "Token extraction uncertain"
    } else {
      "Good confidence in token extraction"
    }
  }

  $row = [pscustomobject]@{
    File                   = $File
    Line                   = $Line
    Type                   = $Type
    CommandToken           = $CommandToken
    GatedNearby            = $GatedNearby
    GatedFor               = $GatedFor
    CommentLikely          = $CommentLikely
    Statement              = $Statement
    OpaqueValue            = $OpaqueValue
    CommandSource          = $CommandSource
    OpenEdgeBuiltIn        = $OpenEdgeBuiltIn
    RHEL96Concern          = $RHEL96Concern
    PlatformClassification = $PlatformClassification
    TokenConfidence        = $TokenConfidence
    ConfidenceScore        = $compositeConfidence
    ConfidenceExplanation  = $confidenceExplanation
  }

  return $row
}

<#
.SYNOPSIS
Calculates token extraction confidence based on token source and characteristics.

.PARAMETER TokenSource
Source of token extraction

.PARAMETER Token
The extracted token

.PARAMETER IsOpaqueValue
Whether the token source was opaque

.RETURNS
Integer 0-100 indicating confidence in token extraction
#>
function Get-TokenConfidence {
  param(
    [string]$TokenSource,
    [string]$Token,
    [bool]$IsOpaqueValue
  )

  if ($IsOpaqueValue) {
    return 10  # Very low confidence for opaque VALUE()
  }

  # High confidence sources
  if ($TokenSource -in @('literal', 'quoted-literal', 'value-literal', 'abs-path', 'openedge-dlc-path', 'search-literal')) {
    return 90
  }

  # Medium confidence
  if ($TokenSource -in @('env-path', 'var-assignment')) {
    return 70
  }

  # Low confidence (opaque or unknown)
  if ($TokenSource -eq 'opaque') {
    return 10
  }

  # Default
  return 50
}

function Test-TruthyValue {
  param(
    $Value
  )

  if ($Value -is [bool]) {
    return $Value
  }

  $text = [string]$Value
  if ([string]::IsNullOrWhiteSpace($text)) {
    return $false
  }

  return $text.Trim().ToLowerInvariant() -in @('true', '1', 'yes', 'y')
}

function Get-NormalizedStringArray {
  param(
    $Values
  )

  $normalized = New-Object System.Collections.Generic.List[string]
  foreach ($item in @($Values)) {
    $text = [string]$item
    if ([string]::IsNullOrWhiteSpace($text)) {
      continue
    }
    $normalized.Add($text.Trim().ToLowerInvariant()) | Out-Null
  }

  return @($normalized | Select-Object -Unique)
}

function Normalize-PlatformClassification {
  param(
    [string]$Value,
    [string]$Fallback = 'unknown'
  )

  $candidate = [string]$Value
  if ([string]::IsNullOrWhiteSpace($candidate)) {
    $candidate = $Fallback
  }

  $candidate = $candidate.Trim().ToLowerInvariant()
  if ($candidate -notin @('windows', 'linux', 'both', 'unknown')) {
    return 'unknown'
  }

  return $candidate
}

function Get-PlatformClassification {
  param(
    [string]$CommandToken,
    [string]$Statement,
    [string]$Concern,
    [pscustomobject]$PlatformRules
  )

  $token = ([string]$CommandToken).Trim().ToLowerInvariant()
  $statementText = ([string]$Statement).ToLowerInvariant()
  $concernText = ([string]$Concern).ToLowerInvariant()

  if (-not $PlatformRules) {
      return 'unknown'
  }

    $unknownDefault = Normalize-PlatformClassification -Value $PlatformRules.unknownDefault -Fallback 'unknown'

  # Check for "both" (cross-platform) commands first
  if (-not [string]::IsNullOrWhiteSpace($token)) {
    if (@($PlatformRules.bothCommands) -contains $token) {
      return 'both'
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($token)) {
    foreach ($suffix in @($PlatformRules.windowsTokenSuffixes)) {
      if ($token.EndsWith([string]$suffix)) {
        return 'windows'
      }
    }

    if (@($PlatformRules.windowsCommands) -contains $token) {
      return 'windows'
    }

    if (@($PlatformRules.linuxCommands) -contains $token) {
      return 'linux'
    }

    foreach ($prefix in @($PlatformRules.linuxPathPrefixes)) {
      if (-not [string]::IsNullOrWhiteSpace($prefix) -and $token.StartsWith([string]$prefix)) {
        return 'linux'
      }
    }
  }

  foreach ($hint in @($PlatformRules.windowsStatementHints)) {
    if (-not [string]::IsNullOrWhiteSpace($hint) -and $statementText.Contains([string]$hint)) {
      return 'windows'
    }
  }

  if ($statementText.Contains('/bin/') -or $statementText.Contains(' unix ')) {
    return 'linux'
  }

  if ($concernText -match '\bwindows\b' -and $concernText -match '\b(only|batch|exe|vbscript|com)\b') {
    return 'windows'
  }

  return $unknownDefault
}

# Resolve workspace root by walking up until openedge-project.json is found.
$workspace = $PSScriptRoot
while($workspace -and -not (Test-Path (Join-Path $workspace 'openedge-project.json'))){
  $parent = Split-Path -Parent $workspace
  if(-not $parent -or $parent -eq $workspace){ break }
  $workspace = $parent
}

if(-not (Test-Path (Join-Path $workspace 'openedge-project.json'))){
  throw "Unable to locate workspace root (openedge-project.json) from $PSScriptRoot"
}

Set-Location $workspace

# Resolve roots relative to workspace and only keep existing paths.
$resolvedRoots = @()
foreach($root in $Roots){
  if([string]::IsNullOrWhiteSpace($root)){ continue }
  $candidate = if([System.IO.Path]::IsPathRooted($root)){ $root } else { Join-Path $workspace $root }
  if(Test-Path $candidate){
    $resolvedRoots += (Resolve-Path $candidate).Path
  } else {
    Write-Warning "Skipping non-existent root: $root"
  }
}

if($resolvedRoots.Count -eq 0){
  throw "No valid roots were provided. Pass -Roots with one or more existing directories or files."
}

$resolvedOutputDir = if([System.IO.Path]::IsPathRooted($OutputDir)){ $OutputDir } else { Join-Path $workspace $OutputDir }
if(-not (Test-Path $resolvedOutputDir)){
  New-Item -Path $resolvedOutputDir -ItemType Directory -Force | Out-Null
}

$outCsv = Join-Path $resolvedOutputDir "os-command-inventory-latest.csv"
$outUnresolvedCsv = Join-Path $resolvedOutputDir "os-command-unresolved-latest.csv"
$outHtml = Join-Path $resolvedOutputDir "os-command-audit-latest.html"
$outMetadata     = Join-Path $resolvedOutputDir "os-command-audit-context-latest.json"
$outDecisionsXlsx    = Join-Path $resolvedOutputDir "command-decisions.xlsx"
$outClientDecisions  = Join-Path $resolvedOutputDir "client-decisions.json"

function Convert-ToWorkspaceRelativePath {
  param(
    [string]$Path,
    [string]$WorkspaceRoot
  )

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return ''
  }

  $normalizedPath = $Path.Replace('/', '\')
  $normalizedWorkspace = $WorkspaceRoot.TrimEnd('\').Replace('/', '\')

  if ($normalizedPath.StartsWith($normalizedWorkspace + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
    return $normalizedPath.Substring($normalizedWorkspace.Length + 1).Replace('\', '/')
  }

  return $Path.Replace('\\', '/')
}

function Convert-GlobToRegex {
    param(
      [string]$GlobPattern
    )

    $glob = ([string]$GlobPattern).Trim().Replace('\\', '/')
    if ([string]::IsNullOrWhiteSpace($glob)) {
      return $null
    }

    if ($glob.StartsWith('./')) {
      $glob = $glob.Substring(2)
    }

    $escaped = [regex]::Escape($glob)
    $escaped = $escaped -replace '\\\*\\\*', '__DOUBLE_STAR__'
    $escaped = $escaped -replace '\\\*', '[^/]*'
    $escaped = $escaped -replace '\\\?', '[^/]'
    $escaped = $escaped -replace '__DOUBLE_STAR__', '.*'

    return '^' + $escaped + '$'
  }

  function Get-MatchingIgnoreGlob {
    param(
      [string]$FilePath,
      [string]$WorkspaceRoot,
      $IgnorePatternRules
    )

    if (-not $IgnorePatternRules -or $IgnorePatternRules.Count -eq 0) {
      return ''
    }

    $relative = Convert-ToWorkspaceRelativePath -Path $FilePath -WorkspaceRoot $WorkspaceRoot
    $normalized = $relative.Replace('\\', '/').TrimStart('/').ToLowerInvariant()

    foreach ($rule in $IgnorePatternRules) {
      if (-not $rule) {
        continue
      }

      $regexPattern = [string]$rule.Regex
      $globPattern = [string]$rule.Glob
      if ([string]::IsNullOrWhiteSpace($regexPattern)) {
        continue
      }

      if ([regex]::IsMatch($normalized, $regexPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        return $globPattern
      }
    }

    return ''
}

$reportRoots = @($resolvedRoots)
$reportRootSource = 'command-line'

if (($Mode -eq 'report-only' -or $Mode -eq 'confidence') -and (Test-Path $outMetadata)) {
  try {
    $metadata = Get-Content $outMetadata -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($metadata -and $metadata.Roots) {
      $reportRoots = @($metadata.Roots | ForEach-Object { [string]$_ })
      $reportRootSource = 'saved-metadata'
    }
  } catch {
    Write-Warning "Unable to load saved audit context from $outMetadata; falling back to current -Roots values."
  }
}

# Load command notes configuration from JSON
$configJsonPath = Join-Path $PSScriptRoot "command-notes-config.json"
$config = @{}
if(Test-Path $configJsonPath){
  $configText = Get-Content $configJsonPath -Raw -Encoding UTF8
  $config = $configText | ConvertFrom-Json
} else {
  Write-Warning "Config JSON not found at $configJsonPath; will use hardcoded defaults"
  $config = [pscustomobject]@{
    ignoreFileGlobs = @()
    basicUnixCommands = @()
    openEdgeCommands = @()
    commandNotes = @{}
    platformRules = [pscustomobject]@{
      windowsTokenSuffixes = @('.exe', '.bat', '.cmd', '.vbs', '.ps1', '.com')
      windowsCommands = @('regsvr32', 'cmd.exe', 'cmd', 'cscript', 'wscript')
      windowsStatementHints = @('win32', 'msos-command', '.bat', '.exe')
      linuxCommands = @('cp', 'mv', 'rm', 'cat', 'chmod', 'chown', 'chgrp', 'grep', 'sed', 'awk', 'find', 'ls', 'mkdir', 'rmdir', 'touch', 'pwd')
      bothCommands = @('pro', 'proapsv', 'probkup', 'procopy', 'promon', 'prorest', 'proserve', 'proshut', 'prostrct', 'proutil', 'rfutil', 'sqlexp', 'sqlexplorer', 'convchar', 'dbtool', 'extractpf', 'idxbuild', 'quoter', 'showcfg', '_mprshut', 'prodb.exe', 'progress', 'pform', 'pform3', 'pcl2pdf', 'perl', 'python', 'ruby', 'java', 'javac', 'node', 'npm', 'git', 'svn', 'curl', 'wget')
      linuxPathPrefixes = @('/', '$dlc/', '$pform/')
      unknownDefault = 'unknown'
    }
  }
}

$ignoreFileGlobs = Get-NormalizedStringArray -Values $config.ignoreFileGlobs
$ignorePatternRules = @(
  $ignoreFileGlobs |
    ForEach-Object {
      $regex = Convert-GlobToRegex -GlobPattern $_
      if (-not [string]::IsNullOrWhiteSpace($regex)) {
        [pscustomobject]@{ Glob = [string]$_; Regex = [string]$regex }
      }
    } |
    Where-Object { $_ -ne $null }
)

$ignoredFileCount = 0
$ignoredPatternCounts = @{}

$basicUnixCommandSet = Get-NormalizedStringArray -Values $config.basicUnixCommands
$basicWindowsCommandSet = Get-NormalizedStringArray -Values $config.basicWindowsCommands
$openEdgeCommandSet = Get-NormalizedStringArray -Values $config.openEdgeCommands
# Select the correct commandNotes section based on the target platform
$commandNotesKey = if ($TargetPlatform -eq 'windows') { 'commandNotes-windows' } else { 'commandNotes' }
$commandNotesLookup = if ($config.PSObject.Properties.Name -contains $commandNotesKey -and $null -ne $config.$commandNotesKey) {
  $config.$commandNotesKey
} else {
  $config.commandNotes
}
$suppressedCommandSet = Get-NormalizedStringArray -Values $config.suppressedCommands

# Load client decisions overlay (written by ingest-decisions mode)
$clientDecisions = @{}
if (Test-Path $outClientDecisions) {
  try {
    $cdRaw = Get-Content $outClientDecisions -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($prop in $cdRaw.PSObject.Properties) {
      $clientDecisions[$prop.Name] = $prop.Value
    }
  } catch {
    Write-Warning "Could not load client-decisions.json: $_"
  }
}

$platformRulesSource = $config.platformRules
if (-not $platformRulesSource) {
  $platformRulesSource = [pscustomobject]@{
    windowsTokenSuffixes = @('.exe', '.bat', '.cmd', '.vbs', '.ps1', '.com')
    windowsCommands = @('regsvr32', 'cmd.exe', 'cmd', 'cscript', 'wscript')
    windowsStatementHints = @('win32', 'msos-command', '.bat', '.exe')
    linuxCommands = @('cp', 'mv', 'rm', 'cat', 'chmod', 'chown', 'chgrp', 'grep', 'sed', 'awk', 'find', 'ls', 'mkdir', 'rmdir', 'touch', 'pwd')
    bothCommands = @('pro', 'proapsv', 'probkup', 'procopy', 'promon', 'prorest', 'proserve', 'proshut', 'prostrct', 'proutil', 'rfutil', 'sqlexp', 'sqlexplorer', 'convchar', 'dbtool', 'extractpf', 'idxbuild', 'quoter', 'showcfg', '_mprshut', 'prodb.exe', 'progress', 'pform', 'pform3', 'pcl2pdf', 'perl', 'python', 'ruby', 'java', 'javac', 'node', 'npm', 'git', 'svn', 'curl', 'wget')
    linuxPathPrefixes = @('/', '$dlc/', '$pform/')
    unknownDefault = 'unknown'
  }
}

$platformRules = [pscustomobject]@{
  windowsTokenSuffixes = Get-NormalizedStringArray -Values $platformRulesSource.windowsTokenSuffixes
  windowsCommands = Get-NormalizedStringArray -Values $platformRulesSource.windowsCommands
  windowsStatementHints = Get-NormalizedStringArray -Values $platformRulesSource.windowsStatementHints
  linuxCommands = Get-NormalizedStringArray -Values $platformRulesSource.linuxCommands
  bothCommands = Get-NormalizedStringArray -Values $platformRulesSource.bothCommands
  linuxPathPrefixes = Get-NormalizedStringArray -Values $platformRulesSource.linuxPathPrefixes
  unknownDefault = Normalize-PlatformClassification -Value ([string]$platformRulesSource.unknownDefault) -Fallback 'unknown'
}

# ============================================================================
# PHASE 1: EXTRACTION (skip if report-only mode)
# ============================================================================
if ($Mode -eq 'ingest-decisions') {
  # Handled below — skip extraction entirely
} elseif ($Mode -eq 'report-only' -or $Mode -eq 'command-summary') {
  # Report-only / command-summary: load from existing CSV and skip extraction
  $effectiveCsvPath = if ([string]::IsNullOrWhiteSpace($CsvPath)) {
    Join-Path $resolvedOutputDir 'os-command-inventory-latest.csv'
  } else {
    $CsvPath
  }

  if (-not (Test-Path $effectiveCsvPath)) {
    throw "CSV path does not exist: $effectiveCsvPath. Cannot regenerate reports without source data."
  }

  Write-Host "Loading from CSV: $effectiveCsvPath" -ForegroundColor Cyan
  $auditRows = @(Import-Csv -Path $effectiveCsvPath) | Sort-Object File,Line

  # Apply GatedFor suppression on loaded CSV data (for CSVs produced after the GatedFor enhancement)
  if ($auditRows.Count -gt 0 -and ($auditRows[0].PSObject.Properties.Name -contains 'GatedFor')) {
    $suppressedGatedRows = ($auditRows | Where-Object {
      $gf = ([string]$_.GatedFor).Trim().ToLowerInvariant()
      $oppositeGate  = if ($TargetPlatform -eq 'linux') { 'windows' } else { 'unix' }
      $oppositeWindow = if ($WindowSystem -eq 'gui') { 'tty' } elseif ($WindowSystem -eq 'tty') { 'gui' } else { $null }
      $gf -in @('vms','os2') -or $gf -eq $oppositeGate -or ($null -ne $oppositeWindow -and $gf -eq $oppositeWindow)
    }).Count
    $auditRows = @($auditRows | Where-Object {
      $gf = ([string]$_.GatedFor).Trim().ToLowerInvariant()
      $oppositeGate  = if ($TargetPlatform -eq 'linux') { 'windows' } else { 'unix' }
      $oppositeWindow = if ($WindowSystem -eq 'gui') { 'tty' } elseif ($WindowSystem -eq 'tty') { 'gui' } else { $null }
      $gf -notin @('vms','os2') -and $gf -ne $oppositeGate -and ($null -eq $oppositeWindow -or $gf -ne $oppositeWindow)
    })
  } else {
    $suppressedGatedRows = 0
  }

  # Re-create summary statistics from loaded CSV
  $total = $auditRows.Count
  $concerns = ($auditRows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.RHEL96Concern) }).Count
  $excludedCommentRows = 0

  Write-Host "Loaded $total rows from CSV" -ForegroundColor Green
} else {
  # Standard mode: extract from source files

$candidateFiles = foreach($rootPath in $resolvedRoots){
  if(Test-Path $rootPath -PathType Container){
    Get-ChildItem $rootPath -Recurse -File | Where-Object { $_.Extension -in '.p','.w','.cls','.i' }
  } elseif(Test-Path $rootPath -PathType Leaf){
    $fi = Get-Item $rootPath
    if($fi.Extension -in '.p','.w','.cls','.i'){ $fi }
  }
}

$files = foreach($candidateFile in $candidateFiles){
  $matchedGlob = Get-MatchingIgnoreGlob -FilePath $candidateFile.FullName -WorkspaceRoot $workspace -IgnorePatternRules $ignorePatternRules
  if(-not [string]::IsNullOrWhiteSpace($matchedGlob)){
    $ignoredFileCount++
    if ($ignoredPatternCounts.ContainsKey($matchedGlob)) {
      $ignoredPatternCounts[$matchedGlob]++
    } else {
      $ignoredPatternCounts[$matchedGlob] = 1
    }
    continue
  }

  $candidateFile
}

if($ignoredFileCount -gt 0){
  Write-Host "Skipped $ignoredFileCount files due to ignoreFileGlobs configuration." -ForegroundColor DarkYellow
}

if(-not $files -or $files.Count -eq 0){
  throw "No ABL source files found under provided roots."
}
$pat = '(?i)\bOS-COMMAND\b|\bUNIX\s+SILENT\b|\bDOS\s+SILENT\b|\bINPUT\s+THROUGH\b|\bOUTPUT\s+THROUGH\b'
$commandMatches = $files | Select-String -Pattern $pat

$executionFiles = $commandMatches | Select-Object -ExpandProperty Path -Unique
$fileCache = @{}
foreach($executionFile in $executionFiles){
  if(-not (Test-Path $executionFile)){
    continue
  }

  $lines = Get-Content $executionFile
  $commentMask = New-Object 'bool[]' $lines.Count
  $inBlockComment = $false

  for($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++){
    $lineText = [string]$lines[$lineIndex]
    $lineTrim = $lineText.Trim()
    $lineIsComment = $false

    if($inBlockComment){
      $lineIsComment = $true
    }

    if(-not $inBlockComment){
      if($lineTrim -match '^(//|\*)'){
        $lineIsComment = $true
      }
      elseif($lineTrim -match '^/\*'){
        $lineIsComment = $true
      }
    }

    if(-not $inBlockComment -and $lineText -match '/\*' -and $lineText -notmatch '/\*.*\*/'){
      $inBlockComment = $true
      $lineIsComment = $true
    }

    if($lineText -match '/\*.*\*/'){
      $lineIsComment = $true
    }

    if($inBlockComment -and $lineText -match '\*/'){
      $lineIsComment = $true
      $inBlockComment = $false
    }

    $commentMask[$lineIndex] = $lineIsComment
  }

  $fileCache[$executionFile] = [pscustomobject]@{
    Lines = $lines
    CommentMask = $commentMask
  }
}

$rows = New-Object System.Collections.Generic.List[object]
foreach($m in $commandMatches){
  $file = $m.Path
  $cache = $fileCache[$file]
  $lines = $cache.Lines
  $idx = [Math]::Max(0, $m.LineNumber - 1)
  $statementParts = New-Object System.Collections.Generic.List[string]
  for($si = $idx; $si -lt $lines.Count; $si++){
    if($si -gt $idx -and $cache.CommentMask[$si]){
      continue
    }

    $statementLine = [string]$lines[$si]
    $statementParts.Add($statementLine.Trim()) | Out-Null

    if($statementLine -match '(?i)(?<!~)\.\s*(/\*.*)?$'){
      break
    }
  }

  $trim = (($statementParts | Where-Object { $_ -ne '' }) -join ' ').Trim()

  $start = [Math]::Max(0, $idx - 3)
  $end = [Math]::Min($lines.Count - 1, $idx + 2)
  $context = ($lines[$start..$end] -join ' ').ToLowerInvariant()

  $gated = ($context -match '\bopsys\b' -or $context -match '\{&opsys\}' -or $context -match 'window-system')

  $gatedFor = ''
  if ($gated) {
    if     ($context -match '(?i)opsys\s*=\s*"vms"')                                       { $gatedFor = 'vms' }
    elseif ($context -match '(?i)opsys\s*=\s*"unix"')                                      { $gatedFor = 'unix' }
    elseif ($context -match '(?i)opsys\s*<>\s*"win32"')                                    { $gatedFor = 'unix' }
    elseif ($context -match '(?i)opsys\s*=\s*"win32"')                                     { $gatedFor = 'windows' }
    elseif ($context -match '(?i)opsys\s*<>\s*"unix"')                                     { $gatedFor = 'windows' }
    # WINDOW-SYSTEM gate: TTY = character-mode client; GUI = windowed client.
    # These are orthogonal to OS — both client types can run on Windows or Linux.
    elseif ($context -match '(?i)window-system.{0,30}(?:eq|=)\s*"tty"')                   { $gatedFor = 'tty' }
    elseif ($context -match '(?i)window-system.{0,30}(?:ne|<>)\s*"tty"')                  { $gatedFor = 'gui' }
    elseif ($context -match '(?i)window-system.{0,30}(?:eq|=)\s*"gui"')                   { $gatedFor = 'gui' }
    elseif ($context -match '(?i)window-system.{0,30}(?:ne|<>)\s*"gui"')                  { $gatedFor = 'tty' }
    else                                                                                     { $gatedFor = 'uncertain' }
  }

  $commentLikely = $cache.CommentMask[$idx]

  $type = if($trim -match '(?i)\bOS-COMMAND\b'){'OS-COMMAND'} elseif($trim -match '(?i)\bUNIX\s+SILENT\b'){'UNIX SILENT'} elseif($trim -match '(?i)\bDOS\s+SILENT\b'){'DOS SILENT'} elseif($trim -match '(?i)\bINPUT\s+THROUGH\b'){'INPUT THROUGH'} else {'OUTPUT THROUGH'}

  $token = ''
  $resolvedFromVar = $false
  $isOpaqueValue = $false
  $tokenSource = ''
  $openEdgeBuiltIn = $false
  $osCommandOptionTokens = @(
    'no-console', 'no-wait', 'silent', 'start', 'minimized', 'maximized',
    'detached', 'no-error', 'echo', 'batch-mode'
  )

  if($commentLikely){
    $token = ''
  }

  # ── Keyword-based extraction ──────────────────────────────────────────────────
  # Find the ABL command keyword, strip any OS-COMMAND option tokens, then try
  # sub-patterns A/B/C in order.  The keyword regex and option-strip run once;
  # there is also a special-case branch for os-command("cmd") where no whitespace
  # separates the keyword from the opening parenthesis.
  if(-not $commentLikely){

    # Special case: os-command("cmd") or os-command('cmd':U) — no space before '('.
    # The standard keyword+\s+ match below would miss this form entirely.
    if(-not $token){
      $osParenMatch = [regex]::Match($trim, '(?i)OS-COMMAND\s*\(\s*(?:"([^"]+)"|''([^'']+)''(?::U)?)\s*\)')
      if($osParenMatch.Success){
        $rawCmd = if($osParenMatch.Groups[1].Value -ne '') { $osParenMatch.Groups[1].Value } else { $osParenMatch.Groups[2].Value }
        $cand = ($rawCmd.Trim() -split '\s+')[0]
        if($cand -match '[\\/]') { $cand = ($cand -split '[\\/]')[-1] }
        $cand = $cand.ToLowerInvariant()
        if($cand -match '^[a-z][a-z0-9_.-]+$' -and $cand.Length -gt 1){
          $token = $cand; $tokenSource = 'quoted-literal'
        }
      }
    }

    # Standard path: keyword followed by whitespace — build $afterKeyword once.
    $keywordMatch = [regex]::Match($trim, '(?i)(UNIX\s+SILENT|OS-COMMAND|DOS\s+SILENT|INPUT\s+THROUGH|OUTPUT\s+THROUGH)\s+')
    if($keywordMatch.Success){
      $afterKeyword = $trim.Substring($keywordMatch.Index + $keywordMatch.Length)
      # Only OS-COMMAND accepts option keywords (ECHO, NO-WAIT, etc.) before the command;
      # UNIX SILENT / DOS SILENT / INPUT|OUTPUT THROUGH have none.
      if($keywordMatch.Groups[1].Value -match '(?i)^OS-COMMAND'){
        while($afterKeyword -match '(?i)^\s*(no-console|no-wait|silent|start|minimized|maximized|detached|no-error|echo|batch-mode)\b\s*'){
          $afterKeyword = $afterKeyword.Substring($matches[0].Length)
        }
      }

      # Sub-pattern A: VALUE("literal") as the direct command expression.
      # e.g. UNIX SILENT VALUE("rm ...") or OS-COMMAND VALUE("pform3 ...")
      if(-not $token -and $afterKeyword -match '(?i)^\s*value\s*\('){
        $valueLiteralMatch = [regex]::Match($afterKeyword, '(?i)^\s*value\s*\(\s*"([a-z0-9_./\-]+)')
        if($valueLiteralMatch.Success){
          $valuedCmd = $valueLiteralMatch.Groups[1].Value.Trim()
          $cand = if($valuedCmd -match '/') { ($valuedCmd -split '/')[-1] } else { $valuedCmd }
          $cand = $cand.ToLowerInvariant()
          if($cand -match '^[a-z][a-z0-9_.-]+$' -and $cand.Length -gt 1){
            $token = $cand; $tokenSource = 'value-literal'
          }
        }
      }

      # Sub-pattern B: quoted literal directly after options are stripped.
      # Handles: "cmd args"  'cmd':U  ("cmd args")  ('cmd':U)
      # The outer parens are optional to cover os-command silent ("startMercury").
      if(-not $token){
        $quotedLiteralMatch = [regex]::Match($afterKeyword, '^\s*\(?\s*(?:"([^"]+)"|''([^'']+)''(?::U)?)\s*\)?')
        if($quotedLiteralMatch.Success){
          $rawBody = if($quotedLiteralMatch.Groups[1].Value -ne '') { $quotedLiteralMatch.Groups[1].Value } else { $quotedLiteralMatch.Groups[2].Value }
          $rawBody = $rawBody.Trim()
          if($rawBody){
            $cand = ($rawBody -split '\s+')[0].Trim()
            if($cand -match '[\\/]') { $cand = ($cand -split '[\\/]')[-1] }
            $cand = $cand.ToLowerInvariant()
            if($cand -match '^[a-z][a-z0-9_.-]+$' -and $cand.Length -gt 1){
              $token = $cand; $tokenSource = 'quoted-literal'
            }
          }
        }
      }

      # Sub-pattern C: bare first word — broadest fallback.
      # Catches commands like ygout2, fxdisable, fxshut, cp, rm, echo, etc.
      if(-not $token){
        $tokenMatch = [regex]::Match($afterKeyword, '^([a-zA-Z0-9_-]+)')
        if($tokenMatch.Success){
          $cand = $tokenMatch.Groups[1].Value.ToLowerInvariant()
          # For OS-COMMAND, skip pure option words (SILENT, NO-WAIT, etc.).
          # For UNIX SILENT / DOS SILENT the command follows directly — ECHO is a real command there.
          $isOptionToken = ($keywordMatch.Groups[1].Value -match '(?i)^OS-COMMAND') -and ($osCommandOptionTokens -contains $cand)
          if($cand.Length -gt 0 -and $cand -notmatch '^[0-9]' -and $cand -notmatch '^(value|if|then|else)$' -and -not $isOptionToken){
            $token = $cand; $tokenSource = 'literal'
          }
        }
      }
    }
  }

  # Pattern 3 (early): backward variable resolution for VALUE(varName).
  # Runs BEFORE path patterns so that an explicit VALUE() expression always takes
  # precedence over any path that might appear later in the statement (e.g. > /dev/null).
  if(-not $token -and $trim -match '(?i)\bVALUE\s*\(\s*(\w[\w-]*)\s*\)' -and -not $commentLikely){
    $varNameCap = [regex]::Match($trim, '(?i)\bVALUE\s*\(\s*(\w[\w-]*)\s*\)')
    if($varNameCap.Success){
      $varName = $varNameCap.Groups[1].Value
      $searchStart = [Math]::Max(0, $idx - 20)
      $searchEnd = $idx - 1
      if($searchEnd -ge $searchStart){
        $assignPat = '(?i)(?:ASSIGN\s+)?' + [regex]::Escape($varName) + '\s*=\s*"([^"]+)"'
        for($bi = $searchEnd; $bi -ge $searchStart; $bi--){
          $assignMatch = [regex]::Match($lines[$bi], $assignPat)
          if($assignMatch.Success){
            $cmdStr = $assignMatch.Groups[1].Value.Trim()
            $cmdStr = [regex]::Replace($cmdStr, '^\$\w+(?:/\w+)*/','').Trim()
            $cmdStr = [regex]::Replace($cmdStr, '^/(?:[\w-]+/)+','').Trim()
            $firstToken = ($cmdStr -split '\s+')[0].ToLowerInvariant()
            if($firstToken -match '^[a-z][a-z0-9_.-]+$' -and $firstToken.Length -gt 1){
              $token = $firstToken
              $resolvedFromVar = $true
              $tokenSource = 'var-assignment'
            }
            break
          }
        }
      }
      if(-not $token -and $trim -match '(?i)\bVALUE\s*\('){
        $isOpaqueValue = $true
        $tokenSource = 'opaque'
      }
    }
  }

  # Pattern 1a: env-var-prefixed bin path, e.g. $PFORM/bin/pform3 or $DLC/bin/proserve
  if(-not $token -and -not $commentLikely){
    $envBinMatch = [regex]::Match($trim, '(?i)\$(\w+)/bin/(\w[\w.-]*)')
    if($envBinMatch.Success){
      $token = $envBinMatch.Groups[2].Value.ToLowerInvariant()
      $tokenSource = if($envBinMatch.Groups[1].Value.ToLowerInvariant() -eq 'dlc'){'openedge-dlc-path'}else{'env-path'}
    }
  }

  # Pattern 1b: broader env-var paths, including $DLC/proserve
  if(-not $token -and -not $commentLikely){
    $envPathMatch = [regex]::Match($trim, '(?i)\$(\w+)(?:/(?:[\w.-]+))+/(\w[\w.-]*)')
    if($envPathMatch.Success){
      $token = $envPathMatch.Groups[2].Value.ToLowerInvariant()
      $tokenSource = if($envPathMatch.Groups[1].Value.ToLowerInvariant() -eq 'dlc'){'openedge-dlc-path'}else{'env-path'}
    }
  }

  # Pattern 1c: absolute paths like /usr/pform/bin/pcl2pdf
  # Skip paths that appear after a shell redirection operator (> or >>) — those are
  # output targets (e.g. > /dev/null), not the command being executed.
  if(-not $token -and -not $commentLikely){
    $absPathMatch = [regex]::Match($trim, '(?i)/(?:[\w.-]+/)+(\w[\w.-]*)')
    if($absPathMatch.Success){
      $beforePath = $trim.Substring(0, $absPathMatch.Index).TrimEnd()
      if($beforePath -notmatch '>+\s*$'){
        $token = $absPathMatch.Groups[1].Value.ToLowerInvariant()
        $tokenSource = 'abs-path'
      }
    }
  }

  # Pattern 1d: quoted search("toolname") extraction, e.g. search("quoter")
  # Only use quoted literal search() values; do not treat search(variable) as a command token.
  if(-not $token -and -not $commentLikely){
    $searchPattern = '(?i)search\s*\(\s*["'']([a-z0-9_/.-]+)["'']\s*\)'
    $searchMatch = [regex]::Match($trim, $searchPattern)
    if($searchMatch.Success){
      $searched = $searchMatch.Groups[1].Value.Trim()
      if($searched -match '/'){
        $token = ($searched -split '/')[-1].ToLowerInvariant()
      } else {
        $token = $searched.ToLowerInvariant()
      }
      if(-not ($token -match '^[a-z][a-z0-9_.-]+$' -and $token.Length -gt 1)){
        $token = ''
      } else {
        $tokenSource = 'search-literal'
      }
    }
  }

  # Strip a trailing '.' that is the OpenEdge statement terminator, not part of the command name.
  # e.g. "unix silent faxissue." extracts "faxissue." -> normalize to "faxissue"
  if ($token -match '\.$') {
    $token = $token.TrimEnd('.')
    if ($token.Length -lt 2) { $token = '' }
  }

  if($token -and $trim -match ('(?i)\$DLC(?:/bin)?/' + [regex]::Escape($token) + '\b')){
    $tokenSource = 'openedge-dlc-path'
  }

  if($tokenSource -eq 'openedge-dlc-path' -or $openEdgeCommandSet -contains $token){
    $openEdgeBuiltIn = $true
  }

  # Look up the command concern in the loaded JSON configuration
  $concern = ''
  if($commandNotesLookup -and $commandNotesLookup.PSObject.Properties.Name -contains $token){
    $concern = $commandNotesLookup.$token
  }

  if($trim -match '(?i)\bVALUE\s*\(' -and -not $commentLikely){
    if($concern){ $concern += ' ' }
    if($isOpaqueValue){
      $concern += 'OPAQUE VALUE() — command source unknown; requires manual inspection for input validation.'
    } elseif($resolvedFromVar){
      $concern += 'Command resolved from variable assignment; validate input source and quoting.'
    } else {
      $concern += 'Command built dynamically; validate input source and quoting.'
    }
  }

  $platformClassification = Get-PlatformClassification `
    -CommandToken $token `
    -Statement $trim `
    -Concern $concern `
    -PlatformRules $platformRules

  $rel = Convert-ToWorkspaceRelativePath -Path $file -WorkspaceRoot $workspace

  # Confidence reflects how certain the command token extraction is.
  $tokenConfidence = Get-TokenConfidence -TokenSource $tokenSource -Token $token -IsOpaqueValue $isOpaqueValue

  # If no command token was extracted, confidence is 0 (can't evaluate what we don't have)
  if ([string]::IsNullOrWhiteSpace($token)) {
    $tokenConfidence = 0
  }

  # Create normalized row using helper.
  $row = New-AuditRow `
    -File $rel `
    -Line $m.LineNumber `
    -Type $type `
    -CommandToken $token `
    -GatedNearby $gated `
    -GatedFor $gatedFor `
    -CommentLikely $commentLikely `
    -Statement $trim `
    -OpaqueValue $isOpaqueValue `
    -CommandSource $tokenSource `
    -OpenEdgeBuiltIn $openEdgeBuiltIn `
    -RHEL96Concern $concern `
    -PlatformClassification $platformClassification `
    -TokenConfidence $tokenConfidence

  $rows.Add($row) | Out-Null
}

  # Filter rows irrelevant to the target platform and suppress gated-dead-code
  $excludedCommentRows = ($rows | Where-Object { $_.CommentLikely }).Count

  $auditRows = $rows | Where-Object {
    # Always drop commented-out rows (unless IncludeComments flag)
    if ($_.CommentLikely -and -not $IncludeComments) { return $false }

    # For a Linux target: drop native-Windows-only statement types and obvious Windows tokens
    if ($TargetPlatform -eq 'linux') {
      if ($_.Type -eq 'DOS SILENT') { return $false }
      if ($_.Statement -match '(?i)\b(wordpad|notepad\.exe|\bdir\b|\bcopy\b|\bdel\b|cls)\b') { return $false }
    }

    # Suppress obsolete-platform gated rows (dead code on any modern platform)
    $gf = ([string]$_.GatedFor).Trim().ToLowerInvariant()
    if ($gf -in @('vms','os2')) { return $false }

    # Suppress rows gated for the opposite OS
    $oppositeGate = if ($TargetPlatform -eq 'linux') { 'windows' } else { 'unix' }
    if ($gf -eq $oppositeGate) { return $false }

    # Suppress rows gated for the opposite windowing mode (tty vs gui)
    if ($WindowSystem -eq 'gui' -and $gf -eq 'tty') { return $false }
    if ($WindowSystem -eq 'tty' -and $gf -eq 'gui') { return $false }

    return $true
  }

  $suppressedGatedRows = ($rows | Where-Object {
    $gf = ([string]$_.GatedFor).Trim().ToLowerInvariant()
    $oppositeGate  = if ($TargetPlatform -eq 'linux') { 'windows' } else { 'unix' }
    $oppositeWindow = if ($WindowSystem -eq 'gui') { 'tty' } elseif ($WindowSystem -eq 'tty') { 'gui' } else { $null }
    $gf -in @('vms','os2') -or $gf -eq $oppositeGate -or ($null -ne $oppositeWindow -and $gf -eq $oppositeWindow)
  }).Count

  $auditRows | Sort-Object File,Line | Select-Object -Property @(
    'File', 'Line', 'Type', 'CommandToken', 'GatedNearby', 'GatedFor', 'CommentLikely',
    'Statement', 'OpaqueValue', 'CommandSource', 'PlatformClassification', 'OpenEdgeBuiltIn', 'RHEL96Concern',
    'TokenConfidence', 'ConfidenceScore', 'ConfidenceExplanation'
  ) | Export-Csv -Path $outCsv -NoTypeInformation -Encoding UTF8

  # Stage 2 handoff: unresolved rows for AI reasoning review.
  $unresolvedRows = $auditRows | Where-Object {
    [string]::IsNullOrWhiteSpace($_.CommandToken) -or [int]$_.TokenConfidence -lt 75
  } | Sort-Object File,Line

  $unresolvedRows | Select-Object -Property @(
    'File', 'Line', 'Type', 'CommandToken', 'Statement',
    'CommandSource', 'PlatformClassification', 'TokenConfidence', 'ConfidenceScore', 'ConfidenceExplanation'
  ) | Export-Csv -Path $outUnresolvedCsv -NoTypeInformation -Encoding UTF8

  $total = $auditRows.Count
  $concerns = ($auditRows | Where-Object { $_.RHEL96Concern -ne '' }).Count

  $metadataPayload = [pscustomobject]@{
    WorkspaceRoot = $workspace
    Roots = @($resolvedRoots)
    RelativeRoots = @($resolvedRoots | ForEach-Object { Convert-ToWorkspaceRelativePath -Path $_ -WorkspaceRoot $workspace })
    GeneratedAt = (Get-Date).ToString('s')
    Mode = $Mode
    CsvPath = $outCsv
    UnresolvedCsvPath = $outUnresolvedCsv
  }

  if($PSVersionTable.PSVersion.Major -ge 7){
    $metadataPayload | ConvertTo-Json -Depth 4 | Out-File -FilePath $outMetadata -Encoding utf8NoBOM
  } else {
    [System.IO.File]::WriteAllText($outMetadata, ($metadataPayload | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
  }
}

# ============================================================================
# COMMAND SUMMARY EXCEL (client decisions workbook)
# ============================================================================
function Get-RecommendedAction {
  param(
    [string]$Token,
    [string]$Platform,
    [string]$Concern,
    [string]$TargetPlatform = 'linux'
  )
  $t          = $Token.Trim().ToLowerInvariant()
  $p          = $Platform.Trim().ToLowerInvariant()
  $hasConcern = -not [string]::IsNullOrWhiteSpace($Concern)
  $tgt        = $TargetPlatform.Trim().ToLowerInvariant()

  # Commands native to the opposite platform must be replaced
  $oppositeOf = if ($tgt -eq 'linux') { 'windows' } else { 'linux' }
  if ($p -eq $oppositeOf) { return 'B-replace' }

  # File-extension heuristics for the opposite-platform native types
  if ($tgt -eq 'linux'   -and $t -match '\.(exe|bat|cmd|vbs|ps1|com)$') { return 'B-replace' }
  if ($tgt -eq 'windows' -and $t -match '\.sh$') { return 'B-replace' }

  # Shell scripts targeting Linux are site assets that must be deployed to the server
  if ($tgt -eq 'linux' -and $t -match '\.sh$') { return 'C-deploy' }

  # Tokens containing any dot are almost certainly filename fragments or data
  # files (.txt, .ftp, .csv, trailing dot, etc.) rather than real OS commands.
  # These are extraction artifacts — leave blank so the client reviews them.
  if ($t -match '\.' -and $t -notmatch '\.sh$') { return '' }

  # 'null' is never a real command — it is a redirection artifact (e.g. > /dev/null)
  if ($t -eq 'null') { return '' }

  # Same-platform or cross-platform: concern present → verify/install; no concern → standard utility
  if ($p -in @($tgt, 'both')) {
    return $(if ($hasConcern) { 'A-install' } else { 'E-no-action' })
  }

  # Unknown platform — leave blank for the client to decide
  return ''
}

# ============================================================================
# INGEST-DECISIONS MODE
# ============================================================================
if ($Mode -eq 'ingest-decisions') {
  if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    throw "ImportExcel module is required. Install with: Install-Module ImportExcel -Scope CurrentUser -Force"
  }
  Import-Module ImportExcel -ErrorAction Stop

  # Resolve workbook path — default to the standard output location
  $ingestXlsx = if (-not [string]::IsNullOrWhiteSpace($DecisionsXlsxPath)) {
    $DecisionsXlsxPath
  } else {
    $outDecisionsXlsx
  }
  if (-not (Test-Path $ingestXlsx)) {
    throw "Decisions workbook not found: $ingestXlsx"
  }

  Write-Host "Ingesting client decisions from: $ingestXlsx" -ForegroundColor Cyan
  $sheet = Import-Excel -Path $ingestXlsx -WorksheetName 'Decisions'

  $decisions  = @{}
  $newSuppress = [System.Collections.Generic.List[string]]::new()
  $ingested = 0; $skipped = 0; $suppressed = 0

  foreach ($row in $sheet) {
    $token        = ([string]$row.CommandToken).Trim().ToLowerInvariant()
    $stillInUse   = ([string]$row.StillInUse).Trim().ToLowerInvariant()
    $action       = ([string]$row.Action).Trim().ToLowerInvariant()
    $clientNotes  = ([string]$row.ClientNotes).Trim()

    if ([string]::IsNullOrWhiteSpace($token)) { $skipped++; continue }

    $decisions[$token] = [pscustomobject]@{
      StillInUse  = $stillInUse
      Action      = $action
      ClientNotes = $clientNotes
    }
    $ingested++

    # Suppress tokens the client marks as dead code or not-in-use
    if ($action -eq 'd-dead-code' -or $stillInUse -eq 'no') {
      if ($suppressedCommandSet -notcontains $token) {
        $newSuppress.Add($token)
        $suppressed++
      }
    }
  }

  # Write client-decisions.json
  $decisions | ConvertTo-Json -Depth 4 | ForEach-Object {
    [System.IO.File]::WriteAllText($outClientDecisions, $_, (New-Object System.Text.UTF8Encoding($false)))
  }
  Write-Host "Written: $outClientDecisions ($ingested decisions ingested, $skipped skipped)" -ForegroundColor Green

  # Update suppressedCommands in config JSON if any new ones found
  if ($newSuppress.Count -gt 0) {
    $configJson = Get-Content $configJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $existing   = Get-NormalizedStringArray -Values $configJson.suppressedCommands
    $merged     = @($existing) + @($newSuppress) | Select-Object -Unique | Sort-Object
    $configJson.suppressedCommands = $merged
    $configJson | ConvertTo-Json -Depth 10 | ForEach-Object {
      [System.IO.File]::WriteAllText($configJsonPath, $_, (New-Object System.Text.UTF8Encoding($false)))
    }
    Write-Host "Added $suppressed new suppressed command(s) to command-notes-config.json: $($newSuppress -join ', ')" -ForegroundColor Yellow
  } else {
    Write-Host "No new commands to suppress." -ForegroundColor Gray
  }

  Write-Host ""
  Write-Host "Next steps:" -ForegroundColor Cyan
  Write-Host "  1. Run -Mode report-only    to regenerate the HTML with decisions overlaid" -ForegroundColor Cyan
  Write-Host "  2. Run -Mode command-summary to regenerate the Excel workbook" -ForegroundColor Cyan
  exit 0
}

if ($Mode -eq 'command-summary') {
  if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    throw "ImportExcel module is required. Install with: Install-Module ImportExcel -Scope CurrentUser -Force"
  }
  Import-Module ImportExcel -ErrorAction Stop
  Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

  # One row per unique non-baseline, non-OE command token
  $summaryRows = $auditRows |
    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.CommandToken) } |
    Where-Object { $suppressedCommandSet -notcontains ([string]$_.CommandToken).Trim().ToLowerInvariant() } |
    Group-Object CommandToken |
    Where-Object {
      $name = ([string]$_.Name).Trim().ToLowerInvariant()
      $basicUnixCommandSet -notcontains $name -and
      $openEdgeCommandSet  -notcontains $name
    } |
    Sort-Object Name |
    ForEach-Object {
      $cmd  = [string]$_.Name
      $grp  = $_.Group
      $note = if ($commandNotesLookup -and $commandNotesLookup.PSObject.Properties.Name -contains $cmd) { $commandNotesLookup.$cmd } else { '' }
      $exs  = $grp | Sort-Object File,Line | Select-Object -First 3
      $plats = @($grp | ForEach-Object {
        Normalize-PlatformClassification -Value ([string]$_.PlatformClassification) -Fallback $platformRules.unknownDefault
      } | Sort-Object -Unique)
      # Merge multiple classifications for the same token into one canonical value.
      # 'both' wins over any single-platform value (it is a superset).
      # If the only disagreement is linux vs unknown, linux wins.
      # Conflicting linux/windows means truly unknown for this token.
      $nonUnknown = @($plats | Where-Object { $_ -ne 'unknown' })
      $plat = if ($plats.Count -eq 0) {
        'unknown'
      } elseif ($plats.Count -eq 1) {
        $plats[0]
      } elseif ($nonUnknown -contains 'both') {
        'both'
      } elseif ($nonUnknown.Count -eq 1) {
        $nonUnknown[0]
      } elseif (($nonUnknown | Sort-Object -Unique).Count -eq 1) {
        $nonUnknown[0]
      } else {
        # Genuinely conflicting (e.g. linux + windows on same token) - flag as unknown
        'unknown'
      }
      # Overlay client decisions if available
      $cd = if ($clientDecisions.ContainsKey($cmd)) { $clientDecisions[$cmd] } else { $null }
      [pscustomobject]@{
        CommandToken           = $cmd
        Hits                   = $grp.Count
        Files                  = ($grp | Select-Object -ExpandProperty File -Unique).Count
        PlatformClassification = $plat
        RHEL96Concern          = $note
        ExampleSites           = ($exs | ForEach-Object { (Convert-ToWorkspaceRelativePath -Path ([string]$_.File) -WorkspaceRoot $workspace) + ':' + $_.Line }) -join '; '
        StillInUse             = if ($cd) { [string]$cd.StillInUse } else { '' }
        Action                 = if ($cd -and -not [string]::IsNullOrWhiteSpace([string]$cd.Action)) { [string]$cd.Action } else { Get-RecommendedAction -Token $cmd -Platform $plat -Concern $note -TargetPlatform $TargetPlatform }
        ClientNotes            = if ($cd) { [string]$cd.ClientNotes } else { '' }
      }
    }

  if ($summaryRows.Count -eq 0) {
    Write-Warning "No non-baseline commands found in inventory. Nothing to export."
    exit 0
  }

  Write-Host "Building command-decisions workbook: $($summaryRows.Count) commands..." -ForegroundColor Cyan
  if (Test-Path $outDecisionsXlsx) { Remove-Item $outDecisionsXlsx -Force }

  # --- Instructions sheet ---
  $instrRows = @(
    [pscustomobject]@{ Column = 'CommandToken';           Description = 'The command or script name found in ABL source code.  Read-only — do not edit.' }
    [pscustomobject]@{ Column = 'Hits';                   Description = 'Total number of OS-command execution sites that call this command.  Read-only.' }
    [pscustomobject]@{ Column = 'Files';                  Description = 'Number of distinct source files that invoke this command.  Read-only.' }
    [pscustomobject]@{ Column = 'PlatformClassification'; Description = 'Detected platform:  linux = Linux-only  |  windows = Windows-only  |  both = cross-platform  |  unknown = undetermined.  Read-only.' }
    [pscustomobject]@{ Column = 'RHEL96Concern';          Description = 'Migration concern notes for this command on RHEL 9.6.  Read-only.' }
    [pscustomobject]@{ Column = 'ExampleSites';           Description = 'Up to 3 example source-file locations (file:line) where this command appears.  Read-only.' }
    [pscustomobject]@{ Column = 'StillInUse';             Description = 'YOU FILL IN:  Is this command part of active production functionality?  Choose one:  yes  /  no  /  maybe' }
    [pscustomobject]@{ Column = 'Action';                 Description = 'YOU FILL IN:  What should happen with this command?  A recommended value has been pre-filled where we are reasonably confident — change it if you disagree.  Choices:  A-install = confirm it is installed and working on the new RHEL server  |  B-replace = the code needs to change to use a different tool or approach  |  C-deploy = this is a custom script or binary in our codebase that must be copied to the server  |  D-dead-code = this code is no longer used and can be ignored or removed  |  E-no-action = standard OS utility expected to be present on RHEL 9.6 by default; no explicit action needed' }
    [pscustomobject]@{ Column = 'ClientNotes';            Description = 'YOU FILL IN:  Any additional context — who owns this, notes about replacements, open questions, etc.' }
    [pscustomobject]@{ Column = '---';                    Description = '--- ROW COLOR KEY (Decisions sheet) ---' }
    [pscustomobject]@{ Column = 'Green row';              Description = 'PlatformClassification = linux — command is Linux-native; likely compatible with RHEL 9.6 if installed.' }
    [pscustomobject]@{ Column = 'Red row';                Description = 'PlatformClassification = windows — Windows-only command; will NOT run on Linux and requires action (replace or confirm dead).' }
    [pscustomobject]@{ Column = 'Amber row';              Description = 'PlatformClassification = both — cross-platform command; should work on Linux but verify installation.' }
    [pscustomobject]@{ Column = 'Grey row';               Description = 'PlatformClassification = unknown — platform could not be determined automatically; needs your input.' }
  )
  $instrRows | Export-Excel -Path $outDecisionsXlsx -WorksheetName 'Instructions' `
    -AutoSize -FreezeTopRow -BoldTopRow -TableName 'InstrTable' -TableStyle Medium2

  # Apply actual background colors to the color-key rows in the Instructions sheet
  # so the client can see the colors alongside the descriptions
  $instrPkg = Open-ExcelPackage -Path $outDecisionsXlsx
  $wsInstr  = $instrPkg.Workbook.Worksheets['Instructions']
  $colorKeyMap = @{
    12 = [System.Drawing.Color]::FromArgb(226, 239, 218)  # Green  (linux)   — row 12 (1 header + 9 data rows + 1 separator + this)
    13 = [System.Drawing.Color]::FromArgb(255, 199, 206)  # Red    (windows) — row 13
    14 = [System.Drawing.Color]::FromArgb(255, 235, 156)  # Amber  (both)    — row 14
    15 = [System.Drawing.Color]::FromArgb(237, 237, 237)  # Grey   (unknown) — row 15
  }
  foreach ($rowNum in $colorKeyMap.Keys) {
    $bg = $colorKeyMap[$rowNum]
    for ($ci = 1; $ci -le 2; $ci++) {
      $wsInstr.Cells[$rowNum, $ci].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
      $wsInstr.Cells[$rowNum, $ci].Style.Fill.BackgroundColor.SetColor($bg)
    }
  }
  $instrPkg.Save()
  $instrPkg.Dispose()

  # --- Decisions sheet ---
  $excelPkg = $summaryRows | Export-Excel -Path $outDecisionsXlsx -WorksheetName 'Decisions' `
    -AutoSize -FreezeTopRow -BoldTopRow `
    -TableName 'DecisionsTable' -TableStyle Light1 `
    -PassThru

  $ws        = $excelPkg.Workbook.Worksheets['Decisions']
  $dataStart = 2
  $lastRow   = $summaryRows.Count + 1

  # Column indices match pscustomobject property order (1-based)
  $colPlatform   = 4
  $colConcern    = 5
  $colExamples   = 6
  $colStillInUse = 7
  $colAction     = 8
  $colNotes      = 9

  # Row fill color by platform classification
  $fillColors = @{
    'linux'   = [System.Drawing.Color]::FromArgb(226, 239, 218)  # soft green
    'windows' = [System.Drawing.Color]::FromArgb(255, 199, 206)  # soft red
    'both'    = [System.Drawing.Color]::FromArgb(255, 235, 156)  # soft amber
    'unknown' = [System.Drawing.Color]::FromArgb(237, 237, 237)  # soft grey
  }
  for ($r = $dataStart; $r -le $lastRow; $r++) {
    $pval  = ([string]$ws.Cells[$r, $colPlatform].Value).Trim().ToLowerInvariant()
    $color = if ($fillColors.ContainsKey($pval)) { $fillColors[$pval] } else { $fillColors['unknown'] }
    for ($c = 1; $c -le 9; $c++) {
      $ws.Cells[$r, $c].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
      $ws.Cells[$r, $c].Style.Fill.BackgroundColor.SetColor($color)
    }
  }

  # Blue header tint on the three client-editable columns
  $headerBlue = [System.Drawing.Color]::FromArgb(189, 215, 238)
  foreach ($ci in @($colStillInUse, $colAction, $colNotes)) {
    $ws.Cells[1, $ci].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
    $ws.Cells[1, $ci].Style.Fill.BackgroundColor.SetColor($headerBlue)
    $ws.Cells[1, $ci].Style.Font.Bold = $true
  }

  # Dropdown — StillInUse (column G)
  $dvUse = $ws.DataValidations.AddListValidation("G${dataStart}:G${lastRow}")
  $dvUse.ShowErrorMessage = $true
  $dvUse.ErrorTitle = 'Invalid value'
  $dvUse.Error = 'Please choose: yes, no, or maybe'
  $dvUse.Formula.Values.Add('yes')
  $dvUse.Formula.Values.Add('no')
  $dvUse.Formula.Values.Add('maybe')

  # Dropdown — Action (column H)
  $dvAct = $ws.DataValidations.AddListValidation("H${dataStart}:H${lastRow}")
  $dvAct.ShowErrorMessage = $true
  $dvAct.ErrorTitle = 'Invalid value'
  $dvAct.Error = 'Please choose one of the action codes — see the Instructions sheet for descriptions.'
  $dvAct.Formula.Values.Add('A-install')
  $dvAct.Formula.Values.Add('B-replace')
  $dvAct.Formula.Values.Add('C-deploy')
  $dvAct.Formula.Values.Add('D-dead-code')
  $dvAct.Formula.Values.Add('E-no-action')

  # Column width overrides for long-text columns
  $ws.Column($colConcern).Width  = 42
  $ws.Column($colExamples).Width = 48
  $ws.Column($colNotes).Width    = 32
  for ($r = $dataStart; $r -le $lastRow; $r++) {
    $ws.Cells[$r, $colConcern].Style.WrapText  = $true
    $ws.Cells[$r, $colExamples].Style.WrapText = $true
  }

  $excelPkg.Save()
  $excelPkg.Dispose()

  Write-Host "Written: $outDecisionsXlsx" -ForegroundColor Green
  Write-Host "  Decisions tab    : $($summaryRows.Count) commands (client fills columns G-I)" -ForegroundColor Green
  Write-Host "  Instructions tab : column descriptions and action-code guide" -ForegroundColor Green
  Write-Host ""
  Write-Host "Send to client. On return run -Mode ingest-decisions to merge their feedback." -ForegroundColor Yellow
  exit 0
}

if ($Mode -eq 'report-only' -or $Mode -eq 'confidence') {
  # ============================================================================
  # PHASE 2: REPORT GENERATION
  # ============================================================================

  foreach ($row in $auditRows) {
    $existing = [string]$row.PlatformClassification
    if ([string]::IsNullOrWhiteSpace($existing)) {
      $existing = Get-PlatformClassification -CommandToken ([string]$row.CommandToken) -Statement ([string]$row.Statement) -Concern ([string]$row.RHEL96Concern) -PlatformRules $platformRules
    }

    $normalizedPlatform = Normalize-PlatformClassification -Value $existing -Fallback $platformRules.unknownDefault
    if ($row.PSObject.Properties.Name -contains 'PlatformClassification') {
      $row.PlatformClassification = $normalizedPlatform
    } else {
      $row | Add-Member -NotePropertyName 'PlatformClassification' -NotePropertyValue $normalizedPlatform
    }
  }

  $allUniqueCommands = $auditRows | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.CommandToken) } | Group-Object CommandToken | Sort-Object Name
  $basicCommandSetToExclude = if ($TargetPlatform -eq 'windows') { $basicWindowsCommandSet } else { $basicUnixCommandSet }
  $displayedUniqueCommands = $allUniqueCommands | Where-Object {
    $name = ([string]$_.Name).Trim().ToLowerInvariant()
    $basicCommandSetToExclude -notcontains $name -and
    $openEdgeCommandSet -notcontains $name
  }

  # Build dependency summary from unique non-basic, non-OpenEdge command tokens in the main rows
  $distinctDependencies = $displayedUniqueCommands |
    ForEach-Object {
      $cmd = [string]$_.Name
      $note = if($commandNotesLookup -and $commandNotesLookup.PSObject.Properties.Name -contains $cmd){ $commandNotesLookup.$cmd } else { '' }
      $examples = $_.Group | Sort-Object File,Line | Select-Object -First 3
      $platforms = @($_.Group | ForEach-Object { Normalize-PlatformClassification -Value ([string]$_.PlatformClassification) -Fallback $platformRules.unknownDefault } | Sort-Object -Unique)
      [pscustomobject]@{
        CommandToken = $cmd
        HitCount = $_.Count
        FileCount = ($_.Group | Select-Object -ExpandProperty File -Unique).Count
        ExampleSites = ($examples | ForEach-Object { $_.File + ':' + $_.Line }) -join '; '
        Concern = $note
        PlatformClassification = if ($platforms.Count -eq 0) { 'unknown' } else { ($platforms -join ',') }
      }
    }

  # Build mode-specific table headers.
  # Substitute $TargetPlatformLabel directly here so the concern column header is correct
  # even when {{MODE_SPECIFIC_COLUMNS}} is injected after {{CONCERN_LABEL}} was already replaced.
  $concernColLabel = [System.Net.WebUtility]::HtmlEncode($TargetPlatformLabel + ' Concern')
  $modeSpecificColumns = if ($Mode -eq 'confidence') {
    '<th onclick="sortTable(5)">Confidence</th><th onclick="sortTable(6)">Explanation</th><th onclick="sortTable(7)">OE</th><th onclick="sortTable(8)">Statement</th>'
  } else {
    "<th onclick=`"sortTable(5)`">Gated</th><th onclick=`"sortTable(6)`">GatedFor</th><th onclick=`"sortTable(7)`">Src</th><th onclick=`"sortTable(8)`">Confidence</th><th onclick=`"sortTable(9)`">OE</th><th onclick=`"sortTable(10)`">Statement</th><th onclick=`"sortTable(11)`">$concernColLabel</th><th onclick=`"sortTable(12)`">Explanation</th>"
  }

  # Report metadata
  $generatedAt = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $scopeDisplay = ($reportRoots | ForEach-Object { Convert-ToWorkspaceRelativePath -Path $_ -WorkspaceRoot $workspace }) -join ', '

  # oppositePlatform must be defined before the $htmlRows loop uses it for ungated-risk detection
  $oppositePlatform = if ($TargetPlatform -eq 'linux') { 'windows' } else { 'linux' }

  # Mode-specific title — incorporates TargetPlatformLabel so it is always descriptive
  $pageTitle = if ($Mode -eq 'confidence') {
    "OS Command Audit (Confidence Summary) - $TargetPlatformLabel"
  } elseif ($Mode -eq 'report-only') {
    "OS Command Audit (Regenerated) - $TargetPlatformLabel"
  } elseif ($Mode -eq 'export') {
    'OS Command Audit (Export Format)'
  } else {
    "OS Command Audit - $TargetPlatformLabel"
  }

  $htmlRows = $auditRows | Sort-Object File,Line | ForEach-Object {
    $platformClass = Normalize-PlatformClassification -Value ([string]$_.PlatformClassification) -Fallback $platformRules.unknownDefault
    $gfNorm = ([string]$_.GatedFor).Trim().ToLowerInvariant()
    # Opposite-platform command: token known and not gated
    $isOppositeUngated = (-not [string]::IsNullOrWhiteSpace([string]$_.CommandToken)) -and
                         (-not (Test-TruthyValue $_.OpaqueValue)) -and
                         $platformClass -eq $oppositePlatform -and
                         [string]::IsNullOrWhiteSpace($gfNorm)
    # Keyword mismatch: UNIX SILENT won't execute on Windows; DOS SILENT won't execute on Linux
    $rowType = [string]$_.Type
    $isTypeKeywordRisk = [string]::IsNullOrWhiteSpace($gfNorm) -and
                         (($TargetPlatform -eq 'windows' -and $rowType -eq 'UNIX SILENT') -or
                          ($TargetPlatform -eq 'linux'   -and $rowType -eq 'DOS SILENT'))
    $isUngatedRisk = $isOppositeUngated -or $isTypeKeywordRisk
    $rowClass = ''
    if([string]::IsNullOrWhiteSpace($_.CommandToken))       { $rowClass = 'unresolved' }
    elseif(Test-TruthyValue $_.OpaqueValue)                 { $rowClass = 'opaque' }
    elseif($isUngatedRisk)                                  { $rowClass = 'ungated-risk' }
    $stmt = [System.Net.WebUtility]::HtmlEncode($_.Statement)
    $conc = [System.Net.WebUtility]::HtmlEncode($_.RHEL96Concern)
    $src = [System.Net.WebUtility]::HtmlEncode($_.CommandSource)
    $confExp = [System.Net.WebUtility]::HtmlEncode($_.ConfidenceExplanation)
    $oe = if(Test-TruthyValue $_.OpenEdgeBuiltIn){'True'}else{'False'}

    if ($Mode -eq 'confidence') {
      "<tr class='$rowClass' data-platform='$platformClass'><td>$($_.File)</td><td>$($_.Line)</td><td>$($_.Type)</td><td>$($_.CommandToken)</td><td>$platformClass</td><td>$($_.ConfidenceScore)</td><td>$confExp</td><td>$oe</td><td>$stmt</td></tr>"
    } else {
      $gatedForVal = [System.Net.WebUtility]::HtmlEncode([string]$_.GatedFor)
      "<tr class='$rowClass' data-platform='$platformClass'><td>$($_.File)</td><td>$($_.Line)</td><td>$($_.Type)</td><td>$($_.CommandToken)</td><td>$platformClass</td><td>$($_.GatedNearby)</td><td>$gatedForVal</td><td>$src</td><td>$($_.ConfidenceScore)</td><td>$oe</td><td>$stmt</td><td>$conc</td><td>$confExp</td></tr>"
    }
  }

  $dependencyHtmlRows = $distinctDependencies | ForEach-Object {
    $examples = [System.Net.WebUtility]::HtmlEncode($_.ExampleSites)
    $concern = [System.Net.WebUtility]::HtmlEncode($_.Concern)
    $platform = [System.Net.WebUtility]::HtmlEncode(([string]$_.PlatformClassification).ToLowerInvariant())
    "<tr data-platform='$platform'><td>$($_.CommandToken)</td><td>$($_.HitCount)</td><td>$($_.FileCount)</td><td>$platform</td><td>$examples</td><td>$concern</td></tr>"
  }

  # Load the HTML template from file
  $templatePath = Join-Path -Path $PSScriptRoot -ChildPath 'templates' | Join-Path -ChildPath 'audit-report-template.html'
  if (-not (Test-Path -LiteralPath $templatePath)) {
    throw "Template file not found: $templatePath"
  }

  $html = Get-Content -LiteralPath $templatePath -Raw

  # Load Progress logo from the shared analyze-abl-dependencies templates folder
  $sharedTemplatesDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'analyze-abl-dependencies' | Join-Path -ChildPath 'templates'
  $logoPath = Join-Path $sharedTemplatesDir 'progresslogo.png'
  $logoDataUri = ''
  if (Test-Path $logoPath) {
    $logoBytes = [System.IO.File]::ReadAllBytes($logoPath)
    $logoBase64 = [Convert]::ToBase64String($logoBytes)
    $logoDataUri = "data:image/png;base64,$logoBase64"
  } else {
    Write-Warning "Progress logo not found at: $logoPath - header will render without logo"
  }

  # Compute values for token substitution
  $totalRows = @($auditRows).Count
  $openedgeUtilitySites = @($auditRows | Where-Object { Test-TruthyValue $_.OpenEdgeBuiltIn }).Count
  $basicUnixSites = @(
    $auditRows | Where-Object {
      $token = ([string]$_.CommandToken).Trim().ToLowerInvariant()
      -not [string]::IsNullOrWhiteSpace($token) -and $basicUnixCommandSet -contains $token
    }
  ).Count
  $windowsSites = @($auditRows | Where-Object { (Normalize-PlatformClassification -Value ([string]$_.PlatformClassification) -Fallback $platformRules.unknownDefault) -eq 'windows' }).Count
  $linuxSites = @($auditRows | Where-Object { (Normalize-PlatformClassification -Value ([string]$_.PlatformClassification) -Fallback $platformRules.unknownDefault) -eq 'linux' }).Count
  $bothSites = @($auditRows | Where-Object { (Normalize-PlatformClassification -Value ([string]$_.PlatformClassification) -Fallback $platformRules.unknownDefault) -eq 'both' }).Count
  $unknownSites = @($auditRows | Where-Object { (Normalize-PlatformClassification -Value ([string]$_.PlatformClassification) -Fallback $platformRules.unknownDefault) -eq 'unknown' }).Count
  $ungatedRiskSites = @($auditRows | Where-Object {
    $plt = Normalize-PlatformClassification -Value ([string]$_.PlatformClassification) -Fallback $platformRules.unknownDefault
    $gf  = ([string]$_.GatedFor).Trim()
    $typ = [string]$_.Type
    $isOppUngated = $plt -eq $oppositePlatform -and [string]::IsNullOrWhiteSpace($gf) -and -not [string]::IsNullOrWhiteSpace([string]$_.CommandToken)
    $isTypeRisk   = [string]::IsNullOrWhiteSpace($gf) -and
                    (($TargetPlatform -eq 'windows' -and $typ -eq 'UNIX SILENT') -or
                     ($TargetPlatform -eq 'linux'   -and $typ -eq 'DOS SILENT'))
    $isOppUngated -or $isTypeRisk
  }).Count
  $basicCommandsJson = ($basicCommandSetToExclude | ConvertTo-Json -Compress)
  $openEdgeCommandsJson = ($openEdgeCommandSet | ConvertTo-Json -Compress)

  # Perform token replacements (literal Replace avoids regex replacement surprises with $ and \ in content)
  $html = $html.Replace('{{LOGO_DATA_URI}}', $logoDataUri)
  $html = $html.Replace('{{PAGE_TITLE}}', [System.Net.WebUtility]::HtmlEncode($pageTitle))
  $html = $html.Replace('{{CONCERN_LABEL}}', [System.Net.WebUtility]::HtmlEncode($TargetPlatformLabel + ' Concern'))
  $html = $html.Replace('{{PLATFORM_LABEL}}', [System.Net.WebUtility]::HtmlEncode($TargetPlatformLabel + ' Sites'))
  $html = $html.Replace('{{SUPPRESSED_ROWS}}', [string]$suppressedGatedRows)
  $html = $html.Replace('{{UNGATED_RISK_SITES}}', [string]$ungatedRiskSites)
  $winSysLabel = if ($WindowSystem -eq 'gui') { 'GUI (prowin)' } elseif ($WindowSystem -eq 'tty') { 'TTY (_progres)' } else { 'Any mode' }
  $html = $html.Replace('{{WINDOW_SYSTEM_LABEL}}', [System.Net.WebUtility]::HtmlEncode($winSysLabel))
  $html = $html.Replace('{{GENERATED_AT}}', [string]$generatedAt)
  $html = $html.Replace('{{SCOPE_DISPLAY}}', [string]$scopeDisplay)
  $html = $html.Replace('{{TOTAL}}', [string]$totalRows)
  $html = $html.Replace('{{OPENEDGE_UTILITY_SITES}}', [string]$openedgeUtilitySites)
  $html = $html.Replace('{{BASIC_UNIX_SITES}}', [string]$basicUnixSites)
  $html = $html.Replace('{{WINDOWS_SITES}}', [string]$windowsSites)
  $html = $html.Replace('{{LINUX_SITES}}', [string]$linuxSites)
  $html = $html.Replace('{{BOTH_SITES}}', [string]$bothSites)
  $html = $html.Replace('{{UNKNOWN_SITES}}', [string]$unknownSites)
  $html = $html.Replace('{{CONCERNS}}', [string]$concerns)
  $html = $html.Replace('{{EXCLUDED_COMMENTS}}', [string]$excludedCommentRows)
  $html = $html.Replace('{{ALL_UNIQUE_COMMANDS_COUNT}}', [string]@($allUniqueCommands).Count)
  $html = $html.Replace('{{DISTINCT_DEPENDENCIES_COUNT}}', [string]@($distinctDependencies).Count)
  $html = $html.Replace('{{BASIC_COMMANDS_JSON}}', [string]$basicCommandsJson)
  $html = $html.Replace('{{OPENEDGE_COMMANDS_JSON}}', [string]$openEdgeCommandsJson)
  $html = $html.Replace('{{DEPENDENCY_ROWS}}', [string]($dependencyHtmlRows -join "`n"))
  $html = $html.Replace('{{TOTAL_ROWS}}', [string]$totalRows)
  $html = $html.Replace('{{MODE_SPECIFIC_COLUMNS}}', [string]$modeSpecificColumns)
  $html = $html.Replace('{{TABLE_ROWS}}', [string]($htmlRows -join "`n"))

  if($PSVersionTable.PSVersion.Major -ge 7){
    $html | Out-File -FilePath $outHtml -Encoding utf8NoBOM
  } else {
    [System.IO.File]::WriteAllText($outHtml, $html, (New-Object System.Text.UTF8Encoding($false)))
  }

  if ($Mode -eq 'report-only') {
    Start-Process $outHtml
    Write-Output "BROWSER_OPENED=true"
    Write-Output "BROWSER_OPEN_HINT=Report opened automatically because Mode=report-only"
  } else {
    Write-Output "BROWSER_OPENED=false"
    Write-Output "BROWSER_OPEN_HINT=HTML generated, but auto-open is only enabled for Mode=report-only"
  }
  Write-Output "HTML_GENERATED=true"
} else {
  Write-Output "BROWSER_OPENED=false"
  Write-Output "BROWSER_OPEN_HINT=No HTML generated during extraction-only mode; run with -Mode report-only after AI review"
  Write-Output "HTML_GENERATED=false"
}

Write-Output "ROOTS=$($resolvedRoots -join ';')"
Write-Output "REPORT_ROOTS=$($reportRoots -join ';')"
Write-Output "REPORT_ROOT_SOURCE=$reportRootSource"
Write-Output "OUTPUT_DIR=$resolvedOutputDir"
Write-Output "CSV_PATH=$outCsv"
Write-Output "UNRESOLVED_CSV_PATH=$outUnresolvedCsv"
Write-Output "HTML_PATH=$outHtml"
Write-Output "CONTEXT_PATH=$outMetadata"
Write-Output "IGNORED_FILE_COUNT=$ignoredFileCount"
if ($ignoredPatternCounts.Count -eq 0) {
  Write-Output "IGNORED_PATTERNS=NONE"
} else {
  $ignoredPatternSummary = @(
    $ignoredPatternCounts.GetEnumerator() |
      Sort-Object Name |
      ForEach-Object { "$($_.Name):$($_.Value)" }
  ) -join ';'
  Write-Output "IGNORED_PATTERNS=$ignoredPatternSummary"
}
