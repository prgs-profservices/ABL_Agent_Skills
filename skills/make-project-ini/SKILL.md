---
name: make-project-ini
description: Create a .ini file to set the PROPATH when running an OpenEdge program.
license: Apache-2.0
allowed-tools: Read, Grep, Glob, Write, Edit
compatibility: Cross-platform, OpenEdge project (openedge-project.json)
---

<!--
make-project-ini: Create a.

Copyright 2026 Progress Software Corporation
SPDX-License-Identifier: Apache-2.0
-->

## Objective

Generate an .ini file that configures the PROPATH for OpenEdge program execution on Windows.

## Prerequisites

- The `get-workspace-propath` skill to extract PROPATH from workspace configuration
- The `determine-oe-params` skill to determine the DLC (OpenEdge installation directory)

## Steps

1. **Check if .ini file needs regeneration**
   - Ensure the workspace has a `.vscode` directory (create it if it doesn't exist)
   - Look for `.vscode/quickrun.ini` file
   - **When called as a prerequisite by another skill**: If `quickrun.ini` exists and its modification date is newer than `openedge-project.json` in the workspace root, skip regeneration and stop here
   - **When user explicitly requests regeneration**: Always proceed to generate/update the file regardless of dates
   - Otherwise, proceed to generate/update the file

2. **Gather required information**
   - Use the `get-workspace-propath` skill to determine the PROPATH entries
   - Use the `determine-oe-params` skill to determine the DLC directory

3. **Generate the quickrun.ini file**
   - Copy `initemplate.ini` from the skill directory to `.vscode/quickrun.ini`
   - Set the `DLC` value in both `[Startup]` and `[WinChar Startup]` sections
   - Set the `PROPATH` value in both sections:
     - **Always start with `.`** (current directory)
     - Follow with the PROPATH entries from `get-workspace-propath`
     - Separate all entries with commas
     - Example: `PROPATH=.,src,lib,rcode`


## Common Issues

- If `openedge-project.json` doesn't exist or can't be read, the skills may fail
- Ensure the workspace root is correctly identified
- PROPATH entries should be workspace-relative paths

## Examples

**Example quickrun.ini output:**
```ini
[Startup]
DLC=C:\Progress\OpenEdge
PROPATH=.,src,lib,rcode

[WinChar Startup]
DLC=C:\Progress\OpenEdge
PROPATH=.,src,lib,rcode
```
