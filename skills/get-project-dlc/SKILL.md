---
name: get-project-dlc
description: Determine the OpenEdge installation path (DLC) for the current project.
license: Apache-2.0
allowed-tools: Read, Grep, Glob
compatibility: Cross-platform, OpenEdge project (openedge-project.json)
---

<!--
get-project-dlc: Determine the OpenEdge installation path (DLC) for the current project.

Copyright 2026 Progress Software Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Get Project DLC Path Skill

## Description
Determines the OpenEdge installation path ($DLC or %DLC) for the current project by analyzing the openedge-project.json and VS Code settings.json files.

## Instructions

Follow this sequence to determine the OpenEdge installation path:

### Step 0: Check the DLC environment variable

If the `DLC` environment variable is already set and points to an existing directory, use it and skip the remaining steps. This is the most portable path and works in any IDE/agent, including environments where VS Code settings do not exist.

### Step 1: Check for openedge-project.json

1. Search the workspace root for `openedge-project.json` file
2. If found, read the file and look for the `oeversion` element
3. Note the version value (e.g., "12.8", "12.2", "11.7")

### Step 2: Resolve VS Code Settings Path

1. Use the **resolve-vscode-settings-path** skill to determine the user's settings.json location
2. Read the settings.json file

### Step 3: Find Matching Runtime Configuration

1. In settings.json, locate the `abl.configuration.runtimes` array
2. Search for an array element where `name` matches the `oeversion` from openedge-project.json
3. If found, extract the `path` value - this is the DLC path

Example settings.json structure:
```json
{
    "abl.configuration.runtimes": [
        {
            "name": "12.8",
            "path": "C:\\Progress\\Openedge"
        },
        {
            "name": "12.2",
            "path": "C:\\Progress\\OpenEdge122"
        }
    ]
}
```

### Step 4: Fallback to Default Runtime

If no openedge-project.json exists or it doesn't have an `oeversion` element:

1. Look for `abl.configuration.defaultRuntime` in settings.json
2. Use that version name to find the matching runtime in `abl.configuration.runtimes`
3. Extract the `path` value

### Step 5: Ultimate Fallback

If no configuration is found:
- Default to `C:\Progress\Openedge` on Windows
- Default to `/usr/dlc` on Linux/macOS

### Step 6: Verify the Path

1. Check that the resolved path exists on disk using a directory listing or file system checks
2. If the directory doesn't exist, inform the user and suggest checking their configuration
3. The DLC directory should typically contain subdirectories like `bin`, `gui`, `tty`, etc.

## Usage Example

```
User: "What's my DLC path?"
Assistant: [Reads openedge-project.json, finds oeversion="12.8", reads settings.json,
           finds runtime with name="12.8" and path="C:\Progress\Openedge",
           verifies directory exists]
"Your OpenEdge installation path (DLC) is C:\Progress\Openedge"
```

## Common Use Cases

- Locating the Progress binary executables (e.g., `_progres`, `prowin`)
- Finding ABL include files
- Resolving paths to OpenEdge libraries
- Setting up build configurations
- Running database utilities
- Determining which OpenEdge version is in use

## Related Settings

- `oeversion` - Version identifier in openedge-project.json
- `abl.configuration.runtimes` - Array of runtime configurations
- `abl.configuration.defaultRuntime` - Default runtime name to use
- `speedscript.dlcPath` - Alternative DLC path for SpeedScript projects

## Error Handling

- **openedge-project.json not found**: Fall back to defaultRuntime
- **oeversion missing**: Fall back to defaultRuntime
- **No matching runtime**: Use fallback default path
- **Path doesn't exist**: Warn user and suggest verifying their settings
- **settings.json not found**: Use system default path

## Notes

- The DLC path may contain spaces and should be properly quoted when used in commands
- On Windows, paths typically use backslashes but forward slashes usually work too
