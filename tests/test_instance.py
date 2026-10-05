"""Exercise the VM launcher's trust checks without downloading or booting a VM."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class InstanceSecurityTests(unittest.TestCase):
    def launch(self, digest=None, image_url='https://example.invalid/image.img'):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            instance = base / 'instance'
            shutil.copytree(ROOT / 'instance', instance, ignore=shutil.ignore_patterns('.local'))
            local = instance / '.local'
            local.mkdir()
            image = local / 'noble-server-cloudimg-amd64.img'
            image.write_bytes(b'verified image test fixture')
            bins = base / 'bin'
            bins.mkdir()
            capture = base / 'launch.json'
            for name in ('qemu-system-x86_64', 'qemu-img', 'cloud-localds'):
                p = bins / name
                p.write_text('#!/bin/sh\nexit 0\n')
                p.chmod(0o755)
            tmux = bins / 'tmux'
            tmux.write_text(
                '#!/usr/bin/env python3\nimport os,sys,json\n'
                'from pathlib import Path\n'
                'if "has-session" in sys.argv: sys.exit(1)\n'
                'Path(os.environ["TEST_CAPTURE"]).write_text(json.dumps(sys.argv))\n'
            )
            tmux.chmod(0o755)
            env = os.environ.copy()
            env.update(
                PATH=str(bins) + os.pathsep + env['PATH'],
                OCTELIUM_CLOUD_IMAGE_URL=image_url,
                OCTELIUM_CLOUD_IMAGE_SHA256=digest or hashlib.sha256(image.read_bytes()).hexdigest(),
                TEST_CAPTURE=str(capture),
            )
            result = subprocess.run(['bash', str(instance / 'create-instance.sh')], env=env,
                                    capture_output=True, text=True)
            args = json.loads(capture.read_text()) if capture.exists() else None
            return result, args

    def test_verified_image_launches_with_loopback_ports(self):
        result, args = self.launch()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('user,id=n0,hostfwd=tcp:127.0.0.1:2222-:22,hostfwd=tcp:127.0.0.1:8443-:443', args)
        self.assertNotIn('StrictHostKeyChecking=no', result.stdout)
        if not os.access('/dev/kvm', os.R_OK):
            self.assertIn('accel=tcg', args)

    def test_invalid_image_digest_prevents_launch(self):
        result, args = self.launch(digest='0' * 64)
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(args)

    def test_plain_http_image_is_rejected(self):
        result, args = self.launch(image_url='http://example.invalid/image.img')
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(args)


if __name__ == '__main__':
    unittest.main()
