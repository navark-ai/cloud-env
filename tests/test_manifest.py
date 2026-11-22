"""Run with: python3 -m unittest discover tests"""
import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
MANIFEST = json.loads((ROOT / 'stacks.json').read_text())


def default(name):
    return re.search(rf'^{name}="([^"]*)"', (ROOT / 'defaults.sh').read_text(), re.MULTILINE).group(1)


def detect_tuple(name):
    return tuple(re.findall(r"'([\d.]+)'", re.search(rf'^{name} = \(([^)]*)\)', (ROOT / 'detect.py').read_text(), re.MULTILINE).group(1)))


class ManifestTest(unittest.TestCase):
    def test_its_version_is_the_one_the_setup_script_clones(self):
        script = (ROOT / 'environment-setup.sh').read_text()
        self.assertIn(f'CLOUD_ENV_VERSION={MANIFEST["version"]}\n', script)

    def test_each_stack_has_its_file_and_template(self):
        for stack in MANIFEST['stacks']:
            self.assertTrue((ROOT / f'stacks/{stack["id"]}.sh').is_file(), stack['id'])
            self.assertTrue((ROOT / f'stacks/{stack["id"]}.md').is_file(), stack['id'])
            self.assertTrue((ROOT / stack['template']).is_file(), stack['template'])
            for example in stack.get('examples', []):
                self.assertTrue((ROOT / example['file']).is_file(), example['file'])

    def test_versions_and_defaults_match_the_scripts(self):
        php = MANIFEST['stacks'][0]['languages']['php']
        self.assertEqual(php['default'], default('PHP_VERSION'))
        databases = MANIFEST['databases']
        self.assertEqual(tuple(databases['mysql']['versions']), detect_tuple('SUPPORTED_MYSQL_VERSIONS'))
        self.assertEqual(databases['mysql']['default'], default('MYSQL_VERSION'))
        self.assertEqual(tuple(databases['pgsql']['versions']), detect_tuple('SUPPORTED_POSTGRES_VERSIONS'))
        self.assertEqual(databases['pgsql']['default'], default('POSTGRES_VERSION'))
        self.assertEqual(MANIFEST['stacks'][0]['defaultDatabase'], default('DATABASE_ENGINE'))

    def test_the_environment_files_exist(self):
        for key in ('setupScript', 'allowedDomains'):
            self.assertTrue((ROOT / MANIFEST['environment'][key]).is_file(), key)


if __name__ == '__main__':
    unittest.main()
