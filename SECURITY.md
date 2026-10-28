# Security Policy

## Reporting a Vulnerability

Do not open a public issue or PR for security problems. Report them privately
through GitHub's private vulnerability reporting:

<https://github.com/prgs-profservices/ABL_Agent_Skills/security/advisories/new>

This includes:

- a skill that contains harmful, misleading, or prompt-injection instructions
- a skill or helper file that exfiltrates data or runs unexpected commands
- a weakness in the repository's workflows or scanning pipeline
- a leaked credential in the repository or its history

Please include the affected skill or file, the release or commit, and the steps
needed to reproduce the problem. Maintainers will acknowledge the report, work
on a fix privately, and publish an advisory when a fix is released.

## Supported Versions

Fixes are made on `main` and shipped in the next release. Older releases are
not patched; upgrade to the latest release to get security fixes.

## How Skills Are Checked

Every change to `main` passes the required checks described in
[CONTRIBUTING.md](CONTRIBUTING.md), including the Cisco AI Skill Scanner, and is
approved by a maintainer. Automated scans reduce risk but do not guarantee that
a skill is safe; review any skill before giving it to an agent.
