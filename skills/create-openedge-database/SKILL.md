---
name: create-openedge-database
description: Create an empty OpenEdge database from structure and schema definition files.
license: Apache-2.0
allowed-tools: Read, Grep, Glob, Write, Bash, PowerShell
compatibility: Windows, PowerShell 5.1+, OpenEdge DLC
---

<!--
create-openedge-database: Create an empty OpenEdge database from structure and schema definition files.

Copyright 2026 Progress Software Corporation
SPDX-License-Identifier: Apache-2.0
-->

## Objective

Create a new OpenEdge database using structure file (.st) and schema definition file (.df) along with the appropriate OpenEdge utilities.

## Prerequisites

- OpenEdge installation (DLC environment)
- Structure file (.st) defining storage areas and extents
- Optional: Schema definition file (.df) for table definitions

## Instructions

### Input validation (required)

User-supplied database names and filesystem paths are untrusted input. Before using them in any command:

- **Database name**: must match `^[A-Za-z][A-Za-z0-9_-]*$` (no path separators, no shell metacharacters, no whitespace). Reject anything else.
- **Filesystem paths**: normalize with `[System.IO.Path]::GetFullPath()` (or `Resolve-Path` for existing paths), reject any path that still contains `..` traversal segments after normalization, and require absolute paths. Forward slashes are converted to backslashes (Step 4).
- **No string concatenation into command lines**: pass each validated value as a separate command argument (e.g. `prostrct create $dbName $stFile -blocksize 8192` with variables), never interpolate raw user input into a single shell string.
- **Confirmation**: show the exact commands (directory creation, `prostrct create`, `procopy`) and get explicit user confirmation before creating anything on disk.

### Step 1: Determine database location and name

Ask the user where to create the database and what it should be called. Parse their input to determine the target location:

**Case 1: Full path with .db extension**
- Input: `C:\databases\mydatabase.db`
- Action: Create database directly in `C:\databases\` with name `mydatabase.db`
- The parent directory (`C:\databases\`) must exist

**Case 2: Path without .db extension**
- Input: `C:\databases\mydatabase` or `create mydatabase in C:\databases\mydatabase`
- Action: Ensure the directory `C:\databases\mydatabase` exists (create if needed), then create database `mydatabase` inside it
- Result: Database created as `C:\databases\mydatabase\mydatabase.db`

**Important**:
- Database files use `.db` extension
- Always use absolute paths
- Verify parent directory exists before attempting database creation

### Step 2: Check for structure file

Determine if the user has provided a structure file (.st):

- **If provided**: Note the path to the .st file (e.g., `Schema\mydb.simplified.st`)
- **If not provided**: OpenEdge will use default structure (single data area)

The structure file defines:
- Storage areas (Schema Area, Data Area, Index Areas, etc.)
- Extents and their initial sizes
- Before-image and after-image file locations

### Step 3: Determine the OpenEdge installation path (DLC)

Use the **get-project-dlc** skill to determine the OpenEdge installation path. This is required to run OpenEdge utilities like `proutil` and `prostrct`.

The DLC path will be used in subsequent steps to:
- Locate the empty database template (`empty.db`)
- Run database utilities (`proutil`, `prostrct`)
- Apply structure files and load schema definitions

### Step 4: Ensure the database directory exists

Before creating the database, ensure the target directory exists:

```powershell
New-Item -ItemType Directory -Path "C:\databases\mydatabase" -Force
```

**Important:**
- Use PowerShell's `New-Item` with `-Force` to create the directory and any missing parent directories
- If the user specifies forward slashes (e.g., `C:/databases/mydatabase`), convert them to backslashes for Windows
- The `-Force` parameter ensures no error if the directory already exists

**Example path conversions:**
- Input: `C:/databases/test/mydb` → Convert to: `C:\databases\test\mydb`
- Input: `C:\databases\test\mydb` → Use as-is

**Check for existing database:**

Before proceeding, verify that a database with the same name does not already exist in the target location:

```powershell
if (Test-Path "C:\databases\mydatabase\mydatabase.db") {
    Write-Error "Database already exists at C:\databases\mydatabase\mydatabase.db - refusing to overwrite"
    exit
}
```

**Important:**
- Check is case-insensitive (Windows default behavior)
- If database exists, stop immediately and inform the user
- Do not proceed with any database creation steps if the database already exists

### Step 5: Copy and rename the structure file (if provided)

**If a structure file was provided from elsewhere:**

Copy the structure file to the database directory and rename it to match the database name:

```powershell
Copy-Item "path\to\original.st" "C:\databases\mydatabase\mydatabase.st"
```

**Important:**
- The structure file should be renamed to match the database name (e.g., `mydb.db` → `mydb.st`)
- This keeps all database-related files in one location
- If the structure file is already in the database directory with the correct name, no copy is needed

**Example:**
```powershell
Copy-Item "C:\projects\schemas\mydb.simplified.st" "C:\databases\test\mydb.st"
```

### Step 6: Create the database

**If a structure file (.st) was provided:**

First, change to the database directory:

```powershell
Set-Location "C:\databases\mydatabase"
```

Then use the `prostrct create` command to create the database with the specified structure:

```powershell
$DLC/bin/prostrct create dbname dbname.st -blocksize 8192
```

**Parameters:**
- `dbname` - Database name without path or .db extension (e.g., `testdb`)
- `dbname.st` - Structure file in the current directory with same name as database
- `-blocksize 8192` - Sets the database block size to 8KB (8192 bytes)

**Example:**
```powershell
Set-Location "C:\databases\test"
C:\openedge\12.8\bin\prostrct create testdb testdb.st -blocksize 8192
```

**Important:**
- Run the command from inside the target database directory
- This ensures all extents are created in the correct location
- The blocksize must match the empty database template (8192 = empty8, 4096 = empty4)

This command will:
1. Create the database structure at the current location
2. Apply the storage area definitions from the .st file
3. Create all extents, before-image, and after-image files in the current directory

**If no structure file was provided:**

Skip the `prostrct create` step. Change to the database directory and the database will be created with default structure in the next step.

```powershell
Set-Location "C:\databases\mydatabase"
```

### Step 7: Copy the empty database template

**Regardless of whether a structure file was used**, run the `procopy` command to copy the empty database template:

```powershell
$DLC/bin/procopy $DLC/empty8 dbname
```

**Parameters:**
- `$DLC/empty8` - Path to the OpenEdge empty database template (8KB blocksize is preferred unless user specifies otherwise)
- `dbname` - Database name without path or .db extension (matches the name used in prostrct)

**Important:**
- Use `empty8` if blocksize was 8192 (8KB)
- Use `empty4` if blocksize was 4096 (4KB)
- The blocksize must match what was specified in prostrct create

**Example:**
```powershell
C:\openedge\12.8\bin\procopy C:\openedge\12.8\empty8 testdb
```

This command:
- Copies the empty database template to create the actual database files
- If a structure file was used, the storage areas defined earlier are now populated
- Creates the `.db` file and all associated extent files in the current directory

### Step 8: Load the schema definitions (optional)

If the user provided a schema definition file (.df), apply it to the newly created database using the **load-openedge-schema** skill:

- Pass the .df file path as `SchemaPath` and the new database path (without `.db` extension) as `DbName`
- The database is offline at this point, so no host/port parameters are needed (file-based, single-user access)
- If no .df file was provided, skip this step — the database is ready to use with an empty schema

## Quality Assurance

- Verify the database was created successfully
- Confirm all storage areas and extents are created
- Check that schema definitions (if provided) were loaded correctly
- Ensure database can be connected to

## Output

Provide a summary of:
- Database name and location
- Number of storage areas created
- Number of tables loaded (if schema was provided)
- Connection parameters for accessing the database
