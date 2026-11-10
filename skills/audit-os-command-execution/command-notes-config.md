# command-notes-config.json Reference

This file documents the schema and tuning guidance for `command-notes-config.json`, which lives next to this file in the audit-os-command-execution skill folder.

## Top-level Keys
- `platformRules`: deterministic platform classification rules.
- `ignoreFileGlobs`: glob-style file patterns to fully exclude from deterministic scanning.
- `basicUnixCommands`: baseline Unix commands used for dependency filtering.
- `openEdgeCommands`: OpenEdge utility commands.
- `commandNotes`: migration concern notes keyed by command token.

## ignoreFileGlobs
Purpose: fully skip matching files during deterministic extraction. Skipped files are never scanned and never appear in output rows.

Pattern style: glob/minimatch-like patterns using `/` separators.

Examples:
- `**/blah.*` matches files named `blah.*` in any directory.
- `**/*.bak*` matches backup-style files.
- `src/legacy/**` matches everything under a legacy subtree.
- `**/tmp/**` matches files under any `tmp` directory.
- `**/mark/*` matches files directly under any `mark` subdirectory.

Behavior notes:
- Matching is performed on workspace-relative file paths with `/` separators.
- Patterns are case-insensitive in this script implementation.
- Use this only for files you intentionally want to exclude because they are not used by your environment.

## platformRules
Purpose: classify each usage row into `windows`, `linux`, `both`, or `unknown` before any AI pass.

### windowsTokenSuffixes
Array of lowercase filename suffixes that indicate Windows-oriented executables/scripts.

Examples:
- `.exe`
- `.bat`
- `.cmd`
- `.vbs`

### windowsCommands
Array of lowercase exact command tokens that should classify as `windows`.

Examples:
- `regsvr32`
- `cmd.exe`
- `cscript`
- `wscript`

### windowsStatementHints
Array of lowercase statement substrings that indicate Windows paths or logic.
These are matched case-insensitively against the statement text.

Examples:
- `win32`
- `msos-command`
- `.bat`
- `.exe`

### linuxCommands
Array of lowercase exact command tokens that should classify as `linux`.
These are typically shell commands expected on Linux/Unix hosts.

Examples:
- `cp`
- `mv`
- `chmod`
- `grep`
- `sendmail`
- `date`
- `who`
- `echo`

### bothCommands
Array of lowercase exact command tokens that should classify as `both` (cross-platform).
These are commands that we KNOW are cross-platform:
- OpenEdge utilities (pro, proserve, quoter, pform, pform3, pcl2pdf, etc.)
- Interpreters (perl, python, ruby, java, javac, node, npm)
- Version control (git, svn)
- Network tools (curl, wget)

Checked BEFORE other platform rules during classification.

### linuxPathPrefixes
Array of lowercase prefixes that classify tokens as Linux-oriented paths.

Examples:
- `/`
- `$dlc/`
- `$pform/`

### unknownDefault
Fallback classification used when no deterministic rule matches.
Allowed values are:
- `unknown` (recommended)
- `both` (rarely used)
- `windows`
- `linux`

## Tuning Guidance
- Keep all entries lowercase for consistency.
- Prefer exact command tokens over broad hints.
- Add entries to `bothCommands` ONLY for commands you KNOW are truly cross-platform.
- Add common Unix commands to `linuxCommands` to reduce AI review overhead.
- If a rule causes misclassification, remove or narrow it and regenerate the report.
- Keep this JSON as pure data (no inline metadata/comment fields).

## Runtime Behavior
- Deterministic pass checks `bothCommands` first, then `windows`/`linux` rules, before falling back to `unknownDefault`.
- Rows classified as `both` are safe to exclude from platform-specific compatibility reviews.
- AI pass should process only rows classified as `unknown`.
- Deterministic `windows`/`linux`/`both` classifications should not be overwritten during routine AI runs.
