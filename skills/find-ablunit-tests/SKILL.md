---
name: find-ablunit-tests
description: Locate existing ABLUnit test files for a given OpenEdge ABL source file.
license: Apache-2.0
allowed-tools: Read, Grep, Glob
compatibility: Cross-platform, OpenEdge project (openedge-project.json)
---

<!--
find-ablunit-tests: Locate existing ABLUnit test files for a given OpenEdge ABL source file.

Copyright 2026 Progress Software Corporation
SPDX-License-Identifier: Apache-2.0
-->

## Objective

Determine if one or more ABLUnit test classes exist for a given OpenEdge ABL source file (.cls, .p, .w) and return the test file path(s) if found.

**Key principle:** An ABLUnit test class ALWAYS contains at least one `@Test.` annotation. This is the definitive indicator of a test file.

## Input

- Source file path (e.g., `src/system/DateUtils.cls` or `src/myapp/DatasetBuilder.cls`)
- OR test file path (e.g., `src/test/system/test_DateUtils.cls`)

## Output

- **If test file(s) exist**: Full workspace path(s) to the test file(s)
- **If multiple test files found**: List all with brief description of what each tests (based on naming and content)
- **If test file does not exist**: Indication that no test exists
- **If input is already a test file**: Return the same path with confirmation

## Steps

### Step 1: Determine if Input is Already a Test File

Check if the provided path:
- Contains a test-related directory (e.g., `/test/`, `/tests/`, `/testing/`, `/unit/`, `/integration/`)
- Has filename starting with `test_`
- Contains `@Test` annotation in the file (definitive check)

If yes, return the path as-is and exit.

### Step 2: Extract Class/Program Name

From the source file path (e.g., `src/system/DateUtils.cls`):
- Extract the filename without extension: `DateUtils`
- Note the directory structure: `system/`
- Note the file extension: `.cls`

### Step 3: Search for Test File

Use your agent's file-search tool (e.g. `file_search` in Copilot, `Glob` in Claude Code) to look for the test file using a broad pattern to accommodate various test folder naming conventions:

**Primary search pattern:**
```
**/test_ClassName.ext
```

This searches the entire workspace for files matching the test naming convention, regardless of folder structure.

**Alternative approach (if needed):** Search using multiple patterns:
- `**/test/**/test_ClassName.ext` (most common)
- `**/tests/**/test_ClassName.ext`
- `**/testing/**/test_ClassName.ext`
- `**/unit/**/test_ClassName.ext`
- `**/integration/**/test_ClassName.ext`

Where:
- `test_ClassName` is the test file naming convention
- `.ext` matches the source file extension (.cls, .p, or .w)

**Example patterns:**
- Source: `src/system/DateUtils.cls` → Search: `**/test_DateUtils.cls`
- Source: `src/myapp/DatasetBuilder.cls` → Search: `**/test_DatasetBuilder.cls`
- Source: `src/procs/ValidateUser.p` → Search: `**/test_ValidateUser.p`

**Important:** The broad search may return non-test files. Step 4 verification using `@Test` annotation is essential to confirm actual test files.

### Step 4: Verify Test Files

**Critical step:** For each file found, verify it's an actual ABLUnit test by checking for `@Test` annotations:
- Use your agent's content-search tool (e.g. `grep_search` in Copilot, `Grep` in Claude Code) to search the file contents for `@Test` annotation
- If found, confirm it's a valid ABLUnit test class
- If not found, exclude it from results (not a test file despite naming)

This verification step is essential because:
- The broad search pattern may return non-test files
- Test folder naming varies across projects (test, tests, testing, unit, integration, etc.)
- `@Test` annotation is the definitive marker of an ABLUnit test

### Step 5: Analyze What Each Test Covers

For valid test files, determine what they test by examining:

1. **File header comments**: Look for Purpose, Description, or Notes sections that describe testing scope
2. **Test class name**: Often indicates primary purpose (e.g., `test_CustomerValidation.cls` tests validation logic)
3. **Class dependencies**: Check USING statements and object instantiations to identify what's being tested
4. **Test method names**: Method names often reveal specific functionality being tested

**Important considerations:**
- One source file may have multiple test classes testing different aspects
- Test classes may instantiate multiple support classes (mocks, utilities, dependencies)
- Focus on the primary class being tested, typically indicated by:
  - Most frequent class references in the test
  - Class mentioned in test file header
  - Class name matching the test file name pattern

### Step 6: Return Results

**If test file(s) found:**
- Return full workspace path(s)
- For each test file, include brief description of what it tests based on analysis
- If multiple tests exist, explain how they differ (e.g., "integration tests vs. unit tests")

**Common patterns:**
- `src/system/ClassName.cls` → `src/test/system/test_ClassName.cls`
- `src/myapp/ClassName.cls` → `src/test/myapp/test_ClassName.cls`
- `src/procs/Program.p` → `src/test/procs/test_Program.p`

**If test file not found:**
- Report that no test file exists for this source file
- Suggest the expected test file path following the convention

## Example Usage

**Input:** `src/system/DateUtils.cls`

**Process:**
1. Not a test file (doesn't contain test-related directory or @Test annotation)
2. Extract: class = `DateUtils`, dir = `system/`, ext = `.cls`
3. Search: `**/test_DateUtils.cls`
4. Found: `src/test/system/test_DateUtils.cls`
5. Verify: Contains @Test annotations ✓

**Output:** `src/test/system/test_DateUtils.cls` - Tests date utility methods

---

**Input:** `src/system/CustomerValidator.cls`

**Process:**
1. Not a test file
2. Extract: class = `CustomerValidator`, dir = `system/`, ext = `.cls`
3. Search: `**/test_CustomerValidator.cls`
4. Found multiple:
   - `src/test/system/test_CustomerValidator.cls`
   - `src/tests/integration/test_CustomerValidatorIntegration.cls`
5. Verify and analyze each:
   - First file: Contains @Test annotations ✓, header says "Unit tests for CustomerValidator", instantiates CustomerValidator
   - Second file: Contains @Test annotations ✓, header says "Integration tests with database", instantiates CustomerValidator plus database connections

**Output:**
- `src/test/system/test_CustomerValidator.cls` - Unit tests for CustomerValidator methods
- `src/tests/integration/test_CustomerValidatorIntegration.cls` - Integration tests with database

---

**Input:** `src/myapp/NewFeature.cls`

**Process:**
1. Not a test file
2. Extract: class = `NewFeature`, dir = `myapp/`, ext = `.cls`
3. Search: `**/test_NewFeature.cls`
4. Not found

**Output:** No test file exists. Expected location would be: `src/test/myapp/test_NewFeature.cls`

## Notes

- **@Test annotation is definitive**: A file is only an ABLUnit test if it contains @Test annotations - this verification is critical
- Test files typically follow naming convention: `test_` prefix + source filename
- **Test folder naming varies**: Projects may use `test/`, `tests/`, `testing/`, `unit/`, `integration/`, or other variations
- Use broad search pattern (`**/test_ClassName.ext`) then verify with @Test annotation rather than assuming specific folder names
- Test files usually mirror source directory structure under a test-related subdirectory
- **Multiple tests are common**: A single source file may have multiple test classes covering different scenarios (unit vs. integration, different features, etc.)
- **Test classes use multiple classes**: Don't assume every USING statement or instantiation is the class being tested - focus on the primary subject
- Test file names and headers are the best indicators of testing scope
- If a source file doesn't have a test, this skill returns the expected path for creating one
