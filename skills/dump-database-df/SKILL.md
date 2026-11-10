---
name: dump-database-df
description: To create a database definitions (.df) file (a.k.a. "dump a schema"for a given database.
license: Apache-2.0
allowed-tools: Read, Grep, Glob, Write, Bash, PowerShell
compatibility: Windows, PowerShell 5.1+, OpenEdge DLC
---

<!--
dump-database-df: To create a database definitions (.

Copyright 2026 Progress Software Corporation
SPDX-License-Identifier: Apache-2.0
-->

## Objective

Export OpenEdge database schema to a .df (database definitions) file for:
- Environment setup and database recreation
- IDE code completion (OpenEdge ABL extension requires .df files)
- Schema analysis and optimization recommendations
- Version control of database structure

## Prerequisites

- OpenEdge installation (DLC environment)
- Database access (connected or file path)
- Write permissions for output location

## Efficiency Notes

**This skill supports efficient batch execution for multiple databases.**

**Cache between runs in same session:**
- $DLC path (determine once, reuse for all)
- openedge-project.json data (read once)
- Schema output location pattern (e.g., "Schema/" folder)
- Editor command from detect-editor skill (code/devin)

**Execute each time:**
- The dump command itself (schema may have changed)
- File verification and opening in editor

**Communication:** On 2nd+ run, use concise acknowledgment: "Using cached $DLC, dumping ffwpasoe..." instead of verbose step-by-step narration.

## Instructions

### Input validation (required)

Database paths, connection parameters, `.pf` files, hosts/ports, and output paths are untrusted input (from the user or from `openedge-project.json`). Before building any command:

- **Host**: must match a hostname/IP pattern (`^[A-Za-z0-9.-]+$`). Reject anything else.
- **Port**: must be an integer in range 1–65535.
- **Database path / name**: normalize with `[System.IO.Path]::GetFullPath()`; reject `..` traversal segments and values containing `;`, `&`, `|`, or backtick.
- **.pf file**: verify with `Test-Path` before use; resolve to an absolute path.
- **Output path (.df)**: normalize to an absolute path; reject `..` traversal; create parent dirs only after validation.
- **Structured argument passing**: build the `_progres.exe` invocation as an argument array, never a single concatenated string:

```powershell
$progArgs = @('-b', '-db', $dbPath, '-H', $dbHost, '-S', $dbPort, '-p', 'prodict/batch_dump_df.p', '-param', "FILE-NAME=ALL;DF-FILE-NAME=$outputPath")
& "$env:DLC\bin\_progres.exe" $progArgs
```

- Quote/escape each argument individually; show the final command to the user before executing.

### Step 1: Identify Database Connection

User input can be:
- **Logical name** (e.g., "sports2020") → Look up in openedge-project.json dbConnections
- **File path** (e.g., "C:\databases\mydb.db") → Connect directly to file
- **Connection parameters** → Use provided host/port or .pf file

From openedge-project.json extract: `-db`, `-H`, `-S` parameters from the `connect` string.

### Step 2: Determine Output Path

Priority order:
1. **User explicit path** → Use it (create dirs if needed)
2. **schemaFile in openedge-project.json** → Use this (safe to overwrite)
3. **Existing Schema/ folder** → Place file there
4. **Fallback** → Workspace root

Filename: `<database-name>.df` (extract name without path/extension)

### Step 3: Get DLC Path

**Only if not already cached in this session.**

Use **get-project-dlc** skill to determine OpenEdge installation path. Cache result for reuse.

### Step 4: Execute Dump Command

**Basic command:**
```powershell
$env:DLC = "<DLC from Step 3>"
& "$env:DLC\bin\_progres.exe" -b <connection-params> -p prodict/batch_dump_df.p -param "FILE-NAME=ALL;DF-FILE-NAME=<output-path>"
```

**Connection parameters by type:**

**Networked database:** `-db <name> -H <host> -S <port>`
```powershell
& "$env:DLC\bin\_progres.exe" -b -db sports2020 -H localhost -S 9200 -p prodict/batch_dump_df.p -param "FILE-NAME=ALL;DF-FILE-NAME=sports2020.df"
```

**File-based database:** Check for `.lk` file to determine single/multi-user mode
```powershell
$lockFile = "C:\databases\cars\cars.lk"
$singleUser = if (!(Test-Path $lockFile)) { "-1" } else { "" }
& "$env:DLC\bin\_progres.exe" -b $singleUser -db "C:\databases\cars\cars" -p prodict/batch_dump_df.p -param "FILE-NAME=ALL;DF-FILE-NAME=C:\databases\cars\cars.df"
```
- **No .lk file** → Add `-1` flag (single-user mode)
- **.lk file exists** → Omit `-1` flag (multi-user mode)

**With .pf file:** `-pf <file>`
```powershell
& "$env:DLC\bin\_progres.exe" -b -pf dbconn.pf -p prodict/batch_dump_df.p -param "FILE-NAME=ALL;DF-FILE-NAME=output.df"
```

**Key parameters:**
- `-b` = Batch mode (no GUI)
- `-1` = Single-user mode (for file-based DBs without server)
- `FILE-NAME=ALL` = Export all tables
- `DF-FILE-NAME` = Output file path

### Step 5: Verify Output

```powershell
Get-Item "<output-file>" | Select-Object Name, Length, LastWriteTime
```

Check: File exists, non-zero size, recent timestamp.

Expected format: ADD SEQUENCE, ADD TABLE, ADD FIELD, ADD INDEX statements.

### Step 6: Open File(s) in Editor

**Open ALL .df files created in this invocation** (not just the last one).

Use the **detect-editor** skill to determine the correct editor command (`code` or `devin`). Cache the result for subsequent file operations in this session.

```powershell
& $editor "file1.df" "file2.df"  # List all files created
```

## Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| 1423: "no server for database" | File-based DB without server, missing `-1` flag | Check for `.lk` file; if absent, add `-1` flag |
| Database not found | Invalid path | Verify `Test-Path "<path>.db"` |
| Permission denied | Insufficient permissions | Check read (DB) and write (output) permissions |
| Empty .df file | Connection interrupted or no tables | Re-run dump, verify DB integrity |

## Output Format

**Single database:** "Dumped sports2020 (60KB) to sports2020.df"

**Multiple databases:** "Dumped 3 databases: sports2020 (60KB), ffwpasoe (145KB), testdb (32KB). All files in Schema/"

**Subsequent runs:** "Using cached $DLC, dumping ffwpasoe..."
