---
name: detect-editor
description: Detect whether the user is running VS Code or Devin to open files in the correct editor.
license: Apache-2.0
allowed-tools: Read, Grep, Glob, Write, Bash, PowerShell
compatibility: Windows, PowerShell 5.1+, OpenEdge DLC
---

<!--
detect-editor: Detect whether the user is running VS Code or Devin to open files in the correct editor.

Copyright 2026 Progress Software Corporation
SPDX-License-Identifier: Apache-2.0
-->

## Objective

Determine which code editor the user is running (VS Code or Devin) to open files in the appropriate editor.

## Prerequisites

None - this skill uses environment variables and command availability checks.

## Efficiency Notes

**Cache the result within the same conversation session.** The editor being used doesn't change during a session, so detect once and reuse.

**On 2nd+ invocation:** Use cached result. Don't re-run detection commands.

## Instructions

### Detection Logic

Check in this order:

1. **Check `$env:TERM_PROGRAM` environment variable**
   ```powershell
   $env:TERM_PROGRAM
   ```
   - If value is `"vscode"` → Use `code` command
   - Otherwise, continue to step 2

2. **Check if `devin` command exists**
   ```powershell
    Get-Command devin -ErrorAction SilentlyContinue
   ```
    - If command found → Use `devin` command
   - Otherwise, fallback to `code`

3. **Fallback:** Use `code` command (VS Code is most common)

### Complete Detection Code

```powershell
$editor = if ($env:TERM_PROGRAM -eq "vscode") {
    "code"
} elseif (Get-Command devin -ErrorAction SilentlyContinue) {
    "devin"
} else {
    "code"
}
```

### Opening Files

**Single file:**
```powershell
& $editor "myfile.txt"
```

**Multiple files:**
```powershell
& $editor "file1.txt" "file2.txt" "file3.txt"
```

Both editors support opening multiple files in one command.

## Security & execution requirements

- **Execution capability**: This skill runs read-only PowerShell checks (`$env:TERM_PROGRAM`, `Get-Command`) and can launch the detected editor executable (`code` or `devin`) — nothing else.
- **Only these two commands**: never substitute a different executable for `$editor`; the value must be exactly `"code"` or `"devin"` from the detection logic above.
- **Confirm before launching**: when opening files is a side effect of another task (rather than an explicit user request to open a file), tell the user which files will be opened and confirm first.
- **File arguments**: only pass file paths from the current task context; quote each path as a separate argument, never concatenate them into a single command string.

## Output

Store the result for reuse: `"code"` or `"devin"`

**Example:** "Detected editor: code" or simply cache the value without announcing it.
