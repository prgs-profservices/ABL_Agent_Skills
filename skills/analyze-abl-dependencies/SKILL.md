---
name: analyze-abl-dependencies
description: Analyze OpenEdge ABL code to determine external (non-ABL) dependencies such as .NET assemblies, Java classes, COM objects, DLLs, and web services
license: Apache-2.0
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, PowerShell
compatibility: Cross-platform, OpenEdge project (openedge-project.json)
---

<!--
analyze-abl-dependencies: Analyze OpenEdge ABL code to determine external (non-ABL) dependencies such as.

Copyright 2026 Progress Software Corporation
SPDX-License-Identifier: Apache-2.0
-->

## When to Use
Use this skill when you need to:
- Identify external (non-ABL) dependencies such as .NET assemblies, Java classes, or COM objects
- Determine which external libraries are required to run ABL code
- Find references to DLLs or external procedures
- Analyze external dependencies for deployment planning or compatibility assessment

**Note**: This skill does NOT analyze internal ABL dependencies (USING statements, include files, or ABL procedure calls).

## Inputs
The user must specify the scope of analysis:
- **File**: Single ABL source file (.cls, .p, .w, or .i)
- **Directory**: All ABL files within a specific directory (optionally recursive)
- **Workspace**: All ABL files in the current workspace

Optional parameters:
- Dependency types to analyze (.NET assemblies, Java classes, COM objects, DLLs, etc.)
- Recursive flag for directory analysis
- File patterns to include/exclude
- Output format: `html` (default) or `markdown`

## Process
1. Determine the scope (file, directory, or workspace) based on user input
2. Collect all ABL files (.cls, .p, .w, .i) within the specified scope using your agent's file-search tool (e.g. `file_search` in Copilot, `Glob` in Claude Code)
   - **Critical**: When searching a specific directory (not workspace), ensure the content-search include pattern is correct
   - For directories: Use `**/directory-name/**/*.{cls,p,w,i}` pattern
   - For absolute paths outside workspace: Convert to relative pattern or use the full path in the include pattern
   - Always verify the include pattern matches the directory being analyzed
3. Use the openedge-abl MCP to look up relevant language elements if needed
4. Search for external dependencies using **BROAD searches first, then narrow down**:

   **CRITICAL SEARCH STRATEGY:**
   - **Start with broad plain-text searches** (not regex) to avoid missing matches
   - Example: Search for `EXTERNAL` (plain text) instead of complex regex patterns
   - Example: Search for `.dll` (plain text) to find all DLL references
   - **Then examine specific files/directories** that are likely to contain external calls (e.g., `winapi`, `system`, `lib` directories)
   - **Finally use more specific searches** once you understand the patterns in the codebase

   **Search patterns for each dependency type:**
   - **.NET assemblies**:
     - Search: `FROM ASSEMBLY` (plain text)
     - Then: `USING.*FROM.*ASSEMBLY` (regex) and `NEW.*FROM.*ASSEMBLY` (regex)
   - **COM/OCX/ActiveX controls** (Windows only):
     - **CRITICAL**: COM-HANDLE and COMPONENT-HANDLE are synonyms - both used for ActiveX AND COM automation
     - **Distinguish by context**: ActiveX uses CONTROL-FRAME + LoadControls(); COM automation uses CREATE "App.Name"
     - **Search patterns** (in order):
       1. `CONTROL-FRAME` - widget container for ActiveX controls
       2. `COM-HANDLE` or `COMPONENT-HANDLE` - search for both
       3. `LoadControls` - loads controls from .wrx files
       4. `.wrx` - binary control definition files (search code and file system)
       5. `OCXINFO:CREATE-CONTROL` - AppBuilder comment with CLSID
     - **TIPS**: Use maxResults=500+; examine entire files; verify results by counting unique files
   - **ADM2 Framework Indirect OCX Dependencies** (CRITICAL — often missed):
     - ADM2 (Progress Application Development Manager v2) is the OE GUI framework. Some ADM2 components use OCX controls internally. Many customer codebases do **not** contain ADM2 source — it is resolved via `$DLC/gui/adm2/` or PROPATH — so standard OCX pattern searches on the customer's `src/` tree will find nothing. However, customer code that **calls** certain ADM2 components will trigger those OCX dependencies at runtime.
     - **ADM2 components that carry OCX dependencies:**
       - `adm2/dyntreeview.w` — Uses `MSCOMCTL.OCX` (TreeView + ImageList controls, CLSID `{C74190B6-8589-11D1-B16A-00C0F0283628}` and `{2C247F23-8591-11D1-B16A-00C0F0283628}`). 32-bit Windows only. Hard runtime dependency — will fail if `MSCOMCTL.OCX` is not registered.
       - `adm2/browser.p` + `adm2/data.p` — Uses `CrystalRuntime.Application.7` for the "Print Preview" toolbar button. 32-bit Windows only. **Lazy dependency** — Crystal is only activated when `CrystalRuntime.Application.7` is registered; if not registered, Print Preview silently hides itself. Still a blocker for 64-bit OE.
     - **If ADM2 source IS present in the codebase** (e.g., as an `adm-override/` layer or copied into `src/`): scan those override files directly using the COM/OCX patterns above. Findings are direct dependencies.
     - **If ADM2 is NOT present in the codebase** (resolved via DLC/PROPATH): search the customer's code for usage patterns that invoke the OCX-bearing ADM2 components:
       - Search `dyntreeview` (plain text) — finds `RUN adm2/dyntreeview.w` calls, include references, and SmartTreeView instantiation
       - Search `SmartTreeView` (plain text) — ADM2 naming convention for dyntreeview-based components
       - Search `getPrintPreviewActive` (plain text) — procedure in `browser.p` that activates Crystal
       - Search `printToCrystal` (plain text) — direct call into `data.p` Print Preview logic
       - Search `CrystalRuntime` (plain text) — may appear in any custom browse override inheriting from `browser.p`
       - Additionally: **any SmartBrowser** (ADM2 browser SDO) transitively inherits `browser.p` behaviour including Crystal activation. If the codebase contains SmartBrowsers (search `adm2/browser.p` or `BROWSER-OBJECT = "adm2/browser.p"`), flag Crystal as a possible dependency even without a direct `printToCrystal` call.
     - **How to report ADM2 indirect findings:**
       - dyntreeview.w called directly → Report as **Confirmed OCX dependency**: MSCOMCTL.OCX (32-bit), via ADM2 dyntreeview.w
       - SmartBrowsers present, no Crystal calls found → Report as **Possible OCX dependency**: CrystalRuntime.Application.7 (32-bit), via ADM2 browser.p Print Preview — verify whether Crystal is deployed on client machines
       - Crystal calls or CrystalRuntime references found → Report as **Confirmed OCX dependency**: CrystalRuntime.Application.7 (32-bit), via ADM2 data.p
   - **External DLLs** (Windows only):
     - Search: `EXTERNAL` (finds PROCEDURE EXTERNAL statements) or `.dll` (finds filenames)
     - **TIPS**: Use maxResults=500+; read entire files (often group many procedures); count unique files
   - **OS commands**:
     - Search: `OS-COMMAND` (plain text)
     - Also search: `INPUT THROUGH`, `OUTPUT THROUGH`, `UNIX SILENT`, `DOS SILENT`
     - Classify as: Standard OS commands, OpenEdge utilities, or Custom scripts/executables
   - **COM Automation** (Windows only - Excel, Word, Notes, Outlook):
     - Search: `COM-HANDLE`, `COMPONENT-HANDLE`, `Excel.Application`, `Word.Application`, `Lotus.NotesSession`
     - **Pattern**: `CREATE "Application.Name"` statements
     - **TIPS**: Can return hundreds of matches; check for commented-out code; requires Office/apps installed
   - **Web services**:
     - Search: `HttpClient`, `WebRequest`, `SOAP`, `REST`, `JSON` (plain text)
5. For DLLs and OCX controls, attempt to determine bitness (32-bit vs 64-bit):
   - **For ActiveX/OCX controls**:
     - Search for `.wrx` files in the workspace (binary control definition files)
     - Extract control name/type from `LoadControls()` calls or comments
     - Most legacy ActiveX controls (especially Progress-provided ones) are 32-bit only
     - Missing .wrx files indicate deployment/runtime issues
     - **CRITICAL**: 32-bit ActiveX controls CANNOT run in 64-bit OpenEdge (migration blocker)
   - **For DLLs**:
     - Check if the referenced DLL files exist in the folder or workspace
     - If found locally, examine the PE header directly to determine bitness
     - Check common installation paths (System32 vs SysWOW64)
     - Report bitness when determinable, flag as "unknown" otherwise
6. For OS-COMMAND scripts, check if custom scripts exist in the folder or workspace:
   - Look for referenced script files (.sh, .bat, .cmd, .ps1, etc.)
   - Note their presence and location for deployment planning
7. **Inventory all external dependency files** found in the analyzed directory/workspace:
   - **CRITICAL**: Only inventory external dependency files (.dll, .ocx, .wrx)
   - **DO NOT include**: ABL source files (.cls, .p, .w, .i), config files (.xml, .json, .ini), or other project files
   - Search for `.dll` files (file search)
   - Search for `.ocx` files (file search)
   - Search for `.wrx` files (file search)
   - For each external dependency file found, determine if it's referenced in the code:
     - Match file names against code references found in step 4
     - Flag files as "Used" or "Not Referenced" in code
     - Include file location (relative path)
   - This inventory helps identify:
     - Deployment bloat (unused .dll/.ocx files)
     - Legacy/backup files (e.g., xFilename.dll, Filename_old.dll)
     - Missing references (files present but not loaded)
     - Cleanup opportunities
8. For dependencies that cannot be identified locally:
   - Use web search to identify the DLL/OCX purpose, vendor, and bitness
   - Search for migration guides or 64-bit availability
   - Document findings with source URLs
9. **Analyze platform dependencies** for each external dependency found:
   - **Windows-specific**: DLLs (user32.dll, kernel32.dll, etc.), Windows API calls, Windows-only commands
   - **Linux/Unix-specific**: Unix commands (sleep, chmod, grep, etc.), shell scripts (.sh)
   - **Cross-platform**: Standard tools available on both (though syntax may differ)
   - Document which dependencies are platform-specific vs. portable
10. **Perform security analysis for command injection risks** (CRITICAL for OS-COMMAND and INPUT THROUGH):
   - **Identify all OS command execution points**:
     - OS-COMMAND statements
     - INPUT THROUGH / OUTPUT THROUGH statements
     - UNIX SILENT / DOS SILENT (legacy)
   - **For each command execution point, perform taint analysis**:
     - Identify the variable(s) used to build the command string (e.g., `pc-command`, `cOSCommand`, etc.)
     - Trace each variable backward through the code:
       - Is it a parameter passed in (INPUT/INPUT-OUTPUT)?
       - Is it assigned from another variable?
       - Is it built using SUBSTITUTE() or concatenation (+)?
       - Follow the data flow through method calls, property assignments, function returns
     - Continue tracing until you reach the **ultimate source**:
       - 🔴 **CRITICAL RISK**: User-controlled input (web request parameters, HTTP headers, form fields, uploaded file content, URL paths, query strings)
       - 🟠 **HIGH RISK**: Database fields or file content that external users can modify
       - 🟡 **MEDIUM RISK**: Configuration files, environment variables, registry values (admin-controlled)
       - 🟢 **LOW RISK**: Hardcoded string constants, validated enum values, internal logic only
       - ℹ️ **UNKNOWN**: Cannot determine source (needs manual review)
   - **Check for security controls**:
     - Allowlist validation (LOOKUP() against known-good values, CASE statement with limited options)
     - Regex validation or sanitization (REPLACE() to remove dangerous characters)
     - Input escaping or quoting
     - Length limits or format validation
   - **Assess injection vulnerability**:
     - **VULNERABLE**: User input reaches OS-COMMAND with no validation
     - **LIKELY SAFE**: Allowlist validation or hardcoded values only
     - **NEEDS REVIEW**: Some validation present but may be bypassable
   - **Cross-reference with usage analysis**:
     - If file is unused (no includes found from step 4), note "Theoretical risk - file not used"
     - If file has callers, trace parameters through the call chain:
       - What do callers pass to the command parameter?
       - Can you trace to user input in calling code?
       - Document the full call chain with file:line references
   - **Report security findings**:
     - List each OS command execution point with line number
     - Show the parameter name and traced data flow
     - Classify risk level (Critical/High/Medium/Low/Unknown)
     - Note validation present (if any)
     - Provide specific remediation guidance
11. Categorize and consolidate findings, including:
   - All code-referenced dependencies (from step 4)
   - All physical files found (from step 7)
   - Development observations (unused files, naming patterns, multiple versions)
12. Generate report in requested format (HTML by default, markdown if specified):
   - **HTML format** (default):
     - Read template files from `templates/` directory with **EXPLICIT UTF-8 ENCODING**:
       - `report-styles.css` - embed in `<style>` tag (use `-Encoding UTF8`)
       - `report-framework.js` - embed in `<script>` tag (use `-Encoding UTF8`)
       - `section-patterns.md` - reference for HTML structure patterns
       - `progresslogo.png` - read as binary and encode as base64 for header
       - **CRITICAL**: Always use `Get-Content -Raw -Encoding UTF8` when reading CSS/JS to preserve Unicode characters
     - Encode logo image:
       - Read `<skill-dir>/templates/progresslogo.png` as binary (`<skill-dir>` = this skill's own folder, resolved from where the skill was loaded — do not hardcode a root like `.github/skills` or `.claude/skills`)
       - Convert to base64 string using PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes($logoPath))`
       - Embed in header as data URI: `data:image/png;base64,[BASE64_STRING]`
     - Build self-contained HTML with:
       - Executive summary with counts and risk levels
         - **CRITICAL**: Always show summary cards for ALL dependency types (even if count is 0)
         - Mandatory cards: ABL Files, .NET Assemblies, COM/ActiveX, External DLLs (Win32), OS Commands
         - Optional cards based on findings: Total DLL Files, Unreferenced DLLs, Web Services, Java Classes
         - For file inventory: Use clear labels like "Total DLL Files", "Referenced DLLs", "Unreferenced DLLs"
       - Table of Contents (compact navigation links to all sections)
         - Place after summary cards, before main content
         - Link to section IDs using anchor tags (#section-id)
         - Include only sections that exist in the report
       - **Security Analysis - Command Injection Risks** (if OS-COMMAND/INPUT THROUGH found)
         - Must appear early in report (high visibility for security issues)
         - Show each command execution point with risk classification
         - Display traced data flow with color-coded severity
         - Include validation status and remediation guidance
       - Collapsible sections for each dependency type (with id attributes for TOC linking)
       - Color-coded severity indicators (red=32-bit blockers, yellow=platform-specific, green=cross-platform)
       - Searchable/filterable interface
       - Sortable tables (click headers to sort)
       - Migration impact assessment section
     - Save HTML to the workspace `docs/` folder: `{workspace}\docs\abl-dependency-report.html`
       - **CRITICAL**: Create the `docs/` folder first if it does not exist: `New-Item -ItemType Directory -Force -Path "$workspace\docs" | Out-Null`
       - **CRITICAL**: Write the report via a PowerShell terminal command (`Out-File`), NOT via the agent's file-creation tool — in some IDEs (e.g. VS Code Copilot) file-creation tools trigger per-file acceptance prompts for generated reports
       - **CRITICAL**: Use UTF-8 WITHOUT BOM to properly display Unicode emojis (🔧, 🔴, 📊)
       - PowerShell Core/7+: `$htmlContent | Out-File -FilePath "$workspace\docs\abl-dependency-report.html" -Encoding utf8NoBOM`
       - PowerShell 5.1: `[System.IO.File]::WriteAllText("$workspace\docs\abl-dependency-report.html", $htmlContent, (New-Object System.Text.UTF8Encoding($false)))`
     - Open report in default browser using PowerShell `Start-Process`
   - **Markdown format** (if user specifies):
     - Generate structured markdown report
     - Present findings in chat window

## Expected Outputs

### HTML Report (default)
An interactive HTML report opened in the default browser containing:
- **Executive Summary**: File counts, dependency counts by type, overall risk level
- **Table of Contents**: Quick navigation links to all report sections
- **Dependency Sections** (expandable/collapsible):
  - .NET Assemblies (version info, file locations)
  - ActiveX/OCX Controls (⚠️ 32-bit blockers highlighted in red)
  - COM Automation (Office dependencies, installation requirements)
  - External DLLs (grouped by library, bitness indicators)
  - OS Commands (classified: standard/OpenEdge/custom, platform markers)
  - Web Services (HTTP clients, SOAP/REST endpoints)
- **Platform Analysis**: Windows-only / Linux-only / Cross-platform / Mixed indicators
- **ADM2 Indirect OCX Dependencies** (if ADM2 usage patterns detected): Clearly distinguish between *Confirmed* (direct call to dyntreeview.w or explicit Crystal COM creation) and *Possible* (SmartBrowsers present, Crystal may activate via Print Preview). Include the ADM2 component involved and whether OCX usage is a hard or lazy dependency.
- **Migration Impact**: 32-bit blockers, deprecated APIs, remediation recommendations
- **Interactive Features**:
  - Quick navigation via table of contents links
  - Search/filter box to find specific dependencies
  - Sortable tables (click column headers)
  - Color coding: 🔴 Red (blockers) | 🟡 Yellow (warnings) | 🟢 Green (compatible)
  - Copy-friendly file paths

### Markdown Report (if specified)
A structured text report in the chat window containing:
- List of external dependencies found
- Categorization by dependency type (.NET assemblies, COM/OCX controls, DLLs, OS commands, web services)
- **OS commands classified** into:
  - Standard OS commands (rm, hostname, dir, etc.) - generally available
  - OpenEdge utilities (proserve, proutil, etc.) - always available in OE environment
  - Custom scripts/executables - **focus area** requiring validation
- **Bitness information** (32-bit, 64-bit, or unknown) for DLLs and OCX controls
- **Platform compatibility analysis**: Clearly identify whether code is:
  - ✅ **Windows-only** (contains Windows DLLs or Windows-specific commands)
  - ✅ **Linux/Unix-only** (contains Unix commands or shell scripts)
  - ✅ **Cross-platform** (no platform-specific dependencies)
  - ⚠️ **Mixed** (contains both Windows and Unix dependencies - may indicate conditional code or deployment issues)
- Migration compatibility assessment (flags 32-bit dependencies that may block 64-bit OpenEdge upgrade)
- **ADM2 indirect OCX dependencies** (if detected): list each finding as Confirmed or Possible with the triggering ADM2 component, the OCX it carries, and whether it is a hard or lazy dependency

## Error Handling
- Handle missing or inaccessible files
- Report invalid ABL syntax if encountered

## Examples

### Example 1: Analyzing a single file
```
User: Analyze external dependencies in src/web/CustomerHandler.cls
```
Output:
```
External Dependencies Found in CustomerHandler.cls:
- .NET Assemblies: System.Net.Http.dll, Newtonsoft.Json.dll
- OS Commands: OS-COMMAND "ping 8.8.8.8" (line 45)
```

### Example 2: Analyzing a directory
```
User: Analyze external dependencies in src/winapi/ directory recursively
```
Output:
```
External Dependencies Found (8 files analyzed):

External DLLs (Windows-specific):
  - user32.dll [64-bit] - 40+ functions (window management, UI)
  - kernel32.dll [64-bit] - 20+ functions (process management, file I/O)
  - wsock32.dll [32-bit legacy] ⚠️ - 5 functions (Windows Sockets 1.1)
  - shell32.dll [64-bit] - 5 functions (ShellExecute, folder dialogs)
  - gdi32.dll [64-bit] - 8 functions (graphics, printing)
  - advapi32.dll [64-bit] - 7 functions (registry, user info)
  - ole32.dll [64-bit] - 1 function (COM memory)

Platform Analysis:
  ⚠️ This codebase is **Windows-only** - contains extensive Windows DLL dependencies

Migration Warnings:
  ⚠️ wsock32.dll is legacy (Winsock 1.1) - should migrate to ws2_32.dll or OpenEdge SOCKET API
  ⚠️ All external DLLs are Windows-specific - cannot run on Linux/Unix without refactoring
```

### Example 3: Analyzing workspace
```
User: Analyze all external dependencies in the workspace
```
Output:
```
External Dependencies Found (127 files analyzed):
.NET Assemblies: 8 unique assemblies
COM/OCX Controls: 2 controls
External DLLs: 4 procedures
OS Commands: 15 instances
```

### Example 4: Proper HTML file creation (avoiding file-acceptance prompts in some IDEs)
```powershell
# Read CSS and JS templates with explicit UTF-8 encoding
# <skill-dir> = this skill's folder, resolved from where the skill was loaded
$cssPath = "<skill-dir>\templates\report-styles.css"
$jsPath = "<skill-dir>\templates\report-framework.js"
$logoPath = "<skill-dir>\templates\progresslogo.png"

# CRITICAL: Use -Encoding UTF8 when reading text files to preserve Unicode characters
$cssContent = Get-Content $cssPath -Raw -Encoding UTF8
$jsContent = Get-Content $jsPath -Raw -Encoding UTF8

# Read and encode logo as base64
$logoBytes = [IO.File]::ReadAllBytes($logoPath)
$logoBase64 = [Convert]::ToBase64String($logoBytes)

# Build HTML content as string variable
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$htmlContent = @"
<!DOCTYPE html>
<html>
<head>...</head>
<body>
    <header>
        <div style="display: flex; align-items: center; gap: 20px;">
            <img src="data:image/png;base64,$logoBase64" alt="Progress Logo" style="height: 60px;">
            <div style="flex: 1;">
                <div style="font-size: 0.9em; opacity: 0.9; margin-bottom: 5px;">Progress Professional Services</div>
                <h1 style="margin: 0;">External Dependencies Report</h1>
                ...
            </div>
        </div>
    </header>
    ...complete HTML here...
</body>
</html>
"@

# Write file using UTF-8 WITHOUT BOM (via terminal, not the agent's file-creation tool)
$reportPath = "$env:TEMP\abl-dependency-report-$timestamp.html"

# PowerShell Core/7+ (preferred)
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $htmlContent | Out-File -FilePath $reportPath -Encoding utf8NoBOM
} else {
    # PowerShell 5.1 - use .NET method for UTF-8 without BOM
    [System.IO.File]::WriteAllText($reportPath, $htmlContent, (New-Object System.Text.UTF8Encoding($false)))
}

# Open in browser
Start-Process $reportPath
```

**Why this approach:**
- Writing via the terminal bypasses IDE file tracking (e.g. Copilot's)
- No user prompt asking to accept/reject the generated report
- Report is treated as output, not as source code
- $env:TEMP keeps reports separate from project workspace

## Notes
- **ABL is case-insensitive**: All grep searches are case-insensitive by default, so searching for `os-command` will match `OS-COMMAND`, `Os-Command`, etc.
- **CRITICAL SEARCH APPROACH**: Start with BROAD plain-text searches (e.g., `EXTERNAL`, `.dll`) before using complex regex patterns. Regex patterns that are too specific will miss matches.
- **CRITICAL includePattern ISSUE**:
  - Using `includePattern` with paths like `gui-myapp/**` may NOT work correctly and will miss files
  - **SOLUTION**: Either search globally (omit includePattern) or use file type patterns: `**/*.w`, `**/*.cls`, `**/*.p`
  - If analyzing a specific directory, search globally first, then filter results by path
  - **VERIFY your results**: If you get suspiciously few matches, try searching without includePattern
- **HTML Report Templates**: Located in `templates/` subdirectory:
  - `report-styles.css` - Complete CSS framework (embed in `<style>` tag)
  - `report-framework.js` - Search/sort/toggle JavaScript (embed in `<script>` tag)
  - `section-patterns.md` - Documented HTML patterns for building report sections
  - **CRITICAL**: Read CSS/JS with UTF-8 encoding: `Get-Content -Raw -Encoding UTF8`
  - CSS uses Unicode escape sequences (e.g., `\26A0` for ⚠) to avoid encoding issues
  - All HTML reports must be **self-contained** (no external file references)
  - Reports saved to temp directory: `$env:TEMP\abl-dependency-report-{timestamp}.html`
- **CRITICAL - File Writing**: Use a PowerShell terminal command to write HTML files (UTF-8 WITHOUT BOM)
  - Do NOT use the agent's file-creation tool — in some IDEs (e.g. VS Code Copilot) it triggers file acceptance prompts for users
  - PowerShell Core/7+: `$htmlContent | Out-File -FilePath "$env:TEMP\report.html" -Encoding utf8NoBOM`
  - PowerShell 5.1: `[System.IO.File]::WriteAllText($path, $htmlContent, (New-Object System.Text.UTF8Encoding($false)))`
  - UTF-8 WITHOUT BOM is critical for proper emoji display (🔧, 🔴, 📊, etc.)
  - This writes the file directly without requiring user approval
  - Reports in $env:TEMP keep project workspace clean and separate from source code
- **CRITICAL maxResults HANDLING**:
  - Use high maxResults (500-1000) for DLLs, OCX, and COM searches to ensure comprehensive coverage
  - If results end abruptly or show round numbers (10, 20, 50), run follow-up searches
  - Better to over-retrieve than miss dependencies
- **Examine specialized directories**: `winapi`, `system`, `lib`, `utils` often contain external dependency declarations
- **Read entire files**: External procedures are often grouped (e.g., 50+ procedures in one file)
- **Platform dependency indicators**:
  - **Windows-only**: DLL references, Windows paths (C:\, backslashes), Windows commands (dir, copy, del)
  - **Linux/Unix-only**: Unix commands (sleep, chmod), shell scripts (.sh), Unix paths (/usr/, /var/)
  - **Mixed platforms**: May indicate conditional compilation ({&OPSYS})
- **Bitness determination** (critical for 64-bit OpenEdge migration):
  - 32-bit DLLs/ActiveX controls will NOT work with 64-bit OpenEdge
  - Check local files first, examine PE headers, or use web search for vendor info
  - Windows: System32 = 64-bit, SysWOW64 = 32-bit
- **ActiveX controls**: Most are 32-bit only and BLOCK 64-bit migration; require .wrx files at runtime
- **COM automation**: Requires Office/apps installed; works with both 32/64-bit but requires matching bitness
- **Security analysis - Command injection risks**:
  - ALWAYS perform taint analysis for OS-COMMAND and INPUT THROUGH statements
  - Trace command parameters backward to their ultimate source
  - User-controlled input in OS commands = CRITICAL security vulnerability
  - Even "unused" files should document theoretical risks
  - Follow call chains: if file has callers, analyze what they pass to command parameters
  - **Risk classification by source**:
    - 🔴 CRITICAL: Web params, HTTP headers, form fields, URL paths → OS command
    - 🟠 HIGH: Database/file content users can modify → OS command
    - 🟡 MEDIUM: Config files, env vars (admin-only) → OS command
    - 🟢 LOW: Hardcoded constants, validated enums
    - ℹ️ UNKNOWN: Cannot trace source (manual review required)
  - **Look for security controls**: LOOKUP(), CASE statements, REPLACE() sanitization, regex validation
  - **Remediation priorities**:
    1. Use allowlists (LOOKUP against known-good values)
    2. Validate format with regex before execution
    3. Avoid user input in commands entirely (use APIs instead)
    4. If unavoidable: strict escaping + length limits + logging
