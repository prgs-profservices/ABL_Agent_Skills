import unittest

from scripts.validate_baseline import validate_hooks, validate_reference, validate_skill, validate_workflow
from scripts.configure_github import build_ruleset


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
        validate_skill("---\nname: test-skill\ndescription: Test skill\n---\nInstructions\n", "test-skill")

    def test_skill_without_description_rejected(self):
        with self.assertRaises(ValueError):
            validate_skill("---\nname: test-skill\n---\nInstructions\n", "test-skill")

    def test_skill_directory_mismatch_rejected(self):
        with self.assertRaises(ValueError):
            validate_skill("---\nname: test-skill\ndescription: Test\n---\nInstructions\n", "other")

    def test_ruleset_enforces_pr_and_security_checks(self):
        ruleset = build_ruleset("Polaris policy", 100, "Black Duck policy", 200)
        self.assertEqual(ruleset["bypass_actors"], [])
        rules = {rule["type"]: rule.get("parameters", {}) for rule in ruleset["rules"]}
        self.assertTrue(rules["pull_request"]["required_review_thread_resolution"])
        self.assertTrue(rules["pull_request"]["dismiss_stale_reviews_on_push"])
        self.assertEqual(rules["pull_request"]["required_approving_review_count"], 1)
        self.assertIn("deletion", rules)
        self.assertIn("non_fast_forward", rules)
        checks = rules["required_status_checks"]["required_status_checks"]
        self.assertEqual(len(checks), 4)
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
