# Database Safety Strategies for ABLUnit Tests

**⚠️ CRITICAL: Never create tests that modify real production data**

When testing methods that create, update, or delete database records, you MUST discuss safety strategies with the user.

## Database Risk Assessment

Ask the user these questions if testing methods that perform database operations:

1. **Does this method create/update/delete database records?**
2. **Which database tables are affected?**
3. **What safety strategy should we use?**

## Safety Strategies

### Strategy 1: Test Data with Identifiable Keys (Recommended)

Use test data with identifiers outside the normal production range that can be easily cleaned up.

**Example from test_BC_Customer.cls:**
```abl
@Test.
METHOD PUBLIC VOID test_add():
    CREATE ttCustomer.
    ASSIGN
        ttCustomer.custNum = 9888  // Test outside range of real customers
        ttCustomer.name = "Southwell Sports"
        ttCustomer.Comments = "Test record".

    oCust:AddData(DATASET-HANDLE hBoundDS).

    FINALLY:
        hBoundDS:EMPTY-DATASET().
    END FINALLY.
END METHOD.

@Test.
METHOD PUBLIC VOID test_update():
    oCust:GetOne(9888, OUTPUT hBoundDS). // Use same test customer
    FIND FIRST ttCustomer.
    ttCustomer.Contact = "Updated Name".
    oCust:SetData("defaultView", DATASET-HANDLE hBoundDS).
END METHOD.

@Test.
METHOD PUBLIC VOID test_delete():
    oCust:GetOne(9888, OUTPUT hBoundDS). // Clean up test customer
    oCust:DeleteData(DATASET-HANDLE hBoundDS).
END METHOD.
```

**Best practices:**
- Use key values outside production range (e.g., 9000-9999 for customer IDs)
- Add comments identifying the values as test data
- Create test data in one test, use it in subsequent tests, delete in final test
- Consider using @BeforeAll to create shared test data

### Strategy 2: Transaction Wrapping with UNDO

Wrap database-modifying tests in transactions and undo them after verification.

**Example:**
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

        // Verify creation
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

**Limitations:**
- Not suitable for testing transaction logic itself
- May not work with methods that commit internally
- Can mask real-world transaction issues

### Strategy 3: Dedicated Test Database

Run tests against a separate test database that can be reset.

**Best practices:**
- Configure test database connection in ablunit.json or dbconn.pf
- Document which database tests run against
- Ensure test database has representative data
- Consider periodic database resets/refreshes

**Configuration example (ablunit.json):**
```json
{
  "options": {
    "dbConnections": [{
      "name": "testdb",
      "connect": "-db testdb -H localhost -S 9201"
    }]
  }
}
```

### Strategy 4: Mock Objects (No Database)

For unit tests, mock database operations entirely to avoid database dependency.

**When to use:**
- Testing business logic that doesn't require actual database validation
- Fast-running tests that don't need database connection
- CI/CD environments where database may not be available
- Isolating units of code from external dependencies

**Considerations:**
- Requires mock/stub infrastructure
- May not catch integration issues
- Best for pure unit tests

## User Consultation Protocol

Before creating tests that modify database records:

### 1. Ask the user explicitly

"This method modifies the [TableName] table. Which safety strategy would you like to use?"
- Test data with specific identifiers (Strategy 1) - **Recommended**
- Transaction wrapping with UNDO (Strategy 2)
- Dedicated test database (Strategy 3)
- Mock objects (Strategy 4)

### 2. If using test data identifiers, ask:

- "What key value range is safe for test data?" (e.g., "Use IDs 9000-9999")
- "Should I create cleanup tests to delete test data?"
- "Should cleanup happen in @AfterAll or in individual delete tests?"

### 3. Document the strategy

- Add comments explaining the safety approach
- Document test data ranges in test file header Notes section
- Include cleanup responsibilities

## Example Consultation

**User wants to test:** `src/BusinessCrud/Customer.cls` (AddData, SetData, DeleteData methods)

**Question:** "These methods modify the Customer database table. Which safety strategy would you like to use? I recommend Strategy 1 (test data with identifiable keys) using customer numbers outside your production range."

**User response:** "Use customer numbers 9000-9999 for test data."

**Action:** Create tests using custNum 9888, 9889, etc. with cleanup in final test or @AfterAll.

**Documentation in test header:**
```abl
/*------------------------------------------------------------------------
    File        : test_BC_Customer
    Purpose     : Unit tests for BC_Customer class
    Syntax      :
    Description : Tests CRUD operations using test data
    Author(s)   :
    Created     : Mon Feb 10 2026
    Notes       : Uses customer numbers 9000-9999 for test data.
                  Tests create, modify, and delete test records.
  ----------------------------------------------------------------------*/
```

## Best Practices Summary

1. **Always assess database impact** before creating tests
2. **Consult user** on safety strategy for any database-modifying tests
3. **Use identifiable test data** (Strategy 1) when possible
4. **Document the approach** in test file header
5. **Add comments** identifying test data values
6. **Include cleanup** to remove test data after tests run
7. **Never assume** - always get user confirmation on key ranges and strategy
