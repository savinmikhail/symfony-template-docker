"""Execute two real deployment run blocks against a fake shared SSH/Docker host."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def run_blocks(path):
    return json.loads(subprocess.check_output(['ruby', '-ryaml', '-rjson', '-e', 'puts JSON.generate(YAML.load_file(ARGV[0]).fetch("jobs").values.flat_map { |j| j.fetch("steps", []) }.map { |s| s["run"] if s.fetch("run", "").include?("docker login ghcr.io") }.compact)', str(path)], text=True))


class DeploymentRegistryTest(unittest.TestCase):
    def test_workflow_shell_syntax(self):
        for path in (ROOT / '.github/workflows').glob('*.yml'):
            if 'docker login ghcr.io' not in path.read_text():
                continue
            for block in run_blocks(path):
                result = subprocess.run(['bash', '-n'], input=block, text=True, capture_output=True)
                self.assertEqual(0, result.returncode, path.name + ': ' + result.stderr)

    def test_concurrent_deployments_keep_their_own_credentials_and_clean_up(self):
        self.run_deployments(fail=False)

    def test_failed_deployments_clean_up_credentials(self):
        self.run_deployments(fail=True)

    def run_deployments(self, fail):
        path = Path(os.environ.get('DEPLOY_WORKFLOW_PATH', ROOT / '.github/workflows/deploy.yml'))
        block, = run_blocks(path)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binaries = root / 'bin'
            binaries.mkdir()
            logins = root / 'logins'
            logins.mkdir()
            (root / 'scripts/local').mkdir(parents=True)
            (root / 'scripts/local/deploy-scope.sh').write_text('echo backend-only\n')
            scripts = {
                'ssh': '''#!/usr/bin/env bash
while (($#)); do
 case "$1" in -i|-p|-o) shift 2;; *) shift; break;; esac
done
if (($# == 1)); then exec bash -c "$1"; else exec "$@"; fi
''',
                'docker': '''#!/usr/bin/env bash
set -eu
config="${DOCKER_CONFIG:-$FAKE_SHARED_CONFIG}"
mkdir -p "$config"
if [ "$1" = login ]; then
 cat > "$config/token"
 printf '%s' "$config" > "$FAKE_LOGINS/$TEST_SLOT-path"
 touch "$FAKE_LOGINS/$TEST_SLOT-ready"
 echo 'Login Succeeded'
fi
''',
                'git': '''#!/usr/bin/env bash
if [ "${1:-}" = rev-list ]; then echo fixture-sha; fi
exit 0
''',
                'make': '''#!/usr/bin/env bash
set -eu
if [[ "$*" == *current-prod-image-sha* ]]; then echo previous-sha; exit 0; fi
for ((i=0;i<100;i++)); do
 [ -f "$FAKE_LOGINS/A-ready" ] && [ -f "$FAKE_LOGINS/B-ready" ] && break
 sleep .05
done
config="${DOCKER_CONFIG:-$FAKE_SHARED_CONFIG}"
[ "$(cat "$config/token")" = "$GHCR_TOKEN" ] || exit 42
[ "$FORCE_FAILURE" = 0 ] || exit 43
''',
            }
            for name, body in scripts.items():
                p = binaries / name
                p.write_text(body)
                p.chmod(0o755)
            processes = []
            for slot in ('A', 'B'):
                env = {**os.environ, 'PATH': str(binaries) + ':' + os.environ['PATH'], 'DEPLOY_HOST': 'fixture-host', 'DEPLOY_USER': 'fixture-user', 'DEPLOY_PORT': '22', 'DEPLOY_PATH': str(root), 'DEPLOY_TAG': 'v0.0.1', 'CURRENT_TAG': 'v0.0.1', 'RUNNER_TEMP': str(root), 'GHCR_USERNAME': 'fixture', 'GHCR_TOKEN': 'fixture-token-' + slot, 'FAKE_LOGINS': str(logins), 'FAKE_SHARED_CONFIG': str(root / 'shared'), 'TEST_SLOT': slot, 'FORCE_FAILURE': '1' if fail else '0'}
                processes.append(subprocess.Popen(['bash', '-c', block], cwd=root, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True))
            outputs = [process.communicate(timeout=20) for process in processes]
            for process, (stdout, stderr) in zip(processes, outputs):
                self.assertEqual(43 if fail else 0, process.returncode, stdout + stderr)
            paths = [(logins / (slot + '-path')).read_text() for slot in ('A', 'B')]
            self.assertNotEqual(paths[0], paths[1])
            for path in paths:
                self.assertFalse(Path(path).exists(), 'Credentials directory was not cleaned up')
            self.assertFalse((root / 'shared').exists(), 'Global Docker credentials were touched')


if __name__ == '__main__':
    unittest.main()
