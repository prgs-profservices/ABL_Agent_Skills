# OpenEdge ABL Coding Standards

## Class and File Naming

### Rule: Class name case must match file name case
**Severity**: Critical
**Applies to**: .cls files

The class name case must exactly match the file name case to avoid compilation problems on UNIX/Linux systems.

**Bad:**
```abl
// File: ExampleClass.cls
PUBLIC CLASS exampleclass:
END CLASS.
```

**Good:**
```abl
// File: ExampleClass.cls
PUBLIC CLASS ExampleClass:
END CLASS.
```

## File Header Comments

### Rule: All ABL source files must have complete header comments
**Severity**: Suggestion
**Applies to**: .cls, .i, .p, .w files

All class files must include a header comment block with:
- File name (which must match the name on disk)
- Purpose
- Description
- Author(s)
- Created date
- Notes section
- History section

**Example:**
```abl
/*------------------------------------------------------------------------
   File        : CustomerService.cls
   Purpose     : Business logic for customer management
   Description : Handles customer CRUD operations and validation
   Author(s)   : John Doe
   Created     : Mon Feb 03 2026
   Notes       :
   History     : 2026-02-03  John Doe - Initial creation
 ----------------------------------------------------------------------*/
```

### Rule: Update History section when modifying files
**Severity**: Critical
**Applies to**: .cls, .p files

Whenever a file is edited, add an entry to the History section with:
- Date (YYYY-MM-DD format)
- Author name
- Brief description of changes

Multiple changes on the same date can be listed under the same date entry.

## Variable Declarations

### Rule: Use modern VAR syntax
**Severity**: Warning
**Applies to**: All files

Use `VAR` instead of `DEFINE VARIABLE` for variable declarations unless the variable is undoable.

**Bad:**
```abl
DEFINE VARIABLE cName AS CHARACTER NO-UNDO.
DEFINE VARIABLE iCount AS INTEGER NO-UNDO.
```

**Good:**
```abl
VAR CHAR cName.
VAR INT iCount.
```

### Rule: Use CHAR and INT synonyms
**Severity**: Suggestion
**Applies to**: All files

Prefer `CHAR` and `INT` over `CHARACTER` and `INTEGER` for brevity.

### Rule: Consolidate variables of the same type
**Severity**: Suggestion
**Applies to**: All files

Variables of the same type can be declared together with commas.

**Example:**
```abl
VAR INT iCount, iTotal, iMax.
VAR CHAR cName, cStatus.
```

### Rule: Avoid unnecessary variable initialization
**Severity**: Suggestion
**Applies to**: All files

Don't initialize variables to their default values unless necessary:
- CHARACTER defaults to "" (empty string)
- INTEGER/DECIMAL default to 0
- LOGICAL defaults to false
- DATE/DATETIME default to ?

### Rule: Remove unused variables
**Severity**: Warning
**Applies to**: All files

Remove variable declarations that are never used. Unused variables add clutter, can confuse readers, and often indicate incomplete refactoring.

**Bad:**
```abl
METHOD PUBLIC VOID ProcessData():
    VAR INT iCount, iTotal, iUnused.

    iCount = 5.
    iTotal = iCount * 2.
    // iUnused is never used
END METHOD.
```

**Good:**
```abl
METHOD PUBLIC VOID ProcessData():
    VAR INT iCount, iTotal.

    iCount = 5.
    iTotal = iCount * 2.
END METHOD.
```

**Note:** This is especially common after refactoring code to use early returns instead of result variables.

## Property Definitions

### Rule: Don't use PROTECTED SET on PROTECTED PROPERTY
**Severity**: Warning
**Applies to**: .cls files

When a property is PROTECTED, the setter is automatically protected.

**Bad:**
```abl
DEFINE PROTECTED PROPERTY Name AS CHARACTER NO-UNDO
    GET.
    PROTECTED SET.
```

**Good:**
```abl
DEFINE PROTECTED PROPERTY Name AS CHARACTER NO-UNDO GET. SET.
```

### Rule: Keep empty getters/setters on same line
**Severity**: Suggestion
**Applies to**: .cls files

When getters and setters have no logic, keep them on the same line as the property definition.

## Class Organization

### Rule: Constructors before methods
**Severity**: Warning
**Applies to**: .cls files

All constructors must be placed before methods in a class.

### Rule: Order constructors by parameter count
**Severity**: Suggestion
**Applies to**: .cls files

Order constructors from shortest (fewest parameters) to longest (most parameters).

### Rule: Init() method placement
**Severity**: Suggestion
**Applies to**: .cls files

If a class has an Init() method, place it immediately after constructors and destructors.

## Method Documentation

### Rule: Section comments for all methods and constructors
**Severity**: Warning
**Applies to**: .cls files

All methods and constructors must have section comment blocks.

**Example:**
```abl
/*------------------------------------------------------------------------------
 Purpose: Calculate total price including tax
 Notes:   Tax rate is retrieved from system configuration
 @param iQuantity Number of items
 @param dUnitPrice Price per item
 @return Total price with tax
------------------------------------------------------------------------------*/
METHOD PUBLIC DECIMAL CalculateTotal(
    INPUT iQuantity AS INTEGER,
    INPUT dUnitPrice AS DECIMAL):
    // implementation
END METHOD.
```

### Rule: Multi-line parameter formatting
**Severity**: Suggestion
**Applies to**: All files

When methods or constructors have multiple INPUT/OUTPUT parameters, break them onto separate lines and indent.

## Code Structure

### Rule: Single-statement IF blocks
**Severity**: Suggestion
**Applies to**: All files

Don't use DO...END blocks for single statements after IF/THEN or ELSE.

**Bad:**
```abl
IF iCount > 0 THEN DO:
    cStatus = "active".
END.
```

**Good:**
```abl
IF iCount > 0 THEN
    cStatus = "active".
```

### Rule: Guard clauses for early exit
**Severity**: Suggestion
**Applies to**: All files

Use guard clauses (early exit pattern) to reduce nesting when appropriate.

**Example:**
```abl
// Instead of:
IF condition THEN DO:
    // 20 lines of code
END.

// Use:
IF NOT condition THEN RETURN.
// 20 lines of code without nesting
```

**Specific Case - Function/Method/Procedure-wide conditional:**
When an entire function, method, or procedure body (or most of it) is wrapped in a single IF...THEN DO block with no ELSE clause, invert the condition and return/exit early instead.

```abl
// Method example - Instead of:
METHOD PUBLIC DATETIME-TZ ProcessData(INPUT cInput AS CHAR):
    VAR DATETIME-TZ result.
    IF cInput MATCHES "valid-pattern*" THEN DO:
        // 50 lines of processing
        result = /* calculated value */.
    END.
    RETURN result.
END METHOD.

// Use:
METHOD PUBLIC DATETIME-TZ ProcessData(INPUT cInput AS CHAR):
    VAR DATETIME-TZ result.
    IF NOT cInput MATCHES "valid-pattern*" THEN
        RETURN ?.
    // 50 lines of processing without nesting
    result = /* calculated value */.
    RETURN result.
END METHOD.

// Function example - Instead of:
FUNCTION CalculateTotal RETURNS DECIMAL (INPUT iQty AS INT):
    DEFINE VARIABLE dTotal AS DECIMAL NO-UNDO.
    IF iQty > 0 THEN DO:
        // calculation logic
        dTotal = iQty * unitPrice.
    END.
    RETURN dTotal.
END FUNCTION.

// Use:
FUNCTION CalculateTotal RETURNS DECIMAL (INPUT iQty AS INT):
    DEFINE VARIABLE dTotal AS DECIMAL NO-UNDO.
    IF iQty <= 0 THEN
        RETURN 0.
    // calculation logic without nesting
    dTotal = iQty * unitPrice.
    RETURN dTotal.
END FUNCTION.
```

**Caution**: Only use when the early exit doesn't skip subsequent logic that should execute.

### Rule: Remove unnecessary nested DO blocks
**Severity**: Suggestion
**Applies to**: All files

When IF contains only a DO block with a single statement (like a loop), remove the outer DO.

**Bad:**
```abl
IF condition THEN DO:
    DO i = 1 TO 10:
        // code
    END.
END.
```

**Good:**
```abl
IF condition THEN
    DO i = 1 TO 10:
        // code
    END.
```

### Rule: Combine multiple assignments with ASSIGN
**Severity**: Suggestion
**Applies to**: All files

Use ASSIGN statement to group multiple variable assignments, especially in IF/THEN/ELSE.

**Bad:**
```abl
ELSE DO:
    var1 = value1.
    var2 = value2.
    var3 = value3.
END.
```

**Good:**
```abl
ELSE ASSIGN
    var1 = value1
    var2 = value2
    var3 = value3.
```

### Rule: CASE statements should have OTHERWISE clause
**Severity**: Suggestion
**Applies to**: All files

CASE statements should include an OTHERWISE clause to handle unexpected or default situations, improving code robustness and clarity.

**Bad:**
```abl
CASE cStatus:
    WHEN "active" THEN
        ProcessActive().
    WHEN "pending" THEN
        ProcessPending().
END CASE.
```

**Good:**
```abl
CASE cStatus:
    WHEN "active" THEN
        ProcessActive().
    WHEN "pending" THEN
        ProcessPending().
    OTHERWISE
        LogUnexpectedStatus(cStatus).
END CASE.
```

## General Best Practices

### Rule: Avoid abbreviating ABL syntax
**Severity**: Warning
**Applies to**: All files

Don't abbreviate ABL keywords. Use full keywords or approved alternate syntax.

**Bad:**
```abl
DEF VAR x AS INT NO-UNDO.
```

**Good:**
```abl
VAR INT x.
```

### Rule: Meaningful variable and method names
**Severity**: Warning
**Applies to**: All files

Use descriptive names that convey purpose. Avoid single-letter variables except for loop counters.

### Rule: Consistent indentation
**Severity**: Suggestion
**Applies to**: All files

Use consistent indentation (typically 4 spaces or 1 tab) throughout the file.
