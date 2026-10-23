# Contributing

Thank you for helping build agent skills for OpenEdge ABL. Every contribution is
reviewed by a maintainer and scanned before it can be merged.

## Adding a Skill

Create one directory per skill under `skills/`:

```text
skills/
  my-skill-name/
    SKILL.md
    (optional helper files)
```

`SKILL.md` starts with YAML frontmatter, followed by the instructions:

```markdown
---
name: my-skill-name
description: One or two sentences on what the skill does and when to use it.
---

Instructions for the agent.
```

The validator enforces these rules:

- `name` uses lowercase letters, numbers and hyphens, is at most 64 characters,
  and matches the directory name.
- `description` is not empty and is at most 1024 characters.
- There are instructions after the frontmatter.
- Symlinks are not allowed.

Keep helper files to what the skill needs. Do not include secrets, credentials,
internal URLs, customer data, or instructions that hide what the skill does.

## Local Checks

Follow the setup in the [README](README.md), then run:

```bash
pre-commit run --all-files
```

The Cisco skill scanner hook needs Python 3.13 on a supported platform; see the
README if it cannot run on your machine.

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

Changes to `.github/`, `scripts/`, pinned dependencies, or scanning
configuration are made by maintainers only.

## Releases

Maintainers publish releases by tagging a commit on `main`. Each release tag
re-runs the Cisco, Black Duck and Polaris scans before the GitHub Release is
created.

## License

By contributing, you agree that your contribution is licensed under the
[MIT License](LICENSE).
