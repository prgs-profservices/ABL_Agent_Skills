---
name: tighten-up
description: Reduce code volume for a file while keeping the functionality the same.
license: Apache-2.0
allowed-tools: Read, Grep, Glob, Write, Edit
compatibility: Cross-platform
---

<!--
tighten-up: Reduce code volume for a file while keeping the functionality the same.

Copyright 2026 Progress Software Corporation
SPDX-License-Identifier: Apache-2.0
-->

When asked to "tighten up" code or reduce code volume while maintaining functionality, follow these steps:

## Objective
Refactor code to be more concise and efficient without changing its behavior or functionality.

## Analysis Steps

1. **Read and understand the code**
   - Read the entire file to understand its purpose and functionality
   - Identify all functions, methods, and their responsibilities
   - Note any tests or documentation that define expected behavior
   - Make note of how many lines of code there are.

2. **Identify opportunities for improvement**
   - Look for duplicate code blocks that can be consolidated
   - Find complex conditional logic that can be simplified
   - Identify similar functions that can be merged or refactored
   - Spot unnecessary variables or temporary storage
   - Find verbose patterns that can use more concise syntax
   - Locate redundant comments or overly verbose code
   - If there are DEFINE VARIABLE statements, use the modernize-variables skill to convert them to VAR statements that save space.
   - Watch for needless initializations of variables.  Variables of certain types have default values: Character="" (empty string), integer or decimal = 0, date or datetime or datetime-tz = ?, logical = false.  These shouldn't need to be set unless the variable is reused.  If a variable is defined, then assigned to the default value before other logic is executed that could change the value, then you can delete the assignment of that variable.  If it is initialized to a constant before being used, then that can be moved into the VAR statement that defines it.

3. **Plan refactoring**
   - Prioritize changes that provide the most significant reduction
   - Ensure changes maintain the same functionality
   - Consider readability vs. conciseness trade-offs
   - Group related changes together

## Refactoring Techniques

- **Eliminate duplication**: Extract common code into reusable functions
- **Simplify conditionals**: Use guard clauses, early returns, or ternary operators where appropriate
  - **Single-line IF/THEN**: When an `IF` condition and its `THEN` action together fit within 80 characters, place them on one line. This applies to ALL single-statement THEN actions ? RETURN, NEXT, LEAVE, assignments, DELETE OBJECT, procedure calls, etc. Do NOT break the THEN action to the next line unless the combined line would exceed 80 characters. Examples: `IF x = "" THEN RETURN "".` / `IF lDebug THEN dtStart = NOW.` / `IF VALID-HANDLE(h) THEN DELETE OBJECT h NO-ERROR.`
  - **Two-line IF/THEN/ELSE**: When an `IF/THEN/ELSE` spans 4 lines and both the THEN and ELSE actions are short, collapse to 2 lines by joining THEN inline and keeping ELSE on its own line. Example: `IF x = "" THEN y = a.` / `ELSE y = b.` -- apply this whenever both combined lines stay within 80 characters.
  - **Guard clauses (early exit pattern)**: When a large block of code is wrapped in an IF/THEN/DO block, invert the condition and use NEXT (in loops), RETURN (in methods), or LEAVE (in blocks) to exit early. This reduces nesting and improves readability.
  - Example: `IF condition THEN DO: /* 20 lines */ END.` becomes `IF NOT condition THEN NEXT. /* 20 lines without nesting */`
  - In loops, when checking multiple conditions with AND, invert to OR with NEXT: `IF a = x AND b = y THEN DO: ... END.` becomes `IF a <> x OR b <> y THEN NEXT. ...`
  - **Guard clauses in CATCH blocks**: LEAVE works in CATCH blocks to exit early without throwing. Example: `CATCH e AS Error: IF testConfig:ThrowError THEN DO: message "msg". undo, throw e. END. END.` becomes `CATCH e AS Error: IF NOT testConfig:ThrowError THEN LEAVE. message "msg". undo, throw e. END.`
  - **CRITICAL WARNING**: Only use guard clauses when the early exit doesn't skip subsequent logic that should still execute. In loops, NEXT exits the ENTIRE iteration - if you need to check multiple independent conditions for the same item, keep the nested structure. Example: DON'T convert if you have `IF conditionA THEN DO: /*logic A*/ END. IF conditionB THEN DO: /*logic B*/ END.` where both checks operate on the same iteration.
- **Remove unnecessary nested DO blocks**: When an IF statement contains only a DO block with no additional logic, the outer DO can be removed. Most commonly, if the inner block is an iterating DO loop or FOR EACH statement, it can be controlled directly by the IF.
  - Example with DO loop: `IF condition THEN DO: DO i = 1 TO 10: /* code */ END. END.` becomes `IF condition THEN DO i = 1 TO 10: /* code */ END.`
  - Example with FOR EACH: `IF condition THEN DO: FOR EACH customer: /* code */ END. END.` becomes `IF condition THEN FOR EACH customer: /* code */ END.`
  - This applies when the DO block contains exactly one statement (even if that statement is multi-line like a loop or another block)
- **Combine multiple assignments**: Use the ASSIGN statement to group multiple variable assignments together, which can eliminate the need for DO blocks.
  - Example: `ELSE DO: var1 = value1. var2 = value2. var3 = value3. END.` becomes `ELSE ASSIGN var1 = value1 var2 = value2 var3 = value3.`
  - This is especially useful after IF/THEN/ELSE where it reduces nesting and saves 2 lines per occurrence
- **Consolidate functions**: Merge similar functions with parameter-based variations
- **Remove unnecessary variables**: Inline variables used only once
- **Remove dead code**: Delete unused variables, functions, or imports

## Things not to do
- Do not eliminate comments, but you can rephrase them or de-duplicate them to make them shorter.  You can remove excess newlines if appropriate.
- Do not abbreviate ABL syntax. But you may use an alternate form of syntax that is shorter.
-- Bad: Changing "DEFINE VARIABLE x AS INTEGER NO-UNDO." to "DEF VAR x AS INT NO-UNDO".
-- Good: Changing "DEFINE VARIABLE x AS INTEGER NO-UNDO." to "VAR INTEGER x.""

## Implementation

1. Make changes incrementally
2. **CRITICAL**: Before making any changes, search for test files matching the source file pattern using `**/test/**/test_ClassName.cls` (note the `**/` after test to search all subdirectories). If tests exist, you MUST use the test-with-ablunit skill to run them after each significant change and verify all tests pass before proceeding with additional changes.
3. Preserve all existing functionality
4. Maintain or improve code readability
5. Keep the same public API/interface
6. Ensure that the code compiles (if it is a .w, .p, or .cls file) or that you fix any errors.

## Output

Provide a summary of:
- What was changed and why
- How much code volume was reduced (line count or percentage)
- Any trade-offs made between conciseness and readability
- Suggestions for further improvements if any remain
