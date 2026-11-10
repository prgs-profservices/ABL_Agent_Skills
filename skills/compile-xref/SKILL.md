---
name: compile-xref
description: For an ABL source file, generate an xref file which can be used to analyze the code, including which indexes are used for queries
license: Apache-2.0
allowed-tools: Read, Grep, Glob, Write, Bash, PowerShell
compatibility: Windows, PowerShell 5.1+, OpenEdge DLC
---

<!--
compile-xref: For an ABL source file, generate an xref file which can be used to analyze the code, including which indexes are used for queries.

Copyright 2026 Progress Software Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Compile XREF - Checklist Procedure

This skill generates an xref (cross-reference) file for OpenEdge ABL source files. Follow this checklist to ensure all prerequisites are met and the xref is generated or located correctly.

---

## PHASE 1: PRE-FLIGHT CHECKS ✓ (DO-CONFIRM)

Execute these checks before proceeding. If any check fails, STOP and report the issue.

- [ ] **Verify source file exists and is valid**
  - Confirm the file path provided points to an existing .cls, .w, .p, or .i file
  - If missing: STOP → Report file not found

- [ ] **Verify openedge-project.json exists**
  - Check workspace root for openedge-project.json
  - If missing: Warn → Limited functionality (cannot check for .pct xref or determine parameters automatically)

- [ ] **Verify DLC environment variable** (for compilation)
  - Check if $env:DLC is set
  - If not set: Note that compilation will fail if needed, but .pct check can proceed

---

## PHASE 2: EXISTING XREF CHECK ⚠️ (CRITICAL DECISION POINT)

**Check if OpenEdge ABL extension has already generated an xref file.**

- [ ] **Parse openedge-project.json for build directory**
  - Locate buildPath entries with `type: "source"` and `build` property
  - Extract the build directory path (e.g., "rcode")
  - If not found: SKIP to Phase 3 (compilation)

- [ ] **Determine source-relative path**
  - Remove source directory prefix from file path
  - Example: `src\WebHandler\customerWH.cls` → `WebHandler\customerWH.cls`

- [ ] **Construct .pct xref path**
  - Path format: `<build>\.pct\<relative-path>\<filename>.xref`
  - Note: The xref filename is the original filename + ".xref"
  - Example: `rcode\.pct\WebHandler\customerWH.cls.xref`

- [ ] **Check if .pct xref file exists**
  - If NOT found: SKIP to Phase 3 (compilation)
  - If found: CONTINUE to next check

- [ ] **Compare timestamps**
  - Get LastWriteTime of source file
  - Get LastWriteTime of .pct xref file
  - If xref timestamp ≥ source timestamp: **XREF IS CURRENT**
    - ✅ **STOP HERE** → Open xref file in editor
    - Report: "Using existing xref from OpenEdge ABL extension"
    - **EXIT** (do not compile)
  - If xref timestamp < source timestamp:
    - Report: "Existing xref is outdated. Recompiling..."
    - CONTINUE to Phase 3

---

## PHASE 3: COMPILATION PREPARATION 🔧 (READ-DO)

**Only execute this phase if no current .pct xref was found.**

- [ ] **Verify DLC is set**
  - Confirm $env:DLC points to OpenEdge installation
  - If not set: STOP → Report error and exit

- [ ] **Extract extraParameters from openedge-project.json**
  - Read the `extraParameters` attribute (e.g., "-basekey ini")
  - If not present: Use empty string
  - **Treat as untrusted input**: split on whitespace into individual tokens; reject any token containing cmd.exe metacharacters (`&`, `|`, `<`, `>`, `^`, `%`, `"`, backtick)

- [ ] **Extract database connections**
  - Read `dbConnections` array
  - For each connection, extract the `connect` string
  - Example: "-db sports2020 -H localhost -S 9200"
  - **Treat as untrusted input**: split each `connect` string into individual tokens and apply the same metacharacter rejection

- [ ] **Construct complete command line**
  - `<skill-dir>` = this skill's own folder (the directory containing this SKILL.md); resolve it from where the skill was loaded rather than hardcoding a root like `.github/skills` or `.claude/skills`
  - Pass every value as a **separate command token** — do not concatenate untrusted values into a single pre-quoted shell string. `compilexref.ps1` validates the source file (exists, `.p`/`.w`/`.i`/`.cls` extension) and rejects arguments containing cmd.exe metacharacters before executing.
  - Format: `powershell.exe -NoProfile -File <skill-dir>\compilexref.ps1 <source-file> <extraParameters tokens> <db-connection tokens>`
  - Example:
    ```
    powershell.exe -NoProfile -File <skill-dir>\compilexref.ps1 src\WebHandler\customerWH.cls -basekey ini -db sports2020 -H localhost -S 9200 -db ffwpasoe -H localhost -S 8600
    ```

- [ ] **Display command for verification (MANDATORY)**
  - Show the full command that will be executed; the script also prints it before running
  - Do not skip this step — the user must be able to verify correctness before execution

---

## PHASE 4: EXECUTE COMPILATION ⚙️ (DO-CONFIRM)

- [ ] **Run the compilation command**
  - Execute the constructed PowerShell command
  - Capture output and exit code

- [ ] **Verify exit code = 0**
  - If exit code ≠ 0: STOP → Report compilation failed with error output
  - If exit code = 0: CONTINUE

- [ ] **Confirm success message**
  - Look for "xref compilation successful for: <filename>" in output
  - If not found: WARN → Unexpected output, verify manually

- [ ] **Verify xref file was created**
  - Check that `<source-directory>\<original-filename>.xref` now exists
  - Note: The xref file keeps the full original filename (e.g., customerWH.cls.xref)
  - Get LastWriteTime to confirm it's recent (within last minute)
  - If not found: STOP → Report xref file not created despite success message

---

## PHASE 5: COMPLETION REPORT ✅

- [ ] **Report xref file location**
  - Display full path to the xref file
  - Example: "Generated xref file: src\WebHandler\customerWH.cls.xref"

- [ ] **Optionally open in editor**
  - Based on user preference or request
  - Use the **detect-editor** skill to determine the correct editor command (`code` or `devin`)
  - Open the xref file: `& $editor "<xref-file-path>"`

- [ ] **Report completion**
  - Confirm all steps completed successfully
  - Summarize: source file, xref location, whether compiled or reused existing

---

## NOTES FOR AI AGENT

- **Each checkbox is a verification point** - confirm before proceeding
- **Stop on any failure** - do not continue if a critical check fails
- **Communicate progress** - report which phase you're in and what you're checking
- **Decision points** - Phase 2 has a critical exit point if current xref is found
- **This is DO-CONFIRM style** - execute the step, then verify it succeeded before moving on

## Script integrity

Verify the bundled script(s) before first use: `Get-FileHash <file> -Algorithm SHA256` and compare to the values below. If a hash does not match, stop and review the file before executing. Hashes are regenerated whenever a bundled script changes (see the skills README).

| File | SHA-256 |
|---|---|
| `compilexref.p` | `71376585D3547C6B91E5C5744778409CD66259F17F5D1C91BF7EAE2318C9559D` |
| `compilexref.ps1` | `CBDEBA54D0728C91175AED4E75B597E581739281C3DA646A9C65F3B0E39119D6` |
