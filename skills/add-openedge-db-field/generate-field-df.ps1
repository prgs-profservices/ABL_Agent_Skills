# Copyright 2026 Progress Software Corporation
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
  Generate an OpenEdge .df schema file to add a field to a table.

.EXAMPLE
  .\generate-field-df.ps1 -TableName "Customer" -FieldName "Email" -DataType "character" -Format "x(100)" -Label "Email Address"

.EXAMPLE
  .\generate-field-df.ps1 -TableName "Order" -FieldName "ShippedDate" -DataType "date" -Mandatory
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [string]$TableName,

  [Parameter(Mandatory=$true)]
  [string]$FieldName,

  [Parameter(Mandatory=$true)]
  [ValidateSet("character", "integer", "decimal", "date", "datetime", "datetime-tz", "logical", "int64", "recid")]
  [string]$DataType,

  # Field attributes
  [string]$Format,
  [string]$Initial,
  [string]$Label,
  [string]$ColumnLabel,  # Optional abbreviated label for columnar display
  [string]$Help,
  [string]$Description,
  [int]$Position = 50,  # Default position
  [int]$Order = 0,      # 0 = auto-calculate as Position * 10
  [int]$MaxWidth = 0,   # 0 = auto-calculate based on data type
  [int]$Length = -1,    # -1 = auto, 0 = variable (for character), N = fixed length
  [string]$Valexp,
  [string]$Valmsg,
  [switch]$Mandatory,

  # Output
  [string]$OutputPath
)

function Get-DefaultFormat($type) {
  switch ($type) {
    "character" { return "x(50)" }
    "integer" { return "zzzzzzzzz9" }
    "int64" { return "->,>>>,>>>,>>9" }
    "decimal" { return "->>,>>>,>>9.99" }
    "date" { return "99/99/9999" }
    "datetime" { return "99/99/9999 HH:MM:SS" }
    "datetime-tz" { return "99/99/9999 HH:MM:SS+HH:MM" }
    "logical" { return "yes/no" }
    "recid" { return "zzzzzzzzz9" }
    default { return "" }
  }
}

function Get-DefaultInitial($type) {
  switch ($type) {
    "character" { return '""' }
    "integer" { return '"0"' }
    "int64" { return '"0"' }
    "decimal" { return '"0"' }
    "date" { return "?" }
    "datetime" { return "?" }
    "datetime-tz" { return "?" }
    "logical" { return '"no"' }
    "recid" { return "?" }
    default { return '""' }
  }
}

function Get-DefaultMaxWidth($type, $fmt) {
  switch ($type) {
    "character" {
      # Try to extract length from format like "x(100)"
      if ($fmt -match 'x\((\d+)\)') {
        return [int]$Matches[1] * 2
      }
      return 100
    }
    "integer" { return 4 }
    "int64" { return 8 }
    "decimal" { return 8 }
    "date" { return 4 }
    "datetime" { return 8 }
    "datetime-tz" { return 12 }
    "logical" { return 1 }
    "recid" { return 8 }
    default { return 4 }
  }
}

function Get-DefaultLength($type) {
  if ($type -eq "character") {
    return 0  # Variable length
  }
  return -1  # Not applicable for non-character types
}

# ---- Apply defaults ----
if ([string]::IsNullOrWhiteSpace($Format)) {
  $Format = Get-DefaultFormat $DataType
}

if ([string]::IsNullOrWhiteSpace($Initial)) {
  $Initial = Get-DefaultInitial $DataType
}

if ($Order -eq 0) {
  $Order = $Position * 10
}

if ($MaxWidth -eq 0) {
  $MaxWidth = Get-DefaultMaxWidth $DataType $Format
}

if ($Length -eq -1 -and $DataType -eq "character") {
  $Length = Get-DefaultLength $DataType
}

if ([string]::IsNullOrWhiteSpace($Label)) {
  # Generate label from field name (split camelCase/PascalCase)
  $Label = $FieldName -creplace '([a-z])([A-Z])', '$1 $2'
}

if ([string]::IsNullOrWhiteSpace($Description)) {
  # Generate description from field name and table name
  $Description = "The $Label field for $TableName"
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = "schema\${TableName}_add_${FieldName}.df"
}

# ---- Build the .df content ----
$dfLines = @()
$dfLines += "ADD FIELD `"$FieldName`" OF `"$TableName`" AS $DataType "
$dfLines += "  FORMAT `"$Format`""
$dfLines += "  INITIAL $Initial"
$dfLines += "  DESCRIPTION `"$Description`""
$dfLines += "  LABEL `"$Label`""
$dfLines += "  POSITION $Position"
$dfLines += "  MAX-WIDTH $MaxWidth"

# Add COLUMN-LABEL only if explicitly provided (typically for abbreviated labels)
if (-not [string]::IsNullOrWhiteSpace($ColumnLabel)) {
  $dfLines += "  COLUMN-LABEL `"$ColumnLabel`""
}

if (-not [string]::IsNullOrWhiteSpace($Valexp)) {
  $dfLines += "  VALEXP `"$Valexp`""
}

if (-not [string]::IsNullOrWhiteSpace($Valmsg)) {
  $dfLines += "  VALMSG `"$Valmsg`""
}

if (-not [string]::IsNullOrWhiteSpace($Help)) {
  $dfLines += "  HELP `"$Help`""
}

# Add LENGTH for character fields
if ($DataType -eq "character" -and $Length -ge 0) {
  $dfLines += "  LENGTH $Length"
}

$dfLines += "  ORDER $Order"

if ($Mandatory.IsPresent) {
  $dfLines += "  MANDATORY"
}

$dfLines += ""  # Blank line at end

# Add .df footer
$dfLines += "."
$dfLines += "PSC"
$dfLines += "cpstream=UTF-8"
$dfLines += "."
$dfLines += ""  # Final blank line

# ---- Write the file ----
$outputDir = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path $outputDir)) {
  New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Write with UTF-8 encoding without BOM
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines((Resolve-Path -Path . | Join-Path -ChildPath $OutputPath), $dfLines, $utf8NoBom)

Write-Host "Generated schema file: $OutputPath"
Write-Host ""
Write-Host "Contents:"
Write-Host "========================================="
$dfLines | ForEach-Object { Write-Host $_ }
Write-Host "========================================="
Write-Host ""
Write-Host "To apply this schema to your database, use the 'load-openedge-schema' skill:"
Write-Host "  load-openedge-schema -SchemaPath `"$OutputPath`" -DbName `"<your-db-name>`""

exit 0
