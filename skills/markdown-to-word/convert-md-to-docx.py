# Copyright 2026 Progress Software Corporation
# SPDX-License-Identifier: Apache-2.0

"""
convert-md-to-docx.py
Convert a Markdown file to a Word (.docx) document.

Usage:
    python convert-md-to-docx.py <input.md> [output.docx]

If the output path is omitted the .docx is written next to the input file.

Requires:  python-docx  (pip install python-docx==1.1.2)
"""

import re
import sys
from pathlib import Path

from docx import Document
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt


# ---------------------------------------------------------------------------
# Inline formatting helpers
# ---------------------------------------------------------------------------

def strip_links(t: str) -> str:
    """Remove markdown hyperlinks, keeping only the display text."""
    return re.sub(r'\[([^\]]+)\]\([^\)]*\)', r'\1', t)


def strip_inline_bold(t: str) -> str:
    """Remove **bold** markers, keeping the text."""
    return re.sub(r'\*\*([^*]+)\*\*', r'\1', t)


def add_runs(para, text: str):
    """
    Append inline-formatted runs to *para*.
    Handles **bold**, `code`, and *italic* spans.
    """
    text = strip_links(text)
    tokens = re.split(r'(\*\*[^*]+\*\*|`[^`]+`|\*[^*]+\*)', text)
    for tok in tokens:
        if not tok:
            continue
        if tok.startswith('**') and tok.endswith('**') and len(tok) > 4:
            r = para.add_run(tok[2:-2])
            r.bold = True
        elif tok.startswith('`') and tok.endswith('`') and len(tok) > 2:
            r = para.add_run(tok[1:-1])
            r.font.name = 'Courier New'
            r.font.size = Pt(9)
        elif tok.startswith('*') and tok.endswith('*') and len(tok) > 2:
            r = para.add_run(tok[1:-1])
            r.italic = True
        else:
            para.add_run(tok)


# ---------------------------------------------------------------------------
# Structural helpers
# ---------------------------------------------------------------------------

def shade_para(p, fill: str = 'F2F2F2'):
    """Apply a background fill colour to a paragraph."""
    pPr = p._p.get_or_add_pPr()
    shd = OxmlElement('w:shd')
    shd.set(qn('w:val'), 'clear')
    shd.set(qn('w:color'), 'auto')
    shd.set(qn('w:fill'), fill)
    pPr.append(shd)


def add_hrule(doc):
    """Insert a thin horizontal rule paragraph."""
    p = doc.add_paragraph()
    pPr = p._p.get_or_add_pPr()
    pBdr = OxmlElement('w:pBdr')
    bot = OxmlElement('w:bottom')
    bot.set(qn('w:val'), 'single')
    bot.set(qn('w:sz'), '6')
    bot.set(qn('w:space'), '1')
    bot.set(qn('w:color'), '999999')
    pBdr.append(bot)
    pPr.append(pBdr)


def flush_table(doc, rows: list):
    """Render accumulated markdown table rows as a Word table."""
    if not rows:
        return
    # Drop separator rows (e.g.  |---|---|)
    data = [r for r in rows if not re.match(r'^\|[\-\s:|]+\|?\s*$', r)]
    if not data:
        return
    parsed = [[c.strip() for c in r.strip('|').split('|')] for r in data]
    ncols = max(len(r) for r in parsed)
    tbl = doc.add_table(rows=len(parsed), cols=ncols)
    tbl.style = 'Table Grid'
    for ri, row in enumerate(parsed):
        for ci in range(ncols):
            cell_text = row[ci] if ci < len(row) else ''
            cell = tbl.cell(ri, ci)
            para = cell.paragraphs[0]
            if ri == 0:
                r = para.add_run(strip_links(strip_inline_bold(cell_text)))
                r.bold = True
            else:
                add_runs(para, cell_text)
    doc.add_paragraph()


# ---------------------------------------------------------------------------
# Main conversion
# ---------------------------------------------------------------------------

def convert(md_path: Path, out_path: Path):
    with md_path.open(encoding='utf-8') as f:
        lines = f.read().splitlines()

    doc = Document()
    style = doc.styles['Normal']
    style.font.name = 'Calibri'
    style.font.size = Pt(11)

    in_code = False
    code_lines: list[str] = []
    in_table = False
    tbl_rows: list[str] = []
    para_lines: list[str] = []

    def flush_para():
        nonlocal para_lines
        if not para_lines:
            return
        text = ' '.join(para_lines).strip()
        if text:
            p = doc.add_paragraph()
            add_runs(p, text)
        para_lines = []

    def flush_tbl():
        nonlocal tbl_rows, in_table
        flush_table(doc, tbl_rows)
        tbl_rows = []
        in_table = False

    def flush_code():
        nonlocal code_lines
        for cl in code_lines:
            p = doc.add_paragraph()
            p.style = 'No Spacing'
            r = p.add_run(cl)
            r.font.name = 'Courier New'
            r.font.size = Pt(9)
            shade_para(p)
        code_lines = []

    i = 0
    while i < len(lines):
        raw = lines[i]
        line = raw.rstrip()
        stripped = line.strip()

        # ---- Code fences ------------------------------------------------
        if stripped.startswith('```'):
            if not in_code:
                flush_para()
                if in_table:
                    flush_tbl()
                in_code = True
            else:
                flush_code()
                in_code = False
            i += 1
            continue

        if in_code:
            code_lines.append(line)
            i += 1
            continue

        # ---- Table rows -------------------------------------------------
        if stripped.startswith('|'):
            flush_para()
            in_table = True
            tbl_rows.append(stripped)
            i += 1
            continue
        elif in_table:
            flush_tbl()

        # ---- Blank line -------------------------------------------------
        if stripped == '':
            flush_para()
            i += 1
            continue

        # ---- Horizontal rule (--- alone) --------------------------------
        if re.match(r'^-{3,}\s*$', stripped) or re.match(r'^\*{3,}\s*$', stripped):
            flush_para()
            add_hrule(doc)
            i += 1
            continue

        # ---- Headings ---------------------------------------------------
        m = re.match(r'^(#{1,4})\s+(.*)', stripped)
        if m:
            flush_para()
            lvl = len(m.group(1))
            htxt = strip_links(strip_inline_bold(m.group(2)))
            doc.add_heading(htxt, level=lvl)
            i += 1
            continue

        # ---- Blockquotes (may span multiple lines) ----------------------
        if stripped.startswith('>'):
            flush_para()
            while i < len(lines) and lines[i].strip().startswith('>'):
                qt = lines[i].strip()
                qt_text = qt[1:].lstrip() if len(qt) > 1 else ''
                if qt_text:
                    p = doc.add_paragraph()
                    p.style = 'Normal'
                    p.paragraph_format.left_indent = Inches(0.4)
                    p.paragraph_format.space_before = Pt(2)
                    p.paragraph_format.space_after = Pt(2)
                    shade_para(p, 'F8F8F8')
                    add_runs(p, qt_text)
                i += 1
            continue

        # ---- Unordered list ---------------------------------------------
        if re.match(r'^[-*+]\s+', stripped):
            flush_para()
            item = re.sub(r'^[-*+]\s+', '', stripped)
            p = doc.add_paragraph(style='List Bullet')
            add_runs(p, item)
            i += 1
            continue

        # ---- Ordered list -----------------------------------------------
        if re.match(r'^\d+\.\s+', stripped):
            flush_para()
            item = re.sub(r'^\d+\.\s+', '', stripped)
            p = doc.add_paragraph(style='List Number')
            add_runs(p, item)
            i += 1
            continue

        # ---- Hard line break (trailing two spaces) ----------------------
        if raw.endswith('  '):
            if para_lines:
                para_lines.append(stripped)
                flush_para()
            else:
                p = doc.add_paragraph()
                add_runs(p, stripped)
            i += 1
            continue

        # ---- Normal paragraph text --------------------------------------
        para_lines.append(stripped)
        i += 1

    # Flush any remaining state
    flush_para()
    if in_table:
        flush_tbl()
    if in_code:
        flush_code()

    doc.save(out_path)
    print(f'Saved: {out_path}')


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    md_path = Path(sys.argv[1])
    if not md_path.exists():
        print(f'Error: file not found: {md_path}', file=sys.stderr)
        sys.exit(1)

    out_path = Path(sys.argv[2]) if len(sys.argv) >= 3 else md_path.with_suffix('.docx')
    convert(md_path, out_path)
