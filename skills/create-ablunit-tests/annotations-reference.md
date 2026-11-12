# ABLUnit Annotations Reference

Understanding ABLUnit annotations is crucial for creating well-structured tests. Annotations execute in a specific lifecycle order.

**Official Documentation:** [ABLUnit Annotations](https://docs.progress.com/bundle/openedge-developer-studio-help/page/Annotations-supported-with-ABLUnit.html)

## Lifecycle Annotations (Execution Order)

| Current Name | Legacy Name | Execution | Use Case |
|-------------|-------------|-----------|----------|
| `@BeforeAll` | `@Before` (deprecated) | Once per class, before all tests | Expensive setup: database connections, loading config |
| `@BeforeEach` | `@Setup` (deprecated) | Before each test method | Prepare test environment, initialize objects |
| `@Test` | *(mandatory)* | Each test method | Mark a method as a test case |
| `@AfterEach` | `@TearDown` (deprecated) | After each test method | Cleanup: delete temp data, restore defaults |
| `@AfterAll` | `@After` (deprecated) | Once per class, after all tests | Final cleanup: disconnect databases |

## Test Annotations

| Annotation | Description | Example |
|-----------|-------------|---------|
| `@Test` | Mandatory annotation for test methods | `@Test.` |
| `@Test(expected="Type")` | Test expects specific exception to be thrown | `@Test(expected="Progress.Lang.AppError").` |
| `@Ignore` | Skip test execution (incomplete or long-running) | `@Ignore.` |

## Important Notes

- **Use current names** (@BeforeAll, @BeforeEach, @AfterEach, @AfterAll) for new tests - legacy names are deprecated
- **Multiple @BeforeEach** methods allowed - they execute in definition order
- **@BeforeAll/@AfterAll** methods must be STATIC
- **@Test annotation is mandatory** - without it, the method won't be recognized as a test
- Tests without `@TestSuite` annotation or at least one `@Test` annotation are ignored by ABLUnit

## Lifecycle Execution Example

```
Class: test_Calculator
├─ @BeforeAll setupDatabase()        ← Runs once (STATIC)
├─ @BeforeEach setUp()               ← Runs before test1
├─ @Test test_Addition()             ← Test 1
├─ @AfterEach tearDown()             ← Runs after test1
├─ @BeforeEach setUp()               ← Runs before test2
├─ @Test test_Subtraction()          ← Test 2
├─ @AfterEach tearDown()             ← Runs after test2
└─ @AfterAll cleanupDatabase()       ← Runs once (STATIC)
```

## Annotation Details

### @BeforeAll (Legacy: @Before)

**Purpose:** One-time setup before any tests run

**Requirements:**
- Method must be STATIC
- Runs once per test class
- Use for expensive operations like database connections, file loading

**Example:**
```abl
DEFINE PRIVATE STATIC VARIABLE hDatabase AS HANDLE NO-UNDO.

@BeforeAll.
METHOD PUBLIC STATIC VOID setupDatabase():
    CONNECT VALUE("sports2020") NO-ERROR.
    hDatabase = LAST-EVENT:SELF.
END METHOD.
```

### @BeforeEach (Legacy: @Setup)

**Purpose:** Setup before each test method

**Requirements:**
- Can have multiple @BeforeEach methods - execute in definition order
- Runs before each @Test method
- Use for per-test initialization like creating objects

**Example:**
```abl
DEFINE PRIVATE VARIABLE oValidator AS DateValidator NO-UNDO.

@BeforeEach.
METHOD PUBLIC VOID setUp():
    oValidator = NEW DateValidator().
END METHOD.
```

### @Test

**Purpose:** Mark a method as a test case

**Requirements:**
- Mandatory for test methods
- Without this annotation, method won't be executed as a test

**Basic example:**
```abl
@Test.
METHOD PUBLIC VOID test_ValidateDate_validFormat():
    DEFINE VARIABLE lResult AS LOGICAL NO-UNDO.

    lResult = oValidator:ValidateDate("2026-02-10").

    Assert:IsTrue(lResult, "Should accept valid date format").
END METHOD.
```

**Expected exception example:**
```abl
@Test(expected="Progress.Lang.AppError").
METHOD PUBLIC VOID test_Method_throwsAppError():
    DEFINE VARIABLE oObj AS ClassName NO-UNDO.

    oObj = NEW ClassName().
    oObj:ProcessInvalidData(?). // Should throw AppError
END METHOD.
```

### @AfterEach (Legacy: @TearDown)

**Purpose:** Cleanup after each test method

**Requirements:**
- Runs after each @Test method
- Use for cleanup like deleting objects, restoring state

**Example:**
```abl
@AfterEach.
METHOD PUBLIC VOID tearDown():
    DELETE OBJECT oValidator NO-ERROR.
END METHOD.
```

### @AfterAll (Legacy: @After)

**Purpose:** One-time cleanup after all tests run

**Requirements:**
- Method must be STATIC
- Runs once after all tests complete
- Use for cleanup like disconnecting databases

**Example:**
```abl
@AfterAll.
METHOD PUBLIC STATIC VOID cleanupDatabase():
    DISCONNECT VALUE("sports2020") NO-ERROR.
END METHOD.
```

### @Ignore

**Purpose:** Skip test execution

**Use cases:**
- Test is incomplete or under development
- Test is too slow for regular runs
- Test is temporarily broken

**Example:**
```abl
@Ignore.
@Test.
METHOD PUBLIC VOID test_ComplexOperation_notReady():
    // Test implementation in progress
END METHOD.
```

## Assertion Types (OpenEdge.Core.Assert)

| Method | Description |
|--------|-------------|
| `Assert:Equals(expected, actual)` | Value equality - no message parameter |
| `Assert:IsTrue(condition[, message])` | Boolean true - optional message |
| `Assert:IsFalse(condition[, message])` | Boolean false - optional message |
| `Assert:IsNull(object[, message])` | Null check - optional message |
| `Assert:NotNull(object[, message])` | Not null check - optional message |
| `Assert:NotNullOrEmpty(string[, message])` | String not empty - optional message |

**Note:** Not all Assert methods support optional message parameters. `Equals()` and `NotEqual()` only accept two parameters (expected and actual values). If you need a custom error message when comparing values, use `Assert:IsTrue(value1 = value2, "custom message")` instead.

## Best Practices

1. **Use current annotation names** - @BeforeAll, @BeforeEach, @AfterEach, @AfterAll
2. **Keep setup/teardown focused** - Only initialize what's needed for tests
3. **Use @BeforeAll sparingly** - Only for truly expensive operations
4. **Clean up in @AfterEach** - Don't let tests affect each other
5. **Document @Ignore usage** - Explain why test is skipped
6. **Use @Test(expected) for error testing** - Cleaner than try-catch blocks
