# ABL Agent Skills

Agent skills and documentation for OpenEdge ABL.

## Installing Skills

Install from a release to get a fixed, scanned version:

```bash
npx skills add prgs-profservices/ABL_Agent_Skills#<release-tag>
```

Without a tag, `npx skills add prgs-profservices/ABL_Agent_Skills` installs the
latest commit on `main`. Everything on `main` has passed the required scans and
review, but it may contain changes that are not yet in a release. See the
[releases](https://github.com/prgs-profservices/ABL_Agent_Skills/releases) for
available versions.

## Contributing and Security

See [CONTRIBUTING.md](CONTRIBUTING.md) to add a skill, and
[SECURITY.md](SECURITY.md) to report a problem privately. This project is
licensed under the [MIT License](LICENSE).

## Development

Use Python 3.13 and Git:

```powershell
py -3.13 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv\Scripts\python.exe -m pre_commit install
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
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

See the [security baseline](docs/security-baseline.md) for activation steps,
scan policy, and outstanding requirements. Maintainers: see the
[maintainer guide](docs/maintainers.md) for reviewing community PRs and
publishing releases.
