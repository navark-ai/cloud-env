#!/usr/bin/env python3
"""Prints what a project says about itself, as shell assignments.

setup.sh runs this once per snapshot, before PHP exists in the VM. The output is sourced by scripts
that run as root and ends up in apt package names, so only a strict format leaves this file. A value
it cannot read is left out, and defaults.sh applies.
"""
import json
import pathlib
import re
import sys

# The MySQL apt source has one series per LTS, and the image ships 8.0.
SUPPORTED_MYSQL_VERSIONS = ('8.0', '8.4')
# The image ships PostgreSQL 16, and the PostgreSQL apt source (PGDG) the newer ones.
SUPPORTED_POSTGRES_VERSIONS = ('16', '17', '18')
# The DB_CONNECTION of Laravel, as an engine of this VM. sqlite keeps the default: a real app moves to a server.
ENGINES = {'mysql': 'mysql', 'mariadb': 'mysql', 'pgsql': 'pgsql'}
DATABASE_IMAGE = re.compile(r'\b(mysql|mariadb|postgres|postgis/postgis):(\d+)(?:\.(\d+))?')
INSTALL_COMMANDS = ('src/App/Console/Commands/Install.php', 'app/Console/Commands/Install.php')


def read_json(file):
    try:
        content = json.loads(file.read_text())
    except (OSError, ValueError):
        return {}

    return content if isinstance(content, dict) else {}


def required_packages(package):
    require = package.get('require')

    return require if isinstance(require, dict) else {}


def php_minors_in_constraint(composer):
    # An upper bound names a version the project cannot use.
    constraint = re.sub(r'<=?\s*[\d.*]+', '', str(required_packages(composer).get('php', '')))

    return re.findall(r'(?<![\d.])8\.(\d{1,2})(?!\d)', constraint)


# A package can list "^8.4 || ^8.3" with the newest first, and it accepts the lowest of them.
def lowest_php_version(constraint):
    versions = [re.match(r'[>=^~\s]*(\d+)\.(\d+)', alternative) for alternative in constraint.split('|')]

    return min(((int(version.group(1)), int(version.group(2))) for version in versions if version), default=None)


# "^8.3" in composer.json can hide a lock file that needs 8.4, and Composer then installs nothing.
def php_floors_in_lock(lock):
    floors = []
    for package in (lock.get('packages') or []) + (lock.get('packages-dev') or []):
        lowest = lowest_php_version(str(required_packages(package).get('php', '')))
        if lowest and lowest[0] == 8:
            floors.append(lowest[1])

    return floors


def php_version(root, composer):
    minors = php_minors_in_constraint(composer) + php_floors_in_lock(read_json(root / 'composer.lock'))

    # "8.3.* || 8.4.*" allows both: the newest is the closest to what the project moves toward.
    return f'8.{max(map(int, minors))}' if minors else None


def workflows(root):
    return [workflow.read_text(errors='ignore') for workflow in sorted((root / '.github/workflows').glob('*.y*ml'))]


def mysql_version(root):
    for workflow in workflows(root):
        match = re.search(r'\bmysql:(\d+\.\d+)', workflow)
        if match:
            return match.group(1) if match.group(1) in SUPPORTED_MYSQL_VERSIONS else None

    return None


def postgres_version(root):
    for workflow in workflows(root):
        match = re.search(r'\b(?:postgres|postgis/postgis):(\d+)', workflow)
        if match:
            return match.group(1) if match.group(1) in SUPPORTED_POSTGRES_VERSIONS else None

    return None


def env_example_connection(root):
    try:
        match = re.search(r'^DB_CONNECTION=["\']?(\w+)', (root / '.env.example').read_text(errors='ignore'), re.MULTILINE)
    except OSError:
        return None

    return ENGINES.get(match.group(1)) if match else None


# What the project declares first, then the first database image of its CI.
def database_engine(root):
    engine = env_example_connection(root)
    if engine:
        return engine

    for workflow in workflows(root):
        match = DATABASE_IMAGE.search(workflow)
        if match:
            return 'pgsql' if 'postgres' in match.group(1) else 'mysql'

    return None


def has_seed_install_command(root):
    for path in INSTALL_COMMANDS:
        file = root / path
        if file.is_file() and re.search(r"\$signature\s*=\s*['\"]install\s*\{--seed\}", file.read_text(errors='ignore')):
            return True

    return False


def app_title(root):
    words = re.findall(r'[a-z0-9]+', root.name.lower())

    return ' '.join(word.capitalize() for word in words) + ' Cloud' if words else None


# Any repository that is not a Laravel project is a custom one: its .claude/cloud.sh says how to run it.
def detect_custom(root):
    values = {
        'STACK': 'custom',
        'DATABASE_ENGINE': database_engine(root) or 'none',
        'MYSQL_VERSION': mysql_version(root),
        'POSTGRES_VERSION': postgres_version(root),
        'APP_DATABASE': re.sub(r'[^a-z0-9]+', '_', root.name.lower()).strip('_') or None,
        'APP_TITLE': app_title(root),
        # No page is known to answer: the project names one.
        'SITE_CHECK_PATH': '',
        'SITE_LOGIN_PATH': '',
    }

    return {name: value for name, value in values.items() if value is not None}


def detect(root):
    if not (root / 'artisan').is_file():
        return detect_custom(root)

    composer = read_json(root / 'composer.json')
    packages = required_packages(composer)
    has_admin_routes = (root / 'routes/admin.php').is_file()
    # A Filament panel has its own login page, and the project may have no /login at all.
    has_filament_login = 'filament/filament' in packages and not has_admin_routes
    login_path = '/admin/login' if has_filament_login else None

    values = {
        'STACK': 'laravel',
        'PHP_VERSION': php_version(root, composer),
        'DATABASE_ENGINE': database_engine(root),
        'MYSQL_VERSION': mysql_version(root),
        'POSTGRES_VERSION': postgres_version(root),
        'APP_DATABASE': re.sub(r'[^a-z0-9]+', '_', root.name.lower()).strip('_') or None,
        'APP_TITLE': app_title(root),
        'SITE_CHECK_PATH': login_path,
        'SITE_LOGIN_PATH': login_path,
        'SITE_LANDING_PATH': '/admin' if has_admin_routes or has_filament_login else None,
        'HAS_INSTALL_COMMAND': str(has_seed_install_command(root)).lower(),
        'HAS_DEMO_SEEDER': str((root / 'database/seeders/DemoSeeder.php').is_file()).lower(),
        'USES_HORIZON': str('laravel/horizon' in packages).lower(),
        'USES_REVERB': str('laravel/reverb' in packages).lower(),
    }

    return {name: value for name, value in values.items() if value is not None}


if __name__ == '__main__':
    for name, value in detect(pathlib.Path(sys.argv[1])).items():
        print(f"{name}='{value}'")
