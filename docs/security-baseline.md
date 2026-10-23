# Repository Security Baseline

## Status

The repository is already public. Local configuration does not establish
GitHub enforcement until it is committed, reviewed, and activated.
The full organization policy is still awaiting an approved Confluence export.
This baseline is not a certification of compliance.

### Live Settings Verified on 2026-10-23

The active `main` ruleset (`Public repository security baseline`) requires PRs
with at least one approval from a reviewer with write access, code-owner review,
approval of the most recent push by someone other than its pusher, dismissal of
stale approvals on new pushes, resolved review conversations, and all six
security/CI checks from GitHub Actions. Up-to-date checks are required; force
pushes and branch deletion are blocked. There are no bypass actors. Approvals
have been required since 2026-10-15; earlier PRs could be merged by their author
without review.

`.github/CODEOWNERS` assigns every path to `@prorpy` and `@SteveSouthwell`, so
one of them must approve each PR. A second ruleset, `Release tags`, protects
`refs/tags/v*` from deletion and from being moved, with no bypass actors.

Workflows from fork PRs only run after a maintainer approves them, for all
external contributors (Settings > Actions > Fork pull request workflows).

Dependency alerts and automated security updates, native secret scanning and
push protection, and private vulnerability reporting are enabled. The project is
licensed under the MIT License; see `LICENSE`.

All six required checks run on PRs. Black Duck and Polaris authenticate with
repository secrets, and Dependabot PRs use separate Dependabot secrets with the
same names; rotate both copies together. Scheduled TruffleHog runs succeed
daily on `main`.

## Cisco AI Skill Scanning

Cisco Skill Scanner is required by the supplied skill-security policy for
development, PR review, and pre-publication. Version `2.2.2` is pinned in
`requirements-skill-scanner.txt` and the local pre-commit hook. CI uses Python
3.13 to meet the organization's prerequisite. The scanner's published package
supports older Python too, but that does not override the organization policy.

The `cisco-skill-static` hook runs on every commit. A separate Linux workflow
runs static analysis, then a Nuclia-backed semantic check on PRs, `main` pushes,
merge groups, and manual dispatch. Content CI skips the duplicate static hook
because the dedicated Cisco job provides that check. Required check names are
`Cisco skill static scan` and `Cisco skill semantic scan`; both are included in
the active main ruleset.

The semantic job always runs after the static job. Before scanning, the wrapper
validates the Nuclia configuration and sends a minimal `Reply with OK` request
to the gateway, so a missing, revoked, or unauthorized key fails the check even
when the repository has no skills. With zero skills, no skill content is sent
and no semantic coverage is claimed.

The semantic job reads `SKILL_SCANNER_LLM_API_KEY` from repository secrets
(and from Dependabot secrets for Dependabot PRs). There is no separate GitHub
Environment deployment approval; the job runs automatically on internal PRs.
Fork PRs fail closed. PR code runs with this key before review, so a required
approval stops unreviewed changes from being merged, but it does not stop a PR
branch from using the key while its checks run. Only people with write access
can push internal branches.

The wrapper discovers every Git-visible `SKILL.md`, snapshots its directory's
Git-visible helper files, and does not include ignored `.env` files, local
settings, or symlinks. This covers tracked and eligible untracked skills locally;
CI scans the checked-out commit. Skills installed elsewhere or downloaded at
runtime need a separate review before consumption.

Static mode does not request an LLM. Semantic mode enables LLM, behavioral, and
meta analysis. Any retained finding, including informational/medium findings,
blocks until human validation and remediation. Analyzer failures, missing
analyzer evidence, malformed results, and scanner failures also block. This
conservative gate is not a substitute for manual triage and may need an
organization-approved false-positive policy. No blanket ignore list is added.

### Nuclia Activation

1. Contact your BU management/Product Security for Nuclia onboarding and an
   approved NUA key in `aws-us-east-2-1`. Do not send the key through chat.
2. Add `SKILL_SCANNER_LLM_API_KEY` as both a repository Actions secret and a
   Dependabot secret, entered directly in GitHub:

   ```powershell
   gh secret set SKILL_SCANNER_LLM_API_KEY --repo prgs-profservices/ABL_Agent_Skills
   gh secret set SKILL_SCANNER_LLM_API_KEY --app dependabot --repo prgs-profservices/ABL_Agent_Skills
   ```

   Confirm that sending reviewed skill content to this gateway is authorized.
3. Optionally set repository variable `SKILL_SCANNER_LLM_MODEL` to one of the
   four approved model IDs. Default is `openai/aws-claude-4-6-opus`. The
   `openai/` prefix is the LiteLLM provider prefix used by the scanner; the
   gateway itself expects the bare ID (for example `aws-claude-4-6-opus`), and
   the wrapper strips the prefix for its direct gateway probe.
4. The workflow supplies `SKILL_SCANNER_LLM_BASE_URL` as
   `https://aws-us-east-2-1.rag.progress.cloud/api/v1/predict/compat`.
   Do not use `SKILL_SCANNER_LLM_API_BASE`. The wrapper rejects that misspelling,
   other endpoints, missing keys, and unapproved model IDs before LLM scanning.
5. Run `python scripts/scan_skills.py --mode llm` with the three variables set
   to confirm the gateway accepts the key, then scan every skill with semantic
   mode before publication. Fork PRs fail closed and follow the community
   contribution path below; credentials are never provided through a privileged
   `pull_request_target` workflow.

Gateway authorization was verified on 2026-10-15 in
[run 38789719153](https://github.com/prgs-profservices/ABL_Agent_Skills/actions/runs/38789719153).
That run had zero skills, so it proves connectivity only, not semantic coverage.

For local use, source the three approved environment variables from an
access-restricted file outside this repository, such as
`~/.config/progress-rag/skill-scanner.env`. Never commit credentials.
On a supported platform with Python 3.13 and the pinned scanner installed:

```bash
python -m pip install -r requirements-skill-scanner.txt
skill-scanner --version
python scripts/scan_skills.py --mode static \
  --reports .skill-scanner-reports/static
python scripts/scan_skills.py --mode llm \
  --reports .skill-scanner-reports/llm
```

Use `--format json` with scanner 2.2.2; the supplied documentation's
`--output-format` spelling is not supported by this release. Raw JSON and logs
can contain skill content and findings. The optional local report directory is
ignored by Git and must stay access-controlled. Public CI emits only counts;
raw reports are not uploaded and temporary reports are deleted. Reproduce
failures privately for triage and preserve approved evidence in restricted storage.

Current local verification: 32 unit tests passed, including 18 Cisco gate tests;
workflow syntax and immutable references passed. The repository currently has
zero Git-visible skills, so no skill coverage or semantic verdict is claimed.
The actual scanner installs under per-user Python 3.13 x64, but its CEL helper
rejects the Windows ARM64 host even under emulation. A benign static smoke test
failed closed at that platform check. No analyzer was disabled as a workaround.
WSL is not installed here; use supported Linux CI or provision a supported
development environment through your normal process.

### VMware Fusion and the Mac Host

Fusion running Windows ARM64 on Apple silicon does not make the guest a
supported Windows x64 host. Emulated x64 Python still leaves the CEL helper
seeing ARM64, which the scanner rejects (observed with 2.1.0).

The scanner supports native macOS ARM64 and Linux ARM64. Run it in a terminal
on the Mac host, or in a supported Linux ARM64 VM. Create a separate checkout
and Python 3.13 virtual environment for that OS; do not reuse the Windows venv.
With Python 3.13 installed on the Mac or Linux guest:

```bash
git clone https://github.com/prgs-profservices/ABL_Agent_Skills.git
cd ABL_Agent_Skills
python3.13 -m venv .venv
.venv/bin/python -m pip install -r requirements-dev.txt
.venv/bin/python -m pip install -r requirements-skill-scanner.txt
.venv/bin/python -m pre_commit install
.venv/bin/python scripts/scan_skills.py --mode static
```

These are supported-platform instructions, not a claim that the Mac host was
tested from this Windows session. LLM mode still needs authorized Nuclia access
and the three approved environment variables described above.

## Vendor Configuration

The scan workflows adapt the Polaris/Black Duck example from
`Progress-OpenEdge/OpenEdgeMCPConnector4ABLPlugins`. Its Progress composite
actions live in a private repository, so this public repository calls the same
public vendor action directly, pinned to commit
`152247222aa9cd38124acd5c0cf60f4db71adc3f` (v2.11.0).

Configure these secrets through GitHub's settings, or grant this repository
access to approved organization secrets. Never include their values in code.
Each must exist both as an Actions secret and as a Dependabot secret, because
workflows triggered by Dependabot PRs only see Dependabot secrets. When a token
is rotated, update both copies; a stale Dependabot copy makes only Dependabot
PRs fail with `Request failed authorization`.

- `POLARIS_ACCESS_TOKEN`
- `BLACKDUCK_TOKEN`
- `SKILL_SCANNER_LLM_API_KEY`

Configure these non-secret repository or organization variables:

- `BLACKDUCK_PROJECT_GROUP_NAME`: configured as `Progress-OpenEdge`.
- `POLARIS_APPLICATION_NAME`: configured as `ADP-OpenEdge-Platform`.
- `SECURITY_BRIDGE_CLI_VERSION`: configured as `4.5.0`.

Polaris uses the `POLARIS_APPLICATION_NAME` application and the
`ABL_Agent_Skills` project. Black Duck uses the project name `ABL_Agent_Skills`
in the configured group. The service endpoints are
`https://polaris.blackduck.com` and `https://progresssoftware.app.blackduck.com`.
All scanner secrets are repository-level; none are inherited from an organization.

GitHub does not expose stored secret values, so they cannot be copied through
the API. Organization secrets cannot be shared directly between the example's
`Progress-OpenEdge` organization and this repository's `prgs-profservices`.
Ask a scan administrator to provision approved tokens for this project:

1. In the target repository, open **Settings > Secrets and variables > Actions**.
2. Under **Secrets**, create `POLARIS_ACCESS_TOKEN` and `BLACKDUCK_TOKEN` using
   approved tokens entered directly in GitHub, not chat or repository files.
   Alternatively, a `prgs-profservices` administrator can create organization
   secrets with those names and grant access to this selected repository.
3. Under **Variables**, create `SECURITY_BRIDGE_CLI_VERSION` using an approved
   fixed release. The example defaults to a moving version, so it supplies no
   fixed version to copy. Ask the scan owner for a compatible supported version.
4. Confirm the Polaris token can scan the `ABL_Agent_Skills` application and
   project, and that the Black Duck token can scan its configured group/project;
   then run both workflows after publication.

Polaris uploads a Git archive for remote Python SAST and waits for completion.
Black Duck inventories the installed development dependencies and repository
source, uses strict detector accuracy, and fails for `BLOCKER,CRITICAL,MAJOR`.
Both enable internal-PR comments and failure status; diagnostics uploads are off.
Confirm severity thresholds, source-upload support, and remote SAST applicability
with policy owners. The example's Node/VSIX builds and relaxed accuracy settings
are not used here.

Fork PRs fail closed before checkout and follow the community contribution
path below. No credential-bearing `pull_request_target` workflow is introduced.
Do not enable a merge queue until vendor checks also support merge-group runs.
Expected job check names are `Polaris SAST Scan` and `Black Duck SCA Scan`,
normally published by GitHub Actions (App ID 15368). Verify actual successful
check runs before supplying these names and IDs to the ruleset helper.

Both vendor scans run on PRs and on `main`; Black Duck also runs daily. Polaris
and Black Duck post ordinary PR comments, not review threads, so the "resolve
conversations" rule does not apply to them; their findings are enforced through
the failing required check. Black Duck fails for `BLOCKER,CRITICAL,MAJOR`.
Polaris sets no failure severity in the workflow, so whether findings fail the
check depends on the server-side Polaris policy; confirm it with the Polaris owner.

The Black Duck action downloads Bridge CLI and Detect at run time by version,
not by hash. These downloads are outside the repository's SHA-pin enforcement.

## Community Contributions

GitHub never passes repository secrets to `pull_request` workflows from forks,
so the Cisco semantic scan, Polaris and Black Duck fail on fork PRs by design,
and those PRs cannot be merged directly. The process, also described in
`CONTRIBUTING.md`, is:

1. A maintainer approves running workflows on the fork PR. Content validation,
   TruffleHog and the Cisco static scan run without credentials.
2. A maintainer reviews the change by hand, including helper files, and rejects
   any change to `.github/`, `scripts/`, pinned dependencies, or scanning
   configuration from outside contributors.
3. The maintainer pushes the contributor's commits to an internal branch and
   opens a new PR, so all six checks run with credentials:

   ```powershell
   gh pr checkout <fork-pr-number> -b community/<fork-pr-number>
   git push origin community/<fork-pr-number>
   gh pr create --base main --head community/<fork-pr-number>
   ```

4. A code owner other than the maintainer who pushed approves it, and the
   original fork PR is closed with a link to the internal PR.

Submitted skill text can contain prompt injection aimed at the LLM analyzer.
Treat the semantic verdict as advisory; the static and behavioral analyzers and
human review remain the gate.

## Releases

Releases are annotated tags on a commit that is already on `main`, named
`vMAJOR.MINOR.PATCH`, with an optional pre-release suffix such as
`v0.1.0-preview.1`. Pushing a `v*` tag runs `.github/workflows/release.yml`,
which:

1. rejects tags that are not annotated, are not semantic versions, or point to a
   commit that is not on `main`
2. re-runs the Cisco static and semantic scans, Black Duck, and Polaris on the
   tagged commit; Black Duck records the result under a project version named
   after the tag, and Polaris under a branch named after the tag with `main` as
   its parent
3. creates the GitHub Release with generated notes only if every scan passes;
   tags with a pre-release suffix are published as pre-releases

To publish:

```powershell
git fetch origin
git tag -a v1.0.0 -m "ABL Agent Skills 1.0.0" origin/main
git push origin v1.0.0
```

If a release scan fails, no release is created. The tag cannot be moved or
deleted, so fix the problem on `main` and publish the next version.

`npx skills add prgs-profservices/ABL_Agent_Skills` installs the default branch,
not the latest release. Users who want a fixed version add `#<tag>`.

## Initial Local Verification

Local checks on 2026-10-02 passed: 14 unit tests, applicable pre-commit hooks,
the baseline validator, and actionlint 1.7.12 for both workflows. Shellcheck and
pyflakes were unavailable locally; those integrations were disabled for that run.

TruffleHog 3.90.12 returned zero findings and exit code 0 across 11 candidate
files in an initial filesystem scan before the final CI refinements.
No commits exist, so this is provisional working-tree evidence, not a release
or Git-history scan. Ignored local files were outside that scan's scope.
The Docker-based GitHub scan has not run locally because Docker is unavailable.
Black Duck and Polaris have not run; no vendor verdict is implied.

## Control Matrix

| Control | Implementation | Remaining work |
| --- | --- | --- |
| Content CI | YAML/JSON, Markdown, skills, validator tests | None |
| Immutable pins | Action/hook SHAs, scanner digest | Vendor runtime downloads |
| Dependabot | Daily Actions, pip, and pre-commit update PRs | None |
| Secret scanning | TruffleHog PR, push, daily, manual | None |
| PR-only main | Active ruleset; no bypass actors | None |
| PR approval | 1 approval, last-push approval, stale dismissal | None |
| Code owners | `CODEOWNERS` and required code-owner review | None |
| Fork workflows | Maintainer approval for all external contributors | None |
| Review resolution | Required by active ruleset | None |
| Releases | Tag ruleset and scanned release workflow | None |
| License | MIT | None |
| Polaris | Pinned workflow and PR feedback | Confirm server policy |
| Black Duck | Pinned workflow and PR feedback | None |
| Cisco AI skills | Static hook and semantic CI | Skills to scan |

The skills validator checks frontmatter names/descriptions and a nonempty
instruction body. It does not yet validate all referenced links or an
organization-specific skill schema. Local editor settings and environment
files are ignored; ignoring files does not replace secret scanning.

## Activate GitHub Controls

1. Obtain the approved scanner configuration, policy thresholds, review count,
   and ownership requirements. Confirm legal approval before adding project
   content. The project uses the MIT License.
2. Establish the initial `main` through an approved, externally reviewed
   bootstrap process. This empty repository has no branch for a normal PR yet.
   The assistant does not commit or push automatically.
3. Install/configure both approved scanner apps or reusable workflows. Include
   fork PRs safely, publish PR feedback, and fail checks for policy violations,
   scan errors, missing credentials, or unsupported analysis. Do not execute
   untrusted fork code with vendor credentials or a write-capable token.
4. Run all six required checks on the same `main` commit. Determine exact vendor
   check names and their GitHub App IDs from actual check runs. Do not substitute
   dashboard labels, app installation IDs, or a successful skipped scan.
5. Authenticate GitHub CLI directly with `gh auth login --web`. Never provide
   passwords, API tokens, or session cookies in chat.
6. Preview the ruleset using the command below. Replace example names and IDs
   with the observed values; examples are not organizational defaults.
7. Review the preview against the full policy, then add `--apply`. The helper
   requires repository admin rights and successful checks from expected apps.
   It creates a new ruleset, not a replacement for existing protections.

```powershell
python scripts/configure_github.py `
  --polaris-check "Actual Polaris check" --polaris-app-id 100 `
  --blackduck-check "Actual Black Duck check" --blackduck-app-id 200
```

The proposed ruleset requires one approval, code-owner review, approval of the
latest push, dismissal of stale approvals, resolved review threads, and
up-to-date passing checks. It prevents deletion and force pushes with no
administrator bypass.
The helper also requests dependency alerts/security updates, GitHub native
secret scanning/push protection, and private vulnerability reporting.
API operations are not transactional: inspect settings after an error rather
than blindly retrying. An existing baseline ruleset is never overwritten.

Verify settings in GitHub and test that direct pushes, failing or missing
checks, and unresolved conversations block changes. Confirm a real Dependabot
PR and scheduled scan run. Review organization-level rules as well.
Security reports go through private vulnerability reporting, as described in
`SECURITY.md`.

## Scanner Scope and Evidence

TruffleHog 3.90.12 uses an immutable container digest and full-history checkout.
PRs scan their checked-out merge commit plus available references, not just
changed files. Scheduled/manual runs scan history reachable from fetched refs.
This does not cover deleted branches, unreachable commits, issue text, or all
historical fork objects. The scanner has no credentials or network access.

Verification is disabled, so detected unverified candidates also fail the job.
This conservative policy needs organization approval and may need false-positive
triage. Scanner errors also fail. Logs and summaries contain only finding counts,
exit codes, and commit/image identifiers; raw findings are temporary and deleted.
Raw scanner diagnostics are also suppressed because they can contain secrets.
Reproduce failures in a restricted environment and keep reports access-controlled.

Polaris and Black Duck configuration must specify server/project mappings,
supported analysis scope, thresholds, PR reporting, and report retention.
Documentation-only content may need a policy-owner-approved applicability
exception. Development dependencies are now Python packages and must be included
in dependency analysis even if the skill content is documentation only.

For each real scan, retain the reviewed commit SHA, tool version/configuration,
timestamp, scope, finding severity/count, policy verdict, run/report link,
remediation, and approved exceptions. Do not publish raw secrets or restricted
vendor reports as public artifacts. Rerun affected checks after fixes.

## Maintain Pins

Dependabot updates Actions, Python requirements, and pre-commit hooks. For
pre-commit, it updates the external hook `rev` SHAs (the `# frozen:` comment
records the matching tag) and the `additional_dependencies` of the local Python
hooks. The same package can appear in a requirements file and in a hook, for
example `cisco-ai-skill-scanner` and `pymarkdownlnt`. Dependabot then opens
separate pip and pre-commit PRs; merge both so the versions stay aligned.

Dependabot does not update the TruffleHog scanner digest, the actionlint binary,
the `SECURITY_BRIDGE_CLI_VERSION` variable, or the Python runtime versions.
Review scanner release provenance, replace its digest, and rerun scanning.
Update actionlint's release URL and checksum together and validate both workflows.
All changes must follow the same PR and security-check requirements.

GitHub-hosted runner labels are platform-managed rather than immutable images.
Confirm whether the complete policy requires a different runner arrangement.
