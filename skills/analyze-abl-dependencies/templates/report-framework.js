/*
 * Copyright 2026 Progress Software Corporation
 * SPDX-License-Identifier: Apache-2.0
 */

/* ABL External Dependencies Report - JavaScript Framework */
/* Version: 1.0 | Date: 2026-02-06 */

// Search functionality - filters sections and table rows based on search term
document.getElementById('searchBox').addEventListener('input', function(e) {
    const searchTerm = e.target.value.toLowerCase();
    const sections = document.querySelectorAll('.section');

    sections.forEach(section => {
        const text = section.textContent.toLowerCase();
        if (text.includes(searchTerm) || searchTerm === '') {
            section.style.display = 'block';
            // Expand section if search matches
            if (searchTerm !== '') {
                const header = section.querySelector('.section-header');
                const body = section.querySelector('.section-body');
                header.classList.remove('collapsed');
                body.classList.add('expanded');
            }
        } else {
            section.style.display = 'none';
        }
    });

    // Search within tables
    const rows = document.querySelectorAll('tbody tr');
    rows.forEach(row => {
        const text = row.textContent.toLowerCase();
        if (text.includes(searchTerm) || searchTerm === '') {
            row.style.display = '';
        } else {
            row.style.display = 'none';
        }
    });
});

// Toggle section expansion - called via onclick in section headers
function toggleSection(header) {
    header.classList.toggle('collapsed');
    const body = header.nextElementSibling;
    body.classList.toggle('expanded');
}

// Table sorting - called via onclick in table headers
function sortTable(th, columnIndex) {
    const table = th.closest('table');
    const tbody = table.querySelector('tbody');
    const rows = Array.from(tbody.querySelectorAll('tr'));

    const isAscending = th.classList.contains('sort-asc');

    // Remove sort classes from all headers
    table.querySelectorAll('th').forEach(header => {
        header.classList.remove('sort-asc', 'sort-desc');
    });

    // Sort rows
    rows.sort((a, b) => {
        const aText = a.cells[columnIndex].textContent.trim();
        const bText = b.cells[columnIndex].textContent.trim();

        if (isAscending) {
            return bText.localeCompare(aText);
        } else {
            return aText.localeCompare(bText);
        }
    });

    // Update sort indicator
    th.classList.add(isAscending ? 'sort-desc' : 'sort-asc');

    // Reorder rows
    rows.forEach(row => tbody.appendChild(row));
}

// Expand first few sections by default
document.addEventListener('DOMContentLoaded', function() {
    const sections = document.querySelectorAll('.section-header');
    sections.forEach((section, index) => {
        if (index < 5) {  // Expand first 5 sections
            const body = section.nextElementSibling;
            section.classList.remove('collapsed');
            body.classList.add('expanded');
        }
    });
});
