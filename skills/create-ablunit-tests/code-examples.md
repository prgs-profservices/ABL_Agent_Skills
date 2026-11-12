# ABLUnit Test Code Examples

This file contains complete examples and common patterns for writing ABLUnit tests.

## Complete Test Class Example

Here's a complete example showing all required standards:

```abl
/*------------------------------------------------------------------------
    File        : test_DateValidator
    Purpose     : Unit tests for DateValidator class
    Syntax      :
    Description : Tests date validation functionality
    Author(s)   : S.E. Southwell
    Created     : Mon Feb 10 2026
    Notes       :
  ----------------------------------------------------------------------*/

USING Progress.Lang.*.
USING OpenEdge.Core.Assert FROM PROPATH.
USING system.DateValidator FROM PROPATH.

BLOCK-LEVEL ON ERROR UNDO, THROW.

CLASS test.system.test_DateValidator USE-WIDGET-POOL:

    DEFINE PRIVATE VARIABLE oValidator AS DateValidator NO-UNDO.

    @BeforeEach.
    METHOD PUBLIC VOID setUp():
        oValidator = NEW DateValidator().
    END METHOD.

    @AfterEach.
    METHOD PUBLIC VOID tearDown():
        DELETE OBJECT oValidator NO-ERROR.
    END METHOD.

    /*------------------------------------------------------------------------------
     Purpose: Verify valid date format is accepted
     Notes:
    ------------------------------------------------------------------------------*/
    @Test.
    METHOD PUBLIC VOID test_ValidateDate_validFormat():
        DEFINE VARIABLE lResult AS LOGICAL NO-UNDO.

        lResult = oValidator:ValidateDate("2026-02-10").

        Assert:IsTrue(lResult, "Should accept valid date format").
    END METHOD.

    /*------------------------------------------------------------------------------
     Purpose: Verify invalid date format is rejected
     Notes:
    ------------------------------------------------------------------------------*/
    @Test.
    METHOD PUBLIC VOID test_ValidateDate_invalidFormat():
        DEFINE VARIABLE lResult AS LOGICAL NO-UNDO.

        lResult = oValidator:ValidateDate("02/10/2026").

        Assert:IsFalse(lResult, "Should reject invalid date format").
    END METHOD.

END CLASS.
```

## Common Patterns

### Pattern 1: Testing Constructors

```abl
/*------------------------------------------------------------------------------
 Purpose: Verify constructor initializes properties correctly
 Notes:
------------------------------------------------------------------------------*/
@Test.
METHOD PUBLIC VOID test_Constructor_withParameters():
    DEFINE VARIABLE oObj AS ClassName NO-UNDO.

    oObj = NEW ClassName("param1", 123).

    Assert:NotNull(oObj, "Constructor should create instance").
    Assert:Equals("param1", oObj:PropertyName).

    FINALLY:
        DELETE OBJECT oObj NO-ERROR.
    END FINALLY.
END METHOD.
```

### Pattern 2: Testing Multiple Constructor Overloads

```abl
@Test.
METHOD PUBLIC VOID test_Constructor_default():
    DEFINE VARIABLE oObj AS ClassName NO-UNDO.

    oObj = NEW ClassName().

    Assert:NotNull(oObj, "Default constructor should create instance").
    Assert:Equals("", oObj:PropertyName).

    FINALLY:
        DELETE OBJECT oObj NO-ERROR.
    END FINALLY.
END METHOD.

@Test.
METHOD PUBLIC VOID test_Constructor_withName():
    DEFINE VARIABLE oObj AS ClassName NO-UNDO.

    oObj = NEW ClassName("TestName").

    Assert:Equals("TestName", oObj:PropertyName).

    FINALLY:
        DELETE OBJECT oObj NO-ERROR.
    END FINALLY.
END METHOD.
```

### Pattern 3: Testing Exceptions (Try-Catch)

```abl
/*------------------------------------------------------------------------------
 Purpose: Verify method throws error for null input
 Notes:
------------------------------------------------------------------------------*/
@Test.
METHOD PUBLIC VOID test_Method_throwsErrorOnInvalidInput():
    DEFINE VARIABLE oObj AS ClassName NO-UNDO.
    DEFINE VARIABLE lErrorThrown AS LOGICAL NO-UNDO INITIAL FALSE.

    oObj = NEW ClassName().

    DO ON ERROR UNDO, LEAVE:
        oObj:ValidateInput(?).
        CATCH e AS Progress.Lang.Error:
            lErrorThrown = TRUE.
        END CATCH.
    END.

    Assert:IsTrue(lErrorThrown, "Should throw error for null input").

    FINALLY:
        DELETE OBJECT oObj NO-ERROR.
    END FINALLY.
END METHOD.
```

### Pattern 4: Testing Expected Exceptions (@Test with expected)

```abl
/*------------------------------------------------------------------------------
 Purpose: Verify method throws AppError for invalid input
 Notes:   Using @Test(expected) to assert exception is thrown
------------------------------------------------------------------------------*/
@Test(expected="Progress.Lang.AppError").
METHOD PUBLIC VOID test_Method_throwsAppErrorOnInvalidInput():
    DEFINE VARIABLE oObj AS ClassName NO-UNDO.

    oObj = NEW ClassName().

    // This should throw Progress.Lang.AppError
    oObj:ProcessInvalidData(?).

    FINALLY:
        DELETE OBJECT oObj NO-ERROR.
    END FINALLY.
END METHOD.
```

### Pattern 5: Testing with @BeforeEach and @AfterEach

```abl
DEFINE PRIVATE VARIABLE oTestInstance AS ClassName NO-UNDO.

@BeforeEach.
METHOD PUBLIC VOID setUp():
    oTestInstance = NEW ClassName().
END METHOD.

@AfterEach.
METHOD PUBLIC VOID tearDown():
    DELETE OBJECT oTestInstance NO-ERROR.
END METHOD.

@Test.
METHOD PUBLIC VOID test_Method_usesSetupInstance():
    DEFINE VARIABLE cResult AS CHARACTER NO-UNDO.

    cResult = oTestInstance:GetValue().

    Assert:NotNullOrEmpty(cResult, "Should return value").
END METHOD.

@Test.
METHOD PUBLIC VOID test_AnotherMethod_usesSetupInstance():
    oTestInstance:SetValue("TestValue").

    Assert:Equals("TestValue", oTestInstance:GetValue(), "Value should be set").
END METHOD.
```

### Pattern 6: Using @BeforeAll for Expensive Setup

```abl
DEFINE PRIVATE STATIC VARIABLE hDatabase AS HANDLE NO-UNDO.
DEFINE PRIVATE VARIABLE oTestInstance AS ClassName NO-UNDO.

@BeforeAll.
METHOD PUBLIC STATIC VOID setupDatabase():
    // Expensive operation - runs once before all tests
    CONNECT VALUE("sports2020") NO-ERROR.
    hDatabase = LAST-EVENT:SELF.
END METHOD.

@AfterAll.
METHOD PUBLIC STATIC VOID cleanupDatabase():
    // Runs once after all tests complete
    DISCONNECT VALUE("sports2020") NO-ERROR.
END METHOD.

@BeforeEach.
METHOD PUBLIC VOID setUp():
    // Runs before each test
    oTestInstance = NEW ClassName().
END METHOD.

@AfterEach.
METHOD PUBLIC VOID tearDown():
    // Runs after each test
    DELETE OBJECT oTestInstance NO-ERROR.
END METHOD.
```

**Continued in `code-examples-advanced.md`:** Pattern 7 (database operations with test data), Pattern 8 (transaction rollback), Pattern 9 (edge cases), Pattern 10 (state changes), Pattern 11 (multiple assertions), test method naming conventions, and the Arrange-Act-Assert pattern.
