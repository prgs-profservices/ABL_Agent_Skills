# Copyright 2026 Progress Software Corporation
# SPDX-License-Identifier: Apache-2.0

# runtest.ps1 - Execute ABLUnit tests
# Usage: runtest.ps1 <test-file> [startup-params...]

if ($args.Count -lt 1) {
    Write-Error "Usage: runtest.ps1 <test-file> [startup-params...]"
    Write-Error "Example: runtest.ps1 'test/system/test_BaseError.cls' '-pf dbconn.pf -basekey ini'"
    exit 1
}

# Auto-detect and set DLC if not already set
if (-not $env:DLC) {
    Write-Host "DLC not set, attempting to auto-detect from VS Code settings..."

    # Read OpenEdge version from openedge-project.json
    $projectJsonPath = "openedge-project.json"
    if (Test-Path $projectJsonPath) {
        $projectJson = Get-Content $projectJsonPath -Raw | ConvertFrom-Json
        $oeVersion = $projectJson.oeversion

        if ($oeVersion) {
            # Read VS Code settings to find matching runtime
            $settingsPath = "$env:APPDATA\Code\User\settings.json"
            if (Test-Path $settingsPath) {
                $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
                $runtime = $settings.'abl.configuration.runtimes' | Where-Object { $_.name -eq $oeVersion } | Select-Object -First 1

                if ($runtime -and $runtime.path) {
                    $env:DLC = $runtime.path
                    Write-Host "Auto-detected DLC: $env:DLC (version $oeVersion)"
                }
            }
        }
    }

    # If still not found, error out
    if (-not $env:DLC) {
        Write-Error "Could not auto-detect DLC. Please set the DLC environment variable or configure abl.configuration.runtimes in VS Code settings."
        exit 2
    }
}

$testFile = $args[0]
$startupParams = if ($args.Count -gt 1) { $args[1..($args.Count-1)] -join ' ' } else { "" }

# --- Input validation (allowlist; all arguments are untrusted) ---
# The final command runs via cmd.exe /s /c, so unvalidated tokens could inject commands.

# Test file: ABL test extension and allowlisted path characters only.
if ([System.IO.Path]::GetExtension($testFile).ToLowerInvariant() -notin @('.p', '.w', '.cls')) {
    Write-Error "Test file must be .p, .w or .cls. Got: $testFile"
    exit 1
}
if ($testFile -notmatch '^[A-Za-z0-9_.\\/-]+$') {
    Write-Error "Test file path contains disallowed characters: $testFile"
    exit 1
}

# Startup parameters: every whitespace-separated token must be an option flag (-pf) or a plain value.
# Reject everything else (quotes, redirection, &, |, %, backticks, etc.).
foreach ($token in ($startupParams -split '\s+' | Where-Object { $_ })) {
    if ($token -notmatch '^-[A-Za-z0-9]+$' -and $token -notmatch '^[A-Za-z0-9_.\\/:=,-]+$') {
        Write-Error "Startup parameter token contains disallowed characters: $token"
        exit 1
    }
}

# Locate the ABLUnit extension's core runner
$extensionPattern = "$env:USERPROFILE\.vscode\extensions\kherring.ablunit-test-runner-*\resources\VSCodeTestRunner\ABLUnitCore.p"
$ablunitCorePath = Get-ChildItem -Path $extensionPattern -ErrorAction SilentlyContinue |
    Sort-Object -Property FullName -Descending |
    Select-Object -First 1 -ExpandProperty FullName

if (-not $ablunitCorePath -or -not (Test-Path $ablunitCorePath)) {
    Write-Error "ABLUnit extension not found. Please install the 'kherring.ablunit-test-runner' extension."
    Write-Error "Looking for: $extensionPattern"
    exit 3
}

Write-Host "Using ABLUnit Core: $ablunitCorePath"

# Extract PROPATH from openedge-project.json
$projectJsonPath = "openedge-project.json"
$propath = ""
if (Test-Path $projectJsonPath) {
    $projectJson = Get-Content $projectJsonPath -Raw | ConvertFrom-Json
    if ($projectJson.buildPath) {
        $propathEntries = @()
        foreach ($entry in $projectJson.buildPath) {
            if ($entry.path) {
                $path = $entry.path
                # Replace ${DLC} with actual DLC value
                $path = $path -replace '\$\{DLC\}', $env:DLC
                $propathEntries += $path
            }
        }
        if ($propathEntries.Count -gt 0) {
            $propath = $propathEntries -join ";"
        }
    }
}

if ($propath) {
    # Add the ABLUnit extension's resources directory to PROPATH
    $ablunitResourcesDir = Split-Path -Parent $ablunitCorePath
    $env:PROPATH = "$ablunitResourcesDir;$propath"
    Write-Host "Set PROPATH: $env:PROPATH"
} else {
    Write-Warning "Could not extract PROPATH from openedge-project.json"
}

# Default temp directory
$tempDir = "ablunit"

# Ensure temp directory exists
if (-not (Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
}

# Create ablunit.json configuration
$ablunitJsonPath = Join-Path $tempDir "ablunit.json"
$ablunitConfig = @{
    '$comment' = "Generated for ABLUnit test run"
    options = @{
        output = @{
            location = (Resolve-Path $tempDir).Path
            filename = "results.xml"
            format = "xml"
            writeJson = $true
            updateFile = "updates.log"
        }
        quitOnEnd = $true
        writeLog = $false
        showErrorMessage = $true
        throwError = $true
    }
    tests = @(
        @{
            test = $testFile
        }
    )
} | ConvertTo-Json -Depth 10

Set-Content -Path $ablunitJsonPath -Value $ablunitConfig -Encoding UTF8
Write-Host "Created ablunit.json at: $ablunitJsonPath"

# Extract database aliases from openedge-project.json if it exists
$aliasesString = ""
$projectJsonPath = "openedge-project.json"
if (Test-Path $projectJsonPath) {
    $projectJson = Get-Content $projectJsonPath -Raw | ConvertFrom-Json
    if ($projectJson.dbConnections) {
        $aliasList = @()
        foreach ($conn in $projectJson.dbConnections) {
            if ($conn.aliases -and $conn.aliases.Count -gt 0) {
                $aliasStr = $conn.name + "," + ($conn.aliases -join ",")
                $aliasList += $aliasStr
            }
        }
        if ($aliasList.Count -gt 0) {
            $aliasesString = $aliasList -join ";"
        }
    }
}

# Build the -param string
$updatesLogPath = Join-Path $tempDir "updates.log"
$paramString = "CFG=$ablunitJsonPath ALIASES=$aliasesString ATTR_ABLUNIT_EVENT_FILE=$updatesLogPath"

# Build the command line
$cmdLine = "$env:DLC\bin\_progres -b -p `"$ablunitCorePath`" -T $tempDir $startupParams -param `"$paramString`""

Write-Host '==== ABLUNIT TEST COMMAND ===='
Write-Host $cmdLine
Write-Host '=============================='

# Execute the command
cmd.exe /s /c $cmdLine

# Check exit code and results
$exitCode = $LASTEXITCODE
$resultsPath = Join-Path $tempDir "results.xml"

if (Test-Path $resultsPath) {
    Write-Host "`nTest execution completed. Results:" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`nNo results file generated. Test execution may have failed." -ForegroundColor Yellow
    Write-Host "Check $tempDir\updates.log for details." -ForegroundColor Yellow
    exit $exitCode
}
