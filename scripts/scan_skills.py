import argparse
from collections import Counter
import importlib.metadata
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tempfile


NUCLIA_URL = "https://aws-us-east-2-1.rag.progress.cloud/api/v1/predict/compat"
APPROVED_MODELS = {
    "openai/aws-claude-4-6-opus",
    "openai/aws-claude-4-6-sonnet",
    "openai/aws-claude-4-5-haiku",
    "openai/gcp-claude-4-6-opus",
}
SEVERITIES = {"CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO"}


def repository_files(root):
    result = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=root, check=True, capture_output=True,
    )
    files = sorted(set(result.stdout.decode("utf-8").split("\0")) - {""})
    for name in files:
        relative = PurePosixPath(name)
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError("Git returned a path outside the repository")
        source = root / name
        if source.is_symlink() or not source.resolve().is_relative_to(root.resolve()):
            raise ValueError("Skill scanning does not permit repository symlinks")
    return [name for name in files if (root / name).is_file()]


def skill_directories(files):
    return sorted({PurePosixPath(name).parent for name in files if PurePosixPath(name).name == "SKILL.md"})


def stage_skill(root, files, skill, destination):
    destination.mkdir(parents=True, exist_ok=True)
    for name in files:
        relative = PurePosixPath(name)
        if not relative.is_relative_to(skill):
            continue
        source = root / name
        if source.is_symlink() or not source.resolve().is_relative_to(root.resolve()):
            raise ValueError("Skill files must remain inside the repository")
        target = destination / relative.relative_to(skill)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)


def llm_environment(environment):
    result = dict(environment)
    if result.get("SKILL_SCANNER_LLM_BASE_URL", "").rstrip("/") != NUCLIA_URL:
        raise ValueError("LLM scanning requires the approved SKILL_SCANNER_LLM_BASE_URL")
    if result.get("SKILL_SCANNER_LLM_API_BASE"):
        raise ValueError("Remove SKILL_SCANNER_LLM_API_BASE; use SKILL_SCANNER_LLM_BASE_URL")
    if result.get("SKILL_SCANNER_LLM_MODEL") not in APPROVED_MODELS:
        raise ValueError("Configure an approved Nuclia SKILL_SCANNER_LLM_MODEL")
    if not result.get("SKILL_SCANNER_LLM_API_KEY", "").strip():
        raise ValueError("Configure SKILL_SCANNER_LLM_API_KEY directly, never in repository files")
    result["SKILL_SCANNER_LLM_BASE_URL"] = NUCLIA_URL
    for name in list(result):
        if name.startswith("SKILL_SCANNER_META_LLM_"):
            del result[name]
    return result


def validate_report(report, mode):
    if not isinstance(report, dict) or not isinstance(report.get("findings"), list):
        raise ValueError("Scanner returned an invalid JSON report")
    if report.get("analyzers_failed"):
        raise ValueError("A requested analyzer failed; review the restricted scanner report")
    analyzers = report.get("analyzers_used")
    if not isinstance(analyzers, list) or not all(isinstance(name, str) for name in analyzers):
        raise ValueError("Scanner report lacks analyzer execution evidence")
    required = {"static"} if mode == "static" else {"static", "behavioral", "llm"}
    if not required.issubset(analyzers):
        raise ValueError("A required analyzer did not run")
    if not isinstance(report.get("is_safe"), bool):
        raise ValueError("Scanner report lacks a safety verdict")
    counts = Counter()
    for finding in report["findings"]:
        if not isinstance(finding, dict) or finding.get("severity") not in SEVERITIES:
            raise ValueError("Scanner returned an invalid finding severity")
        counts[finding["severity"]] += 1
    if report.get("findings_count") != len(report["findings"]):
        raise ValueError("Scanner finding count does not match the structured report")
    if mode == "llm" and counts and "meta_analyzer" not in analyzers:
        raise ValueError("Requested meta-analysis did not complete")
    return dict(counts), bool(counts) or not report["is_safe"]


def scan_skill(snapshot, report_path, mode, environment):
    command = [
        sys.executable, "-m", "skill_scanner.cli.cli", "scan", str(snapshot),
        "--format", "json", "--output", str(report_path),
        "--policy", "strict", "--fail-on-severity", "info", "--verbose",
    ]
    if mode == "llm":
        command.extend(["--use-llm", "--use-behavioral", "--enable-meta"])
    with report_path.with_suffix(".log").open("w", encoding="utf-8") as diagnostics:
        result = subprocess.run(
            command, cwd=snapshot, env=environment, stdout=diagnostics,
            stderr=subprocess.STDOUT, timeout=300 if mode == "llm" else 120,
        )
    if not report_path.is_file():
        raise ValueError("Scanner did not produce a report; review restricted diagnostics")
    report = json.loads(report_path.read_text(encoding="utf-8"))
    counts, blocked = validate_report(report, mode)
    if result.returncode not in (0, 1) or (result.returncode == 1 and not blocked):
        raise ValueError("Scanner execution failed; review restricted diagnostics")
    return counts, blocked or result.returncode != 0


def main():
    parser = argparse.ArgumentParser(description="Scan Git-visible AI skills without exposing raw findings")
    parser.add_argument("--mode", choices=("static", "llm"), default="static")
    parser.add_argument("--count-only", action="store_true")
    parser.add_argument("--reports", type=Path, help="Private report directory; do not publish raw reports")
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    try:
        files = repository_files(root)
        skills = skill_directories(files)
        if arguments.count_only:
            print(len(skills))
            return 0
        if not skills:
            print("Cisco Skill Scanner: no Git-visible SKILL.md files; no security coverage claimed.")
            return 0
        if sys.version_info < (3, 13):
            raise ValueError("Organization policy requires Python 3.13+ for skill scanning")
        version = importlib.metadata.version("cisco-ai-skill-scanner")
        environment = dict(os.environ)
        if arguments.mode == "llm":
            environment = llm_environment(environment)
        else:
            environment = {name: value for name, value in environment.items() if not name.startswith("SKILL_SCANNER_LLM_")}
        with tempfile.TemporaryDirectory(prefix="abl-skill-scan-") as temporary:
            workspace = Path(temporary)
            reports = arguments.reports.resolve() if arguments.reports else workspace / "reports"
            reports.mkdir(parents=True, exist_ok=True, mode=0o700)
            total = Counter()
            blocked = False
            for index, skill in enumerate(skills, 1):
                snapshot = workspace / f"skill-{index}"
                stage_skill(root, files, skill, snapshot)
                counts, failed = scan_skill(snapshot, reports / f"skill-{index}.json", arguments.mode, environment)
                total.update(counts)
                blocked = blocked or failed
            print(f"Cisco Skill Scanner {version}: mode={arguments.mode}; skills={len(skills)}; findings={sum(total.values())}")
            print("Severity counts: " + json.dumps(dict(total), sort_keys=True))
            if blocked:
                print("Findings require human validation and remediation before merge/publication.", file=sys.stderr)
            return 1 if blocked else 0
    except (ValueError, OSError, subprocess.SubprocessError, importlib.metadata.PackageNotFoundError):
        print("Cisco skill scan failed or is incompletely configured. Review private reports/configuration; raw diagnostics are suppressed.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
