#!/usr/bin/env python3
"""Exercise actual builder naming with hosted and self-hosted runner names."""
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

class BuilderNameTest(unittest.TestCase):
    def name(self, repository='template', runner='GitHub Actions 1000000674', trust='trusted'):
        result = subprocess.check_output(['bash', str(ROOT / 'scripts/ci/builder-name.sh'), repository, runner, trust], text=True).strip()
        self.assertRegex(result, r'^[a-zA-Z][a-zA-Z0-9_.-]+$')
        return result

    def test_hosted_names_are_valid_and_stable(self):
        self.assertEqual(self.name(), self.name())

    def test_existing_valid_self_hosted_name_keeps_its_cache(self):
        self.assertEqual('ci-template-CI-worker-1-trusted', self.name(runner='CI-worker-1'))

    def test_runner_identity_survives_normalization_collisions(self):
        self.assertNotEqual(self.name(runner='runner one'), self.name(runner='runner-one'))

    def test_repository_and_trust_boundaries_remain_separate(self):
        self.assertNotEqual(self.name(), self.name(repository='other'))
        self.assertNotEqual(self.name(), self.name(trust='pr'))

    def test_special_characters_are_data(self):
        self.name(repository='Repo / punctuation!', runner='runner $(false) `false` ü')

    def test_action_uses_safe_output(self):
        action = (ROOT / '.github/actions/setup-ci-builder/action.yml').read_text()
        self.assertIn('name: ${{ steps.builder-id.outputs.name }}', action)
        self.assertIn('scripts/ci/builder-name.sh', action)
        self.assertNotIn('name: ci-${{', action)
        self.assertIn('python3 scripts/tests/ci_builder_name_test.py', (ROOT / '.github/workflows/ci.yml').read_text())

if __name__ == '__main__':
    unittest.main()
