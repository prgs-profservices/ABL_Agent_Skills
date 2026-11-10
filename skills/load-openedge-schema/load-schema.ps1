# Copyright 2026 Progress Software Corporation
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
  Load OpenEdge DB schema (.df) into a DB using OEDF LoadDBSchema via $DLC/bin/progradle.

.EXAMPLE
  .\load-schema.ps1 -SchemaPath .\schema\myDb.df -DbName "db\sports2020\sports2020" -ConnectionParameters "-1" -OnlineChanges

.EXAMPLE
  .\load-schema.ps1 -SchemaPath .\schema -DbName "db\sports2020\sports2020" -PfFile .\db\connect.pf
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [string]$SchemaPath,

  [Parameter(Mandatory=$true)]
  [string]$DbName,

  # Option A: Let script find connection in openedge-project.json (default)
  # Option B: Explicit connection parameters
  [string]$Hostname,
  [string]$Port,
  [string]$Username,
  [SecureString]$Password,

  # Option C: pass connectionParameters string (e.g. "-H localhost -S 8000 -U user -P pass -1")
  [string]$ConnectionParameters,

  # Option D: pass a .pf file containing connection args
  [string]$PfFile,

  # Path to openedge-project.json (defaults to ./openedge-project.json)
  [string]$ProjectJsonPath = "openedge-project.json",

  [switch]$OnlineChanges,

  # OpenEdge installation directory (DLC). If not provided, uses $env:DLC.
  [string]$Dlc,

  # OEDF plugin version. You can pin to whatever your org standardizes on.
  [string]$OedfPluginVersion = "2.3.0"
)

function Fail($msg) {
  Write-Error $msg
  exit 1
}

# ---- Validate DLC / progradle ----
if ([string]::IsNullOrWhiteSpace($Dlc)) {
  $dlc = $env:DLC
  if ([string]::IsNullOrWhiteSpace($dlc)) {
    Fail "DLC parameter not provided and DLC environment variable is not set. Provide -Dlc parameter or set `$env:DLC."
  }
} else {
  $dlc = $Dlc
}

$progradle = Join-Path $dlc "bin/progradle"
# $IsWindows is only available in PowerShell 6+. In PS 5.1, we assume Windows.
$isWindowsOS = if ($null -eq $IsWindows) { $true } else { $IsWindows }

if ($isWindowsOS -and -not (Test-Path $progradle)) {
  # Some installs may have progradle.bat on Windows
  $progradleBat = "$progradle.bat"
  if (Test-Path $progradleBat) { $progradle = $progradleBat } else { Fail "Could not find $progradle or $progradleBat" }
} elseif (-not $isWindowsOS -and -not (Test-Path $progradle)) {
  Fail "Could not find $progradle"
}

# ---- Validate schema path ----
$schemaFull = Resolve-Path -LiteralPath $SchemaPath -ErrorAction SilentlyContinue
if (-not $schemaFull) { Fail "SchemaPath does not exist: $SchemaPath" }
$schemaFull = $schemaFull.Path

# ---- Determine connection parameters ----
$finalConnectionParams = ""
$pfFull = $null

if (-not [string]::IsNullOrWhiteSpace($PfFile)) {
  # Option D: Use .pf file
  $pfFull = Resolve-Path -LiteralPath $PfFile -ErrorAction SilentlyContinue
  if (-not $pfFull) { Fail "PfFile does not exist: $PfFile" }
  $pfFull = $pfFull.Path
}
elseif (-not [string]::IsNullOrWhiteSpace($ConnectionParameters)) {
  # Option C: Use explicit connection parameters string
  $finalConnectionParams = $ConnectionParameters
}
else {
  # Option A or B: Try to find in openedge-project.json, or use explicit params
  $dbConnectionFound = $false

  if (Test-Path $ProjectJsonPath) {
    try {
      $projectJson = Get-Content $ProjectJsonPath -Raw | ConvertFrom-Json

      if ($projectJson.dbConnections) {
        $dbConn = $projectJson.dbConnections | Where-Object { $_.name -eq $DbName }

        if ($dbConn -and $dbConn.connect) {
          Write-Host "Found database '$DbName' in openedge-project.json"
          $finalConnectionParams = $dbConn.connect
          $dbConnectionFound = $true
        }
      }
    }
    catch {
      Write-Host "Warning: Could not parse openedge-project.json: $_"
    }
  }

  if (-not $dbConnectionFound) {
    # Not found in project JSON, build from explicit parameters
    if (-not [string]::IsNullOrWhiteSpace($Hostname) -and -not [string]::IsNullOrWhiteSpace($Port)) {
      Write-Host "Using explicit host/port parameters"
      $finalConnectionParams = "-H $Hostname -S $Port"

      if (-not [string]::IsNullOrWhiteSpace($Username)) {
        $finalConnectionParams += " -U $Username"
      }
      if ($Password) {
        # Convert SecureString to plain text for OpenEdge connection parameters
        $passwordPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
          [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
        )
        $finalConnectionParams += " -P $passwordPlain"
      }

      $finalConnectionParams += " -1"  # Single-user mode flag
    }
    else {
      # No connection info found - treat as file-based database
      Write-Host "No connection parameters found - treating as file-based database"
      $finalConnectionParams = "-1"
    }
  }
}

# ---- Create isolated temp Gradle project ----
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("oedf-loadschema-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempRoot | Out-Null

# We’ll keep Gradle caches inside the temp project to avoid polluting user caches in locked-down CI
$gradleUserHome = Join-Path $tempRoot ".gradle-user-home"
New-Item -ItemType Directory -Path $gradleUserHome | Out-Null

$settingsGradle = @"
rootProject.name = "oedf-loadschema"
"@
# Write without BOM to avoid Gradle parsing errors
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $tempRoot "settings.gradle"), $settingsGradle, $utf8NoBom)

# ---- Build the dbConnection { ... } block ----
# LoadDBSchema expects dbConnection closure matching DBConnection structure (dbName/parameterFile/connectionParameters/etc).
# We'll prefer a parameterFile if provided; else use connectionParameters.
$dbConnLines = @()
$dbConnLines += "dbName = " + ('"' + ($DbName.Replace('\','/')) + '"')

if (-not [string]::IsNullOrWhiteSpace($PfFile)) {
  $dbConnLines += "parameterFile = " + ('"' + ($pfFull.Replace('\','/')) + '"')
} else {
  # Strip "-db <name>" from connectionParameters if present since dbName is specified separately
  $paramsWithoutDb = $finalConnectionParams -replace '^\s*-db\s+\S+\s*', ''

  # NOTE: this is a string passed through to PCT as described in the docs for DBConnection / LoadDBSchema.
  $escaped = $paramsWithoutDb.Replace('\\','\\\\').Replace('"','\\"')
  $dbConnLines += "connectionParameters = " + ('"' + $escaped + '"')
}

$onlineChangesStr = if ($OnlineChanges.IsPresent) { "true" } else { "false" }

# ---- Write build.gradle ----
# We keep it minimal: apply abl-base plugin and define one LoadDBSchema task.
$buildGradle = @"
plugins {
  id "progress.openedge.abl-base" version "$OedfPluginVersion"
}

task loadSchema(type: LoadDBSchema) {
  // Accept a single .df file or a directory. Include pattern keeps it df-only.
  include('**/*.df')
  source("$($schemaFull.Replace('\','/'))")

  onlineChanges = $onlineChangesStr

  dbConnection {
    $($dbConnLines -join "`n    ")
  }
}
"@

# Write without BOM to avoid Gradle parsing errors
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $tempRoot "build.gradle"), $buildGradle, $utf8NoBom)

Write-Host "Temp Gradle project: $tempRoot"
Write-Host "Using progradle: $progradle"
Write-Host "OEDF plugin version: $OedfPluginVersion"
Write-Host "Online changes: $onlineChangesStr"

# ---- Run progradle ----
# Ensure DLC is visible to Gradle/plugin, and isolate GRADLE_USER_HOME.
$env:GRADLE_USER_HOME = $gradleUserHome

# progradle is a wrapper that sets up Gradle/JDK appropriately for OpenEdge.
# -p <dir> runs build in our temp project.
$cmd = @(
  $progradle,
  "-p", $tempRoot,
  "--no-daemon",
  "loadSchema"
)

Write-Host ("Running: " + ($cmd -join " "))
& $cmd[0] $cmd[1..($cmd.Length-1)]
$exitCode = $LASTEXITCODE

# ---- Cleanup ----
try {
  Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
} catch {
  # Non-fatal cleanup failure
}

if ($exitCode -ne 0) {
  Fail "Load schema failed with exit code $exitCode"
}

Write-Host "Schema load complete."
exit 0
