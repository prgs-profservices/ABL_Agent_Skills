---
name: modernize-variables
description: Convert legacy DEFINE VARIABLE syntax to modern VAR syntax in ABL code.
license: Apache-2.0
allowed-tools: Read, Grep, Glob, Write, Edit
compatibility: Cross-platform, OpenEdge project (openedge-project.json)
---

<!--
modernize-variables: Convert legacy DEFINE VARIABLE syntax to modern VAR syntax in ABL code.

Copyright 2026 Progress Software Corporation
SPDX-License-Identifier: Apache-2.0
-->

## Objective
This helps streamline code by using newer syntax to define variables.

## Analysis Steps
1. **Read and understand the code**
   - Read the entire file to understand its purpose and functionality
   - Make note of any variables defined using the DEFINE VARIABLE x AS ... syntax.

2. **Identify opportunities for improvement**
   - Look for places where variables are defined after executable code.  Variables should always be at the top of any procedure, method, or function, and never inside loops or conditionals.
   - Only variables that are defined with NO-UNDO may be converted to VAR ... x syntax.
   - Variables should not be defined in CATCH or FINALLY blocks.  These need to move up to the beginning of the containing procedure, method, or function.

3. **Consolidate existing VAR statements**
   - After converting any DEFINE VARIABLE statements, review all VAR statements within each scope (file-level, procedure, method, or function)
   - Identify groups of VAR statements that define variables of the same datatype
   - Combine these into single VAR statements with comma-separated variable lists


## Conversion Rules
- Use the correct ABL syntax for the VAR statement as described by the openedge-abl-mcp-server MCP.
- Any usage of INIT in the original definition can be converted to an initial assignment in the VAR statement.  e.g. DEFINE VARIABLE i AS INTEGER INIT 4 NO-UNDO would convert to VAR INT i = 4.
- **EXTENT (array) variables can also be converted to VAR syntax** using square-bracket notation instead of the `EXTENT` keyword:
  - Determinate (fixed-size) extent: `DEFINE VARIABLE cNames AS CHARACTER NO-UNDO EXTENT 5.` becomes `VAR CHAR[5] cNames.`
  - Indeterminate (runtime-sized) extent: `DEFINE VARIABLE hBuf AS HANDLE NO-UNDO EXTENT.` becomes `VAR HANDLE[] hBuf.`
  - Initial values for determinate arrays carry over using `= [v1, v2, ...]` syntax: `DEFINE VARIABLE iVals AS INTEGER NO-UNDO EXTENT 3 INITIAL [1,2,3].` becomes `VAR INT[3] iVals = [1,2,3].`
  - Note: `NO-UNDO` is still required on the original for conversion to be valid (same rule as non-extent variables).
- **Always use INT and CHAR instead of INTEGER and CHARACTER when using VAR syntax.** These shorter synonyms are preferred for modern VAR declarations.
  - `DEFINE VARIABLE cName AS CHARACTER NO-UNDO.` becomes `VAR CHAR cName.`
  - `DEFINE VARIABLE iCount AS INTEGER NO-UNDO.` becomes `VAR INT iCount.`
  - This applies even if consolidating existing VAR statements that use the longer forms - convert them to use the shorter synonyms.
- **Consolidate all variable definitions of the same type into a single VAR statement**, regardless of whether they were originally defined using VAR or DEFINE VARIABLE syntax. For example:
  - `var integer cnt.` and `var int maxWait = 30000.` should be combined into `var int cnt, maxWait = 30000.`
  - `VAR INT j.`, `VAR INT i = 4.`, and `VAR INT numTiles.` should be combined into `VAR INT j, i = 4, numTiles.`
  - `var character cName.` should be converted to `var char cName.` when consolidating (use the shorter synonym)
  - Exception: Don't consolidate extent (array) variables with non-extent variables, and don't consolidate extent variables with different sizes (e.g. `VAR INT[3]` and `VAR INT[5]` must stay separate; `VAR INT[]` and `VAR INT[3]` must stay separate).
- There is no need to initialize a value for the variable unless the value would differ from the default for that datatype.  For example, integers and decimals default to 0, dates default to ?, logicals default to false, and characters default to "" (empty string).
- If a given variable definition is commented, be sure to retain that comment, but ensure the comment references which variable.

## Quality Assurance
- After making changes, check for syntax errors or compilation problems in the modified file: use your IDE's diagnostics tool if available (e.g. `get_errors` in Copilot), otherwise compile the file with the **compile-openedge-abl** skill
- Address any errors that appear before considering the conversion complete
- Common issues to watch for:
  - `CLASS` keyword incorrectly used with VAR syntax
  - `INIT` used instead of `=` for initialization
  - Variables with UNDO that cannot be converted
  - Executable statements placed before variable definitions
- If VAR statements were previously used, you may end up with opportunities to further consolidate definitions.  After making your first pass at modernizing, go back through looking at VAR statements to see if any of them are of the same type and can be combined.

## Output
Display the number of variables converted.
Display the number of variables that couldn't be converted.  If there are fewer than 4, display a parenthetical list of line numbers.
