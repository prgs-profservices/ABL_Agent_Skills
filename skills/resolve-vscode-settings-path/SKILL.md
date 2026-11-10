---
name: resolve-vscode-settings-path
description: Resolve the absolute path to the user's VS Code settings.json file.
license: Apache-2.0
allowed-tools: Read, Grep, Glob
compatibility: Cross-platform
---

<!--
resolve-vscode-settings-path: Resolve the absolute path to the user's VS Code settings.

Copyright 2026 Progress Software Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Resolve VS Code Settings Path Skill

## Description
Resolves the absolute file system path to the user's VS Code settings.json file based on their operating system.

## Instructions
When you need to access the user's VS Code settings.json file:

1. **Determine the user's operating system** from the environment info provided in the context.

2. **Construct the appropriate path** based on the OS:
   - **Windows**: `%APPDATA%\Code\User\settings.json` (typically `C:\Users\{username}\AppData\Roaming\Code\User\settings.json`)
   - **Linux**: `~/.config/Code/User/settings.json` (typically `/home/{username}/.config/Code/User/settings.json`)
   - **macOS**: `~/Library/Application Support/Code/User/settings.json` (typically `/Users/{username}/Library/Application Support/Code/User/settings.json`)

3. **For VS Code variants**, adjust the path accordingly:
   - **VS Code Insiders**: Replace `Code` with `Code - Insiders`
   - **VSCodium**: Replace `Code` with `VSCodium`
   - **Cursor**: Replace `Code` with `Cursor`
   - **Devin**: Replace `Code` with `Devin`

4. **Use PowerShell environment variables on Windows**:
   - You can resolve `$env:APPDATA` in PowerShell commands
   - Example: `$env:APPDATA\Code\User\settings.json`

5. **Use shell expansion on Unix systems**:
   - You can use `~` or `$HOME` in bash/zsh commands
   - Example: `~/.config/Code/User/settings.json`

## Usage Example

When the user asks you to read or reference VS Code settings:

```
User: "What's my ABL runtime path?"
Assistant: [Resolves path based on OS, reads the file, extracts abl.configuration.runtimes]
```

## Common Settings to Extract

- `abl.configuration.defaultRuntime` - Default OpenEdge runtime version
- `abl.configuration.runtimes` - Array of configured OpenEdge runtimes with name and path
- `templates.author` - Author name for file templates
- OpenEdge DLC paths for various extensions

## Notes

- The settings.json file may not exist if the user has never modified VS Code settings
- The file may be read-only or require elevated permissions in some environments
- Workspace settings (`.vscode/settings.json`) take precedence over user settings for workspace-specific configurations
