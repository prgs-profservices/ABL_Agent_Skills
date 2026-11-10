---
name: create-ablunit-tests
description: Create an ABLUnit test class for a given OpenEdge ABL program that the user wants testing for.
license: Apache-2.0
allowed-tools: Read, Grep, Glob, Write, Edit
compatibility: Cross-platform, OpenEdge project (openedge-project.json)
---

<!--
create-ablunit-tests: Create an ABLUnit test class for a given OpenEdge ABL program that the user wants testing for.

Copyright 2026 Progress Software Corporation
SPDX-License-Identifier: Apache-2.0
-->

## Objective

Create or enhance ABLUnit test classes for OpenEdge ABL programs (.cls, .p, .w) based on user requirements. The user specifies what needs testing - either full coverage or specific methods.

**Critical principle:** Do NOT create a new test class if one already exists unless the user explicitly requests it. Instead, enhance the existing test class with additional tests.

## User Input Requirements

The user must provide:
- **Source file** to be tested (e.g., `src/myapp/OrderCalculator.cls`)
- **Test scope**:
  - "Full unit testing" - test all public methods
  - Specific methods - list of method names to test
  - "Additional tests for..." - enhance existing test class

## Prerequisites

- Access to the source file to be tested
- Use the **find-ablunit-tests** skill to check if a test file already exists
- Understanding of the class/program structure and public methods
- Access to `openedge-project.json` to determine test file location conventions
- Access to the project's coding-standards instructions file if one exists (e.g. `CLAUDE.md`, `AGENTS.md`, or `.github/copilot-instructions.md` — whichever this project uses)

## Important References

When creating tests, reference these detailed guides as needed. They live in this skill's own folder (the directory containing this SKILL.md — resolve it from where the skill was loaded, do not hardcode a root like `.github/skills` or `.claude/skills`):

- **Database safety** → Read `database-safety.md` for safety strategies when testing methods that modify database records
- **ABLUnit annotations** → Read `annotations-reference.md` for details on @BeforeAll, @BeforeEach, @Test, @AfterEach, @AfterAll
- **Code examples** → Read `code-examples.md` for complete examples and common patterns, and `code-examples-advanced.md` for database patterns, edge cases, and naming conventions

## Steps

### Step 1: Use find-ablunit-tests Skill

**Always check for existing tests first:**
- Use the **find-ablunit-tests** skill with the provided source file
- If test file(s) exist, read them to understand current coverage
- Analyze existing test methods to identify gaps
- Determine if user wants to enhance existing tests or create new ones

**Decision tree:**
- **Test exists + user wants "full testing"**: Add missing test methods to existing file
- **Test exists + user specifies methods**: Add only those specific test methods to existing file
- **Test exists + user says "create new test"**: Create additional test file with descriptive name
- **No test exists**: Create new test file following project conventions

### Step 2: Analyze the Source File

Read and analyze the source file to understand:

1. **File type**: Class (.cls), procedure (.p), or window (.w)
2. **Public interface**: Identify all PUBLIC methods, functions, or procedures
3. **Method signatures**: Parameters (INPUT/OUTPUT), return types
4. **Dependencies**: USING statements, class references
5. **Constructor overloads**: Multiple constructors with different parameters
6. **Properties**: PUBLIC properties that may need testing
7. **⚠️ Database operations**: Identify methods that CREATE, UPDATE, or DELETE database records

**For classes:**
- Focus on PUBLIC methods and properties
- Note PROTECTED/PRIVATE methods (generally not tested directly)
- Identify static vs. instance methods

**For procedures (.p):**
- Identify RUN statements and parameters
- Look for FUNCTION definitions

**⚠️ Database impact assessment:**
- If methods perform CREATE/UPDATE/DELETE operations, **read `database-safety.md`** for safety strategies
- Consult user on safety approach before creating database-modifying tests
- Never create tests that modify real production data without explicit user agreement

### Step 3: Determine Test File Location

**If test exists:** Use the existing test file path

**If creating new test:**
- Read `openedge-project.json` to find source buildPath (typically `src/`)
- Mirror the source directory structure under a test-related folder
- Common pattern: `src/path/ClassName.cls` → `src/test/path/test_ClassName.cls`
- Naming convention: `test_` prefix + source filename

**For additional test files:**
- Use descriptive suffix: `test_ClassName_Integration.cls`, `test_ClassName_EdgeCases.cls`
- Place in same directory as primary test file

### Step 4: Generate Test Class Structure

**If enhancing existing test:** Skip to Step 5

**If creating new test class:**

1. **File header comment** (follow the project's coding-standards file format):
   ```abl
   /*------------------------------------------------------------------------
       File        : test_ClassName
       Purpose     : Unit tests for ClassName class
       Syntax      :
       Description : Tests [describe what's being tested]
       Author(s)   : [from the project's coding-standards file or user]
       Created     : [current date]
       Notes       : [Document database safety strategy if applicable]
   ----------------------------------------------------------------------*/
   ```

2. **USING statements:**
   - `USING Progress.Lang.*`
   - `USING OpenEdge.Core.Assert FROM PROPATH.`
   - Source class being tested
   - Any required dependencies

3. **Error handling directive** (required):
   ```abl
   BLOCK-LEVEL ON ERROR UNDO, THROW.
   ```

4. **Class declaration** (package name must follow directory structure):
   ```abl
   CLASS test.path.test_ClassName USE-WIDGET-POOL:
   ```

   Examples:
   - Directory: `src/test/myapp/` → `CLASS test.myapp.test_ClassName USE-WIDGET-POOL:`
   - Directory: `src/test/system/` → `CLASS test.system.test_ClassName USE-WIDGET-POOL:`

5. **Setup and teardown methods** (if needed):

   For details on annotations, **read `annotations-reference.md`**. Summary:

   - `@BeforeAll` - Once per class before all tests (STATIC, for database connections)
   - `@BeforeEach` - Before each test (for object initialization)
   - `@AfterEach` - After each test (for cleanup)
   - `@AfterAll` - Once after all tests (STATIC, for database disconnect)

   Use current annotation names (not legacy @Before, @Setup, @TearDown, @After)

### Step 5: Create Test Methods

For each method to be tested, create one or more test methods:

**Basic structure:**
```abl
/*------------------------------------------------------------------------------
 Purpose: [What this test verifies]
 Notes:   [Any important details about the test]
------------------------------------------------------------------------------*/
@Test.
METHOD PUBLIC VOID test_methodName_scenario():
    // Arrange - setup test data
    // Act - execute the method being tested
    // Assert - verify expected results

    Assert:Equals(expected, actual, "description").
END METHOD.
```

**Test naming convention:**
- Pattern: `test_MethodName_scenario`
- Examples: `test_ValidateInput_validData`, `test_Constructor_withDefaultParams`, `test_Calculate_throwsError`

**Test coverage considerations:**
- Happy path (normal inputs)
- Edge cases (boundary values, empty, zero)
- Error cases (invalid inputs, nulls)
- State changes (verify side effects)

**Common assertions:**
- `Assert:Equals(expected, actual, message)`
- `Assert:IsTrue(condition, message)` / `Assert:IsFalse(condition, message)`
- `Assert:IsNull(object, message)` / `Assert:NotNull(object, message)`
- `Assert:NotNullOrEmpty(string, message)`

For complete examples and patterns, **read `code-examples.md` and `code-examples-advanced.md`**.

### Step 6: Follow Coding Standards

Apply standards from the project's coding-standards instructions file (e.g. `CLAUDE.md`, `AGENTS.md`, or `.github/copilot-instructions.md`):

- Complete file header with all sections
- Section comments before each test method
- @Test annotation on separate line before method
- Method organization: lifecycle methods before test methods, grouped by annotation type
- Constructor parameter formatting: multiple parameters on separate lines
- All DEFINE VARIABLE at top of method
- No DO...END for single statements

## Output Format

**If enhancing existing test file:**
- Add new test methods to the existing file
- Update the History section in the file header
- Maintain existing code organization
- Report what tests were added

**If creating new test file:**
- Generate complete test class with header
- Include all requested test methods
- Follow project structure conventions
- Report the new file location

**User communication:**
- Summarize what tests were created/added
- List test method names and what they test
- Note any methods that couldn't be tested (e.g., private methods)
- Suggest running tests with **test-with-ablunit** skill

## Example Workflows

### Example 1: Create Tests for New Class

**User request:** "Create unit tests for src/system/DateValidator.cls"

**Process:**
1. Use find-ablunit-tests → No test exists
2. Analyze DateValidator.cls → PUBLIC methods: ValidateDate(), ValidateDateRange()
3. Determine location → `src/test/system/test_DateValidator.cls`
4. Create test class with @BeforeEach setup and tests for each method

**Output:** Created `src/test/system/test_DateValidator.cls` with 5 test methods.

### Example 2: Add Tests to Existing Class

**User request:** "Add tests for the CalculateTotal method in src/myapp/PriceCalculator.cls"

**Process:**
1. Use find-ablunit-tests → Found `src/test/myapp/test_PriceCalculator.cls`
2. Read existing test → has tests for ApplyDiscount() only
3. Add tests for CalculateTotal with different scenarios
4. Update History section

**Output:** Added 3 test methods to existing test file.

### Example 3: Database Testing with Safety Strategy

**User request:** "Create tests for src/BusinessCrud/Customer.cls"

**Process:**
1. Analyze Customer.cls → Has AddData(), SetData(), DeleteData() (database operations)
2. **Read `database-safety.md`** for strategies
3. Consult user: "These methods modify the Customer table. Recommend Strategy 1 (test data with identifiable keys). What key range is safe?"
4. User: "Use customer numbers 9000-9999"
5. Create tests using custNum 9888 with add/update/delete sequence

**Output:** Created test file with database safety strategy documented in header.

## Notes

### Required Standards

- **BLOCK-LEVEL ON ERROR UNDO, THROW** - Always include before class declaration
- **USE-WIDGET-POOL** - Always include in class declaration
- **Package naming** - Must follow directory structure (e.g., `src/test/myapp/` → `test.myapp.test_ClassName`)

### Best Practices

- **Always use find-ablunit-tests first** to avoid creating duplicate test files
- **⚠️ Assess database safety first** - Read `database-safety.md` if testing database operations
- **Never test against production data** - Use test data with identifiable keys outside production range
- **Use current annotation names** - @BeforeAll, @BeforeEach, @AfterEach, @AfterAll (see `annotations-reference.md`)
- Test method naming: `test_MethodName_scenario()` clearly describes what's tested
- One assertion per test when possible (makes failures easier to diagnose)
- Consider edge cases and error conditions, not just happy paths
- Use meaningful assertion messages to help identify failures
- **Don't test PRIVATE or PROTECTED methods directly** - test through public interface
- Follow project coding standards from the project's instructions file
- Suggest running tests with **test-with-ablunit** skill after creation

### Additional Resources

- **`database-safety.md`** - Comprehensive guide to 4 safety strategies for database-testing tests
- **`annotations-reference.md`** - Complete ABLUnit annotations reference with lifecycle details
- **`code-examples.md`** - Full examples: complete test class, constructors, exceptions, setup/teardown
- **`code-examples-advanced.md`** - Database patterns, transaction rollback, edge cases, state testing, naming conventions, Arrange-Act-Assert
