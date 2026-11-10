---
name: drop-openedge-db-field
description: Remove a field from an OpenEdge database table by generating a .df schema file
license: Apache-2.0
allowed-tools: Read, Grep, Glob, Write, Bash, PowerShell
compatibility: Windows, PowerShell 5.1+, OpenEdge DLC
---

<!--
drop-openedge-db-field: Remove a field from an OpenEdge database table by generating a.

Copyright 2026 Progress Software Corporation
SPDX-License-Identifier: Apache-2.0
-->

# drop-openedge-db-field

Remove a field from an OpenEdge database table by generating a .df schema file.

## When to use this skill

Use this skill when you need to:
- Remove an existing field from an OpenEdge database table
- Generate a schema delta file (.df) that drops a field when loaded
- Clean up obsolete or unused fields

## Inputs to collect

- tableName: The name of the table containing the field to drop
- fieldName: The name of the field to remove
- outputPath: Where to save the generated .df file (defaults to ./schema/<tableName>_drop_<fieldName>.df)

## Process

**CRITICAL: This is a DESTRUCTIVE operation. NEVER apply the schema without explicit user confirmation after review.**

1. **Validate inputs**
   - Ensure tableName and fieldName are provided
   - Warn the user this is a destructive operation

2. **Generate the .df file** using the PowerShell script. `<skill-dir>` means this skill's own folder (the directory containing this SKILL.md); resolve it from where the skill was loaded rather than hardcoding a root like `.github/skills` or `.claude/skills`:

```powershell
powershell -NoProfile -File <skill-dir>\generate-drop-field-df.ps1 --% `
  -TableName "Customer" `
  -FieldName "OldField" `
  -OutputPath "schema\customer_drop_oldfield.df"
```

3. **Present the generated .df file to the user**
   - Read and show the contents of the generated file
   - Explain what will happen when applied
   - Warn about data loss and irreversibility

4. **STOP and wait for explicit user confirmation**
   - Ask the user if they want to apply the schema change
   - Provide the exact command they can run to apply it themselves
   - **DO NOT automatically proceed to load-openedge-schema** without explicit user request

5. **Only if user explicitly requests**: Apply the schema using `load-openedge-schema` skill
   - User must have reviewed the .df file first
   - User must have explicitly confirmed they want to proceed

## How it works

The script generates a .df file containing a `DROP FIELD` statement:
- Simple one-line statement: `DROP FIELD "FieldName" OF "TableName"`
- Includes proper .df footer with codepage information

## Important Notes

- **DESTRUCTIVE OPERATION**: Dropping a field permanently deletes all data in that field
- **No undo**: Once applied, the field and its data are gone
- **Dependencies**: Dropping a field may break:
  - Application code that references the field
  - Indexes that include the field (may need separate DROP INDEX statements)
  - Validation expressions in other fields that reference this field
  - Database triggers that access the field
- **Backup recommended**: Always backup the database before dropping fields
- **Index cleanup**: If the field is part of any indexes, those indexes must be dropped first or will be automatically dropped
- The .df file only drops the field; any associated indexes referencing this field will also be removed
- After generating the .df, use `load-openedge-schema` skill to apply it to your database

## Example

Generate a .df to drop the Email field from the Customer table:
```powershell
powershell -NoProfile -File <skill-dir>\generate-drop-field-df.ps1 --% `
  -TableName "Customer" `
  -FieldName "Email"
```

This generates `schema\customer_drop_email.df` containing:
```
DROP FIELD "Email" OF "Customer"

.
PSC
cpstream=UTF-8
.
```

## Security & execution requirements

- **Execution capability**: This skill executes the bundled PowerShell script `generate-drop-field-df.ps1` (an unsigned local script); it only generates a local `.df` file.
- **Execution policy**: The invocation does not bypass PowerShell execution policy. The environment must permit local scripts (e.g. `RemoteSigned`, the Windows default). If execution is blocked by policy, stop and ask the user to adjust their policy consciously — never bypass it silently.
- **Safeguards**: the script is resolved only from the canonical skill directory (`<skill-dir>`) and verified with `Test-Path` before execution — missing script = stop. No PATH or current-directory fallback.
- **Schema changes are never applied automatically**: the generated `.df` is only loaded into a database after explicit user confirmation via the `load-openedge-schema` skill.

## Script integrity

Verify the bundled script(s) before first use: `Get-FileHash <file> -Algorithm SHA256` and compare to the values below. If a hash does not match, stop and review the file before executing. Hashes are regenerated whenever a bundled script changes (see the skills README).

| File | SHA-256 |
|---|---|
| `generate-drop-field-df.ps1` | `F3876DA5DC2580D2D635240D94E02C0C58478DF5EE1D60BE05CC462350B70170` |
