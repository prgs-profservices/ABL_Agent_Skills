# Copyright 2026 Progress Software Corporation
# SPDX-License-Identifier: Apache-2.0

param(
  [Parameter(Mandatory = $true)]
  [string[]]$Roots,
  [string]$OutputDir = 'docs',
  [string]$ReportFileName = 'abl-memory-leak-report.html',
  [switch]$NoOpenReport
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$workspace = Resolve-Path (Join-Path $scriptDir '..\..\..') | Select-Object -ExpandProperty Path
Set-Location $workspace

$resolvedOutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) {
  $OutputDir
} else {
  Join-Path $workspace $OutputDir
}

if (-not (Test-Path $resolvedOutputDir)) {
  New-Item -ItemType Directory -Path $resolvedOutputDir -Force | Out-Null
}

$templatePath = Join-Path $scriptDir 'templates/memory-leak-report-template.html'
if (-not (Test-Path $templatePath)) {
  throw "Template not found: $templatePath"
}

$filePatterns = @('.p', '.w', '.i', '.cls')

function Encode-Html {
  param([string]$Text)
  [System.Net.WebUtility]::HtmlEncode([string]$Text)
}

function Convert-ToRelativePath {
  param(
    [string]$Path,
    [string]$Root
  )

  $normalizedRoot = $Root.TrimEnd('\', '/')
  if ($Path.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $Path.Substring($normalizedRoot.Length + 1) -replace '\\', '/'
  }

  return $Path -replace '\\', '/'
}

function Get-CodeOnlyLine {
  param(
    [string]$Line,
    [ref]$InBlockComment
  )

  $text = [string]$Line

  if (-not $InBlockComment.Value) {
    $trimLeading = $text.TrimStart()
    if ($trimLeading -match '^\*') {
      return ''
    }
  }

  $sb = New-Object System.Text.StringBuilder
  $inSingle = $false
  $inDouble = $false
  $idx = 0

  while ($idx -lt $text.Length) {
    if ($InBlockComment.Value) {
      if ($idx + 1 -lt $text.Length -and $text[$idx] -eq '*' -and $text[$idx + 1] -eq '/') {
        $InBlockComment.Value = $false
        $idx += 2
        continue
      }

      $idx++
      continue
    }

    if (-not $inSingle -and -not $inDouble -and $idx + 1 -lt $text.Length -and $text[$idx] -eq '/' -and $text[$idx + 1] -eq '/') {
      break
    }

    if (-not $inSingle -and -not $inDouble -and $idx + 1 -lt $text.Length -and $text[$idx] -eq '/' -and $text[$idx + 1] -eq '*') {
      $InBlockComment.Value = $true
      $idx += 2
      continue
    }

    $ch = $text[$idx]

    if ($ch -eq '''') {
      if (-not $inDouble) {
        $inSingle = -not $inSingle
      }
      [void]$sb.Append($ch)
      $idx++
      continue
    }

    if ($ch -eq '"') {
      if (-not $inSingle) {
        $inDouble = -not $inDouble
      }
      [void]$sb.Append($ch)
      $idx++
      continue
    }

    [void]$sb.Append($ch)
    $idx++
  }

  return $sb.ToString()
}

function Add-Occurrence {
  param(
    [hashtable]$Table,
    [string]$Var,
    [int]$Line
  )
  if (-not $Table.ContainsKey($Var)) { $Table[$Var] = New-Object System.Collections.Generic.List[int] }
  $Table[$Var].Add($Line) | Out-Null
}

function Add-Finding {
  param(
    [System.Collections.Generic.List[object]]$Target,
    [string]$File,
    [int]$Line,
    [string]$Category,
    [string]$Severity,
    [string]$Symbol,
    [string]$Confidence,
    [string]$WidgetPoolContext,
    [string]$Rationale,
    [string]$Evidence
  )

  $Target.Add([pscustomobject]@{
    File = $File
    Line = $Line
    Category = $Category
    Severity = $Severity
    Symbol = $Symbol
    Confidence = $Confidence
    WidgetPoolContext = $WidgetPoolContext
    Rationale = $Rationale
    Evidence = $Evidence
  }) | Out-Null
}

$scanRoots = @()
foreach ($root in $Roots) {
  $resolvedRoot = if ([System.IO.Path]::IsPathRooted($root)) { $root } else { Join-Path $workspace $root }
  if (Test-Path $resolvedRoot) {
    $scanRoots += (Resolve-Path $resolvedRoot | Select-Object -ExpandProperty Path)
  }
}

if ($scanRoots.Count -eq 0) {
  throw 'No valid roots to scan. Provide one or more existing paths via -Roots.'
}

$files = foreach ($root in $scanRoots) {
  if (Test-Path $root -PathType Container) {
    Get-ChildItem -Path $root -Recurse -File | Where-Object { $filePatterns -contains $_.Extension.ToLowerInvariant() }
  } elseif (Test-Path $root -PathType Leaf) {
    $item = Get-Item $root
    if ($filePatterns -contains $item.Extension.ToLowerInvariant()) { $item }
  }
}
$files = $files | Sort-Object FullName -Unique

$findings = New-Object System.Collections.Generic.List[object]

foreach ($file in $files) {
  $rel = Convert-ToRelativePath -Path $file.FullName -Root $workspace
  $rawLines = Get-Content -Path $file.FullName

  $codeRows = New-Object System.Collections.Generic.List[object]
  $inBlockComment = $false

  for ($i = 0; $i -lt $rawLines.Count; $i++) {
    $code = Get-CodeOnlyLine -Line ([string]$rawLines[$i]) -InBlockComment ([ref]$inBlockComment)
    if ([string]::IsNullOrWhiteSpace($code)) { continue }

    $codeRows.Add([pscustomobject]@{
      Line = $i + 1
      Code = $code.Trim()
    }) | Out-Null
  }

  if ($codeRows.Count -eq 0) { continue }

  $hasWidgetPool = $false

  $memptrDefined = @{}
  $memptrAlloc = @{}
  $memptrFreed = @{}

  $persistentSet = @{}
  $persistentDeleted = @{}

  $queryCreated = @{}
  $queryClosedOrDeleted = @{}

  $handleCreated = @{}
  $handleDeleted = @{}

  $widgetCreated = @{}
  $widgetDeleted = @{}

  $subscribeLines = New-Object System.Collections.Generic.List[int]
  $unsubscribeLines = New-Object System.Collections.Generic.List[int]

  $inputOpenLines = New-Object System.Collections.Generic.List[int]
  $inputCloseLines = New-Object System.Collections.Generic.List[int]
  $outputOpenLines = New-Object System.Collections.Generic.List[int]
  $outputCloseLines = New-Object System.Collections.Generic.List[int]

  $pointerZeroMisuse = @{}
  $comCreated = @{}
  $comReleased = @{}
  $newInstanceCreated = @{}
  $asyncRequestSet = @{}
  $longcharUnknownLines = New-Object System.Collections.Generic.List[int]
  $hasStaticTempTableInClass = $false
  $isClassFile = ($file.Extension.ToLowerInvariant() -eq '.cls')

  foreach ($row in $codeRows) {
    $line = $row.Line
    $text = $row.Code

    if ($text -match '(?i)\bCREATE\s+WIDGET-POOL\b') {
      $hasWidgetPool = $true
    }

    $m = [regex]::Match($text, '(?i)\b(?:DEF|DEFINE)\s+(?:VAR|VARIABLE)\s+([A-Z0-9_-]+)\s+AS\s+MEMPTR\b')
    if ($m.Success) {
      $var = $m.Groups[1].Value.ToLowerInvariant()
      if (-not $memptrDefined.ContainsKey($var)) { $memptrDefined[$var] = $line }
    }

    $mAlloc1 = [regex]::Match($text, '(?i)\bSET-SIZE\s*\(\s*([A-Z0-9_-]+)\s*\)\s*=\s*(.+)$')
    if ($mAlloc1.Success) {
      $var = $mAlloc1.Groups[1].Value.ToLowerInvariant()
      $rhs = $mAlloc1.Groups[2].Value.Trim().TrimEnd('.')
      if ($rhs -match '^0$') {
        if (-not $memptrFreed.ContainsKey($var)) { $memptrFreed[$var] = $line }
      } else {
        if (-not $memptrAlloc.ContainsKey($var)) { $memptrAlloc[$var] = $line }
      }
    }

    $mAlloc2 = [regex]::Match($text, '(?i)\bSET-SIZE\s+([A-Z0-9_-]+)\s*=\s*(.+)$')
    if ($mAlloc2.Success) {
      $var = $mAlloc2.Groups[1].Value.ToLowerInvariant()
      $rhs = $mAlloc2.Groups[2].Value.Trim().TrimEnd('.')
      if ($rhs -match '^0$') {
        if (-not $memptrFreed.ContainsKey($var)) { $memptrFreed[$var] = $line }
      } else {
        if (-not $memptrAlloc.ContainsKey($var)) { $memptrAlloc[$var] = $line }
      }
    }

    $mPersist = [regex]::Match($text, '(?i)\bRUN\b.+\bPERSISTENT\b.+\bSET\s+([A-Z0-9_-]+)\b')
    if ($mPersist.Success) {
      $var = $mPersist.Groups[1].Value.ToLowerInvariant()
      if (-not $persistentSet.ContainsKey($var)) { $persistentSet[$var] = $line }
    }

    $mDelProc = [regex]::Match($text, '(?i)\bDELETE\s+PROCEDURE\s+([A-Z0-9_-]+)\b')
    if ($mDelProc.Success) {
      $var = $mDelProc.Groups[1].Value.ToLowerInvariant()
      if (-not $persistentDeleted.ContainsKey($var)) { $persistentDeleted[$var] = $line }
    }

    $mCreateQuery = [regex]::Match($text, '(?i)\bCREATE\s+QUERY\s+([A-Z0-9_-]+)\b')
    if ($mCreateQuery.Success) {
      $var = $mCreateQuery.Groups[1].Value.ToLowerInvariant()
      if (-not $queryCreated.ContainsKey($var)) { $queryCreated[$var] = $line }
    }

    $mQueryCloseA = [regex]::Match($text, '(?i)\b([A-Z0-9_-]+):QUERY-CLOSE\s*\(')
    if ($mQueryCloseA.Success) {
      $var = $mQueryCloseA.Groups[1].Value.ToLowerInvariant()
      if (-not $queryClosedOrDeleted.ContainsKey($var)) { $queryClosedOrDeleted[$var] = $line }
    }

    $mQueryCloseB = [regex]::Match($text, '(?i)\bQUERY-CLOSE\s*\(\s*([A-Z0-9_-]+)\s*\)')
    if ($mQueryCloseB.Success) {
      $var = $mQueryCloseB.Groups[1].Value.ToLowerInvariant()
      if (-not $queryClosedOrDeleted.ContainsKey($var)) { $queryClosedOrDeleted[$var] = $line }
    }

    $mCreateHandle = [regex]::Match($text, '(?i)\bCREATE\s+(BUFFER|TEMP-TABLE|DATASET|DATA-SOURCE|SOCKET|SERVER|SERVER-SOCKET|CLIENT-PRINCIPAL|SAX-READER|SAX-WRITER|SAX-ATTRIBUTES|X-DOCUMENT|X-NODEREF|CALL)\s+([A-Z0-9_-]+)\b')
    if ($mCreateHandle.Success) {
      $kind = $mCreateHandle.Groups[1].Value.ToUpperInvariant()
      $var = $mCreateHandle.Groups[2].Value.ToLowerInvariant()
      if (-not $handleCreated.ContainsKey($var)) {
        $handleCreated[$var] = [pscustomobject]@{ Line = $line; Kind = $kind }
      }
    }

    $mCreateWidget = [regex]::Match($text, '(?i)\bCREATE\s+(BUTTON|BROWSE|COMBO-BOX|DIALOG-BOX|EDITOR|FILL-IN|FRAME|IMAGE|MENU|MENU-ITEM|RECTANGLE|SELECTION-LIST|TEXT|TOGGLE-BOX|WINDOW)\s+([A-Z0-9_-]+)\b')
    if ($mCreateWidget.Success) {
      $kind = $mCreateWidget.Groups[1].Value.ToUpperInvariant()
      $var = $mCreateWidget.Groups[2].Value.ToLowerInvariant()
      if (-not $widgetCreated.ContainsKey($var)) {
        $widgetCreated[$var] = [pscustomobject]@{ Line = $line; Kind = $kind }
      }
    }

    $mDeleteObject = [regex]::Match($text, '(?i)\bDELETE\s+OBJECT\s+([A-Z0-9_-]+)\b')
    if ($mDeleteObject.Success) {
      $var = $mDeleteObject.Groups[1].Value.ToLowerInvariant()
      Add-Occurrence -Table $handleDeleted -Var $var -Line $line
      if (-not $queryClosedOrDeleted.ContainsKey($var)) { $queryClosedOrDeleted[$var] = $line }
      if (-not $persistentDeleted.ContainsKey($var)) { $persistentDeleted[$var] = $line }
    }

    $mDeleteWidget = [regex]::Match($text, '(?i)\bDELETE\s+WIDGET\s+([A-Z0-9_-]+)\b')
    if ($mDeleteWidget.Success) {
      $var = $mDeleteWidget.Groups[1].Value.ToLowerInvariant()
      if (-not $widgetDeleted.ContainsKey($var)) { $widgetDeleted[$var] = $line }
    }

    if ($text -match '(?i)\bSUBSCRIBE\b') { $subscribeLines.Add($line) | Out-Null }
    if ($text -match '(?i)\bUNSUBSCRIBE\b') { $unsubscribeLines.Add($line) | Out-Null }

    if ($text -match '(?i)^\s*INPUT\s+FROM\b' -and $text -notmatch '(?i)\bINPUT\s+CLOSE\b') { $inputOpenLines.Add($line) | Out-Null }
    if ($text -match '(?i)\bINPUT\s+CLOSE\b') { $inputCloseLines.Add($line) | Out-Null }

    if ($text -match '(?i)^\s*OUTPUT\s+TO\b' -and $text -notmatch '(?i)\bOUTPUT\s+CLOSE\b') { $outputOpenLines.Add($line) | Out-Null }
    if ($text -match '(?i)\bOUTPUT\s+CLOSE\b') { $outputCloseLines.Add($line) | Out-Null }

    # KB 000215510: SET-POINTER-VALUE(...) = 0 does NOT free MEMPTR memory (unlike SET-SIZE(...) = 0)
    $mPtrZero = [regex]::Match($text, '(?i)\bSET-POINTER-VALUE\s*\(\s*([A-Z0-9_-]+)\s*\)\s*=\s*0\b')
    if ($mPtrZero.Success) {
      $var = $mPtrZero.Groups[1].Value.ToLowerInvariant()
      if (-not $pointerZeroMisuse.ContainsKey($var)) { $pointerZeroMisuse[$var] = $line }
    }

    # COM/ActiveX automation objects: CREATE "ProgID" hVar. Cleanup is RELEASE OBJECT (or DELETE OBJECT).
    $mComCreate = [regex]::Match($text, '(?i)\bCREATE\s+(?:"[^"]+"|''[^'']+'')\s+([A-Z0-9_-]+)\b')
    if ($mComCreate.Success) {
      $var = $mComCreate.Groups[1].Value.ToLowerInvariant()
      Add-Occurrence -Table $comCreated -Var $var -Line $line
    }

    $mRelease = [regex]::Match($text, '(?i)\bRELEASE\s+OBJECT\s*\(?\s*([A-Z0-9_-]+)\s*\)?\b')
    if ($mRelease.Success) {
      $var = $mRelease.Groups[1].Value.ToLowerInvariant()
      Add-Occurrence -Table $comReleased -Var $var -Line $line
    }

    # Class instance creation via NEW(); GC normally reclaims these, but long-running/AppServer
    # scopes and circular references benefit from explicit DELETE OBJECT (see KB 000185865, 000281107).
    $mNewInstance = [regex]::Match($text, '(?i)(?<![:.\w-])([A-Za-z_][A-Za-z0-9_-]*)\s*=\s*NEW\s+[A-Za-z0-9_.]+\s*\(')
    if ($mNewInstance.Success) {
      $var = $mNewInstance.Groups[1].Value.ToLowerInvariant()
      Add-Occurrence -Table $newInstanceCreated -Var $var -Line $line
    }

    # Asynchronous AppServer requests: RUN ... ASYNCHRONOUS SET hRequest requires DELETE OBJECT hRequest.
    $mAsync = [regex]::Match($text, '(?i)\bASYNCHRONOUS\s+SET\s+([A-Z0-9_-]+)\b')
    if ($mAsync.Success) {
      $var = $mAsync.Groups[1].Value.ToLowerInvariant()
      Add-Occurrence -Table $asyncRequestSet -Var $var -Line $line
    }

    # KB 000213596: comparing a LONGCHAR-returning call directly to UNKNOWN can leak the implicit temp value.
    # Excludes common LOGICAL-returning built-ins to reduce noise. Matched on a closing paren immediately
    # followed by "= ?" (or the reverse) so nested-parenthesis calls like MyFunc(a, GetVal(b)) = ? are still caught.
    $excludeCallNamesList = 'AVAILABLE|VALID-OBJECT|VALID-HANDLE|CAN-FIND|CAN-DO|CAN-QUERY|ERROR-STATUS|LOCKED|INDEX'
    $hasCallCompareToUnknown = ($text -match '(?i)\)\s*=\s*\?') -or ($text -match '(?i)\?\s*=\s*[A-Za-z_][A-Za-z0-9_.:-]*\s*\(')
    if ($hasCallCompareToUnknown -and $text -notmatch "(?i)\b($excludeCallNamesList)\s*\(") {
      $longcharUnknownLines.Add($line) | Out-Null
    }

    # KB 000172688: static temp-table defined directly inside a class body, combined with DELETE OBJECT
    # cleanup in the destructor, has caused implicit temp-table/buffer leaks on older OE releases.
    if ($isClassFile -and $text -match '(?i)^\s*DEFINE\s+TEMP-TABLE\b') {
      $hasStaticTempTableInClass = $true
    }
  }

  foreach ($var in $memptrAlloc.Keys) {
    if (-not $memptrFreed.ContainsKey($var)) {
      Add-Finding -Target $findings -File $rel -Line ([int]$memptrAlloc[$var]) -Category 'MEMPTR not released' -Severity 'High' -Symbol $var -Confidence 'High' -WidgetPoolContext 'n/a' -Rationale 'MEMPTR appears to be allocated with SET-SIZE but no clear SET-SIZE(...)=0 release was found in file scope.' -Evidence "SET-SIZE allocation seen for $var without matching release"
    }
  }

  foreach ($var in $persistentSet.Keys) {
    if (-not $persistentDeleted.ContainsKey($var)) {
      Add-Finding -Target $findings -File $rel -Line ([int]$persistentSet[$var]) -Category 'Persistent procedure handle lifecycle' -Severity 'High' -Symbol $var -Confidence 'Medium' -WidgetPoolContext 'n/a' -Rationale 'RUN ... PERSISTENT SET handle appears without clear DELETE PROCEDURE/DELETE OBJECT for the same handle.' -Evidence "Persistent handle $var created but no cleanup found"
    }
  }

  foreach ($var in $queryCreated.Keys) {
    if (-not $queryClosedOrDeleted.ContainsKey($var)) {
      Add-Finding -Target $findings -File $rel -Line ([int]$queryCreated[$var]) -Category 'Dynamic query not closed' -Severity 'Medium' -Symbol $var -Confidence 'Medium' -WidgetPoolContext 'n/a' -Rationale 'CREATE QUERY detected without clear QUERY-CLOSE or DELETE OBJECT for the same query handle.' -Evidence "Query handle $var created without close/delete"
    }
  }

  foreach ($var in $handleCreated.Keys) {
    if (-not $handleDeleted.ContainsKey($var)) {
      $kind = [string]$handleCreated[$var].Kind
      Add-Finding -Target $findings -File $rel -Line ([int]$handleCreated[$var].Line) -Category 'Dynamic handle not deleted' -Severity 'Medium' -Symbol $var -Confidence 'Medium' -WidgetPoolContext 'n/a' -Rationale "CREATE $kind detected without clear DELETE OBJECT for the same handle." -Evidence "Handle $var ($kind) created without delete"
    }
  }

  foreach ($var in $widgetCreated.Keys) {
    if (-not $widgetDeleted.ContainsKey($var)) {
      $kind = [string]$widgetCreated[$var].Kind
      $sev = if ($hasWidgetPool) { 'Low' } else { 'Medium' }
      $ctx = if ($hasWidgetPool) { 'Widget pool detected in file - auto cleanup may occur when pool scope ends.' } else { 'No widget pool detected in file scope.' }
      $conf = if ($hasWidgetPool) { 'Low' } else { 'Medium' }
      Add-Finding -Target $findings -File $rel -Line ([int]$widgetCreated[$var].Line) -Category 'Widget handle lifecycle' -Severity $sev -Symbol $var -Confidence $conf -WidgetPoolContext $ctx -Rationale "CREATE $kind detected without clear DELETE WIDGET for the same handle." -Evidence "Widget $var ($kind) created without explicit delete"
    }
  }

  if ($subscribeLines.Count -gt $unsubscribeLines.Count) {
    Add-Finding -Target $findings -File $rel -Line ([int]$subscribeLines[0]) -Category 'Event subscription lifecycle' -Severity 'Medium' -Symbol 'SUBSCRIBE' -Confidence 'Low' -WidgetPoolContext 'n/a' -Rationale 'SUBSCRIBE appears more times than UNSUBSCRIBE in file scope; event hooks may outlive intended object/session lifetime.' -Evidence "SUBSCRIBE count=$($subscribeLines.Count), UNSUBSCRIBE count=$($unsubscribeLines.Count)"
  }

  if ($inputOpenLines.Count -gt $inputCloseLines.Count) {
    Add-Finding -Target $findings -File $rel -Line ([int]$inputOpenLines[0]) -Category 'Input stream lifecycle' -Severity 'Medium' -Symbol 'INPUT STREAM' -Confidence 'Medium' -WidgetPoolContext 'n/a' -Rationale 'INPUT FROM appears without matching INPUT CLOSE count in file scope.' -Evidence "INPUT FROM count=$($inputOpenLines.Count), INPUT CLOSE count=$($inputCloseLines.Count)"
  }

  if ($outputOpenLines.Count -gt $outputCloseLines.Count) {
    Add-Finding -Target $findings -File $rel -Line ([int]$outputOpenLines[0]) -Category 'Output stream lifecycle' -Severity 'Medium' -Symbol 'OUTPUT STREAM' -Confidence 'Medium' -WidgetPoolContext 'n/a' -Rationale 'OUTPUT TO appears without matching OUTPUT CLOSE count in file scope.' -Evidence "OUTPUT TO count=$($outputOpenLines.Count), OUTPUT CLOSE count=$($outputCloseLines.Count)"
  }

  foreach ($var in $pointerZeroMisuse.Keys) {
    Add-Finding -Target $findings -File $rel -Line ([int]$pointerZeroMisuse[$var]) -Category 'MEMPTR incorrect release (SET-POINTER-VALUE)' -Severity 'High' -Symbol $var -Confidence 'High' -WidgetPoolContext 'n/a' -Rationale 'SET-POINTER-VALUE(...) = 0 only clears the pointer reference; it does NOT free the underlying MEMPTR allocation and will leak memory on every call (Progress KB 000215510). Use SET-SIZE(varname) = 0 instead.' -Evidence "SET-POINTER-VALUE($var) = 0 used instead of SET-SIZE($var) = 0"
  }

  foreach ($var in $comCreated.Keys) {
    $createdLines = $comCreated[$var]
    $releasedCount = 0
    if ($comReleased.ContainsKey($var)) { $releasedCount += $comReleased[$var].Count }
    if ($handleDeleted.ContainsKey($var)) { $releasedCount += $handleDeleted[$var].Count }
    for ($i = 0; $i -lt $createdLines.Count; $i++) {
      if ($i -ge $releasedCount) {
        Add-Finding -Target $findings -File $rel -Line ([int]$createdLines[$i]) -Category 'COM/ActiveX object not released' -Severity 'High' -Symbol $var -Confidence 'Medium' -WidgetPoolContext 'n/a' -Rationale 'CREATE "ProgID" instantiates a COM Automation/ActiveX object. These are not garbage collected and must be explicitly released with RELEASE OBJECT (or DELETE OBJECT); no matching release was found.' -Evidence "COM object $var created without RELEASE OBJECT/DELETE OBJECT"
      }
    }
  }

  foreach ($var in $newInstanceCreated.Keys) {
    $createdLines = $newInstanceCreated[$var]
    $releasedCount = if ($handleDeleted.ContainsKey($var)) { $handleDeleted[$var].Count } else { 0 }
    for ($i = 0; $i -lt $createdLines.Count; $i++) {
      if ($i -ge $releasedCount) {
        Add-Finding -Target $findings -File $rel -Line ([int]$createdLines[$i]) -Category 'Class instance lifecycle (NEW without DELETE OBJECT)' -Severity 'Low' -Symbol $var -Confidence 'Low' -WidgetPoolContext 'n/a' -Rationale 'ABL class instances are normally garbage collected once unreferenced, but instances held in STATIC members, long-running/AppServer sessions, temp-tables, or circular reference graphs can survive indefinitely. Review whether this instance should be explicitly DELETE OBJECTed (see KB 000185865, KB 000281107 for cases GC does not reclaim).' -Evidence "NEW instance assigned to $var without a corresponding DELETE OBJECT $var in file scope"
      }
    }
  }

  foreach ($var in $asyncRequestSet.Keys) {
    $createdLines = $asyncRequestSet[$var]
    $releasedCount = if ($handleDeleted.ContainsKey($var)) { $handleDeleted[$var].Count } else { 0 }
    for ($i = 0; $i -lt $createdLines.Count; $i++) {
      if ($i -ge $releasedCount) {
        Add-Finding -Target $findings -File $rel -Line ([int]$createdLines[$i]) -Category 'Asynchronous request handle not deleted' -Severity 'High' -Symbol $var -Confidence 'Medium' -WidgetPoolContext 'n/a' -Rationale 'RUN ... ASYNCHRONOUS SET creates a request object that survives after the request completes so its status can be checked later. Without an explicit DELETE OBJECT after WAIT-FOR/completion, the request handle is leaked for the life of the session (per Progress documentation example).' -Evidence "Asynchronous request handle $var created without DELETE OBJECT $var"
      }
    }
  }

  if ($longcharUnknownLines.Count -gt 0) {
    Add-Finding -Target $findings -File $rel -Line ([int]$longcharUnknownLines[0]) -Category 'LONGCHAR result compared directly to UNKNOWN' -Severity 'Low' -Symbol 'LONGCHAR/?' -Confidence 'Low' -WidgetPoolContext 'n/a' -Rationale 'Comparing a function/method/property call result directly against the UNKNOWN value (?) can leak memory when the returned value is a LONGCHAR (fixed in OE 12.4/12.2.8/11.7.13 per KB 000213596; verify target runtime). Assign the result to a local variable first, then compare the variable to ?.' -Evidence "Direct call-result-to-UNKNOWN comparison found ($($longcharUnknownLines.Count) occurrence(s)); first at line $($longcharUnknownLines[0])"
  }

  if ($hasStaticTempTableInClass -and $handleDeleted.Count -gt 0) {
    Add-Finding -Target $findings -File $rel -Line 1 -Category 'Static temp-table defined in class body' -Severity 'Low' -Symbol 'DEFINE TEMP-TABLE' -Confidence 'Low' -WidgetPoolContext 'n/a' -Rationale 'A temp-table defined directly in a class body, combined with DELETE OBJECT of the class instance, has historically triggered implicit (undeleted) temp-table/buffer objects on OpenEdge releases prior to 11.2 (KB 000172688). Confirm target OE version and consider EMPTY TEMP-TABLE plus explicit verification via DynObjects logging if targeting older runtimes.' -Evidence 'Class file contains a directly-defined (static) temp-table and at least one DELETE OBJECT statement'
  }
}

$findings = $findings | Sort-Object File, Line, Category, Symbol -Unique
$totalFindings = ($findings | Measure-Object).Count
$affectedFiles = ($findings | Select-Object -ExpandProperty File -Unique | Measure-Object).Count

$highCount = ($findings | Where-Object { $_.Severity -eq 'High' } | Measure-Object).Count
$medCount = ($findings | Where-Object { $_.Severity -eq 'Medium' } | Measure-Object).Count
$lowCount = ($findings | Where-Object { $_.Severity -eq 'Low' } | Measure-Object).Count

$byCategory = if ($totalFindings -gt 0) { $findings | Group-Object Category | Sort-Object Name } else { @() }

$summaryCards = "<div class='card'><h3>Total Findings</h3><div class='value'>$totalFindings</div></div>" +
                "<div class='card'><h3>Files Affected</h3><div class='value'>$affectedFiles</div></div>" +
                "<div class='card'><h3>High Severity</h3><div class='value'>$highCount</div></div>" +
                "<div class='card'><h3>Medium Severity</h3><div class='value'>$medCount</div></div>" +
                "<div class='card'><h3>Low Severity</h3><div class='value'>$lowCount</div></div>"

$categorySummary = if ($byCategory.Count -eq 0) {
  '<li>No findings.</li>'
} else {
  ($byCategory | ForEach-Object { "<li><strong>$(Encode-Html $_.Name)</strong>: $($_.Count)</li>" }) -join ''
}

$rowsHtml = if ($totalFindings -eq 0) {
  "<tr><td colspan='9'>No potential leak patterns found in scoped files.</td></tr>"
} else {
  ($findings | ForEach-Object {
    $sevClass = $_.Severity.ToLowerInvariant()
    "<tr class='sev-$sevClass' data-severity='$(Encode-Html $_.Severity)'><td>$(Encode-Html $_.File)</td><td>$($_.Line)</td><td>$(Encode-Html $_.Category)</td><td>$(Encode-Html $_.Severity)</td><td><code>$(Encode-Html $_.Symbol)</code></td><td>$(Encode-Html $_.Confidence)</td><td>$(Encode-Html $_.WidgetPoolContext)</td><td>$(Encode-Html $_.Rationale)</td><td><code>$(Encode-Html $_.Evidence)</code></td></tr>"
  }) -join "`n"
}

$template = Get-Content -Path $templatePath -Raw
$scopeDisplay = ($scanRoots | ForEach-Object { Convert-ToRelativePath -Path $_ -Root $workspace }) -join ', '
$generatedAt = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

$html = $template.Replace('{{WORKSPACE}}', (Encode-Html $workspace))
$html = $html.Replace('{{GENERATED_AT}}', $generatedAt)
$html = $html.Replace('{{SCOPE_DISPLAY}}', (Encode-Html $scopeDisplay))
$html = $html.Replace('{{SUMMARY_CARDS}}', $summaryCards)
$html = $html.Replace('{{CATEGORY_SUMMARY}}', $categorySummary)
$html = $html.Replace('{{ROWS_HTML}}', $rowsHtml)

$outPath = Join-Path $resolvedOutputDir $ReportFileName
if ($PSVersionTable.PSVersion.Major -ge 7) {
  $html | Out-File -FilePath $outPath -Encoding utf8NoBOM
} else {
  [System.IO.File]::WriteAllText($outPath, $html, (New-Object System.Text.UTF8Encoding($false)))
}

if (-not $NoOpenReport) {
  Start-Process $outPath
}

Write-Output "REPORT_PATH=$outPath"
Write-Output "TOTAL_FINDINGS=$totalFindings"
Write-Output "FILES_AFFECTED=$affectedFiles"
Write-Output "HIGH_SEVERITY=$highCount"
Write-Output "MEDIUM_SEVERITY=$medCount"
Write-Output "LOW_SEVERITY=$lowCount"
Write-Output "COMMENT_FILTER=enabled"
Write-Output "MEMPTR_CHECK=enabled"
Write-Output "WIDGET_POOL_CONTEXT=enabled"
Write-Output "SET_POINTER_VALUE_CHECK=enabled"
Write-Output "COM_ACTIVEX_CHECK=enabled"
Write-Output "CLASS_INSTANCE_CHECK=enabled"
Write-Output "ASYNC_REQUEST_CHECK=enabled"
Write-Output "LONGCHAR_UNKNOWN_CHECK=enabled"
Write-Output "STATIC_TT_IN_CLASS_CHECK=enabled"
