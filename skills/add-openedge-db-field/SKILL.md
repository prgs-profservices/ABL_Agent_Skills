---
name: add-openedge-db-field
description: Add a new field to an OpenEdge database table by generating a .df schema file
license: Apache-2.0
allowed-tools: Read, Grep, Glob, Write, Bash, PowerShell
compatibility: Windows, PowerShell 5.1+, OpenEdge DLC
---

<!--
add-openedge-db-field: Add a new field to an OpenEdge database table by generating a.

Copyright 2026 Progress Software Corporation
SPDX-License-Identifier: Apache-2.0
-->

# add-openedge-db-field

Add a new field to an OpenEdge database table by generating a .df schema file.

## When to use this skill

Use this skill when you need to:
- Add a new field to an existing OpenEdge database table
- Generate a schema delta file (.df) that can be loaded into a database
- Create field definitions with proper OpenEdge ABL syntax

## Inputs to collect

- tableName: The name of the table to add the field to
- fieldName: The name of the new field
- dataType: The ABL data type (character, integer, decimal, date, datetime, logical, recid)
- Optional parameters:
  - format: Display format (e.g., "x(30)" for character, "99/99/9999" for date)
  - initial: Initial value (use "?" for date/datetime, "" for character, "0" for numeric, "no" for logical)
  - label: User-friendly field label (defaults to field name with spaces)
  - columnLabel: Abbreviated label for columnar display (only use when label is long and format is short)
  - help: Help text for the field
  - description: Field description/comments (required - will be auto-generated if not provided)
  - mandatory: Whether field is required (true/false)
  - position: Field position in table structure (defaults to 50)
  - order: Display order (defaults to position * 10)
  - maxWidth: Maximum width for the field (auto-calculated based on data type)
  - length: For character fields, 0 = variable length, N = fixed length
  - valexp: Validation expression (OpenEdge 4GL expression)
  - valmsg: Validation message to display if valexp fails
- outputPath: Where to save the generated .df file (defaults to ./schema/<tableName>_add_<fieldName>.df)

## Process

1. **Understand the field purpose and set appropriate FORMAT**
   - For character fields, analyze the expected content and set a reasonable display format:
     - HTML color codes: "x(7)" (e.g., "#ffffff")
     - US state abbreviations: "x(2)"
     - Email addresses: "x(30)" to "x(60)"
     - Phone numbers: "x(20)"
     - Person names: "x(30)" to "x(50)"
     - Company names: "x(50)" to "x(65)"
     - Notes/long text: "x(65)" maximum for display (even if storing up to 32k)
   - **Important**: Cap display format at ~65 characters to avoid breaking tabular displays
   - Set MAX-WIDTH large enough to handle actual field values (can be much larger than format)

2. **Validate inputs**
   - Ensure tableName and fieldName are provided
   - Validate dataType is a supported OpenEdge data type
   - Set appropriate defaults based on dataType if format/initial not provided

3. **Call the PowerShell script** to generate the .df file. `<skill-dir>` means this skill's own folder (the directory containing this SKILL.md); resolve it from where the skill was loaded rather than hardcoding a root like `.github/skills` or `.claude/skills`.

Resolve the script **only** from `<skill-dir>` and fail closed if it is missing — never search PATH or the current directory for a same-named script:

```powershell
$scriptPath = Join-Path "<skill-dir>" "generate-field-df.ps1"
if (-not (Test-Path $scriptPath)) {
    throw "generate-field-df.ps1 not found in the add-openedge-db-field skill directory - refusing to run an unverified script."
}

powershell -NoProfile -File $scriptPath --% `
  -TableName "Customer" `
  -FieldName "Email" `
  -DataType "character" `
  -Format "x(100)" `
  -Initial "" `
  -Label "Email Address" `
  -Help "Customer email address" `
  -OutputPath "schema\customer_add_email.df"
```

4. **Present the generated .df file to the user**
   - Read and show the contents of the generated file
   - Explain what will be added to the database

5. **Wait for user confirmation before applying**
   - Ask the user if they want to apply the schema change
   - Provide the exact command they can run to apply it themselves
   - **DO NOT automatically proceed to load-openedge-schema** without explicit user request

6. **Only if user explicitly requests**: Apply the schema using `load-openedge-schema` skill

## Security & execution requirements

- **Execution capability**: This skill executes the bundled PowerShell script `generate-field-df.ps1` (an unsigned local script); it only generates a local `.df` file.
- **Execution policy**: The invocation does not bypass PowerShell execution policy. The environment must permit local scripts (e.g. `RemoteSigned`, the Windows default). If execution is blocked by policy, stop and ask the user to adjust their policy consciously — never bypass it silently.
- **Safeguards**:
  - The script is resolved only from the canonical skill directory (`<skill-dir>`) and verified with `Test-Path` before execution — missing script = stop.
  - No PATH or current-directory fallback resolution of same-named scripts.
  - The exact command is shown to the user before running it.
- **Schema changes are never applied automatically**: the generated `.df` is only loaded into a database after explicit user confirmation (see step 5 of the Process).

## How it works

The script generates a .df file containing an `ADD FIELD` statement with proper syntax:
- Sets appropriate FORMAT based on data type if not provided
- Sets appropriate INITIAL value based on data type if not provided
- Includes optional attributes like LABEL, HELP, DESCRIPTION if provided
- Includes validation expressions (VALEXP/VALMSG) if provided
- Generates proper syntax for character fields (LENGTH attribute)

## Data Type Defaults

### character
- **Format Guidelines**:
  - Analyze the field's purpose and expected content
  - Use context-appropriate sizes (email: x(30-60), names: x(30-50), states: x(2), etc.)
  - **Never exceed x(65) for display format** to prevent tabular display issues
  - For large text fields (notes, descriptions), use x(65) for format but set MAX-WIDTH appropriately
  - Programmers can override display format in code; keeping it reasonable ensures safe defaults
- Default Format: "x(50)" (if not specified and no context available)
- Initial: ""
- Length: 0 (variable length)
- MAX-WIDTH: This is used when serving out the database via SQL. Calculate based on actual field size requirements.  Convention is to use double the default format size, but display format can sometimes be smaller than expected usage. For example, a Notes field might have a display format of x(65) but a MAX-WIDTH of 500 to allow for longer content without breaking displays.

### integer
- Format: "zzzzzzzzz9" (if not specified)
- Initial: "0"
- MAX-WIDTH: 4

### decimal
- Format: "->>,>>>,>>9.99" (if not specified)
- Initial: "0"
- MAX-WIDTH: 8

### date
- Format: "99/99/9999" (if not specified)
- Initial: ?
- MAX-WIDTH: 4

### datetime
- Format: "99/99/9999 HH:MM:SS" (if not specified)
- Initial: ?
- MAX-WIDTH: 8

### logical
- Format: "yes/no" (if not specified)
- Initial: "no"
- MAX-WIDTH: 1

## Important Notes

### Field Labels
- **LABEL**: Full descriptive label for the field (defaults to field name with spaces)
- **COLUMN-LABEL**: Optional abbreviated label for columnar/tabular display
  - Only include when the full label is long but the display format is short (e.g., yes/no, X(3), >>9)
  - If omitted, COLUMN-LABEL defaults to LABEL (which is preferred in most cases)
  - If both are omitted, both default to the field name
  - Use abbreviated COLUMN-LABEL to conserve horizontal space in tabular displays

### Description
- Always include a DESCRIPTION for every field
- Use context from the user interaction to determine appropriate description
- If not provided, a generic description will be auto-generated

### Other Notes

- The generated .df file only adds the field; it does NOT create indexes
- If you need to add an index on the new field, create a separate .df with ADD INDEX
- Position defaults to next available (script calculates based on typical patterns)
- ORDER defaults to position * 10 to allow for insertions
- After generating the .df, use `load-openedge-schema` skill to apply it to your database
- The .df file can cause errors if the field already exists in the database

## Example

Generate a .df to add an Email field to the Customer table:
```powershell
powershell -NoProfile -File <skill-dir>\generate-field-df.ps1 --% `
  -TableName "Customer" `
  -FieldName "Email" `
  -DataType "character" `
  -Format "x(100)" `
  -Label "Email Address" `
  -Help "Customer email address for communications" `
  -Mandatory:$true
```

This generates `schema\customer_add_email.df` containing:
```
ADD FIELD "Email" OF "Customer" AS character
  FORMAT "x(100)"
  INITIAL ""
  LABEL "Email Address"
  POSITION 50
  MAX-WIDTH 200
  HELP "Customer email address for communications"
  LENGTH 0
  ORDER 500
  MANDATORY
```

## Script integrity

Verify the bundled script(s) before first use: `Get-FileHash <file> -Algorithm SHA256` and compare to the values below. If a hash does not match, stop and review the file before executing. Hashes are regenerated whenever a bundled script changes (see the skills README).

| File | SHA-256 |
|---|---|
| `generate-field-df.ps1` | `A21297E36F3F9381DA49C8076F7C3AAE870A58C5BCB0C39CFE49179E3AD55EDC` |
