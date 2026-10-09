# ABL Agent Skills

Agent skills and documentation for OpenEdge ABL.

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
Scanner 2.1.0 does not support Windows ARM64 hosts, even with emulated x64 Python;
VMware Fusion does not change that Windows guest limitation. Native macOS ARM64
or a Linux ARM64 VM is supported. Use a separate checkout and virtual environment
for each OS rather than sharing the Windows venv or bypassing the hook.

See the [security baseline](docs/security-baseline.md) for activation steps,
scan policy, and outstanding requirements.
