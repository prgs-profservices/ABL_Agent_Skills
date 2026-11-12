# HTML Section Patterns for ABL Dependency Reports

This document provides reusable HTML patterns for building dependency reports. All patterns use the CSS classes from `report-styles.css` and JavaScript functions from `report-framework.js`.

---

## 1. Page Structure

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>External Dependencies Report - [PROJECT NAME]</title>
    <style>
        /* Embed contents of report-styles.css here */
    </style>
</head>
<body>
    <div class="container">
        <!-- Header -->
        <header>...</header>

        <!-- Search Box -->
        <div class="search-container">...</div>

        <!-- Summary Cards -->
        <div class="summary">...</div>

        <!-- Table of Contents -->
        <div class="toc-container">...</div>

        <!-- Main Content with Sections -->
        <div class="content">...</div>
    </div>

    <script>
        /* Embed contents of report-framework.js here */
    </script>
</body>
</html>
```

**CRITICAL - Character Encoding:**
- File MUST be saved as UTF-8 WITHOUT BOM to properly display Unicode emojis (🔧, 🔴, 📊, etc.)
- PowerShell 5.1's `-Encoding UTF8` writes UTF-8 WITH BOM (causes display issues)
- PowerShell Core/7+ supports `-Encoding utf8NoBOM` (recommended)
- For PowerShell 5.1: Use `[System.IO.File]::WriteAllText($path, $content, (New-Object System.Text.UTF8Encoding($false)))`

**Flow:**
1. Header with title and metadata
2. Search box for filtering
3. Summary cards with key metrics
4. Table of contents for quick navigation
5. Main content with collapsible sections

---

## 2. Header Section

```html
<header>
    <div style="display: flex; align-items: center; gap: 20px;">
        <img src="data:image/png;base64,[BASE64_ENCODED_LOGO]" alt="Progress Logo" style="height: 60px;">
        <div style="flex: 1;">
            <div style="font-size: 0.9em; opacity: 0.9; margin-bottom: 5px;">Progress Professional Services</div>
            <h1 style="margin: 0;">External Dependencies Report</h1>
            <p style="margin: 5px 0 0 0;"><strong>Project:</strong> [PROJECT_NAME] | <strong>Analyzed:</strong> [FILE_COUNT] ABL files | <strong>Date:</strong> [DATE]</p>
        </div>
    </div>
</header>
```

**Customize:**
- Replace [BASE64_ENCODED_LOGO] with actual base64 string from progresslogo.png
- Update project name, file count, and date
- Logo reads from: `templates/progresslogo.png` inside the analyze-abl-dependencies skill folder
- Embedded as data URI for self-contained HTML

---

## 3. Search Box

```html
<div class="search-container">
    <input type="text" class="search-box" id="searchBox" placeholder="🔎 Search dependencies by file name, type, or description...">
</div>
```

**Note:** The `searchBox` ID is required for JavaScript functionality

---

## 4. Table of Contents (Quick Navigation)

```html
<div class="toc-container">
    <div class="toc-links">
        <a href="#external-executables" class="toc-link">🔧 External Executables</a>
        <a href="#os-commands" class="toc-link">🖥️ OS Commands</a>
        <a href="#dotnet-assemblies" class="toc-link">.NET Assemblies</a>
        <a href="#com-activex" class="toc-link">COM/ActiveX</a>
        <a href="#external-dlls" class="toc-link">External DLLs</a>
        <a href="#platform-analysis" class="toc-link">📊 Platform Analysis</a>
        <a href="#code-quality" class="toc-link">🐛 Code Quality</a>
        <a href="#migration" class="toc-link">🔄 Migration Impact</a>
    </div>
</div>
```

**Usage:**
- Place immediately after summary cards, before main content
- Update links to match actual section IDs in your report
- Include only sections that exist in the report
- Use emoji icons for visual hierarchy
- Section IDs must match the `id` attribute on corresponding `<div class="section">` elements

**Link Format:**
- `href="#section-id"` - Must match ID on target section
- `class="toc-link"` - Required for styling
- Include emoji/icon before text for visual consistency with section headers

**Example with Section IDs:**
```html
<!-- Table of Contents -->
<div class="toc-container">
    <div class="toc-links">
        <a href="#external-executables" class="toc-link">🔧 External Executables</a>
        <a href="#com-activex" class="toc-link">COM/ActiveX Controls</a>
    </div>
</div>

<!-- Main Content -->
<div class="content">
    <div class="section" id="external-executables">
        <div class="section-header" onclick="toggleSection(this)">
            ...
        </div>
    </div>

    <div class="section" id="com-activex">
        <div class="section-header" onclick="toggleSection(this)">
            ...
        </div>
    </div>
</div>
```

---

## 5. Summary Cards Grid

```html
<div class="summary">
    <div class="summary-card">
        <h3>ABL Files Analyzed</h3>
        <div class="value">127</div>
    </div>
    <div class="summary-card">
        <h3>.NET Assemblies</h3>
        <div class="value">8</div>
    </div>
    <div class="summary-card success">
        <h3>COM/ActiveX Controls</h3>
        <div class="value">0</div>
    </div>
    <div class="summary-card success">
        <h3>External DLLs (Win32)</h3>
        <div class="value">0</div>
    </div>
    <div class="summary-card">
        <h3>Total DLL Files</h3>
        <div class="value">7</div>
    </div>
    <div class="summary-card warning">
        <h3>Unreferenced DLLs</h3>
        <div class="value">3</div>
    </div>
</div>
```

**CRITICAL Rules:**
- **Always include cards for standard dependency types** even if count is 0:
  - ABL Files Analyzed
  - .NET Assemblies (if applicable to the project)
  - COM/ActiveX Controls (always show, use 0 if none)
  - External DLLs / Win32 DLLs (always show, use 0 if none)
  - OS Commands (always show, use 0 if none)
- **For file inventory metrics, use clear DLL-specific labels:**
  - "Total DLL Files" (not "Files Found")
  - "Referenced DLLs" or "DLLs Used in Code" (not "Used in Code")
  - "Unreferenced DLLs" or "Unused DLL Files" (not "Unused Files")
- **Zero counts should use success (green) styling** to indicate "clean" status

**Card Types:**
- Default (blue): `<div class="summary-card">`
- Warning (red): `<div class="summary-card warning">` - for issues/blockers
- Success (green): `<div class="summary-card success">` - for zero counts or compatible items

**Customize:**
- Update h3 text and value for different metrics
- Use warning class for high-risk items (unreferenced files, 32-bit blockers)
- Use success class for zero counts (no COM, no DLLs = good for migration)

---

## 6. Main Content Container

```html
<div class="content">
    <!-- Impact sections, collapsible sections, etc. go here -->
    <!-- IMPORTANT: Add id attributes to sections for TOC linking -->
    <div class="section" id="external-executables">
        ...
    </div>
</div>
```

**Note:** Always add `id` attributes to sections if using Table of Contents

---

## 7. Impact/Warning Section (Yellow)

```html
<div class="impact-section">
    <h3>⚠️ [SECTION TITLE]</h3>
    <ul class="impact-list">
        <li><strong>[ITEM TITLE]:</strong> [DESCRIPTION]</li>
        <li><strong>[ITEM TITLE]:</strong> [DESCRIPTION]</li>
    </ul>
</div>
```

**Variants:**
- Warning (yellow): `<div class="impact-section">`
- Critical (red): `<div class="impact-section critical">`
- Info (blue): `<div class="impact-section info">`

---

## 8. Collapsible Section with Table

```html
<div class="section">
    <div class="section-header" onclick="toggleSection(this)">
        <h2>
            <span class="severity-indicator severity-[critical|warning|info]"></span>
            [SECTION TITLE]
            <span class="badge [red|yellow|green|blue]">[COUNT] FILES</span>
            <span class="platform-indicator platform-[windows|linux|mixed|cross]">[PLATFORM]</span>
        </h2>
        <span class="toggle-icon">▼</span>
    </div>
    <div class="section-body expanded">
        <p><strong>Impact:</strong> [IMPACT DESCRIPTION]</p>

        <table>
            <thead>
                <tr>
                    <th onclick="sortTable(this, 0)">[COLUMN 1]</th>
                    <th onclick="sortTable(this, 1)">[COLUMN 2]</th>
                    <th onclick="sortTable(this, 2)">[COLUMN 3]</th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td class="file-path">[FILE NAME]</td>
                    <td>[DATA]</td>
                    <td><span class="badge [red|yellow|green]">[LABEL]</span></td>
                </tr>
            </tbody>
        </table>
    </div>
</div>
```

**Severity Indicators:**
- `severity-critical` (red dot)
- `severity-warning` (yellow dot)
- `severity-info` (green dot)

**Badge Colors:**
- `badge red` - Critical/blocking issues
- `badge yellow` - Warnings
- `badge green` - Compatible/safe
- `badge blue` - Informational

**Platform Indicators:**
- `platform-windows` - Windows only (blue)
- `platform-linux` - Linux only (green)
- `platform-mixed` - Mixed platforms (orange)
- `platform-cross` - Cross-platform (green)

**Section Body Expansion:**
- Add `expanded` class to show by default
- Omit to collapse by default

---

## 9. Recommendations Box

```html
<div class="recommendations">
    <h3>💡 Recommendations</h3>
    <ul>
        <li>[RECOMMENDATION 1]</li>
        <li>[RECOMMENDATION 2]</li>
        <li>[RECOMMENDATION 3]</li>
    </ul>
</div>
```

**Use Cases:**
- Migration guidance
- Best practices
- Alternative solutions
- Action items

---

## 10. Security Analysis - Command Injection Risks

**Purpose:** Document OS command execution points and trace data flow to identify command injection vulnerabilities.

```html
<div class="section" id="security-analysis">
    <div class="section-header" onclick="toggleSection(this)">
        <h2>
            <span class="severity-indicator severity-critical"></span>
            🔒 Security Analysis - Command Injection Risks
            <span class="badge red">CRITICAL</span>
        </h2>
        <span class="toggle-icon">▼</span>
    </div>
    <div class="section-body expanded">
        <p><strong>Impact:</strong> OS command execution with user-controlled input can allow attackers to execute arbitrary commands on the server, leading to data theft, system compromise, or complete server takeover.</p>

        <!-- Critical Risk Example -->
        <div class="impact-section critical">
            <h3>🔴 Command Execution Points Identified</h3>
            <p>The following locations execute OS commands. Each has been analyzed for command injection risk based on the source of command parameters.</p>
        </div>

        <table>
            <thead>
                <tr>
                    <th onclick="sortTable(this, 0)">File</th>
                    <th onclick="sortTable(this, 1)">Line</th>
                    <th onclick="sortTable(this, 2)">Statement Type</th>
                    <th onclick="sortTable(this, 3)">Parameter</th>
                    <th onclick="sortTable(this, 4)">Data Source</th>
                    <th onclick="sortTable(this, 5)">Risk Level</th>
                    <th onclick="sortTable(this, 6)">Validation</th>
                </tr>
            </thead>
            <tbody>
                <!-- CRITICAL RISK - User input reaches OS command -->
                <tr>
                    <td class="file-path">src/web/FileHandler.cls</td>
                    <td>156</td>
                    <td>INPUT THROUGH</td>
                    <td><code>cCommand</code></td>
                    <td>Web request parameter "cmd"</td>
                    <td><span class="badge red">🔴 CRITICAL</span></td>
                    <td><span class="badge red">NONE</span></td>
                </tr>

                <!-- HIGH RISK - Database content (user-modifiable) -->
                <tr>
                    <td class="file-path">src/batch/RunJob.p</td>
                    <td>78</td>
                    <td>OS-COMMAND</td>
                    <td><code>pc-command</code></td>
                    <td>Job.CommandLine DB field</td>
                    <td><span class="badge yellow">🟠 HIGH</span></td>
                    <td><span class="badge yellow">LENGTH LIMIT</span></td>
                </tr>

                <!-- MEDIUM RISK - Config file -->
                <tr>
                    <td class="file-path">src/system/AppConfig.cls</td>
                    <td>203</td>
                    <td>OS-COMMAND</td>
                    <td><code>cArchiveCmd</code></td>
                    <td>config.xml (admin-only)</td>
                    <td><span class="badge yellow">🟡 MEDIUM</span></td>
                    <td><span class="badge green">FILE VALIDATION</span></td>
                </tr>

                <!-- LOW RISK - Hardcoded -->
                <tr>
                    <td class="file-path">src/util/NetworkCheck.p</td>
                    <td>45</td>
                    <td>INPUT THROUGH</td>
                    <td><code>(inline)</code></td>
                    <td>Hardcoded "ping 8.8.8.8"</td>
                    <td><span class="badge green">🟢 LOW</span></td>
                    <td><span class="badge green">N/A</span></td>
                </tr>

                <!-- UNKNOWN RISK - Cannot trace -->
                <tr>
                    <td class="file-path">src/lib/oscommand.i</td>
                    <td>60</td>
                    <td>INPUT THROUGH</td>
                    <td><code>pc-command</code></td>
                    <td>Parameter (cannot trace callers)</td>
                    <td><span class="badge blue">ℹ️ UNKNOWN</span></td>
                    <td><span class="badge blue">NOT USED</span></td>
                </tr>
            </tbody>
        </table>

        <h3 style="margin-top: 30px;">🔍 Data Flow Analysis</h3>

        <div style="background: #fff3bf; padding: 15px; margin: 15px 0; border-left: 4px solid #e67700; border-radius: 4px;">
            <h4 style="color: #e67700; margin-bottom: 10px;">🔴 CRITICAL: src/web/FileHandler.cls:156</h4>
            <p><strong>Statement:</strong> <code>INPUT THROUGH VALUE(cCommand)</code></p>
            <p><strong>Data Flow Trace:</strong></p>
            <ol style="padding-left: 20px; margin: 10px 0;">
                <li><code>cCommand</code> assigned at line 145: <code>cCommand = oRequest:GetParameter("cmd"):GetValue()</code></li>
                <li><code>oRequest</code> is WebRequest object containing user HTTP parameters</li>
                <li><strong>Source:</strong> User-controlled URL/form parameter "cmd"</li>
                <li><strong>Validation:</strong> NONE - parameter passed directly to OS</li>
            </ol>
            <p style="color: #c92a2a; font-weight: bold; margin-top: 15px;">⚠️ VULNERABILITY: Arbitrary command injection possible. Attacker can execute any OS command.</p>
            <p><strong>Example Attack:</strong> <code>?cmd=dir | del /F /Q *.db</code></p>
        </div>

        <div style="background: #fff3bf; padding: 15px; margin: 15px 0; border-left: 4px solid #e67700; border-radius: 4px;">
            <h4 style="color: #e67700; margin-bottom: 10px;">🟠 HIGH: src/batch/RunJob.p:78</h4>
            <p><strong>Statement:</strong> <code>OS-COMMAND VALUE(pc-command)</code></p>
            <p><strong>Data Flow Trace:</strong></p>
            <ol style="padding-left: 20px; margin: 10px 0;">
                <li><code>pc-command</code> assigned at line 65: <code>ASSIGN pc-command = Job.CommandLine</code></li>
                <li><code>Job.CommandLine</code> is a database field that users can modify via web UI</li>
                <li><strong>Source:</strong> Database (user-modifiable through admin interface)</li>
                <li><strong>Validation:</strong> Length limit (200 chars) but no content validation</li>
            </ol>
            <p style="color: #e67700; font-weight: bold; margin-top: 15px;">⚠️ RISK: Admin users could inject malicious commands. Length limit provides minimal protection.</p>
        </div>

        <div style="background: #e7f5ff; padding: 15px; margin: 15px 0; border-left: 4px solid #1864ab; border-radius: 4px;">
            <h4 style="color: #1864ab; margin-bottom: 10px;">ℹ️ UNKNOWN: src/lib/oscommand.i:60</h4>
            <p><strong>Statement:</strong> <code>INPUT THROUGH VALUE(pc-command)</code></p>
            <p><strong>Data Flow Trace:</strong></p>
            <ol style="padding-left: 20px; margin: 10px 0;">
                <li><code>pc-command</code> is an INPUT parameter to the procedure</li>
                <li><strong>Cross-reference check:</strong> File is NOT used anywhere in workspace (no includes found)</li>
                <li><strong>Theoretical Risk:</strong> If used, could be vulnerable depending on calling context</li>
            </ol>
            <p style="color: #1864ab; font-weight: bold; margin-top: 15px;">ℹ️ STATUS: Unused code - theoretical risk only. Consider removing if truly obsolete.</p>
        </div>

        <div class="recommendations">
            <h3>🛡️ Remediation Guidance - Priority Order</h3>
            <ol>
                <li><strong>🔴 CRITICAL (Immediate):</strong>
                    <ul>
                        <li><strong>FileHandler.cls:156</strong> - Use allowlist validation:
                            <pre style="background: #f1f3f5; padding: 10px; border-radius: 4px; margin: 10px 0;"><code>DEFINE VARIABLE cValidCommands AS CHARACTER NO-UNDO
    INITIAL "backup,export,cleanup".
IF LOOKUP(cCommand, cValidCommands) = 0 THEN
    UNDO, THROW NEW AppError("Invalid command", 400).
/* Execute only if in allowlist */</code></pre>
                        </li>
                        <li>Alternative: Remove OS command feature entirely - use ABL APIs instead</li>
                    </ul>
                </li>
                <li><strong>🟠 HIGH (This Sprint):</strong>
                    <ul>
                        <li><strong>RunJob.p:78</strong> - Add strict validation:
                            <pre style="background: #f1f3f5; padding: 10px; border-radius: 4px; margin: 10px 0;"><code>/* Validate format: only alphanumeric, spaces, hyphens */
IF NOT CAN-DO("*[^A-Za-z0-9 \-]*", Job.CommandLine) THEN
    UNDO, THROW NEW AppError("Invalid characters in command", 400).
/* Add executable allowlist check */
DEFINE VARIABLE cExecutable AS CHARACTER NO-UNDO.
cExecutable = ENTRY(1, Job.CommandLine, " ").
IF LOOKUP(cExecutable, "backup.bat,export.cmd") = 0 THEN
    UNDO, THROW NEW AppError("Executable not allowed", 400).</code></pre>
                        </li>
                        <li>Restrict Job.CommandLine editing to superadmin role only</li>
                    </ul>
                </li>
                <li><strong>Best Practices (All Cases):</strong>
                    <ul>
                        <li>Prefer ABL APIs over OS commands (e.g., use FILE-INFO instead of dir/ls)</li>
                        <li>Use SUBSTITUTE() with position parameters, not concatenation</li>
                        <li>Log all OS command executions with user context</li>
                        <li>Run OpenEdge processes with minimal OS privileges</li>
                        <li>Consider using SAFE-EXECUTE if available (OpenEdge 12.0+)</li>
                    </ul>
                </li>
            </ol>
        </div>

        <div style="margin-top: 30px; padding: 20px; background: #ffe0e0; border-left: 4px solid #c92a2a; border-radius: 4px;">
            <h3 style="color: #c92a2a;">⚠️ Overall Security Posture</h3>
            <p><strong>Risk Level:</strong> <span class="badge red" style="font-size: 1.2em;">CRITICAL</span></p>
            <p style="margin-top: 15px;"><strong>Summary:</strong></p>
            <ul style="margin: 10px 0 10px 20px;">
                <li>🔴 <strong>1 CRITICAL</strong> vulnerability: Direct user input to OS command</li>
                <li>🟠 <strong>1 HIGH</strong> risk: Database-driven commands with weak validation</li>
                <li>🟡 <strong>1 MEDIUM</strong> risk: Config-file commands (admin-controlled)</li>
                <li>🟢 <strong>1 LOW</strong> risk: Hardcoded commands (safe)</li>
                <li>ℹ️ <strong>1 UNKNOWN</strong>: Unused file with theoretical risk</li>
            </ul>
            <p style="margin-top: 15px; font-weight: bold; color: #c92a2a;">
                ⚠️ IMMEDIATE ACTION REQUIRED: Fix critical vulnerability before production deployment.
            </p>
        </div>
    </div>
</div>
```

**Risk Classification:**
- 🔴 **CRITICAL**: Web request parameters, HTTP headers, URL paths → OS command (direct RCE)
- 🟠 **HIGH**: Database fields, file uploads users can control
- 🟡 **MEDIUM**: Config files, environment variables (admin-only)
- 🟢 **LOW**: Hardcoded constants, validated enums
- ℹ️ **UNKNOWN**: Cannot trace source (needs manual review)

**Data Flow Trace Structure:**
1. Show the OS-COMMAND/INPUT THROUGH statement
2. Trace variable backward through assignments
3. Identify ultimate source (user input, DB, config, hardcoded)
4. Document validation (or lack thereof)
5. Classify risk and provide specific remediation

**Presentation Guidelines:**
- Always expand this section by default (security is critical)
- Use color-coded detail boxes for each finding
- Show concrete code examples for remediation
- Prioritize fixes: Critical → High → Medium
- Include example attack scenarios for critical risks
- Note if file is unused (theoretical risk only)

**When to Include:**
- Any time OS-COMMAND or INPUT THROUGH found
- Even for "safe" hardcoded commands (document low risk)
- For unused files (document theoretical risk)
- Priority: Show this section early in report (high visibility)

---

## 11. Subsection Headings (within section-body)

```html
<h3 style="margin-top: 20px;">📊 [SUBSECTION TITLE]</h3>
<p>[DESCRIPTION]</p>
```

**Emoji Examples:**
- 📊 Excel/Data
- 📝 Word/Documents
- 📧 Email/Messaging
- 🔧 Tools/Utilities
- ⚙️ Configuration
- 🗂️ Files/Directories

---

## 12. Inline Code Formatting

```html
<code>[CODE OR COMMAND]</code>
```

**Use For:**
- Function names
- Commands
- File extensions
- Technical terms

---

## 13. File Path Formatting

```html
<td class="file-path">[path/to/file.ext]</td>
```

**Styling:** Monospace font, gray color, word-break for long paths

---

## 14. Table with Centered Muted Text (for grouping)

```html
<tr>
    <td colspan="3" style="text-align: center; color: #868e96; font-style: italic;">
        [MESSAGE - e.g., "+ 21 additional files in other workspace"]
    </td>
</tr>
```

---

## 15. Migration Assessment Table

```html
<table>
    <thead>
        <tr>
            <th>Dependency Type</th>
            <th>32-bit → 64-bit</th>
            <th>Windows → Linux</th>
            <th>Effort</th>
        </tr>
    </thead>
    <tbody>
        <tr>
            <td>[DEPENDENCY TYPE]</td>
            <td><span class="badge [red|green|yellow]">[STATUS]</span></td>
            <td><span class="badge [red|green|yellow]">[STATUS]</span></td>
            <td><span class="badge [red|yellow|green]">[EFFORT LEVEL]</span></td>
        </tr>
    </tbody>
</table>
```

**Status Labels:**
- `BLOCKER` (red)
- `Compatible` (green)
- `Refactor` (yellow)
- `Deprecated` (yellow)

**Effort Levels:**
- `High` / `Very High` (red)
- `Medium` (yellow)
- `Low` (green)

---

## 16. Summary Box (colored background)

```html
<div style="margin-top: 30px; padding: 20px; background: #[COLOR]; border-left: 4px solid #[BORDER_COLOR]; border-radius: 4px;">
    <h3 style="color: #[TEXT_COLOR];">[ICON] [TITLE]</h3>
    <p><strong>[CONCLUSION LABEL]:</strong> [CONCLUSION TEXT]</p>
    <ul>
        <li>[POINT 1]</li>
        <li>[POINT 2]</li>
    </ul>
    <p style="margin-top: 15px;"><strong>[LABEL]:</strong> [ESTIMATED EFFORT]</p>
</div>
```

**Color Schemes:**
- Red (Critical): bg `#ffe0e0`, border `#c92a2a`, text `#c92a2a`
- Yellow (Warning): bg `#fff3bf`, border `#e67700`, text `#e67700`
- Blue (Info): bg `#e7f5ff`, border `#1864ab`, text `#1864ab`
- Green (Success): bg `#d3f9d8`, border `#2b8a3e`, text `#2b8a3e`

---

## Tips for Creating New Sections

1. **Always use semantic structure:** header → body → tables/lists
2. **Keep consistent spacing:** Use margin/padding values from existing patterns
3. **Use descriptive badge colors:** Red = blocker, Yellow = warning, Green = safe, Blue = info
4. **Add severity indicators** to section headers for quick visual scanning
5. **Include platform indicators** when dependencies are OS-specific
6. **Provide actionable recommendations** at the end of each major section
7. **Use inline code formatting** for technical terms, commands, and file names
8. **Make tables sortable** by adding `onclick="sortTable(this, N)"` to headers
9. **Group related data** in subsections with emoji headings for visual distinction
10. **Test search functionality** - ensure important keywords appear in section text

---

## 17. File Inventory Section (External Dependency Files)

**Purpose:** Show ONLY .dll, .ocx, and .wrx files found in the analyzed directory, indicating which are referenced in code.

**CRITICAL:** Do NOT include ABL source files (.cls, .p, .w), configuration files (.xml, .json), or other project files. Only external dependency binaries.

```html
<div class="section">
    <div class="section-header collapsed" onclick="toggleSection(this)">
        <h2>
            <span class="severity-indicator severity-info"></span>
            📦 File Inventory - External Dependencies
            <span class="badge blue">X FILES</span>
        </h2>
        <span class="toggle-icon">▼</span>
    </div>
    <div class="section-body">
        <p>All external dependency files (.dll, .ocx, .wrx) found in the analyzed directory. This inventory helps identify deployment bloat, unused binaries, and cleanup opportunities.</p>
        <p><strong>Note:</strong> Only external dependency files are listed here. ABL source files and configuration files are not included in this inventory.</p>

        <table>
            <thead>
                <tr>
                    <th onclick="sortTable(this, 0)">File Name</th>
                    <th onclick="sortTable(this, 1)">Type</th>
                    <th onclick="sortTable(this, 2)">Referenced in Code</th>
                    <th onclick="sortTable(this, 3)">Location</th>
                    <th onclick="sortTable(this, 4)">Notes</th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td><code>MyLib.dll</code></td>
                    <td>.NET Assembly</td>
                    <td><span class="badge green">USED</span></td>
                    <td class="file-path">c:\project\MyLib.dll</td>
                    <td>Referenced in 3 files</td>
                </tr>
                <tr>
                    <td><code>xOldLib.dll</code></td>
                    <td>.NET Assembly</td>
                    <td><span class="badge yellow">NOT USED</span></td>
                    <td class="file-path">c:\project\xOldLib.dll</td>
                    <td>Appears to be old/backup version</td>
                </tr>
            </tbody>
        </table>

        <div class="recommendations">
            <h3>File Cleanup Recommendations</h3>
            <ul>
                <li>Remove files with "x" prefix (typically backup/test versions)</li>
                <li>Archive or delete unused files to reduce deployment size</li>
                <li>Document why files are kept if they appear unused</li>
            </ul>
        </div>
    </div>
</div>
```

**Customization:**
- Badge color: Green = Used, Yellow = Not Used, Red = Missing but referenced
- Notes column: Explain naming patterns (x prefix, _old suffix, version numbers)
- Include file size if relevant for deployment analysis

---

## 18. Development Observations / Notes Section

**Purpose:** Capture findings that don't fit into standard dependency sections - oddities, technical debt, cleanup opportunities.

```html
<div class="section">
    <div class="section-header collapsed" onclick="toggleSection(this)">
        <h2>
            <span class="severity-indicator severity-info"></span>
            📝 Development Observations
            <span class="badge blue">NOTES</span>
        </h2>
        <span class="toggle-icon">▼</span>
    </div>
    <div class="section-body">
        <p>Additional observations about the codebase that may be relevant for maintenance, deployment, or migration planning.</p>

        <h3>📂 Code Organization</h3>
        <ul>
            <li>Only 3 .cls files (2 wrappers + 1 test)</li>
            <li>8 .p files (mostly demos and tests)</li>
            <li>Clean structure with <code>security\</code> and <code>system\</code> subdirectories</li>
        </ul>

        <h3>🧹 Technical Debt</h3>
        <ul>
            <li>Commented-out code in showversion.p: <code>//USING System.Environment FROM ASSEMBLY</code></li>
            <li>Empty files: <code>kerbticketlib.p</code> and <code>test2.p</code> contain no code</li>
            <li>Multiple similar implementations: 3 different Kerberos libraries suggest experimental/testing phase</li>
        </ul>

        <h3>🗑️ Cleanup Opportunities</h3>
        <ul>
            <li>3 unused DLL files: <code>xKerberosHelper.dll</code>, <code>xxKerberosHelper.dll</code>, <code>KerberosToOECP.dll</code></li>
            <li>Consider consolidating Kerberos implementations to a single library</li>
            <li>Remove or document empty .p files</li>
        </ul>

        <h3>✅ Quality Indicators</h3>
        <ul>
            <li><code>results.xml</code> file indicates ABLUnit tests have been run</li>
            <li>Consistent file header comments in all source files</li>
            <li>Clear separation of concerns (security, system utilities)</li>
        </ul>

        <div class="impact-section info">
            <h3>Workspace Context</h3>
            <p>This appears to be a <strong>development/testing workspace</strong> rather than production code, based on:
            <ul class="impact-list">
                <li>Multiple versions of similar DLLs (x, xx prefixes)</li>
                <li>Empty or stub files</li>
                <li>Mix of demos and actual utilities</li>
                <li>ABLUnit test classes present</li>
            </ul>
            <p><strong>Recommendation:</strong> Before deployment, consolidate to production-ready versions and remove experimental code.</p>
        </div>
    </div>
</div>
```

**Customization:**
- Use emoji section headers (📂 📝 🧹 🗑️ ✅ ⚠️) for visual organization
- Organize by theme: Organization, Technical Debt, Cleanup, Quality, Testing
- Use inline <code> tags for file names and code snippets
- Add impact-section box at end for high-level context
- Be specific but concise - focus on actionable observations

**When to Use:**
- Unused files found in directory
- Naming patterns suggesting versioning (x prefix, _old suffix)
- Empty or stub files
- Commented-out code
- Multiple implementations of same functionality
- Quality indicators (tests, documentation)
- Deployment-specific notes

---

## Creating Custom Dependency Types

When you encounter new dependency types not covered by existing sections:

1. **Create a new collapsible section** using pattern #7
2. **Choose appropriate severity indicator** (critical/warning/info)
3. **Add platform indicator** if OS-specific
4. **Use a relevant badge color** and count
5. **Structure data in a sortable table** if multiple items
6. **Include impact statement** at the top of section-body
7. **Add recommendations box** with migration/remediation guidance
8. **Use subsections** if dependency has multiple categories

**Example for a new "Database Connectors" section:**

```html
<div class="section">
    <div class="section-header" onclick="toggleSection(this)">
        <h2>
            <span class="severity-indicator severity-info"></span>
            Database Connectors
            <span class="badge blue">3 DRIVERS</span>
            <span class="platform-indicator platform-cross">CROSS-PLATFORM</span>
        </h2>
        <span class="toggle-icon">▼</span>
    </div>
    <div class="section-body expanded">
        <p><strong>Impact:</strong> [Your impact description]</p>
        <!-- Your custom table/content here -->
    </div>
</div>
```
