import hashlib
from pathlib import Path, PurePosixPath
import tempfile
import unittest

from scripts.validate_baseline import (
    LICENSE_MARKER,
    validate_file,
    validate_hooks,
    validate_reference,
    validate_script_hashes,
    validate_skill,
    validate_skill_code,
    validate_skill_license_files,
    validate_workflow,
)
from scripts.configure_github import build_ruleset

HEADER = f"Copyright © 2026 Progress Software Corporation and/or its subsidiaries or affiliates. All Rights Reserved.\n\n{LICENSE_MARKER}\n"
SKILL = f"---\nname: test-skill\ndescription: Test skill\n---\n\n<!--\ntest-skill\n\n{HEADER}-->\n\nInstructions\n"


class BaselineTests(unittest.TestCase):
    def test_full_action_sha(self):
        validate_reference("actions/checkout@" + "a" * 40)

    def test_action_tag_rejected(self):
        with self.assertRaises(ValueError):
            validate_reference("actions/checkout@v4")

    def test_bare_sha_rejected(self):
        with self.assertRaises(ValueError):
            validate_reference("a" * 40)

    def test_local_action(self):
        validate_reference("./.github/actions/check")

    def test_container_tag_rejected(self):
        with self.assertRaises(ValueError):
            validate_reference("docker://alpine:latest")

    def test_reusable_workflow_tag_rejected(self):
        with self.assertRaises(ValueError):
            validate_workflow({"jobs": {"scan": {"uses": "org/repo/.github/workflows/scan.yml@main"}}})

    def test_hook_tag_rejected(self):
        with self.assertRaises(ValueError):
            validate_hooks({"repos": [{"repo": "https://example.com/hooks", "rev": "v1"}]})

    def test_local_hook(self):
        validate_hooks({"repos": [{"repo": "local"}]})

    def test_valid_skill(self):
        validate_skill(SKILL, "test-skill")

    def test_skill_without_description_rejected(self):
        with self.assertRaises(ValueError):
            validate_skill(SKILL.replace("description: Test skill\n", ""), "test-skill")

    def test_skill_directory_mismatch_rejected(self):
        with self.assertRaises(ValueError):
            validate_skill(SKILL, "other")

    def test_skill_without_header_rejected(self):
        with self.assertRaises(ValueError):
            validate_skill("---\nname: test-skill\ndescription: Test skill\n---\nInstructions\n", "test-skill")

    def test_skill_header_without_copyright_rejected(self):
        with self.assertRaises(ValueError):
            validate_skill(SKILL.replace("Copyright © 2026 Progress Software Corporation and/or its subsidiaries or affiliates. All Rights Reserved.\n", ""), "test-skill")

    def test_skill_header_old_copyright_line_rejected(self):
        with self.assertRaises(ValueError):
            validate_skill(
                SKILL.replace(
                    "Copyright © 2026 Progress Software Corporation and/or its subsidiaries or affiliates. All Rights Reserved.",
                    "Copyright 2026 Progress Software Corporation",
                ),
                "test-skill",
            )

    def test_skill_header_copyright_year_range_accepted(self):
        validate_skill(
            SKILL.replace(
                "Copyright © 2026 Progress",
                "Copyright © 2026-2027 Progress",
            ),
            "test-skill",
        )

    def test_skill_header_without_license_notice_rejected(self):
        with self.assertRaises(ValueError):
            validate_skill(SKILL.replace(LICENSE_MARKER, "All rights reserved."), "test-skill")

    def test_skill_without_instructions_after_header_rejected(self):
        with self.assertRaises(ValueError):
            validate_skill(SKILL.replace("Instructions\n", ""), "test-skill")

    def test_skill_code_needs_header(self):
        with self.assertRaises(ValueError):
            validate_skill_code("import os\n")
        validate_skill_code("# " + HEADER.replace("\n", "\n# ") + "\nimport os\n")
        validate_skill_code("/* " + HEADER + "*/\nDISPLAY 'hi'.\n")

    def test_skill_code_old_copyright_line_rejected(self):
        old_header = HEADER.replace(
            "Copyright © 2026 Progress Software Corporation and/or its subsidiaries or affiliates. All Rights Reserved.",
            "Copyright 2026 Progress Software Corporation",
        )
        with self.assertRaises(ValueError):
            validate_skill_code("# " + old_header.replace("\n", "\n# ") + "\nimport os\n")

    def test_skill_code_block_comment_header(self):
        validate_skill_code("/*\n * " + HEADER.replace("\n", "\n * ") + "*/\nDISPLAY 'hi'.\n")

    def test_only_code_inside_skills_needs_header(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "scripts").mkdir()
            (root / "scripts" / "tool.py").write_text("import os\n", encoding="utf-8")
            (root / "skills" / "test-skill" / "assets").mkdir(parents=True)
            (root / "skills" / "test-skill" / "assets" / "data.md").write_text("data\n", encoding="utf-8")
            (root / "skills" / "test-skill" / "run.py").write_text("import os\n", encoding="utf-8")
            skills = {PurePosixPath("skills/test-skill")}
            validate_file(root / "scripts" / "tool.py", root, skills)
            validate_file(root / "skills" / "test-skill" / "assets" / "data.md", root, skills)
            with self.assertRaises(ValueError):
                validate_file(root / "skills" / "test-skill" / "run.py", root, skills)

    def test_skill_license_files_must_match_repository(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "LICENSE").write_text("license text\n", encoding="utf-8")
            (root / "NOTICE").write_text("notice text\n", encoding="utf-8")
            skill = root / "skills" / "test-skill"
            skill.mkdir(parents=True)
            with self.assertRaises(ValueError):
                validate_skill_license_files(skill, root)
            (skill / "LICENSE.txt").write_text("license text\n", encoding="utf-8")
            (skill / "NOTICE.txt").write_text("changed notice\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                validate_skill_license_files(skill, root)
            (skill / "NOTICE.txt").write_text("notice text\n", encoding="utf-8")
            validate_skill_license_files(skill, root)

    def make_skill_with_hash_table(self, root, table_rows):
        skill = root / "skills" / "test-skill"
        skill.mkdir(parents=True)
        table = "\n".join(f"| `{name}` | `{digest}` |" for name, digest in table_rows)
        (skill / "SKILL.md").write_text(
            SKILL + f"\n## Script integrity\n\n| File | SHA-256 |\n|---|---|\n{table}\n",
            encoding="utf-8",
        )
        return skill

    def test_script_hashes_matching_table_passes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            skill = self.make_skill_with_hash_table(root, [("run.ps1", "0" * 64)])
            digest = hashlib.sha256(b"line one\r\nline two\r\n".replace(b"\r\n", b"\n")).hexdigest()
            (skill / "run.ps1").write_bytes(b"line one\r\nline two\r\n")
            (skill / "SKILL.md").write_text(
                (skill / "SKILL.md").read_text(encoding="utf-8").replace("0" * 64, digest),
                encoding="utf-8",
            )
            self.assertEqual(validate_script_hashes(skill), [])

    def test_script_hashes_mismatch_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            skill = self.make_skill_with_hash_table(root, [("run.ps1", "0" * 64)])
            (skill / "run.ps1").write_bytes(b"content\n")
            errors = validate_script_hashes(skill)
            self.assertEqual(len(errors), 1)
            self.assertIn("does not match", errors[0])

    def test_script_hashes_missing_file_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            skill = self.make_skill_with_hash_table(root, [("run.ps1", "0" * 64)])
            errors = validate_script_hashes(skill)
            self.assertEqual(len(errors), 1)
            self.assertIn("does not exist", errors[0])

    def test_script_hashes_malformed_digest_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            skill = self.make_skill_with_hash_table(root, [("run.ps1", "abc123")])
            (skill / "run.ps1").write_bytes(b"content\n")
            errors = validate_script_hashes(skill)
            self.assertEqual(len(errors), 1)
            self.assertIn("not a 64-character SHA-256", errors[0])

    def test_script_hashes_no_section_passes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            skill = root / "skills" / "test-skill"
            skill.mkdir(parents=True)
            (skill / "SKILL.md").write_text(SKILL, encoding="utf-8")
            self.assertEqual(validate_script_hashes(skill), [])

    def test_ruleset_enforces_pr_and_security_checks(self):
        ruleset = build_ruleset("Polaris policy", 100, "Black Duck policy", 200)
        self.assertEqual(ruleset["bypass_actors"], [])
        rules = {rule["type"]: rule.get("parameters", {}) for rule in ruleset["rules"]}
        self.assertTrue(rules["pull_request"]["required_review_thread_resolution"])
        self.assertTrue(rules["pull_request"]["dismiss_stale_reviews_on_push"])
        self.assertEqual(rules["pull_request"]["required_approving_review_count"], 1)
        self.assertTrue(rules["pull_request"]["require_code_owner_review"])
        self.assertIn("deletion", rules)
        self.assertIn("non_fast_forward", rules)
        checks = rules["required_status_checks"]["required_status_checks"]
        self.assertEqual(len(checks), 6)
        self.assertIn({"context": "Cisco skill static scan", "integration_id": 15368}, checks)
        self.assertIn({"context": "Cisco skill semantic scan", "integration_id": 15368}, checks)
        self.assertIn({"context": "Polaris policy", "integration_id": 100}, checks)
        self.assertIn({"context": "Black Duck policy", "integration_id": 200}, checks)

    def test_duplicate_required_check_rejected(self):
        with self.assertRaises(ValueError):
            build_ruleset("Scan", 100, "Scan", 200)

    def test_missing_vendor_app_rejected(self):
        with self.assertRaises(ValueError):
            build_ruleset("Polaris", 0, "Black Duck", 200)


if __name__ == "__main__":
    unittest.main()
