# ABLUnit Test Code Examples — Database, Edge Cases & Conventions

Continuation of `code-examples.md`: database patterns, edge cases, state changes, naming conventions, and the Arrange-Act-Assert pattern.

### Pattern 7: Testing Database Operations with Test Data

```abl
/*------------------------------------------------------------------------------
 Purpose: Test adding a customer using test data outside production range
 Notes:   Uses customer number 9888 for test data
------------------------------------------------------------------------------*/
@Test.
METHOD PUBLIC VOID test_AddCustomer_testData():
    CREATE ttCustomer.
    ASSIGN
        ttCustomer.custNum = 9888  // Test outside range of real customers
        ttCustomer.name = "Test Customer"
        ttCustomer.Comments = "Test record".

    oCust:AddData(DATASET-HANDLE hBoundDS).

    Assert:Equals("ADDED", ttCustomer.ttOpResult).

    FINALLY:
        hBoundDS:EMPTY-DATASET().
    END FINALLY.
END METHOD.
```

### Pattern 8: Testing with Transaction Rollback

```abl
@Test.
METHOD PUBLIC VOID test_CreateCustomer_rollback():
    DEFINE VARIABLE lSuccess AS LOGICAL NO-UNDO.

    DO TRANSACTION ON ERROR UNDO, LEAVE:
        // Create test data
        CREATE Customer.
        ASSIGN
            Customer.CustNum = 9999
            Customer.Name = "Test Customer".

        // Verify creation within transaction
        lSuccess = CAN-FIND(FIRST Customer WHERE Customer.CustNum = 9999).
        Assert:IsTrue(lSuccess, "Customer should be created").

        // Force rollback
        UNDO, LEAVE.
    END.

    // Verify rollback - customer should not exist
    lSuccess = CAN-FIND(FIRST Customer WHERE Customer.CustNum = 9999).
    Assert:IsFalse(lSuccess, "Customer should be rolled back").
END METHOD.
```

### Pattern 9: Testing Edge Cases

```abl
@Test.
METHOD PUBLIC VOID test_Calculate_zeroInput():
    DEFINE VARIABLE dResult AS DECIMAL NO-UNDO.

    dResult = oCalculator:Calculate(0, 10).

    Assert:Equals(0, dResult).
END METHOD.

@Test.
METHOD PUBLIC VOID test_Calculate_negativeInput():
    DEFINE VARIABLE dResult AS DECIMAL NO-UNDO.

    dResult = oCalculator:Calculate(-5, 10).

    Assert:IsTrue(dResult < 0, "Negative input should return negative result").
END METHOD.

@Test.
METHOD PUBLIC VOID test_Calculate_nullInput():
    DEFINE VARIABLE dResult AS DECIMAL NO-UNDO.

    dResult = oCalculator:Calculate(?, 10).

    Assert:Equals(0, dResult).
END METHOD.
```

### Pattern 10: Testing State Changes

```abl
@Test.
METHOD PUBLIC VOID test_SetName_updatesProperty():
    DEFINE VARIABLE oObj AS ClassName NO-UNDO.

    oObj = NEW ClassName().

    // Verify initial state
    Assert:Equals("", oObj:Name).

    // Change state
    oObj:SetName("NewName").

    // Verify state change
    Assert:Equals("NewName", oObj:Name).

    FINALLY:
        DELETE OBJECT oObj NO-ERROR.
    END FINALLY.
END METHOD.
```

### Pattern 11: Multiple Assertions in One Test (When Appropriate)

```abl
/*------------------------------------------------------------------------------
 Purpose: Verify object initialization sets all required properties
 Notes:   Multiple related assertions are acceptable for initialization testing
------------------------------------------------------------------------------*/
@Test.
METHOD PUBLIC VOID test_Init_setsRequiredProperties():
    DEFINE VARIABLE oObj AS ClassName NO-UNDO.

    oObj = NEW ClassName("Name", 123, TRUE).

    Assert:NotNull(oObj, "Object should be created").
    Assert:Equals("Name", oObj:Name).
    Assert:Equals(123, oObj:Value).
    Assert:IsTrue(oObj:IsActive, "IsActive should be true").

    FINALLY:
        DELETE OBJECT oObj NO-ERROR.
    END FINALLY.
END METHOD.
```

## Test Method Naming Conventions

Good test names clearly communicate what is being tested:

```abl
// Pattern: test_MethodName_scenario

test_ValidateInput_validData()
test_ValidateInput_nullInput()
test_ValidateInput_emptyString()
test_ValidateInput_throwsError()

test_Constructor_withDefaultParams()
test_Constructor_withAllParams()
test_Constructor_throwsErrorOnInvalidParam()

test_Calculate_positiveNumbers()
test_Calculate_negativeNumbers()
test_Calculate_zeroInput()
test_Calculate_largeNumbers()
```

## Arrange-Act-Assert Pattern

Use clear sections in your test methods:

```abl
@Test.
METHOD PUBLIC VOID test_Calculate_withValidInputs():
    DEFINE VARIABLE dResult AS DECIMAL NO-UNDO.
    DEFINE VARIABLE oCalc AS Calculator NO-UNDO.

    // Arrange - setup test data
    oCalc = NEW Calculator().

    // Act - execute the method being tested
    dResult = oCalc:Calculate(10, 5).

    // Assert - verify expected results
    Assert:Equals(15, dResult).

    FINALLY:
        DELETE OBJECT oCalc NO-ERROR.
    END FINALLY.
END METHOD.
```
