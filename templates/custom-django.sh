#!/usr/bin/env bash
# .claude/cloud.sh of a Django project on PostgreSQL, tested in the stand-in VM of tests/vm. Its settings
# read DB_HOST, DB_USER and DB_NAME from the environment, with 127.0.0.1, postgres and the app database
# as defaults, so the worker below needs no variable. Adapt the names to the project's settings.
# See templates/custom.sh for what each value does.

DATABASE_ENGINE="pgsql"
POSTGRES_VERSION="16"

SITE_URL="http://localhost:8000"
SITE_CHECK_PATH="/admin/login/"
SITE_LOGIN_PATH="/admin/login/"
SITE_LOGIN_EMAIL="admin"
SITE_LOGIN_PASSWORD="cloud-admin"
SITE_LANDING_PATH="/admin/"

MIGRATION_PATHS="*/migrations/*.py"

# requirements.txt goes into .venv by default (stacks/custom.sh). These reach Django through its settings.
django() {
    (
        cd "$ROOT_DIR" || exit 1
        DB_HOST=127.0.0.1 DB_USER=postgres DB_NAME="${DB_NAME:-$APP_DATABASE}" .venv/bin/python manage.py "$@"
    )
}

migrate_databases() {
    django migrate --no-input && DB_NAME="$TEST_DATABASE" django migrate --no-input
}

install_application() {
    migrate_databases || return 1
    DJANGO_SUPERUSER_PASSWORD="$SITE_LOGIN_PASSWORD" django createsuperuser --no-input --username "$SITE_LOGIN_EMAIL" --email admin@example.test || true
}

background_workers() {
    echo "web|.venv/bin/python manage.py runserver 127.0.0.1:8000 --noreload|8000"
}

project_context() {
    cat <<'EOF'
- Tests: `.venv/bin/python manage.py test`.
EOF
}
