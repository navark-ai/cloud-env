#!/usr/bin/env bash
# .claude/cloud.sh of a repository that is not a Laravel project (the custom stack). Copy it there and
# keep what the project needs. templates/custom-django.sh is a complete example.
# It runs as root at every session start: review a change here like a CI change.
# Never put a secret here. The file is read by a VM where an agent reads untrusted text.
# Use plain assignments, not `declare`: this file is sourced inside a function.
# Packages, the database and the install_* functions take effect only in a new snapshot. Until then, a
# session keeps the snapshot's database and warns (README, "Versions after a push").
#
# What the VM gives every stack: the guard, the hooks of the Navark flow, Chromium with Playwright,
# Redis on 127.0.0.1:6379, Mailpit (SMTP on 127.0.0.1:1025), and the database below. The image already
# holds Python with pip, uv and poetry, Node 20 to 22, Ruby 3.1 to 3.3 with bundler, Go, Rust and Java 21.
# Other versions: a mise.toml or .tool-versions in the repository, and the VM installs mise and them.

# mysql, pgsql or none. Detection reads the CI's database image; say it here when it guesses wrong.
# PostgreSQL: 16 (the image's), 17 or 18. MySQL: 8.0 or 8.4. User `postgres` or `root`, no password.
DATABASE_ENGINE="pgsql"
POSTGRES_VERSION="16"
# APP_DATABASE and TEST_DATABASE are created empty. Default: the repository's name, and `test`.

# apt packages on top of the image.
EXTRA_SYSTEM_PACKAGES=""

# The site, for the session check, the videos and the agent. Its worker serves it (background_workers).
SITE_URL="http://localhost:8000"
# A page that answers 200 with no session. Empty: no check.
SITE_CHECK_PATH="/"
SITE_LOGIN_PATH="/login"
SITE_LOGIN_EMAIL=""
SITE_LOGIN_PASSWORD=""
SITE_LANDING_PATH="/"

# Paths whose change makes cloud-sync run migrate_databases, as git pathspecs.
MIGRATION_PATHS="migrations db/migrate"

# By default the VM runs the package manager of each lock file it finds (npm, pnpm, yarn, uv, poetry,
# pip with requirements.txt into .venv, bundler, Go modules). Replace the function to do otherwise.
# install_dependencies() {
#     cd "$ROOT_DIR" && npm ci
# }

# Fills the application database once per snapshot, with the services up.
install_application() {
    migrate_databases
}

# Runs the migrations on both databases. cloud-sync calls it again when MIGRATION_PATHS change.
migrate_databases() {
    return 0
}

# Long-running workers, one per line: <name>|<command>|<port>. The command must show in `ps` as written.
# Give the port of a worker that listens on 127.0.0.1: the check waits for it.
background_workers() {
    echo "web|npm run start -- --port 8000|8000"
}

# Built once per snapshot. The site must not need a dev server.
# build_frontend() {
#     npm run build
# }

# Notes for the agent: how to run the tests, what does not work here.
project_context() {
    cat <<'EOF'
- Tests: <the command>.
- Does not work in this VM: <integrations with no keys>.
EOF
}
