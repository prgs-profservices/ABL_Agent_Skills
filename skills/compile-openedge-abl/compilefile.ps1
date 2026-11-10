# Copyright 2026 Progress Software Corporation
# SPDX-License-Identifier: Apache-2.0

# Check if DLC environment variable is set
if (-not $env:DLC) {
  Write-Error "DLC environment variable is not set. Please set it to your OpenEdge installation directory."
  exit 1
}

if ($args.Count -lt 1) {
  Write-Error "Usage: compilefile.ps1 <FirstParam> [args for mbpro...]"
  exit 2
}

$first = $args[0]
$rest  = if ($args.Count -gt 1) { $args[1..($args.Count-1)] } else { @() }

# --- Input validation (allowlist; all arguments are untrusted) ---
# The final command runs via cmd.exe /s /c, so unvalidated tokens could inject commands.

# Source file: must exist, have an ABL extension, and contain only allowlisted path characters.
if (-not (Test-Path $first -PathType Leaf)) {
  Write-Error "Source file not found: $first"
  exit 2
}
if ([System.IO.Path]::GetExtension($first).ToLowerInvariant() -notin @('.p', '.w', '.i', '.cls')) {
  Write-Error "Source file must be .p, .w, .i or .cls. Got: $first"
  exit 2
}
if ($first -notmatch '^[A-Za-z0-9_.\\/-]+$') {
  Write-Error "Source file path contains disallowed characters: $first"
  exit 2
}

# Startup parameters: split each argument into whitespace-separated tokens; every token must be
# an option flag (-basekey) or a plain value. Reject everything else (quotes, redirection, &, |, %, etc.).
foreach ($arg in $rest) {
  foreach ($token in ($arg -split '\s+' | Where-Object { $_ })) {
    if ($token -notmatch '^-[A-Za-z0-9]+$' -and $token -notmatch '^[A-Za-z0-9_.\\/:=,-]+$') {
      Write-Error "Startup parameter token contains disallowed characters: $token"
      exit 2
    }
  }
}

# Build a raw tail string EXACTLY as tokens joined by spaces
# (this preserves order; and since you used --%, tokens are already literal)
$restLine = $rest -join ' '

# Get the directory where this script is located
$scriptPath = Join-Path $PSScriptRoot "compilefile.p"

# Build a single command line for cmd.exe to execute
$cmdLine = $env:DLC + "\bin\_progres -b -p ""$scriptPath"" $restLine -param $first"

Write-Host '==== COMMAND LINE TO EXECUTE (via cmd.exe) ===='
Write-Host $cmdLine
Write-Host '================================================'

# Execute via cmd so mbpro.bat sees one cohesive command line
cmd.exe /s /c $cmdLine
