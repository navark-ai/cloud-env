#!/usr/bin/env bash
# Values for every project. detect.py replaces most of them from the project's own files, the stack's
# file (stacks/<STACK>.sh) gives the functions, and the optional .claude/cloud.sh of the project
# replaces what it needs: see templates/.

# laravel: a repository with `artisan`, served by nginx and php-fpm. custom: any other repository; the
# project's .claude/cloud.sh says how to install and run it (templates/custom.sh).
STACK="laravel"

APP_DATABASE="app"
TEST_DATABASE="test"
APP_TITLE="Cloud VM"

SITE_URL="http://localhost"
# curl checks this page at every session start. It must answer 200 with no session. Empty: no check.
SITE_CHECK_PATH="/login"
SITE_LOGIN_PATH="/login"
# Found in the database after the install: see detect_login in setup.sh.
SITE_LOGIN_EMAIL=""
SITE_LOGIN_PASSWORD=""
SITE_LANDING_PATH="/"

# The image is Ubuntu 24.04, and its apt sources ship PHP 8.3, MySQL 8.0 and PostgreSQL 16. Another
# version comes from its vendor's apt source, which costs about a minute more in the setup script.
PHP_VERSION="8.3"
# mysql, pgsql or none. Both servers listen on 127.0.0.1 with no password: MySQL as `root`, PostgreSQL as
# `postgres`.
DATABASE_ENGINE="mysql"
MYSQL_VERSION="8.0"
POSTGRES_VERSION="16"
# Composer stops without imagick in many Laravel projects. opcache is built into PHP 8.5 and later, and
# setup.sh adds pgsql for PostgreSQL.
PHP_EXTENSIONS="fpm cli mysql redis gd imagick intl bcmath zip soap mbstring xml curl sqlite3 opcache gmp"
# PDF work, Loom frames and QR checks. The laravel stack adds nginx and PHP.
SYSTEM_PACKAGES="ffmpeg imagemagick jq lsof ghostscript poppler-utils zbar-tools"
EXTRA_SYSTEM_PACKAGES=""

# Paths whose change asks cloud-sync for a migration, as git pathspecs.
MIGRATION_PATHS="database/migrations database/schema modules/*/migrations/* modules/*/Database/migrations/*"

HAS_INSTALL_COMMAND="false"
HAS_DEMO_SEEDER="false"
USES_HORIZON="false"
USES_REVERB="false"

# Skills that exist only as plugins on a developer machine: cloud sessions install no plugin.
# Format: <github repo>|<comma-separated folders searched for SKILL.md>. On a name collision the first one wins.
SKILL_REPOSITORIES="pbakaus/impeccable|."

# .env lines that replace the ones setup.sh writes (laravel).
project_env() {
    return 0
}

# Markdown the agent reads at every session start, after session-context.md.
project_context() {
    return 0
}
