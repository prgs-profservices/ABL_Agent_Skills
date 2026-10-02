import argparse
import json
import shutil
import subprocess
import sys


RULESET_NAME = "Public repository security baseline"


def build_ruleset(polaris_check, polaris_app_id, blackduck_check, blackduck_app_id):
    checks = [
        {"context": "Content validation", "integration_id": 15368},
        {"context": "TruffleHog secret scan", "integration_id": 15368},
        {"context": polaris_check, "integration_id": polaris_app_id},
        {"context": blackduck_check, "integration_id": blackduck_app_id},
    ]
    if any(not check["context"].strip() or check["integration_id"] <= 0 for check in checks):
        raise ValueError("Required checks must have nonempty names and positive GitHub App IDs")
    if len({check["context"] for check in checks}) != len(checks):
        raise ValueError("All required check names must be distinct")
    return {
        "name": RULESET_NAME,
        "target": "branch",
        "enforcement": "active",
        "bypass_actors": [],
        "conditions": {"ref_name": {"include": ["refs/heads/main"], "exclude": []}},
        "rules": [
            {"type": "deletion"},
            {"type": "non_fast_forward"},
            {
                "type": "pull_request",
                "parameters": {
                    "required_approving_review_count": 1,
                    "dismiss_stale_reviews_on_push": True,
                    "require_code_owner_review": False,
                    "require_last_push_approval": True,
                    "required_review_thread_resolution": True,
                },
            },
            {
                "type": "required_status_checks",
                "parameters": {
                    "strict_required_status_checks_policy": True,
                    "do_not_enforce_on_create": False,
                    "required_status_checks": checks,
                },
            },
        ],
    }


def github_api(endpoint, method="GET", payload=None):
    command = ["gh", "api", endpoint, "--method", method]
    if payload is not None:
        command.extend(["--input", "-"])
    result = subprocess.run(
        command, input=json.dumps(payload) if payload is not None else None,
        text=True, check=True, capture_output=True,
    )
    return json.loads(result.stdout) if result.stdout.strip() else None


def apply_baseline(repository, ruleset):
    if not shutil.which("gh"):
        raise ValueError("Install GitHub CLI and authenticate directly before using --apply")
    metadata = github_api(f"repos/{repository}")
    if not metadata.get("permissions", {}).get("admin"):
        raise ValueError("Authenticated GitHub repository administration is required")
    if metadata["default_branch"] != "main":
        raise ValueError("Confirm the default branch before applying this main-only ruleset")
    branch = github_api(f"repos/{repository}/branches/main")
    observed = github_api(f"repos/{repository}/commits/{branch['commit']['sha']}/check-runs")
    successful = {
        (check["name"], check["app"]["id"])
        for check in observed["check_runs"] if check["conclusion"] == "success"
    }
    required = ruleset["rules"][-1]["parameters"]["required_status_checks"]
    if any((check["context"], check["integration_id"]) not in successful for check in required):
        raise ValueError("Each required check must first succeed on main from its expected GitHub App")
    existing = github_api(f"repos/{repository}/rulesets?includes_parents=true")
    if any(rule["name"] == RULESET_NAME for rule in existing):
        raise ValueError("Baseline ruleset already exists; review it rather than overwriting it")
    created = github_api(f"repos/{repository}/rulesets", "POST", ruleset)
    print(f"Created active baseline ruleset {created['id']} with no bypass actors.")
    github_api(f"repos/{repository}/vulnerability-alerts", "PUT")
    github_api(f"repos/{repository}/automated-security-fixes", "PUT")
    github_api(f"repos/{repository}/private-vulnerability-reporting", "PUT")
    github_api(f"repos/{repository}", "PATCH", {
        "security_and_analysis": {
            "secret_scanning": {"status": "enabled"},
            "secret_scanning_push_protection": {"status": "enabled"},
        },
    })
    print("Requested dependency alerts/security updates, private reporting and native secret protection.")
    confirmed = github_api(f"repos/{repository}/rulesets/{created['id']}")
    if confirmed["enforcement"] != "active" or confirmed.get("bypass_actors"):
        raise ValueError("Ruleset verification failed; inspect repository settings")
    print("Verified baseline ruleset is active without bypass actors; test enforcement with a PR.")


def main():
    parser = argparse.ArgumentParser(description="Preview or apply the repository security baseline")
    parser.add_argument("--repo", default="prgs-profservices/ABL_Agent_Skills")
    parser.add_argument("--polaris-check", required=True)
    parser.add_argument("--polaris-app-id", required=True, type=int)
    parser.add_argument("--blackduck-check", required=True)
    parser.add_argument("--blackduck-app-id", required=True, type=int)
    parser.add_argument("--apply", action="store_true")
    arguments = parser.parse_args()
    try:
        ruleset = build_ruleset(
            arguments.polaris_check, arguments.polaris_app_id,
            arguments.blackduck_check, arguments.blackduck_app_id,
        )
        if arguments.apply:
            apply_baseline(arguments.repo, ruleset)
        else:
            print(json.dumps(ruleset, indent=2))
    except (ValueError, KeyError, subprocess.CalledProcessError) as error:
        if isinstance(error, subprocess.CalledProcessError):
            print("GitHub API operation failed. Earlier changes may have applied; inspect settings before retrying.", file=sys.stderr)
        else:
            print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
