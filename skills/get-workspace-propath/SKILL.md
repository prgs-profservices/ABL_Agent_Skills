---
name: get-workspace-propath
description: Extract PROPATH from openedge-project.json buildPath configuration.
license: Apache-2.0
allowed-tools: Read, Grep, Glob
compatibility: Cross-platform, OpenEdge project (openedge-project.json)
---

<!--
get-workspace-propath: Extract PROPATH from openedge-project.

Copyright 2026 Progress Software Corporation
SPDX-License-Identifier: Apache-2.0
-->

## Overview

This skill extracts the PROPATH from the workspace's `openedge-project.json` file. The PROPATH is used by OpenEdge to locate source files, compiled code, and libraries at runtime.

## Instructions

### Step 1: Locate openedge-project.json

Search for the `openedge-project.json` file in the workspace root.

### Step 2: Parse buildPath Array

1. Read the `openedge-project.json` file
2. Locate the `buildPath` array element
3. Filter for array elements where `"type"` equals `"propath"`
4. **Preserve the order** - PROPATH order matters in OpenEdge

### Step 3: Extract Path Values

For each filtered element:
1. Extract the `"path"` value
2. Keep them in the order they appear in the JSON file
3. Note: Paths may contain variables like `${DLC}` that need to be resolved

### Step 4: Build PROPATH String

1. Combine all paths into a single string
2. **Windows**: Use semicolon (`;`) as separator
3. **Linux/macOS**: Use colon (`:`) as separator
4. The order must match the order in the JSON file (this is critical for OpenEdge)

### Example

Given this `openedge-project.json`:

```json
{
  "buildPath": [
    {
      "path": "src",
      "type": "source",
      "build": "rcode"
    },
    {
      "type": "propath",
      "path": "rcode"
    },
    {
      "type": "propath",
      "path": "src"
    },
    {
      "type": "propath",
      "path": "${DLC}"
    },
    {
      "type": "propath",
      "path": "C:\\apps\\ADE\\"
    }
  ]
}
```

The resulting PROPATH would be:
- **Windows**: `rcode;src;${DLC};C:\apps\ADE\`
- **Linux**: `rcode:src:${DLC}:/apps/ADE/`

### Step 5: Variable Substitution

PROPATH entries may contain variables that need to be resolved:

1. **Get DLC value**: Use the **determine-oe-params** skill to obtain the actual DLC path
2. **Substitute ${DLC}**: Replace all occurrences of `${DLC}` with the actual DLC path
3. **Substitute ${WORKSPACE}**: Replace with the workspace root path (if present)
4. This substitution is **required** for the PROPATH to work correctly

## Usage Notes

- The PROPATH order is significant - OpenEdge searches directories in the order specified
- Typically `rcode` comes before `src` so compiled code is used instead of source when available
- All variables like `${DLC}` must be expanded to their actual paths before use
- Some paths may be absolute, others relative to the workspace root
