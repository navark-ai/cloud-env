"""Run with: python3 -m unittest discover tests"""
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
LIB = ROOT / 'lib.sh'
PACKAGES = ROOT / 'packages.sh'


def run(script, **environment):
    return subprocess.run(['bash', '-s'], input=script, capture_output=True, text=True, check=True, env={'PATH': '/usr/bin:/bin:/usr/local/bin', **environment}).stdout


class FindRootDirTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.home = pathlib.Path(directory.name)

    def root(self):
        return run(f'source "{LIB}" 2>/dev/null\necho "$ROOT_DIR"\n', CLOUD_ENV_HOME_DIR=str(self.home)).strip()

    def test_a_laravel_project_wins_over_another_repository(self):
        (self.home / 'a-tool/.git').mkdir(parents=True)
        (self.home / 'shop/.git').mkdir(parents=True)
        (self.home / 'shop/artisan').write_text('')
        self.assertEqual(self.root(), str(self.home / 'shop'))

    def test_any_repository_is_found(self):
        (self.home / 'api/.git').mkdir(parents=True)
        self.assertEqual(self.root(), str(self.home / 'api'))

    def test_a_folder_that_is_no_repository_is_not(self):
        (self.home / 'notes').mkdir()
        self.assertEqual(self.root(), '')


class StackFileTest(unittest.TestCase):
    def test_the_stack_of_the_detected_values_gives_the_functions(self):
        script = f'''
source "{LIB}" 2>/dev/null
STACK=custom; source "$CLOUD_DIR/stacks/$STACK.sh"
declare -F install_dependencies sync_project >/dev/null && echo custom-functions
background_workers | wc -l | tr -d ' '
'''
        self.assertEqual(run(script).split(), ['custom-functions', '0'])


class DatabaseEnvTest(unittest.TestCase):
    def env(self, engine):
        return run(f'source "{LIB}" 2>/dev/null\nDATABASE_ENGINE={engine}; APP_DATABASE=shop\ndatabase_env\n')

    def test_each_engine_gives_its_connection(self):
        self.assertIn('DB_CONNECTION=mysql\nDB_HOST=127.0.0.1\nDB_PORT=3306\nDB_DATABASE=shop\nDB_USERNAME=root\n', self.env('mysql'))
        self.assertIn('DB_CONNECTION=pgsql\nDB_HOST=127.0.0.1\nDB_PORT=5432\nDB_DATABASE=shop\nDB_USERNAME=postgres\n', self.env('pgsql'))
        self.assertEqual(self.env('none'), '')


class PhpPackagesTest(unittest.TestCase):
    def packages(self, version, engine='mysql', stack='laravel'):
        # Only the functions of setup.sh, not its steps.
        script = f'source "{LIB}" 2>/dev/null\nsource "{PACKAGES}"\nSTACK={stack}; PHP_VERSION={version}; DATABASE_ENGINE={engine}\nphp_packages\n'
        return run(script).split()

    def test_opcache_has_a_package_until_php_8_4(self):
        for version in ['8.2', '8.3', '8.4']:
            self.assertIn(f'php{version}-opcache', self.packages(version), version)

    def test_php_8_5_and_later_have_opcache_built_in(self):
        self.assertNotIn('php8.5-opcache', self.packages('8.5'))
        self.assertIn('php8.5-fpm', self.packages('8.5'))
        self.assertIn('nginx', self.packages('8.5'))
        self.assertNotIn('php8.10-opcache', self.packages('8.10'))

    def test_postgresql_adds_its_extension(self):
        self.assertIn('php8.4-pgsql', self.packages('8.4', 'pgsql'))
        self.assertNotIn('php8.4-pgsql', self.packages('8.4'))

    def test_a_custom_stack_installs_no_php(self):
        self.assertEqual(self.packages('8.4', stack='custom'), [])



class VersionsTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.state = pathlib.Path(directory.name) / 'state'
        self.state.mkdir()
        self.root = pathlib.Path(directory.name) / 'shop'
        (self.root / '.claude').mkdir(parents=True)
        (self.root / 'artisan').write_text('')

    def bash(self, body):
        script = f'source "{LIB}" 2>/dev/null\nROOT_DIR="{self.root}"\n{body}\n'
        return run(script, CLOUD_ENV_STATE_DIR=str(self.state), CLOUD_ENV_LOG_DIR=str(self.state))

    def installed(self, php='8.3', engine='mysql', mysql='8.0', postgres='16', stack='laravel'):
        (self.state / 'installed.sh').write_text(
            f"INSTALLED_STACK='{stack}'\nINSTALLED_PHP_VERSION='{php}'\nINSTALLED_DATABASE_ENGINE='{engine}'\n"
            f"INSTALLED_MYSQL_VERSION='{mysql}'\nINSTALLED_POSTGRES_VERSION='{postgres}'\n")

    def test_the_checkout_asks_for_what_its_files_say_now(self):
        (self.root / 'composer.json').write_text('{"require": {"php": "^8.4"}}')
        (self.root / '.claude/cloud.sh').write_text('MYSQL_VERSION="8.4"\nproject_context() { echo noise; }\n')
        self.assertEqual(self.bash('wanted_versions').split(), ['laravel', '8.4', 'mysql', '8.4', '16'])

    def test_a_session_runs_on_what_the_snapshot_installed(self):
        self.installed(php='8.3', mysql='8.0')
        (self.root / '.claude/cloud.sh').write_text('PHP_VERSION="8.4"\nMYSQL_VERSION="8.4"\n')
        script = 'cp "$ROOT_DIR/.claude/cloud.sh" "$INSTALLED_PROJECT_FILE"; load_project_values; echo "$PHP_VERSION $MYSQL_VERSION"'
        self.assertEqual(self.bash(script).split(), ['8.3', '8.0'])

    def test_setup_reads_the_checkout_and_not_the_last_snapshot(self):
        self.installed(php='8.3')
        (self.root / '.claude/cloud.sh').write_text('PHP_VERSION="8.4"\n')
        script = 'cp "$ROOT_DIR/.claude/cloud.sh" "$INSTALLED_PROJECT_FILE"; CLOUD_ENV_SETUP=1 load_project_values; echo "$PHP_VERSION"'
        self.assertEqual(self.bash(script).strip(), '8.4')

    def warnings(self, *wanted):
        self.installed()
        return self.bash(f'source "$INSTALLED_FILE"; version_warnings {" ".join(wanted)}').splitlines()

    def test_the_same_versions_give_no_warning(self):
        self.assertEqual(self.warnings('laravel', '8.4', 'mysql', '8.0', '17'), [])

    def test_another_database_version_or_engine_is_a_warning_in_english(self):
        [line] = self.warnings('laravel', '8.3', 'mysql', '8.4', '16')
        self.assertTrue(line.startswith('WARNING: the checkout asks for MySQL 8.4, and this snapshot has MySQL 8.0, which this session uses.'), line)
        [line] = self.warnings('laravel', '8.3', 'pgsql', '8.0', '17')
        self.assertIn('asks for PostgreSQL 17, and this snapshot has MySQL 8.0', line)

    def test_another_stack_is_a_warning(self):
        lines = self.warnings('custom', '8.3', 'mysql', '8.0', '16')
        self.assertEqual(len(lines), 1)
        self.assertIn('the checkout is a custom project, and this snapshot was set up for the laravel stack', lines[0])

    def test_the_installed_file_reads_back(self):
        script = 'STACK=laravel PHP_VERSION=8.5 DATABASE_ENGINE=pgsql MYSQL_VERSION=8.0 POSTGRES_VERSION=18 write_installed_versions; source "$INSTALLED_FILE"; echo "$INSTALLED_PHP_VERSION $INSTALLED_DATABASE_ENGINE $INSTALLED_POSTGRES_VERSION"'
        self.assertEqual(self.bash(script).split(), ['8.5', 'pgsql', '18'])


if __name__ == '__main__':
    unittest.main()
