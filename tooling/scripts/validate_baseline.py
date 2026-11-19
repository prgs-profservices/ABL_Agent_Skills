import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys

import yaml


COMMIT_SHA = re.compile(r"[0-9a-f]{40}")
LICENSE_MARKER = "SPDX-License-Identifier: Apache-2.0"
COPYRIGHT_LINE = re.compile(
    r"^Copyright © \d{4}(?:-\d{4})? Progress Software Corporation and/or its subsidiaries or affiliates\. All Rights Reserved\.$",
    re.MULTILINE,
)
SKILL_CODE_SUFFIXES = {".cls", ".i", ".js", ".p", ".ps1", ".py", ".sh", ".ts", ".w"}
CONTENT_SUFFIXES = {".json", ".md", ".yaml", ".yml"}


def validate_reference(reference):
    if not isinstance(reference, str):
        raise ValueError("Action references must be strings")
    if reference.startswith("./"):
        return
    if reference.startswith("docker://"):
        if not re.search(r"@sha256:[0-9a-f]{64}$", reference):
            raise ValueError("Container actions must be pinned to a SHA256 digest")
        return
    if not re.fullmatch(r"[^@\s]+@[0-9a-f]{40}", reference):
        raise ValueError("External actions and workflows must use full commit SHAs")


def validate_workflow(document):
    if not isinstance(document, dict) or not isinstance(document.get("jobs"), dict):
        raise ValueError("A workflow must define jobs")
    for job in document["jobs"].values():
        if "uses" in job:
            validate_reference(job["uses"])
        for step in job.get("steps", []):
            if "uses" in step:
                validate_reference(step["uses"])


def validate_hooks(document):
    for repository in document.get("repos", []):
        if repository["repo"] not in ("local", "meta"):
            if not COMMIT_SHA.fullmatch(str(repository.get("rev", ""))):
                raise ValueError("External pre-commit hooks must use full commit SHAs")


def validate_skill(text, directory_name):
    lines = text.splitlines()
    if not lines or lines[0] != "---":
        raise ValueError("SKILL.md must start with YAML frontmatter")
    try:
        closing = lines.index("---", 1)
    except ValueError:
        raise ValueError("Skill frontmatter must have a closing delimiter") from None
    metadata = yaml.safe_load("\n".join(lines[1:closing]))
    if not isinstance(metadata, dict):
        raise ValueError("Skill frontmatter must be a mapping")
    name = metadata.get("name")
    if not isinstance(name, str) or not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", name):
        raise ValueError("Skill names must use lowercase letters, numbers and hyphens")
    if len(name) > 64 or name != directory_name:
        raise ValueError("Skill names must match their directory and be at most 64 characters")
    description = metadata.get("description")
    if not isinstance(description, str) or not description.strip() or len(description) > 1024:
        raise ValueError("Skills must have a nonempty description of at most 1024 characters")
    body = "\n".join(lines[closing + 1:]).lstrip()
    if not body.startswith("<!--") or "-->" not in body:
        raise ValueError("SKILL.md must have the Apache License 2.0 header comment right after its frontmatter")
    header, instructions = body[4:].split("-->", 1)
    if LICENSE_MARKER not in header or not COPYRIGHT_LINE.search(header):
        raise ValueError("The SKILL.md header must contain the official Progress copyright line and SPDX-License-Identifier: Apache-2.0")
    if not instructions.strip():
        raise ValueError("Skills must contain instructions after their license header")


def validate_skill_license_files(directory, root):
    for bundled, original in (("LICENSE.txt", "LICENSE"), ("NOTICE.txt", "NOTICE")):
        copy = directory / bundled
        if not copy.is_file() or copy.read_text(encoding="utf-8") != (root / original).read_text(encoding="utf-8"):
            raise ValueError(f"Skills must include {bundled} as an exact copy of the repository {original}")


def validate_script_hashes(directory):
    """Check a SKILL.md 'Script integrity' table against the files on disk.

    Documented hashes are SHA-256 over LF-normalized bytes so they match a
    plain Get-FileHash on both LF and CRLF checkouts. Returns a list of
    error strings; an empty list means the table is valid (or absent).
    """
    text = (directory / "SKILL.md").read_text(encoding="utf-8")
    lines = text.splitlines()
    section = None
    for index, line in enumerate(lines):
        if line.startswith("## "):
            if section is None and line.strip().startswith("## Script integrity"):
                section = index + 1
            elif section is not None:
                break
    if section is None:
        return []
    body = "\n".join(lines[section:])
    errors = []
    for filename, documented in re.findall(
        r"`([^`]+)`\s*\|\s*`([0-9a-fA-F]{64})`", body
    ):
        target = directory / filename
        if not target.is_file():
            errors.append(f"'{filename}' is listed in the Script integrity table but does not exist")
            continue
        actual = hashlib.sha256(target.read_bytes().replace(b"\r\n", b"\n")).hexdigest()
        if documented.lower() != actual:
            errors.append(f"documented SHA-256 for '{filename}' does not match the file")
    return errors


def validate_skill_code(text):
    if LICENSE_MARKER not in text or not COPYRIGHT_LINE.search(re.sub(r"^\W+", "", text, flags=re.MULTILINE)):
        raise ValueError("Code files in skills must start with the official Progress copyright line and the Apache License 2.0 header")


def skill_directories(names):
    return {PurePosixPath(name).parent for name in names if PurePosixPath(name).name == "SKILL.md"}


def validate_file(path, root, skills=frozenset()):
    relative = path.relative_to(root).as_posix()
    text = path.read_text(encoding="utf-8")
    if path.suffix.lower() in SKILL_CODE_SUFFIXES and any(PurePosixPath(relative).is_relative_to(s) for s in skills):
        validate_skill_code(text)
    if path.suffix in (".yaml", ".yml"):
        document = yaml.safe_load(text)
        if relative.startswith(".github/workflows/"):
            validate_workflow(document)
        if relative == ".pre-commit-config.yaml":
            validate_hooks(document)
    elif path.suffix == ".json":
        json.loads(text)
    if path.name == "SKILL.md":
        validate_skill(text, path.parent.name)
        validate_skill_license_files(path.parent, root)
        hash_errors = validate_script_hashes(path.parent)
        if hash_errors:
            raise ValueError("; ".join(hash_errors))


def main():
    root = Path(__file__).resolve().parents[2]
    result = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=root, check=True, capture_output=True,
    )
    errors = []
    checked = 0
    names = sorted(set(result.stdout.decode("utf-8").split("\0")) - {""})
    skills = skill_directories(names)
    for name in names:
        path = root / name
        if not path.is_file() or path.suffix.lower() not in CONTENT_SUFFIXES | SKILL_CODE_SUFFIXES:
            continue
        try:
            validate_file(path, root, skills)
            checked += 1
        except (ValueError, yaml.YAMLError, OSError) as error:
            errors.append(f"{name}: {error}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Baseline validation passed for {checked} content files.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
