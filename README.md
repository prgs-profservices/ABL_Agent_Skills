# ABL Agent Skills

Agent skills and documentation for OpenEdge ABL.

## Development

Use Python 3.12 or newer and Git:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv\Scripts\python.exe -m pre_commit install
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
.\.venv\Scripts\python.exe -m pre_commit run --all-files
```

On Linux/macOS, use `.venv/bin/python` instead of the Windows path.
Pre-commit checks all committed files in CI. Before the first commit, run it
with `--files` and the candidate filenames instead of `--all-files`.

See the [security baseline](docs/security-baseline.md) for activation steps,
scan policy, and outstanding requirements.
