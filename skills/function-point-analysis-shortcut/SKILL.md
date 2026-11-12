---
name: function-point-analysis-shortcut
description: Estimate a project's rebuild effort and cost using a fast function-point-analysis shortcut (NESMA Indicative Function Point Count — data functions only, no transaction rating) instead of a full FPA, then convert the result to hours and price using user-supplied hours-per-FP and price-per-hour rates.
license: Apache-2.0
allowed-tools: Read, Grep, Glob, Write
compatibility: Cross-platform, OpenEdge project (openedge-project.json)
---

<!--
function-point-analysis-shortcut: Estimate a project's rebuild effort and cost using a fast function-point-analysis shortcut (NESMA Indicative Function Point Count — data functions only, no transaction rating) instead of a full FPA, then convert the result to hours and price using user-supplied hours-per-FP and price-per-hour rates.

Copyright 2026 Progress Software Corporation
SPDX-License-Identifier: Apache-2.0
-->

## When to Use
- The user wants a rough, order-of-magnitude estimate of what it would cost to **rebuild an existing project from scratch**.
- The user explicitly does **not** want a full function point analysis (which requires enumerating and complexity-rating every External Input, External Output, and External Query — a multi-day exercise).
- A fast, defensible, standards-based number is preferred over a made-up figure.

**Not for**: contractual or certified FP counts, or sizing where accuracy matters (a full IFPUG/NESMA count, accurate to roughly ±10%, is required for that). This shortcut is for early, indicative sizing only.

## Method
This skill uses the **NESMA Indicative Function Point Count** — a recognized, published shortcut method (not an invented heuristic). It counts only **data functions** and skips transactional functions and complexity rating entirely:

- **ILF (Internal Logical File)**: a user-recognizable group of logically related data (or control information) that the application being sized *maintains* (creates, updates, or deletes).
- **EIF (External Interface File)**: a user-recognizable group of logically related data that the application references or reads but that is maintained by another application or system.
- Every ILF and EIF is assumed to be **average complexity** — no low/high rating is attempted (that's what makes this a shortcut instead of a full count).

**Formula (unadjusted function points):**

```
FP = 35 × (number of ILF) + 15 × (number of EIF)
```

Published NESMA data indicates indicative counts typically land within about ±30% of a detailed count — good enough for early sizing, not for contracts. State this caveat in every report.

**The whole basis of this shortcut is database tables — nothing else is counted.** Do not scan the ABL source for CRUD usage, do not look at UI or business logic, and do not go looking for non-OpenEdge schema sources (ORM models, migrations, GraphQL, etc.). Every ILF/EIF comes from the project's `.df` database definitions, found via `openedge-project.json`.

## Required Inputs
Ask for these explicitly if not already provided — do not silently assume them:

1. **Scope** — which repo, directory, or subsystem to analyze (default: the whole current project if the user doesn't narrow it).
2. **Hours per function point** — suggest **6** as a reasonable starting point, but ask the user to confirm or override it before finalizing the estimate, since it varies a lot by tech stack, team seniority, and how much legacy behavior must be reverse-engineered.
3. **Price per hour** — required, no sensible default; always ask.

If the user already supplied hours/FP and/or price/hour in their request, don't ask again for those — just confirm the values you'll use.

## Process

### 1. Determine scope
Confirm which part of the codebase is in scope (default: the whole current project).

### 2. Find the project's databases via openedge-project.json
1. Locate `openedge-project.json` in the project root. If it doesn't exist, tell the user this skill needs it (or a manually-supplied list of database connections/`.df` files) and stop rather than guessing.
2. Read its `dbConnections` array — each entry is a database the project uses. Note each entry's `name` (logical database name).

### 3. Locate the .df file for each database connection
For each entry in `dbConnections`, find its schema definitions file, in this order:
1. An explicit schema/path field on the connection entry itself, if `openedge-project.json` has one (e.g. `schemaFile`).
2. A top-level `schemaFile` attribute in `openedge-project.json`, if present.
3. A `<name>.df` file in a `Schema/` or `schema/` folder, or at the workspace root.
4. Otherwise, use the **dump-database-df** skill to generate one from a live connection.

If no `.df` can be found or generated for a given database, tell the user which one is missing and ask them to point to the file — do not fabricate a table count.

### 4. Count tables per .df file
Read each located `.df` file and count its `ADD TABLE "<name>"` statements — **one table = one candidate logical file**. This is the entire counting basis; no grouping, folding, or exclusion heuristics are applied.

### 5. Classify each database's tables as ILF or EIF
- If the project has a **single** database connection, all of its tables are **ILF** (the app maintains its own database).
- If the project has **multiple** database connections, ask the user which connection(s) hold the database being rebuilt (**ILF**) versus which are external/reference databases the app only reads (**EIF**) — this skill does not infer ownership by scanning code, so ask rather than guess.

### 6. Count and calculate
- Count total ILF and total EIF.
- Apply the formula: `FP = 35 × ILF + 15 × EIF`.
- Confirm hours-per-FP and price-per-hour with the user (see Required Inputs).
- Estimated effort (hours) = `FP × hours-per-FP`
- Estimated rebuild cost = `effort hours × price-per-hour`

### 7. Report
Produce the report described in Expected Output below.

## Expected Output
A Markdown report containing:

1. **Scope analyzed** — the repo or directory and the database connection(s) found in `openedge-project.json`.
2. **Logical file inventory** — a table: `Table | Database | Type (ILF/EIF) | Source (.df file)`, one row per table.
3. **Totals** — ILF count, EIF count.
4. **FP calculation** — shown explicitly: `35 × <ILF> + 15 × <EIF> = <FP> function points`.
5. **Inputs used** — hours per FP, price per hour (state where each came from: user-specified or the suggested default).
6. **Effort estimate** — `<FP> × <hours/FP> = <hours> hours`.
7. **Cost estimate** — `<hours> × <price/hour> = <cost>`.
8. **Caveats** — this is an indicative estimate (NESMA Indicative FP Count), excludes all transactional functions (EI/EO/EQ), which in a full count often make up more than half of total FP; typical accuracy is roughly ±30% versus a detailed count; not suitable for contractual sizing.

## Example

```
User: Estimate the rebuild value of the OrderService project. Use 6 hours per FP and $85/hour.
```

Output:
```
## Rebuild Estimate — OrderService

Found in openedge-project.json: dbConnections = [orderdb, catalogdb (read-only reference DB)]

### Logical Files (tables)
| Table         | Database  | Type | Source        |
|---------------|-----------|------|---------------|
| Customer      | orderdb   | ILF  | orderdb.df    |
| Order         | orderdb   | ILF  | orderdb.df    |
| OrderLine     | orderdb   | ILF  | orderdb.df    |
| Product       | catalogdb | EIF  | catalogdb.df  |
| PriceList     | catalogdb | EIF  | catalogdb.df  |

ILF = 3, EIF = 2

FP = 35 × 3 + 15 × 2 = 135 function points

### Estimate
- Hours per FP: 6 (user-specified)
- Price per hour: $85 (user-specified)
- Effort: 135 × 6 = 810 hours
- Estimated rebuild cost: 810 × $85 = $68,850

### Caveats
Indicative estimate only (NESMA Indicative Function Point Count — data functions only,
average complexity assumed, no transactional functions counted). Typically within ±30%
of a detailed count; not suitable for contractual sizing.
```

## Notes
- This is a recognized shortcut (NESMA Indicative Function Point Count), not an ad hoc heuristic — say so in the report so stakeholders can judge its reliability.
- Never invent a price-per-hour or silently pick a non-default hours-per-FP without telling the user what was used.
- If `openedge-project.json` or a database's `.df` file can't be found or generated, say so and ask the user rather than guessing a table count — an FP estimate with fabricated inputs is worse than no estimate.
- This skill depends on **dump-database-df** (to generate a `.df` when one doesn't already exist) and reads `openedge-project.json` the same way **determine-oe-params** does.
