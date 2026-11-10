# Copyright 2026 Progress Software Corporation
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
  Generate an OpenEdge .df schema file to drop a field from a table.

.EXAMPLE
  .\generate-drop-field-df.ps1 -TableName "Customer" -FieldName "OldField"

.EXAMPLE
  .\generate-drop-field-df.ps1 -TableName "Order" -FieldName "ObsoleteDate" -OutputPath "schema\order_cleanup.df"
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [string]$TableName,

  [Parameter(Mandatory=$true)]
  [string]$FieldName,

  # Output
  [string]$OutputPath
)

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = "schema\${TableName}_drop_${FieldName}.df"
}

# ---- Build the .df content ----
$dfLines = @()
$dfLines += "DROP FIELD `"$FieldName`" OF `"$TableName`""
$dfLines += ""  # Blank line

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
Write-Host "WARNING: This is a DESTRUCTIVE operation!"
Write-Host "  - All data in field '$FieldName' will be permanently deleted"
Write-Host "  - Any indexes referencing this field will be dropped"
Write-Host "  - This operation cannot be easily undone"
Write-Host "  - BACKUP YOUR DATABASE before applying this schema"
Write-Host ""
Write-Host "To apply this schema to your database, use the 'load-openedge-schema' skill:"
Write-Host "  load-openedge-schema -SchemaPath `"$OutputPath`" -DbName `"<your-db-name>`" -OnlineChanges"

exit 0
