## Critical & Blocker Rules

### Rule: Sorting with FIRST/LAST
**Severity**: Critical
**Applies to**: All files

`FOR FIRST` and `FOR LAST` select records based on the index, ignoring any `BY` clause.

**Bad:**
```abl
FOR FIRST Order WHERE Order.Status = 'Shipped' BY Order.Date.
  DISPLAY OrderNum Date.
```

**Good:**
```abl
FOR EACH Order WHERE Order.Status = 'Shipped' BY Order.Date:
  DISPLAY OrderNum Date.
  LEAVE.
END.
```

### Rule: Indentation Irregularity
**Severity**: Critical
**Applies to**: All files

Inconsistent indentation makes code hard to read and may hide logic errors.


### Rule: Implicit WHERE on Primary Key
**Severity**: Critical
**Applies to**: All files

Use a full `WHERE` clause instead of passing a value directly to `FIND`.

**Bad:**
```abl
find Order 1024.
```

**Good:**
```abl
find Order where Order.OrderNum = 1024.
```

### Rule: Ignored Exception
**Severity**: Critical
**Applies to**: All files

A `CATCH` block that defines a variable but never references it implies the error is being ignored.

**Bad:**
```abl
CATCH e AS Progress.Lang.Error:
  DISPLAY "An error occurred".  // 'e' is not used
END CATCH.
```

**Good:**
```abl
CATCH eIgnored AS Progress.Lang.Error:
  DISPLAY "An error occurred".
END CATCH.
```

### Rule: Ambiguous UNDO Action
**Severity**: Critical
**Applies to**: All files

`UNDO` without a directive (like `LEAVE` or `NEXT`) defaults to `RETRY`, often causing infinite loops.

**Bad:**
```abl
BlockA:
DO WHILE lCondition:
  UNDO BlockA.
END.
```

**Good:**
```abl
BlockA:
DO WHILE lCondition:
  UNDO, RETRY BlockA.
END.
```

### Rule: Usage of Shared Variables
**Severity**: Critical
**Applies to**: All files

Shared variables introduce tight coupling and should be avoided.


### Rule: Non-Serializable Error Class
**Severity**: Critical
**Applies to**: .cls files

Classes inheriting from `Progress.Lang.AppError` must be `serializable` for AppServer compatibility.

**Bad:**
```abl
class MyApp.Errors.CustomError inherits AppError:
end class.
```

**Good:**
```abl
class MyApp.Errors.CustomError inherits AppError serializable:
end class.
```

### Rule: Sort-Access with Whole-Index
**Severity**: Blocker
**Applies to**: All files

Combining `SORT-ACCESS` with `WHOLE-INDEX` results in extremely poor performance.


### Rule: Deprecated RECID Usage
**Severity**: Blocker
**Applies to**: All files

Use `ROWID` instead of `RECID`. `RECID` is deprecated and has 32-bit limitations.

**Bad:**
```abl
DEFINE VARIABLE rId AS RECID.
ASSIGN rId = RECID(Customer).
```

**Good:**
```abl
DEFINE VARIABLE rId AS ROWID.
ASSIGN rId = ROWID(Customer).
```

### Rule: Unintentional Double Periods
**Severity**: Critical
**Applies to**: All files

Double periods often occur as typos and result in empty statements.

**Bad:**
```abl
define variable iCount as integer no-undo..
```

**Good:**
```abl
define variable iCount as integer no-undo.
```

### Rule: Conditional Assignment Logic
**Severity**: Blocker
**Applies to**: All files

In an `ASSIGN` statement, `WHEN` conditions are evaluated before any assignments take place.

**Bad:**
```abl
assign
  cStatus = "Active" when cType = "New"
  cColor  = "Green"  when cStatus = "Active".  // cStatus is checked before it is updated!
```

**Good:**
```abl
assign cStatus = "Active" when cType = "New".
assign cColor  = "Green"  when cStatus = "Active".
```

### Rule: Include File Case Mismatch
**Severity**: Critical
**Applies to**: All files

References to include files must match the casing of the actual file on disk.


### Rule: Class/Filename Case Mismatch
**Severity**: Critical
**Applies to**: .cls files

Class names must match their filenames exactly (case-sensitive) to ensure compatibility with Unix/Linux systems.

**Bad:**
```abl
// File: AccountManager.cls
PUBLIC CLASS accountmanager:
END CLASS.
```

**Good:**
```abl
// File: AccountManager.cls
PUBLIC CLASS AccountManager:
END CLASS.
```

### Rule: Unreleased Dynamic Objects
**Severity**: Blocker
**Applies to**: All files

Always delete dynamic objects (queries, buffers) to prevent memory leaks.

**Good:**
```abl
finally:
  if valid-handle(hBuf) then delete object hBuf.
  if valid-handle(hQry) then delete object hQry.
end finally.
```

### Rule: Reusing Loop Variable
**Severity**: Critical
**Applies to**: All files

Do not use the same loop control variable in nested loops.

**Bad:**
```abl
do i = 1 to 5:
  do i = 1 to 5:  // Conflict
  end.
end.
```

### Rule: No-Op Expression
**Severity**: Critical
**Applies to**: All files

Statements that compute a value but don't assign or use it are redundant.

**Bad:**
```abl
iTotal + iTotal + 1.  // Likely meant: iTotal = iTotal + 1
```

### Rule: Incorrect Brace Escape
**Severity**: Critical
**Applies to**: All files

Use the tilde `~` to escape curly braces. Backslashes are not portable across operating systems.

**Bad:**
```abl
DISPLAY "Value: \{ value".
```

**Good:**
```abl
DISPLAY "Value: ~{ value".
```

### Rule: Period at Start of Line
**Severity**: Blocker
**Applies to**: All files

Lines starting with a period are treated as comments but are not highlighted as such by editors, leading to confusion.

**Bad:**
```abl
.MESSAGE "System check".
```

**Good:**
```abl
// MESSAGE "System check".
```

## Major Rules

### Rule: Unprotected FIND
**Severity**: Major
**Applies to**: All files

`FIND` without `NO-ERROR` will terminate the procedure if no record is found.

**Bad:**
```abl
FIND FIRST Order NO-LOCK.
```

**Good:**
```abl
FIND FIRST Order NO-LOCK NO-ERROR.
```

### Rule: Invalid USE-INDEX Name
**Severity**: Major
**Applies to**: All files

If `USE-INDEX` specifies a non-existent index, it is ignored without warning.


### Rule: Dead Code (Comments)
**Severity**: Major
**Applies to**: All files

Remove commented-out code. Use source control history if you need to restore it.

### Rule: OF Keyword Usage
**Severity**: Major
**Applies to**: All files

Use explicit `WHERE` clauses instead of `OF` for better clarity.

**Bad:**
```abl
FOR EACH Header, EACH Detail OF Header:
END.
```

**Good:**
```abl
FOR EACH Header, EACH Detail WHERE Detail.HeadID = Header.HeadID:
END.
```

### Rule: WHERE Clause with TABLE-SCAN
**Severity**: Major
**Applies to**: All files

Using `WHERE` with `TABLE-SCAN` disables index usage for the filter.


### Rule: Missing NO-UNDO
**Severity**: Major
**Applies to**: All files

Define variables with `NO-UNDO` to avoid transaction overhead.

**Bad:**
```abl
DEFINE VARIABLE cName AS CHARACTER.
```

**Good:**
```abl
DEFINE VARIABLE cName AS CHARACTER NO-UNDO.
```

### Rule: Structured Error Handling vs NO-ERROR
**Severity**: Major
**Applies to**: All files

Use `CATCH` blocks instead of `NO-ERROR` and `ERROR-STATUS` checks.

**Bad:**
```abl
ASSIGN iVal = INTEGER(cInput) NO-ERROR.
IF ERROR-STATUS:ERROR THEN ...
```

**Good:**
```abl
DO ON ERROR UNDO, RETURN:
  ASSIGN iVal = INTEGER(cInput).
  CATCH e AS Progress.Lang.Error:
    ...
  END CATCH.
END.
```

### Rule: Implicit Share Lock
**Severity**: Major
**Applies to**: All files

Explicitly specify `NO-LOCK` or `EXCLUSIVE-LOCK`. Default share locks can cause contention.

**Bad:**
```abl
FOR EACH Item:
  DISPLAY Item.
END.
```

**Good:**
```abl
FOR EACH Item NO-LOCK:
  DISPLAY Item.
END.
```

### Rule: Hardcoded Index Selection
**Severity**: Major
**Applies to**: All files

Avoid `USE-INDEX`. Trust the ABL optimizer to pick the best index.


### Rule: Excessive Parameter Count
**Severity**: Major
**Applies to**: All files

Keep parameter lists short (max 8) to maintain readability and maintainability.


### Rule: Unreferenced Buffer
**Severity**: Major
**Applies to**: All files

Remove unused buffer definitions.


### Rule: Forced Full Table Scan
**Severity**: Major
**Applies to**: All files

`WHOLE-INDEX` forces a full table scan, bypassing optimizations.


### Rule: Unused Method/Procedure Parameter
**Severity**: Major
**Applies to**: All files

Remove parameters that are defined but never used.


## Performance Rules

### Rule: Functions in WHERE Clauses
**Severity**: Critical
**Applies to**: All files

Functions in `WHERE` clauses prevent index usage and force client-side filtering.


### Rule: Function Calls in Loops
**Severity**: Minor
**Applies to**: All files

Calculate loop limits before the loop, not in the condition.

**Bad:**
```abl
do i = 1 to CalculateLimit():
end.
```

**Good:**
```abl
assign iLimit = CalculateLimit().
do i = 1 to iLimit:
end.
```

### Rule: Non-Blocking Locks
**Severity**: Info
**Applies to**: All files

Use `NO-WAIT` with `EXCLUSIVE-LOCK` to avoid indefinite hanging.

**Good:**
```abl
FIND FIRST Account EXCLUSIVE-LOCK NO-WAIT.
IF AVAILABLE Account THEN ...
ELSE IF LOCKED Account THEN ...
```

## Code Quality Rules

### Rule: Nested Comment Blocks
**Severity**: Info
**Applies to**: All files

Nested comments are confusing and should be avoided.


### Rule: Unassigned Named Arguments
**Severity**: Critical
**Applies to**: All files

Named parameters in include files must have a value.

**Bad:**
```abl
{ defs.i &Mode &Level=1 }
```

**Good:**
```abl
{ defs.i &Mode="Verbose" &Level=1 }
```

### Rule: FIELDS Option Deprecated
**Severity**: Info
**Applies to**: All files

The `FIELDS()` option is largely ineffective in modern OpenEdge versions.


### Rule: Informative RETURN ERROR
**Severity**: Info
**Applies to**: All files

Provide a message string when using `RETURN ERROR`.

**Bad:**
```abl
RETURN ERROR.
```

**Good:**
```abl
RETURN ERROR "Invalid configuration detected".
```

### Rule: Missing Return Statement
**Severity**: Info
**Applies to**: All files

Functions and methods must explicitly return a value.

**Good:**
```abl
FUNCTION GetStatus RETURNS CHARACTER:
  RETURN "Active".
END FUNCTION.
```

### Rule: Labeled Blocks
**Severity**: Minor
**Applies to**: All files

Use labels for blocks and reference them in `NEXT`/`LEAVE` for clarity.

**Good:**
```abl
blkMain:
FOR EACH Parent:
  FOR EACH Child:
    IF Child.Status = 'Pending' THEN NEXT blkMain.
  END.
END.
```

### Rule: Trigger Disabling
**Severity**: Info
**Applies to**: All files

Avoid using `DISABLE TRIGGERS` in application code.


## Portability Rules

### Rule: Unix Path Separators
**Severity**: Info
**Applies to**: All files

Use tildes `~` to escape characters for OS portability.

**Bad:**
```abl
DISPLAY "Path \\ to \\ file".
```

**Good:**
```abl
DISPLAY "Path ~\ to ~\ file".
```

## Convention Rules

### Rule: Global Shared Scope
**Severity**: Critical
**Applies to**: All files

Avoid `GLOBAL SHARED` variables.


### Rule: On-the-fly Sorting
**Severity**: Info
**Applies to**: All files

`BY` without an index triggers a database sort.


### Rule: OS-COMMAND Quoting
**Severity**: Info
**Applies to**: All files

Quote parameters passed to `OS-COMMAND`.


### Rule: Left-Side Buffer Reference
**Severity**: Critical - Beta
**Applies to**: All files

In `WHERE` clauses, the filtered field should be on the left.

**Good:**
```abl
for each Order where Order.CustNum = iCustomer:
end.
```

### Rule: Translatable List Splitting
**Severity**: Major
**Applies to**: All files

Split comma-separated lists for translation.


### Rule: Quoted String Attributes
**Severity**: Minor
**Applies to**: All files

Use string attributes like `:U` (Untranslatable) or `:L` (Label).

**Bad:**
```abl
cStr = "fixed value".
```

**Good:**
```abl
cStr = "fixed value":U.
```

### Rule: SUBSTITUTE Type Mismatch
**Severity**: Major
**Applies to**: All files

Avoid mixing `CHARACTER` and `LONGCHAR` in `SUBSTITUTE`.


### Rule: Overflow Risk
**Severity**: Major
**Applies to**: All files

Check for potential overflows (e.g., `INT64` to `INTEGER`).

**Bad:**
```abl
def var iSmall as int.
def var iLarge as int64.
iSmall = iLarge.
```

### Rule: Explicit Index Sort Direction
**Severity**: Minor
**Applies to**: All files

Specify `ASCENDING` or `DESCENDING` in temp-table index definitions.

**Good:**
```abl
define temp-table ttData
  field cId as char
  index idx1 is unique cId ascending.
```

### Rule: Case Annotations
**Severity**: Info
**Applies to**: All files

Use annotations like `@LowerCase` to enforce casing conventions.


### Rule: Unary Plus Usage
**Severity**: Info
**Applies to**: All files

The unary `+` operator is unnecessary.

**Bad:**
```abl
iVal =+ 5.
```

### Rule: Deprecated DOS Command
**Severity**: Minor
**Applies to**: All files

Use `OS-COMMAND` instead of `DOS`.


### Rule: Full Keyword Usage
**Severity**: Info
**Applies to**: All files

Write keywords in full. Do not abbreviate.

**Bad:**
```abl
MSG "Hello".
```

**Good:**
```abl
MESSAGE "Hello".
```

### Rule: Immutable WHERE Variables
**Severity**: Major
**Applies to**: All files

Modifying a variable used in an active `WHERE` clause does not affect the query.

**Bad:**
```abl
def var iMax as int init 10.
for each Item where Item.Val < iMax:
  iMax = iMax + 10. // Query ignores this update
end.
```

### Rule: SUBSTITUTE Placeholder Mismatch
**Severity**: Info
**Applies to**: All files

Argument count must match placeholders.

**Bad:**
```abl
message substitute("A: &1, B: &2", "A only").
```

### Rule: Length Function Unit
**Severity**: Major
**Applies to**: All files

Specify the unit for `LENGTH`, `SUBSTRING`, `OVERLAY`.

**Bad:**
```abl
iLen = LENGTH(cData).
```

**Good:**
```abl
iLen = LENGTH(cData, "CHARACTER").
```

### Rule: Specific Imports
**Severity**: Minor
**Applies to**: All files

Avoid wildcard imports (`USING package.*`). Import specific types.

**Bad:**
```abl
USING OpenEdge.Core.*.
```

**Good:**
```abl
USING OpenEdge.Core.String.
```

### Rule: Regex Comment Tracker
**Severity**: Info - Template
**Applies to**: All files

Track comments matching specific patterns.


### Rule: Uninitialized Read Variable
**Severity**: Major
**Applies to**: All files

A variable is read but never initialized.


### Rule: Parenthesized Conditions
**Severity**: Minor
**Applies to**: All files

Wrap embedded `IF` expressions in parentheses.

**Good:**
```abl
message ( if lValid then "Yes" else "No" ).
```

### Rule: Naming Conventions
**Severity**: Minor
**Applies to**: All files

Follow standard casing (PascalCase/camelCase).


### Rule: Trim Attribute
**Severity**: Minor
**Applies to**: All files

The `:T` attribute trims whitespace from strings.

**Bad:**
```abl
MESSAGE "  Data":T.
```

**Good:**
```abl
MESSAGE "Data":T.
```

### Rule: Auto-Implemented Properties
**Severity**: Minor
**Applies to**: All files

Use concise property syntax where possible.

**Bad:**
```abl
property Name as char
  get: return Name. end.
```

**Good:**
```abl
property Name as char get. set.
```

### Rule: Client-Side CAN-DO
**Severity**: Major
**Applies to**: All files

`CAN-DO` forces client-side evaluation.


### Rule: Space Indentation
**Severity**: Info
**Applies to**: All files

Use spaces for indentation, not tabs.


### Rule: Alphanumeric Identifiers
**Severity**: Minor
**Applies to**: All files

Identifiers should contain only alphanumeric characters.

**Bad:**
```abl
PROCEDURE calc_value$:
```

**Good:**
```abl
PROCEDURE CalcValue:
```

### Rule: Unique Index vs FIRST
**Severity**: Minor
**Applies to**: All files

Do not use `FIRST` or `LAST` if the index is unique.

**Bad:**
```abl
FIND FIRST User WHERE UserID = 'admin'.
```

**Good:**
```abl
FIND User WHERE UserID = 'admin'.
```

## Security Rules

### Rule: Dynamic Call Injection
**Severity**: Critical - Security Hotspot
**Applies to**: All files

Validate `DYNAMIC-CALL` targets.


### Rule: Production DEBUGGER
**Severity**: Minor - Vulnerability
**Applies to**: All files

Remove `DEBUGGER` code from production.


### Rule: Redirection Vulnerability
**Severity**: Critical - Security Hotspot
**Applies to**: All files

Sanitize inputs in HTTP Location headers.


### Rule: External Calls
**Severity**: Critical - Security Hotspot
**Applies to**: All files

Audit `PROCEDURE EXTERNAL` calls.


### Rule: PROPATH Manipulation
**Severity**: Info - Security Hotspot
**Applies to**: All files

Runtime `PROPATH` changes are risky.


### Rule: AppServer Export Exposure
**Severity**: Critical - Security Hotspot
**Applies to**: All files

Be careful with `SESSION:EXPORT`.


### Rule: Dynamic Query Injection Risk
**Severity**: Minor - Security Hotspot
**Applies to**: All files

Sanitize inputs in dynamic queries.

**Bad:**
```abl
hQry:QUERY-PREPARE("FOR EACH User WHERE Name = '" + cInput + "'").
```

**Good:**
```abl
hQry:QUERY-PREPARE(SUBSTITUTE("FOR EACH User WHERE Name = &1", QUOTER(cInput))).
```

### Rule: ActiveX Control Usage
**Severity**: Critical - Security Hotspot
**Applies to**: All files

Avoid `CREATE CONTROL-FRAME`.

### Rule: Auth Domain Table Usage
**Severity**: Critical - Vulnerability - Deprecated
**Applies to**: All files

Do not access `_sec-authentication-domain`.


### Rule: Command Injection
**Severity**: Critical - Security Hotspot
**Applies to**: All files

Sanitize inputs to `OS-COMMAND`.


### Rule: Unsalted Hash
**Severity**: Critical - Vulnerability
**Applies to**: All files

Always salt password hashes.


### Rule: Registry/INI Modification
**Severity**: Critical - Security Hotspot
**Applies to**: All files

Do not modify INI/Registry values.


### Rule: Weak Hashing Algorithms
**Severity**: Critical - Vulnerability
**Applies to**: All files

Use SHA-256 or stronger, not MD5/SHA-1.

**Bad:**
```abl
cHash = md5-digest(cData).
```

**Good:**
```abl
cHash = message-digest('sha-512', cData).
```

### Rule: Insecure ENCODE
**Severity**: Critical - Vulnerability
**Applies to**: All files

`ENCODE` is insecure.


### Rule: Production PROFILER
**Severity**: Minor - Vulnerability
**Applies to**: All files

Disable `PROFILER` in production.


### Rule: Internal Context Usage
**Severity**: Minor - Security Hotspot
**Applies to**: All files

Do not use internal `WEB-CONTEXT` features.


### Rule: Insecure Randomness
**Severity**: Minor - Vulnerability
**Applies to**: All files

`RANDOM` is not cryptographically secure.


### Rule: Hardcoded Credentials
**Severity**: Critical - Security Hotspot
**Applies to**: All files

No hardcoded credentials in `CONNECT`.


### Rule: UUID as Primary Key
**Severity**: Critical - Vulnerability
**Applies to**: All files

`GENERATE-UUID` may be predictable.


## Compiler Warning Rules

### Rule: Syntax Quirks
**Severity**: Blocker
**Applies to**: All files

Use standard syntax.


### Rule: Unqualified Field Access
**Severity**: Major
**Applies to**: All files

Qualify field names.


### Rule: Keyword Abbreviation
**Severity**: Info
**Applies to**: All files

Disallow keyword abbreviation.


### Rule: General Compiler Warning
**Severity**: Minor
**Applies to**: All files

Compiler warning.


### Rule: Unformatted Import Limitation
**Severity**: Minor
**Applies to**: All files

`IMPORT UNFORMATTED` limitations.


### Rule: Unreachable Code
**Severity**: Critical
**Applies to**: All files

Remove code after `RETURN`/`THROW`.


### Rule: Translation String Overflow
**Severity**: Critical
**Applies to**: All files

Translation exceeds length.

### Rule: Parse Error
**Severity**: Info
**Applies to**: All files

File parsing failed.


### Rule: Constant Expression
**Severity**: Minor
**Applies to**: All files

Logic error: constant expression.


### Rule: Missing Return Path
**Severity**: Critical
**Applies to**: All files

Ensure all paths return a value.


### Rule: Nested Transactions
**Severity**: Critical
**Applies to**: All files

`TRANSACTION` keyword inside a transaction is ignored.


### Rule: Ignored Array Index in Search
**Severity**: Minor
**Applies to**: All files

`CONTAINS` ignores array indices.


### Rule: Excessive Transaction Scope
**Severity**: Critical
**Applies to**: All files

Limit transaction scope.
