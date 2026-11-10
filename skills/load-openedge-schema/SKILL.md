---
name: load-openedge-schema
description: Load OpenEdge database schema from .df files using OpenEdge DevOps Framework (OEDF) LoadDBSchema task
license: Apache-2.0
allowed-tools: Read, Grep, Glob, Write, Bash, PowerShell
compatibility: Windows, PowerShell 5.1+, OpenEdge DLC
---

<!--
load-openedge-schema: Load OpenEdge database schema from.

Copyright 2026 Progress Software Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Load OpenEdge DB Schema (OEDF LoadDBSchema)

Use this skill to apply one or more .df schema files to an OpenEdge database using
OpenEdge DevOps Framework (progress.openedge.abl-base) task type LoadDBSchema.

## Inputs to collect
- schemaPath: Path to a .df file OR a folder containing .df files
- dbName: Database logical name (e.g., "sports2020") OR full path to .db file
- Optional: host and port (if database is online and not in openedge-project.json)
- Optional: username and password (if required)
- Optional: pfFile (for complex connection parameters)
- onlineChanges: true/false (default false)

## Process

1. **Determine DLC path** using the **get-project-dlc** skill
   - This reads openedge-project.json and VS Code settings to find the correct OpenEdge installation
   - Store the result in a variable (e.g., `$dlcPath`)

2. **Call the PowerShell script** with the DLC path and database name. `<skill-dir>` means this skill's own folder (the directory containing this SKILL.md); resolve it from where the skill was loaded rather than hardcoding a root like `.github/skills` or `.claude/skills`:

### Simple case (database in openedge-project.json):
```powershell
powershell -NoProfile -File <skill-dir>\load-schema.ps1 --% `
  -SchemaPath "<path>" `
  -DbName "sports2020" `
  -Dlc "<dlc path from step 1>"
```

### With explicit host/port (database online but not in config):
```powershell
powershell -NoProfile -File <skill-dir>\load-schema.ps1 --% `
  -SchemaPath "<path>" `
  -DbName "sports2020" `
  -Host "localhost" `
  -Port "9200" `
  -Dlc "<dlc path from step 1>" `
  -OnlineChanges:$true
```

### With connection parameters file:
```powershell
powershell -NoProfile -File <skill-dir>\load-schema.ps1 --% `
  -SchemaPath "<path>" `
  -DbName "sports2020" `
  -PfFile "connect.pf" `
  -Dlc "<dlc path from step 1>"
```

## How it works

1. The script looks for `openedge-project.json` in the workspace root
2. If found, it checks the `dbConnections` array for a matching database name
3. If matched, it extracts the connection parameters from the `connect` string
4. If not matched, it uses explicit parameters (-Host, -Port) if provided
5. If no host/port, it treats DbName as a file path
6. Creates a temporary Gradle project and runs the OEDF LoadDBSchema task

Notes:
- The script requires the OpenEdge DLC directory path (passed via -Dlc parameter)
- This script creates an isolated temporary Gradle project and runs progradle from the specified DLC

## Security & execution requirements

- **Execution capability**: This skill executes the bundled PowerShell script `load-schema.ps1` (an unsigned local script), which runs the OEDF LoadDBSchema Gradle task to apply `.df` schema files to a database.
- **Execution policy**: The invocation does not bypass PowerShell execution policy. The environment must permit local scripts (e.g. `RemoteSigned`, the Windows default). If execution is blocked by policy, stop and ask the user to adjust their policy consciously — never bypass it silently.
- **Schema changes are never applied automatically**: loading a `.df` modifies the database schema (adds/drops/alters tables and fields). Show the user the `.df` file path and target database before executing, and require explicit confirmation.
- **Untrusted input**: `.df` file paths, database names, host/port, and `.pf` files come from the user or `openedge-project.json`. Validate with an allowlist (paths: `^[A-Za-z0-9_.\\/-]+$`; host: `^[A-Za-z0-9.-]+$`; port: integer 1–65535) before passing to the script. Reject values containing shell metacharacters.
- **Credentials**: prefer a `.pf` parameter file over passing `-U`/`-P` credentials on the command line, so credentials do not appear in process listings or logs.

## Script integrity

Verify the bundled script(s) before first use: `Get-FileHash <file> -Algorithm SHA256` and compare to the values below. If a hash does not match, stop and review the file before executing. Hashes are regenerated whenever a bundled script changes (see the skills README).

| File | SHA-256 |
|---|---|
| `load-schema.ps1` | `8498B117BA23343D893C385D791B5D338EFF94FE301B26358AACE5A22004499A` |
