# Repository Security Baseline

## Status

The repository is already public. Local configuration does not establish
GitHub enforcement until it is committed, reviewed, and activated.
The full organization policy is still awaiting an approved Confluence export.
This baseline is not a certification of compliance.

## Vendor Configuration

The scan workflows adapt the Polaris/Black Duck example from
`Progress-OpenEdge/OpenEdgeMCPConnector4ABLPlugins`. Its Progress composite
actions live in a private repository, so this public repository calls the same
public vendor action directly, pinned to commit
`152247222aa9cd38124acd5c0cf60f4db71adc3f` (v2.11.0).

Configure these secrets through GitHub's settings, or grant this repository
access to approved organization secrets. Never include their values in code:

- `POLARIS_ACCESS_TOKEN`
- `BLACKDUCK_TOKEN`

Configure these non-secret repository or organization variables:

- `POLARIS_APPLICATION_NAME`: configured as `Progress-OpenEdge` from the example.
- `BLACKDUCK_PROJECT_GROUP_NAME`: configured as `Progress-OpenEdge`.
- `SECURITY_BRIDGE_CLI_VERSION`: an approved fixed Bridge CLI release version.

Both scanners use the separate project name `ABL_Agent_Skills`. Confirm project
creation/permissions rather than reusing the example's connector project.
The copied service endpoints are `https://polaris.blackduck.com` and
`https://progresssoftware.app.blackduck.com`; confirm both with scan owners.
The two application/group variables were saved and read back on 2026-10-02.
The example inherits its scanner secrets from the `Progress-OpenEdge`
organization. The target repository currently has neither repository-level
scanner secrets nor inherited organization secrets.

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
4. Confirm the tokens permit scanning the new `ABL_Agent_Skills` project in
   the copied application/group, then run both workflows after publication.

Polaris uploads a Git archive for remote Python SAST and waits for completion.
Black Duck inventories the installed development dependencies and repository
source, uses strict detector accuracy, and fails for `BLOCKER,CRITICAL,MAJOR`.
Both enable internal-PR comments and failure status; diagnostics uploads are off.
Confirm severity thresholds, source-upload support, and remote SAST applicability
with policy owners. The example's Node/VSIX builds and relaxed accuracy settings
are not used here.

Fork PRs fail closed before checkout and need an approved external scan/review
path. No credential-bearing `pull_request_target` workflow is introduced.
Do not enable a merge queue until vendor checks also support merge-group runs.
Expected job check names are `Polaris SAST Scan` and `Black Duck SCA Scan`,
normally published by GitHub Actions (App ID 15368). Verify actual successful
check runs before supplying these names and IDs to the ruleset helper.

The two workflows passed SHA validation, actionlint, input-name verification
against the pinned vendor action, and six synthetic preflight scenarios.
These checks are not Black Duck/Polaris scan results: no vendor scan has run.

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

| Control | Implementation | Activation still needed |
| --- | --- | --- |
| Content CI | YAML/JSON, Markdown, skills, validator tests | GitHub run |
| Immutable pins | Action/hook SHAs, scanner digest | Update review |
| Dependabot | Daily Actions and Python update PRs | Main-branch config |
| Secret scanning | TruffleHog PR, push, daily, manual | GitHub scan |
| PR-only main | Ruleset helper; no bypass actors | Admin application |
| Review resolution | Required by proposed ruleset | Admin application |
| Polaris | Pinned workflow and PR feedback | Provisioning and scan results |
| Black Duck | Pinned workflow and PR feedback | Provisioning and scan results |

The skills validator checks frontmatter names/descriptions and a nonempty
instruction body. It does not yet validate all referenced links or an
organization-specific skill schema. Local editor settings and environment
files are ignored; ignoring files does not replace secret scanning.

## Activate GitHub Controls

1. Obtain the approved scanner configuration, policy thresholds, review count,
   and ownership requirements. Confirm legal approval and the intended license
   before adding project content. No license is chosen by this baseline.
2. Establish the initial `main` through an approved, externally reviewed
   bootstrap process. This empty repository has no branch for a normal PR yet.
   The assistant does not commit or push automatically.
3. Install/configure both approved scanner apps or reusable workflows. Include
   fork PRs safely, publish PR feedback, and fail checks for policy violations,
   scan errors, missing credentials, or unsupported analysis. Do not execute
   untrusted fork code with vendor credentials or a write-capable token.
4. Run all four required checks on the same `main` commit. Determine exact vendor
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

The proposed ruleset requires one approval, approval of the latest push,
dismissal of stale approvals, resolved review threads, and up-to-date passing
checks. It prevents deletion and force pushes with no administrator bypass.
The helper also requests dependency alerts/security updates, GitHub native
secret scanning/push protection, and private vulnerability reporting.
API operations are not transactional: inspect settings after an error rather
than blindly retrying. An existing baseline ruleset is never overwritten.

Verify settings in GitHub and test that direct pushes, failing or missing
checks, and unresolved conversations block changes. Confirm a real Dependabot
PR and scheduled scan run. Review organization-level rules as well.
Add approved code ownership and disclosure contacts when supplied; code-owner
review is not enabled in the proposed ruleset yet.

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

Dependabot updates Actions and Python requirements; it does not update every
pre-commit revision, local hook dependency, scanner digest, or actionlint binary.
For external hooks, use `pre-commit autoupdate --freeze` and review the PR.
Update local hook dependencies together with their development requirements.
Review scanner release provenance, replace its digest, and rerun scanning.
Update actionlint's release URL and checksum together and validate both workflows.
All changes must follow the same PR and security-check requirements.

GitHub-hosted runner labels are platform-managed rather than immutable images.
Confirm whether the complete policy requires a different runner arrangement.
