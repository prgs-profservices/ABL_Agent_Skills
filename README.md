# ABL Agent Skills

Skills that help AI coding agents work with OpenEdge ABL projects: compiling
and running code, ABLUnit testing, database schema changes, code review,
modernization and audits.

A skill is a folder with instructions (`SKILL.md`) and optional helper
scripts. Agents that support the open skills format load a skill when a task
needs it.

## Install

With Node.js installed, run this in your project:

```bash
npx skills add prgs-profservices/ABL_Agent_Skills
```

The command lets you choose which skills to install and for which agents.
Other useful forms:

```bash
# List all skills without installing
npx skills add prgs-profservices/ABL_Agent_Skills --list

# Install one skill
npx skills add prgs-profservices/ABL_Agent_Skills --skill compile-openedge-abl

# Install a specific release
npx skills add prgs-profservices/ABL_Agent_Skills@v1.0.0
```

Without a version you get the latest `main`, which has passed review and all
security scans. See the
[releases page](https://github.com/prgs-profservices/ABL_Agent_Skills/releases)
for versions.

Without Node.js, clone the repository and copy or symlink a folder from
`skills/` into the skills directory your agent uses.

## Skills

<!-- pyml disable line-length -->

### Project setup

| Skill | What it does |
| --- | --- |
| [detect-editor](skills/detect-editor/) | Detect whether the user is running VS Code or Devin to open files in the correct editor. |
| [determine-oe-params](skills/determine-oe-params/) | Extract OpenEdge runtime parameters (extraParameters and database connections) from openedge-project.json for running or compiling ABL programs. |
| [get-project-dlc](skills/get-project-dlc/) | Determine the OpenEdge installation path (DLC) for the current project. |
| [get-source-directories](skills/get-source-directories/) | Identify all compilable source directories from openedge-project.json, respecting includes and excludes filters. |
| [get-workspace-propath](skills/get-workspace-propath/) | Extract PROPATH from openedge-project.json buildPath configuration. |
| [make-project-ini](skills/make-project-ini/) | Create a .ini file to set the PROPATH when running an OpenEdge program. |
| [resolve-vscode-settings-path](skills/resolve-vscode-settings-path/) | Resolve the absolute path to the user's VS Code settings.json file. |

### Compile, run and test

| Skill | What it does |
| --- | --- |
| [compile-openedge-abl](skills/compile-openedge-abl/) | Compile or verify compilation of an OpenEdge ABL source file (.cls, .w, .i, or .p), including when building, changing, or checking ABL code. |
| [compile-xref](skills/compile-xref/) | For an ABL source file, generate an xref file which can be used to analyze the code, including which indexes are used for queries. |
| [run-openedge-program](skills/run-openedge-program/) | Execute an OpenEdge ABL program (.p, .cls, or .w file) from the command line. |
| [create-ablunit-tests](skills/create-ablunit-tests/) | Create an ABLUnit test class for a given OpenEdge ABL program that the user wants testing for. |
| [find-ablunit-tests](skills/find-ablunit-tests/) | Locate existing ABLUnit test files for a given OpenEdge ABL source file. |
| [test-with-ablunit](skills/test-with-ablunit/) | Test ABL programs (.w, .cls, .p) by running ABLUnit tests. |

### Databases

| Skill | What it does |
| --- | --- |
| [create-openedge-database](skills/create-openedge-database/) | Create an empty OpenEdge database from structure and schema definition files. |
| [load-openedge-schema](skills/load-openedge-schema/) | Load OpenEdge database schema from .df files using OpenEdge DevOps Framework (OEDF) LoadDBSchema task. |
| [dump-database-df](skills/dump-database-df/) | Create a database definitions (.df) file (a.k.a. "dump a schema") for a given database. |
| [add-openedge-db-field](skills/add-openedge-db-field/) | Add a new field to an OpenEdge database table by generating a .df schema file. |
| [drop-openedge-db-field](skills/drop-openedge-db-field/) | Remove a field from an OpenEdge database table by generating a .df schema file. |
| [simplify-st-file](skills/simplify-st-file/) | Simplify an OpenEdge production database structure file to minimum definition for creating an empty database. |

### Code review and modernization

| Skill | What it does |
| --- | --- |
| [openedge-code-review](skills/openedge-code-review/) | Review OpenEdge ABL code files for conformance to coding standards and best practices. |
| [modernize-variables](skills/modernize-variables/) | Convert legacy DEFINE VARIABLE syntax to modern VAR syntax in ABL code. |
| [tighten-up](skills/tighten-up/) | Reduce code volume for a file while keeping the functionality the same. |
| [purge-junk-files](skills/purge-junk-files/) | Clean up an ABL codebase by identifying and removing old backup copies, version-suffixed files, and temporary junk files. |

### Analysis and audits

| Skill | What it does |
| --- | --- |
| [abl-project-metrics](skills/abl-project-metrics/) | Compute project size and scope metrics for an OpenEdge ABL project, keeping production functional source separate from test source. |
| [analyze-abl-dependencies](skills/analyze-abl-dependencies/) | Analyze OpenEdge ABL code to determine external (non-ABL) dependencies such as .NET assemblies, Java classes, COM objects, DLLs, and web services. |
| [analyze-oe-profile](skills/analyze-oe-profile/) | Parse an OpenEdge PROFILER v3 .out or .prof file and report the hottest source lines by exclusive (self) CPU time, using the LineSummary section for accurate per-line attribution. |
| [audit-abl-memory-leaks](skills/audit-abl-memory-leaks/) | Analyze OpenEdge ABL source for potential memory/resource leak patterns and generate an interactive HTML report with risk-ranked findings. |
| [audit-linux-path-compatibility](skills/audit-linux-path-compatibility/) | Analyze ABL source for Linux path compatibility blockers such as Windows-style separators, hard-coded absolute paths, and non-relative path usage in RUN/include/file I/O contexts. |
| [audit-os-command-execution](skills/audit-os-command-execution/) | Analyze ABL code to inventory OS command execution points and generate a target-platform OS command compatibility audit after two AI passes (unresolved command resolution, then platform-only and gating review). |
| [find-encrypted-source](skills/find-encrypted-source/) | Scan ABL source files in the project to identify which ones are XCODE-encrypted (start with byte 0x13), and write results to a CSV in the docs/ folder. |
| [function-point-analysis-shortcut](skills/function-point-analysis-shortcut/) | Estimate a project's rebuild effort and cost using a fast function-point-analysis shortcut (NESMA Indicative Function Point Count — data functions only, no transaction rating) instead of a full FPA, then convert the result to hours and price using user-supplied hours-per-FP and price-per-hour rates. |

### Documentation

| Skill | What it does |
| --- | --- |
| [markdown-to-word](skills/markdown-to-word/) | Convert a Markdown (.md) file to a Word (.docx) document. |

<!-- pyml enable line-length -->

## Contributing

New skills and fixes are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md).
Report security problems privately as described in
[SECURITY.md](SECURITY.md).

## License

Apache License 2.0, see [LICENSE](LICENSE) and [NOTICE](NOTICE). Each skill
folder includes its own LICENSE.txt and NOTICE.txt, so installed skills keep
their license terms.
