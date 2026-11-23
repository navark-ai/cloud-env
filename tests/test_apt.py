"""Run with: python3 -m unittest discover tests"""
import os
import pathlib
import shutil
import stat
import subprocess
import tempfile
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
LIB = ROOT / 'lib.sh'
PACKAGES = ROOT / 'packages.sh'
TIMEOUT = shutil.which('timeout')


class AptTest(unittest.TestCase):
    def setUp(self):
        self.directory = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.directory)
        for name in ('state', 'logs', 'bin'):
            (self.directory / name).mkdir()

    def command(self, name, body):
        """Puts a command on PATH in front of the real one."""
        path = self.directory / 'bin' / name
        path.write_text(f'#!/bin/bash\n{body}\n')
        path.chmod(path.stat().st_mode | stat.S_IEXEC)

    def run_script(self, script, **environment):
        path = f'{self.directory}/bin:{os.path.dirname(TIMEOUT or "/usr/bin/timeout")}:/usr/bin:/bin'
        environment = {'PATH': path, 'CLOUD_ENV_STATE_DIR': f'{self.directory}/state', 'CLOUD_ENV_LOG_DIR': f'{self.directory}/logs', **environment}
        script = f'source "{LIB}" 2>/dev/null\nsource "{PACKAGES}"\n{script}\n'
        return subprocess.run(['bash', '-s'], input=script, capture_output=True, text=True, env=environment, timeout=60)


@unittest.skipUnless(TIMEOUT, 'needs the timeout command of coreutils')
class AptGetTest(AptTest):
    def test_a_run_that_never_ends_is_stopped_at_its_limit(self):
        self.command('apt-get', 'sleep 30')
        started = time.monotonic()

        result = self.run_script('apt_get 1 update -qq')

        self.assertEqual(result.returncode, 124)
        self.assertLess(time.monotonic() - started, 10)

    def test_a_run_that_ends_in_time_keeps_its_status_and_its_arguments(self):
        self.command('apt-get', f'printf "%s\\n" "$@" >"{self.directory}/arguments"; exit 3')

        result = self.run_script('apt_get 5 install -y -qq nginx')

        self.assertEqual(result.returncode, 3)
        arguments = (self.directory / 'arguments').read_text().split()
        self.assertEqual(arguments[-4:], ['install', '-y', '-qq', 'nginx'])
        self.assertIn('Acquire::https::Timeout=15', arguments)

    def test_the_limits_are_the_setup_budget_unless_a_test_changes_them(self):
        self.assertEqual(self.run_script('echo "$APT_UPDATE_LIMIT $APT_INSTALL_LIMIT"').stdout.split(), ['60', '240'])
        slow = self.run_script('echo "$APT_UPDATE_LIMIT $APT_INSTALL_LIMIT"', CLOUD_ENV_APT_UPDATE_LIMIT='600', CLOUD_ENV_APT_INSTALL_LIMIT='1800')
        self.assertEqual(slow.stdout.split(), ['600', '1800'])


class AnsweringSourceTest(AptTest):
    def curl(self, body):
        """curl replaced: the last argument is the url, and the body decides whether it answers."""
        self.command('curl', f'url="${{@: -1}}"\necho "$url" >>"{self.directory}/requests"\n{body}')

    def chosen(self):
        result = self.run_script('answering_source https://first.test/php http://second.test/php')
        self.assertEqual(result.returncode, 0)
        return result.stdout.strip()

    def test_the_first_source_is_used_when_it_answers(self):
        self.curl('exit 0')

        self.assertEqual(self.chosen(), 'https://first.test/php')
        requests = (self.directory / 'requests').read_text().split()
        self.assertEqual(requests, ['https://first.test/php/dists/noble/InRelease'] * 2)

    def test_the_second_source_is_used_when_the_first_fails(self):
        self.curl('case "$url" in *first*) exit 22 ;; esac\nexit 0')

        self.assertEqual(self.chosen(), 'http://second.test/php')

    def test_a_source_that_fails_one_request_in_two_is_not_used(self):
        counter = self.directory / 'counter'
        self.curl(f'case "$url" in *first*) echo x >>"{counter}"; [ "$(wc -l <"{counter}")" -eq 1 ] && exit 0; exit 22 ;; esac\nexit 0')

        self.assertEqual(self.chosen(), 'http://second.test/php')

    def test_the_first_source_stays_when_none_answers(self):
        self.curl('exit 28')

        self.assertEqual(self.chosen(), 'https://first.test/php')

    def test_the_php_source_has_a_second_host_among_the_default_allowed_domains(self):
        sources = self.run_script('echo "$ONDREJ_PHP_SOURCES"').stdout.split()

        self.assertEqual(sources, ['https://ppa.launchpadcontent.net/ondrej/php/ubuntu', 'http://ppa.launchpad.net/ondrej/php/ubuntu'])


if __name__ == '__main__':
    unittest.main()
