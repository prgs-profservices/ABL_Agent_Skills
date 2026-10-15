import io
import json
from pathlib import Path, PurePosixPath
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

from scripts.scan_skills import (
    NUCLIA_URL,
    llm_environment,
    skill_directories,
    stage_skill,
    validate_report,
    verify_nuclia_gateway,
)


class SkillScannerTests(unittest.TestCase):
    def report(self, analyzers=None, findings=None):
        findings = [] if findings is None else findings
        return {
            "findings": findings,
            "findings_count": len(findings),
            "is_safe": True,
            "analyzers_used": ["static"] if analyzers is None else analyzers,
        }

    def environment(self):
        return {
            "SKILL_SCANNER_LLM_BASE_URL": NUCLIA_URL,
            "SKILL_SCANNER_LLM_MODEL": "openai/aws-claude-4-6-opus",
            "SKILL_SCANNER_LLM_API_KEY": "synthetic-test-value",
        }

    def test_discovery_has_no_hardcoded_skill_root(self):
        self.assertEqual(skill_directories(["skills/one/SKILL.md", "other/two/SKILL.md", "README.md"]),
                         [PurePosixPath("other/two"), PurePosixPath("skills/one")])

    def test_no_skills(self):
        self.assertEqual(skill_directories(["README.md"]), [])

    def test_clean_static_report(self):
        self.assertEqual(validate_report(self.report(), "static"), ({}, False))

    def test_medium_finding_blocks_even_safe_label(self):
        counts, blocked = validate_report(self.report(findings=[{"severity": "MEDIUM"}]), "static")
        self.assertEqual(counts, {"MEDIUM": 1})
        self.assertTrue(blocked)

    def test_analyzer_error_blocks(self):
        report = self.report()
        report["analyzers_failed"] = [{"analyzer": "static", "error": "test"}]
        with self.assertRaises(ValueError):
            validate_report(report, "static")

    def test_missing_llm_analyzer_blocks(self):
        with self.assertRaises(ValueError):
            validate_report(self.report(), "llm")

    def test_clean_llm_report(self):
        self.assertEqual(validate_report(self.report(["static", "behavioral", "llm"]), "llm"), ({}, False))

    def test_missing_meta_analysis_blocks_when_findings_exist(self):
        with self.assertRaises(ValueError):
            validate_report(self.report(["static", "behavioral", "llm"], [{"severity": "HIGH"}]), "llm")

    def test_invalid_report_blocks(self):
        with self.assertRaises(ValueError):
            validate_report({"findings": []}, "static")

    def test_unknown_severity_blocks(self):
        with self.assertRaises(ValueError):
            validate_report(self.report(findings=[{"severity": "UNKNOWN"}]), "static")

    def test_finding_count_mismatch_blocks(self):
        report = self.report()
        report["findings_count"] = 10
        with self.assertRaises(ValueError):
            validate_report(report, "static")

    def test_wrong_gateway_blocks_before_scanning(self):
        environment = self.environment()
        environment["SKILL_SCANNER_LLM_BASE_URL"] = "https://api.openai.com/v1"
        with self.assertRaises(ValueError):
            llm_environment(environment)

    def test_wrong_base_variable_blocks(self):
        environment = self.environment()
        environment["SKILL_SCANNER_LLM_API_BASE"] = NUCLIA_URL
        with self.assertRaises(ValueError):
            llm_environment(environment)

    def test_missing_api_key_blocks(self):
        environment = self.environment()
        del environment["SKILL_SCANNER_LLM_API_KEY"]
        with self.assertRaises(ValueError):
            llm_environment(environment)

    def test_meta_cannot_override_approved_gateway(self):
        environment = self.environment()
        environment["SKILL_SCANNER_META_LLM_BASE_URL"] = "https://example.com"
        self.assertNotIn("SKILL_SCANNER_META_LLM_BASE_URL", llm_environment(environment))

    def test_snapshot_copies_only_git_visible_skill_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "repository"
            skill = root / "skills" / "test"
            skill.mkdir(parents=True)
            (skill / "SKILL.md").write_text("Test instructions", encoding="utf-8")
            (skill / ".env").write_text("ignored-test-file", encoding="utf-8")
            destination = Path(temporary) / "snapshot"
            stage_skill(root, ["skills/test/SKILL.md"], PurePosixPath("skills/test"), destination)
            self.assertTrue((destination / "SKILL.md").is_file())
            self.assertFalse((destination / ".env").exists())

    def test_nuclia_gateway_probe_succeeds_on_valid_response(self):
        response = io.BytesIO(json.dumps({"choices": [{"message": {"content": "OK"}}]}).encode("utf-8"))
        response.__enter__ = lambda self: self
        response.__exit__ = lambda self, *args: False
        with patch("urllib.request.urlopen", return_value=response) as mocked:
            verify_nuclia_gateway(self.environment())
            request = mocked.call_args[0][0]
            self.assertEqual(request.full_url, f"{NUCLIA_URL}/chat/completions")

    def test_nuclia_gateway_probe_blocks_on_http_error(self):
        with patch("urllib.request.urlopen", side_effect=urllib.error.URLError("unauthorized")):
            with self.assertRaises(ValueError):
                verify_nuclia_gateway(self.environment())


if __name__ == "__main__":
    unittest.main()
