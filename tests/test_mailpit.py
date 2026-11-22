"""Run with: python3 -m unittest discover tests"""
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
LIB = ROOT / 'lib.sh'


class RepairMailpitTest(unittest.TestCase):
    def setUp(self):
        self.directory = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.directory)
        for name in ('state', 'logs', 'project', 'bin'):
            (self.directory / name).mkdir()
        self.env_file = self.directory / 'project' / '.env'
        self.marker = self.directory / 'state' / 'mail-log-fallback'

    def repair(self, install_works):
        """Runs repair_mailpit with the download replaced: it puts a mailpit command on PATH, or fails."""
        install = f'printf "#!/bin/sh\\n" >"{self.directory}/bin/mailpit"; chmod +x "{self.directory}/bin/mailpit"' \
            if install_works else 'return 1'
        script = f'''
source "{LIB}" 2>/dev/null
STATE_DIR="{self.directory}/state"
LOG_DIR="{self.directory}/logs"
ROOT_DIR="{self.directory}/project"
install_mailpit() {{ {install}; }}
repair_mailpit
'''
        environment = {'PATH': f'{self.directory}/bin:/usr/bin:/bin'}
        return subprocess.run(['bash', '-s'], input=script, capture_output=True, text=True, env=environment).returncode

    def test_a_repair_puts_the_mail_back_on_mailpit_after_the_setup_fell_back_to_the_log(self):
        self.env_file.write_text('APP_NAME=Demo\nMAIL_MAILER=log\nMAIL_PORT=1025\n')
        self.marker.touch()

        self.assertEqual(self.repair(install_works=True), 0)

        self.assertEqual(self.env_file.read_text(), 'APP_NAME=Demo\nMAIL_MAILER=smtp\nMAIL_PORT=1025\n')
        self.assertFalse(self.marker.exists())

    def test_a_repair_keeps_the_log_mailer_a_project_chose_itself(self):
        self.env_file.write_text('MAIL_MAILER=log\n')

        self.assertEqual(self.repair(install_works=True), 0)

        self.assertEqual(self.env_file.read_text(), 'MAIL_MAILER=log\n')

    def test_a_failed_repair_changes_nothing(self):
        self.env_file.write_text('MAIL_MAILER=log\n')
        self.marker.touch()

        self.assertEqual(self.repair(install_works=False), 1)

        self.assertEqual(self.env_file.read_text(), 'MAIL_MAILER=log\n')
        self.assertTrue(self.marker.exists())


if __name__ == '__main__':
    unittest.main()
