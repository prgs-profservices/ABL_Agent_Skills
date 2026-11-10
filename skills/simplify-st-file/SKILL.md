---
name: simplify-st-file
description: Simplify an OpenEdge production database structure file to minimum definition for creating an empty database.
license: Apache-2.0
allowed-tools: Read, Grep, Glob, Write, Edit
compatibility: Cross-platform, OpenEdge project (openedge-project.json)
---

<!--
simplify-st-file: Simplify an OpenEdge production database structure file to minimum definition for creating an empty database.

Copyright 2026 Progress Software Corporation
SPDX-License-Identifier: Apache-2.0
-->

## Objective

Take a production OpenEdge database structure file (.st) and simplify it down to the minimum definition required to create an empty database with the same basic structure.

## Instructions

When simplifying an OpenEdge database structure file (.st):

### 1. Analyze the file structure

Read the entire .st file and identify:
- Lines starting with `#` - comment/separator lines
- Lines starting with `b` - before-image (backup) files
- Lines starting with `d` - data area extents
- Lines starting with `a` - after-image files

### 2. Simplify data areas

For each data area (identified by a unique area name and number):
- **Keep only the first extent** for each area
- **Remove the directory path** from the filename - keep only the filename itself
- **Remove the `f` flag and size specification** - convert to a variable extent
- **Preserve the area name, number, and parameters** exactly as they appear

**Example transformation:**
- Original: `d "Data Area":7,128;8 /data2/database/proddb/mydb_7.d1 f 1441792`
- Simplified: `d "Data Area":7,128;8 mydb_7.d1`

Multiple extents for the same area should be reduced to just one:
```
# Original (multiple extents):
d "Data Area":7,128;8 /data2/database/proddb/mydb_7.d1 f 1441792
d "Data Area":7,128;8 /data2/database/proddb/mydb_7.d2 f 1441792
d "Data Area":7,128;8 /data2/database/proddb/mydb_7.d3 f 1703936
d "Data Area":7,128;8 /data9/database/proddb/mydb_7.d4 f 1048576
d "Data Area":7,128;8 /data5/database/proddb/mydb_7.d5 f 393216
d "Data Area":7,128;8 /data5/database/proddb/mydb_7.d6 f 1048576
d "Data Area":7,128;8 /data5/database/proddb/mydb_7.d7

# Simplified (single variable extent):
d "Data Area":7,128;8 mydb_7.d1
```

### 3. Simplify before-image files

For before-image lines (starting with `b`):
- Keep only the first before-image file
- Remove the directory path - keep only the filename
- Remove the `f` flag and size specification

**Example:**
- Original: `b /dbbackup/bi/mydb.b1 f 512000`
- Simplified: `b mydb.b1`

### 4. Simplify after-image files

For after-image lines (starting with `a`):
- Keep only the first after-image file
- Remove the directory path - keep only the filename

**Example:**
- Original: `a /dbbackup/ai/mydb.a1`
- Simplified: `a mydb.a1`

### 5. Handle comment lines

- **Remove** empty comment lines (lines with only `#` and no text after it)
- **Keep** comment lines that contain text after the `#`

**Example:**
```
# This comment would be kept
#
# This line above would be removed (empty comment)
```

### 6. Output file naming

- **Do not modify the original file**
- Create a new file with the simplified content
- Name the output file by inserting `.simplified` before the `.st` extension
- Add a comment header as the first line: `# Simplified for empty / dev database creation`

**Example:**
- Original file: `mydb.st`
- Output file: `mydb.simplified.st`
- First line of output: `# Simplified for empty / dev database creation`

## Quality Assurance

- Verify the output .st file is valid OpenEdge structure file syntax
- Ensure all required elements for database creation are preserved
- Confirm the simplified file can be used with `proutil` or database creation tools

## Output

Provide a summary of:
- Number of elements removed
- Number of elements retained
- File size reduction (if applicable)
