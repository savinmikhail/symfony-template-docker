import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / 'docker/audit-image-security.sh'


class ImageSecurityTest(unittest.TestCase):
    def run_gate(self, failure=''):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            docker = root / 'docker'
            docker.write_text('''#!/usr/bin/env python3
import json, os, sys
with open(os.environ['CALLS'], 'a') as log:
    log.write(json.dumps({'args': sys.argv[1:], 'fresh': os.getenv('DOCKER_SCOUT_NO_CACHE'), 'cache': os.getenv('DOCKER_SCOUT_CACHE_DIR')}) + '\\n')
if os.environ.get('FAILURE') == 'build' and sys.argv[1] == 'buildx': sys.exit(9)
if os.environ.get('FAILURE') == 'scan' and sys.argv[1:3] == ['scout', 'cves']: sys.exit(2)
''')
            docker.chmod(0o755)
            calls = root / 'calls'
            result = subprocess.run(['bash', str(SCRIPT), 'fixture:local', 'Dockerfile', 'prod'],
                                    env={**os.environ, 'PATH': f'{root}:{os.environ["PATH"]}',
                                         'CALLS': str(calls), 'FAILURE': failure}, capture_output=True)
            return result.returncode, [json.loads(line) for line in calls.read_text().splitlines()]

    def test_builds_production_architecture_then_freshly_scans(self):
        code, calls = self.run_gate()
        self.assertEqual(code, 0)
        self.assertEqual(calls[1]['args'], ['buildx', 'build', '--load', '--platform', 'linux/amd64', '--file', 'Dockerfile', '--tag', 'fixture:local', '--target', 'prod', '.'])
        self.assertEqual(calls[2]['args'], ['scout', 'cves', '--only-severity', 'critical,high', '--only-fixed', '--exit-code', 'local://fixture:local'])
        self.assertEqual(calls[2]['fresh'], 'true')
        self.assertFalse(Path(calls[2]['cache']).exists())

    def test_scan_failure_blocks_gate(self):
        code, calls = self.run_gate('scan')
        self.assertEqual(code, 2)
        self.assertEqual(len(calls), 3)
        self.assertFalse(Path(calls[-1]['cache']).exists())

    def test_failed_build_is_not_scanned(self):
        code, calls = self.run_gate('build')
        self.assertEqual(code, 9)
        self.assertEqual(len(calls), 2)


if __name__ == '__main__':
    unittest.main()
