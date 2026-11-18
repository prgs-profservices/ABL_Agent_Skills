# Contributing

Thank you for helping build agent skills for OpenEdge ABL. Every contribution is
reviewed by a maintainer and scanned before it can be merged.

## Adding a Skill

Create one directory per skill under `skills/`:

```text
skills/
  my-skill-name/
    SKILL.md
    LICENSE.txt    (exact copy of the repository LICENSE)
    NOTICE.txt     (exact copy of the repository NOTICE)
    (optional helper files)
```

Every skill carries its own license files because tools such as
`npx skills add` install only the skill's directory, not the repository root.
Copy them unchanged:

```bash
cp LICENSE skills/my-skill-name/LICENSE.txt
cp NOTICE skills/my-skill-name/NOTICE.txt
```

`SKILL.md` starts with YAML frontmatter, followed by the license header as an
HTML comment, followed by the instructions:

<!-- pyml disable line-length -->
```markdown
---
name: my-skill-name
description: One or two sentences on what the skill does and when to use it.
---

<!--
my-skill-name: One line describing the purpose of the skill.

Copyright © 2026 Progress Software Corporation and/or its subsidiaries or affiliates. All Rights Reserved.
SPDX-License-Identifier: Apache-2.0
-->

Instructions for the agent.
```
<!-- pyml enable line-length -->

The header is a short reference because `LICENSE.txt` and `NOTICE.txt`, copied
below, already ship the full terms in every skill folder. Code files in the
skill directory (`.py`, `.sh`, `.ps1`, `.js`, `.ts`, and ABL `.p`, `.w`, `.cls`,
`.i`) start with the same Copyright and SPDX lines in that language's comment
syntax, for example `#` lines in Python or a `/* ... */` block in ABL.

The validator enforces these rules on every PR:

- `name` uses lowercase letters, numbers and hyphens, is at most 64 characters,
  and matches the directory name.
- `description` is not empty and is at most 1024 characters.
- The license header comment directly follows the frontmatter and contains the
  official Progress copyright line, exactly as in the template above and in
  `NOTICE`, and `SPDX-License-Identifier: Apache-2.0`. Only the year may
  differ, as a single year or a range such as `2026-2027`.
- There are instructions after the header.
- `LICENSE.txt` and `NOTICE.txt` exist and are exact copies of the repository
  `LICENSE` and `NOTICE`.
- Code files in the skill directory contain the license header.
- Symlinks are not allowed.

Keep helper files to what the skill needs. Do not include secrets, credentials,
internal URLs, customer data, or instructions that hide what the skill does.

## Development Setup

Use Python 3.13 and Git:

```powershell
py -3.13 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r tooling/requirements-dev.txt
.\.venv\Scripts\python.exe -m pre_commit install
.\.venv\Scripts\python.exe -m unittest discover -s tooling/tests -t tooling -v
.\.venv\Scripts\python.exe -m pre_commit run --all-files
```

On Linux/macOS, use `.venv/bin/python` instead of the Windows path.
Pre-commit checks all committed files in CI. Before the first commit, run it
with `--files` and the candidate filenames instead of `--all-files`.

Cisco Skill Scanner runs statically in pre-commit and Linux CI, with a separate
Nuclia semantic check for PRs and pre-publication scans. It scans all Git-visible
`SKILL.md` directories, including helper files. Empty scope is reported explicitly.
The scanner does not support Windows ARM64 hosts, even with emulated x64 Python;
VMware Fusion does not change that Windows guest limitation. Native macOS ARM64
or a Linux ARM64 VM is supported. Use a separate checkout and virtual environment
for each OS rather than sharing the Windows venv or bypassing the hook.

Maintainers: see [tooling/docs/maintainers.md](tooling/docs/maintainers.md).

## Local Checks

Follow the setup in [Development Setup](#development-setup), then run:

```bash
pre-commit run --all-files
```

The Cisco skill scanner hook needs Python 3.13 on a supported platform; see
[Development Setup](#development-setup) if it cannot run on your machine.

## How a Contribution Is Reviewed

1. Fork the repository, create a branch, and open a PR against `main`.
2. A maintainer approves running the workflows on your PR. The checks that need
   no credentials then run: content validation, TruffleHog secret scanning, and
   the Cisco static skill scan.
3. A maintainer reviews the changes by hand.
4. The Cisco semantic scan, Polaris and Black Duck need repository credentials,
   which GitHub never gives to fork PRs, so those checks fail on your PR by
   design. After review, a maintainer copies your commits to a branch in this
   repository and opens a new PR. Your commits and authorship are kept, and the
   original PR is closed with a link to the new one.
5. The PR is merged when all required checks pass, all review conversations are
   resolved, and a code owner has approved it.

Changes to `.github/`, `tooling/` and `.pre-commit-config.yaml` are made by
maintainers only.

## Releases

Maintainers publish releases by tagging a commit on `main`. Each release tag
re-runs the Cisco, Black Duck and Polaris scans before the GitHub Release is
created.

## License

This project is licensed under the [Apache License 2.0](LICENSE); see also
[NOTICE](NOTICE). Under Section 5 of the License, any contribution you
intentionally submit for inclusion in this project is provided under the terms
of the Apache License 2.0, without any additional terms or conditions, unless
you explicitly state otherwise.

Progress Software Corporation, as the licensor, decides whether a contribution
is incorporated. Opening a PR does not guarantee that it will be merged.
