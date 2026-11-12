---
name: markdown-to-word
description: "Convert a Markdown (.md) file to a Word (.docx) document. Use when the user asks to turn a markdown file into a Word doc, generate a .docx from a .md file, or export markdown as Word."
license: Apache-2.0
allowed-tools: Read, Grep, Glob, Write, Bash, PowerShell, Python
compatibility: Windows, PowerShell 5.1+ or Bash, Python 3.8+
---

<!--
markdown-to-word: Convert a Markdown (.

Copyright 2026 Progress Software Corporation
SPDX-License-Identifier: Apache-2.0
-->

## Canonical Script

A ready-to-run Python implementation lives in this skill's own folder:

```
<skill-dir>/convert-md-to-docx.py
```

`<skill-dir>` is the directory containing this SKILL.md; resolve it from where the skill was loaded rather than hardcoding a root like `.github/skills` or `.claude/skills`.

Run it directly — do not reconstruct the logic inline:

```powershell
python "<skill-dir>\convert-md-to-docx.py" "<input.md>" "<output.docx>"
```

The output path is optional; if omitted the `.docx` is written next to the input file with the same base name.

---

## When to Use

Use this skill when the user asks to:
- Convert a Markdown file to a Word document
- "Turn this markdown into a Word doc / .docx"
- Export or share a `.md` file as a `.docx`

---

## Prerequisites

The script requires the `python-docx` Python package.

### Step 1: Check and install dependencies

```powershell
pip show python-docx 2>&1 | Select-String "Version|not found"
```

If `python-docx` is **not installed**, install the pinned, reviewed version — do not install the latest unconditionally:

```powershell
pip install python-docx==1.1.2
```

`python-docx` is a pure-Python package and installs in a few seconds.

**Dependency policy (supply chain):**
- **Approved version**: `1.1.2` (recorded here; update only after review).
- **Trusted source**: PyPI only (`python-docx` by the `python-openxml` project).
- **No unversioned installs**: avoids dependency drift and pulling an unreviewed release.
- Ask the user before installing anything; skip installation if the approved version is already present.

---

## Process

### Step 2: Identify the input file

The user's current file is the target unless they specify otherwise.

### Step 3: Determine the output path

- Default: same directory as the input file, same base name, `.docx` extension.
- Override: use whatever path the user specifies.

### Step 4: Run the conversion

```powershell
python "<skill-dir>\convert-md-to-docx.py" "docs\my-document.md"
```

Or with an explicit output path:

```powershell
python "<skill-dir>\convert-md-to-docx.py" "docs\my-document.md" "docs\my-document.docx"
```

### Step 5: Confirm the output

After the script exits with code 0, verify the file was created:

```powershell
Get-Item "<output.docx>" | Select-Object Name, Length, LastWriteTime
```

Report the output path to the user.

---

## What the Script Converts

| Markdown element | Word output |
|---|---|
| `# H1` … `#### H4` | Word Heading 1–4 styles |
| `---` horizontal rule | Bottom-border paragraph |
| `|` table | Word table with bold header row, "Table Grid" style |
| ` ``` ` code fences | Grey-shaded Courier New 9pt block |
| `` `inline code` `` | Courier New 9pt run |
| `**bold**` | Bold run |
| `*italic*` | Italic run |
| `[text](url)` links | Plain text (link stripped, display text kept) |
| `> blockquote` | Indented, light-grey-shaded paragraph |
| `- ` / `* ` bullet list | Word "List Bullet" style |
| `1. ` numbered list | Word "List Number" style |
| Normal paragraphs | Word "Normal" style (Calibri 11pt) |

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `ModuleNotFoundError: No module named 'docx'` | Run `pip install python-docx==1.1.2` |
| `Error: file not found` | Check the path — use forward slashes or quote the path |
| Tables appear as plain text | Ensure each row starts and ends with `\|` |
| Code blocks not shaded | Ensure fences are exactly ` ``` ` with no extra characters before them |

## Security & execution requirements

- **Execution capability**: This skill executes the bundled Python script `convert-md-to-docx.py`; it reads a `.md` file and writes a `.docx` file. No database or network access.
- **Supply chain**: `python-docx` is pinned to reviewed version `1.1.2` from PyPI; see the Prerequisites section above for the dependency policy.
- **Safeguards**: the script is resolved only from the canonical skill directory (`<skill-dir>`) and verified before execution — missing script = stop.

## Script integrity

Verify the bundled script(s) before first use: `Get-FileHash <file> -Algorithm SHA256` and compare to the values below. If a hash does not match, stop and review the file before executing. Hashes are regenerated whenever a bundled script changes (see the skills README).

| File | SHA-256 |
|---|---|
| `convert-md-to-docx.py` | `A0587BD50A3731AEACD983AA5325ED568BCCFD00001EA0BCD3DA127F7E03CC6B` |
