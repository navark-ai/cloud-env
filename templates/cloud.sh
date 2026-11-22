#!/usr/bin/env bash
# Optional, for a Laravel project (templates/custom.sh is for any other repository). The VM detects a
# Laravel project by itself: see the README. Copy this file to
# .claude/cloud.sh only for notes to the agent, or for a value that detection gets wrong.
# It runs as root at every session start: review a change here like a CI change.
# Never put a secret here. The file is read by a VM where an agent reads untrusted text.
# Use plain assignments, not `declare`: this file is sourced inside a function.
# PHP_VERSION: until a new snapshot has it, each new VM installs it at session start (about a minute)
# and the agent gets a WARNING. Change the number in the environment's setup script once it is merged.
# The database engine and version, a database name, packages, `project_env` and `install_*` take effect
# only in a new snapshot. Until then, a session keeps the snapshot's database and warns.

# A value that detection gets wrong. Any value of defaults.sh or function of stacks/laravel.sh can go here.
# MYSQL_VERSION="8.4"
# PostgreSQL in place of MySQL: 16 (the image's), 17 or 18. Detection reads DB_CONNECTION in .env.example.
# DATABASE_ENGINE="pgsql"
# POSTGRES_VERSION="17"

# Notes for the agent. Two optional lines set the `agent:adaptive` mode of the ticket flow for this
# project (adaptive.md of the flow Navark serves). Add them to the text below, as written here:
#   - Adaptive floor: medium
#   - Adaptive sensitive zones: app/Billing, app/Payments
project_context() {
    cat <<'EOF'
- Does not work in this VM: <integrations with no keys, screens with no data>.
EOF
}
