#!/usr/bin/env bash
# Functions of the custom stack: any repository that is not a Laravel project. The guard, the hooks of
# the flow, the browser tools, Redis, Mailpit and the database (DATABASE_ENGINE) are the same as for
# Laravel. What the project needs on top goes in its .claude/cloud.sh: see templates/custom.sh.
#
# The image already holds Python with pip, uv and poetry, Node 20 to 22, Ruby 3.1 to 3.3 with bundler,
# Go, Rust and Java 21. A project with mise.toml, .mise.toml or .tool-versions gets mise and its tools.

# The lock files this stack knows, in the order their package managers run.
DEPENDENCY_FILES="mise.toml .mise.toml .tool-versions package-lock.json pnpm-lock.yaml yarn.lock uv.lock poetry.lock requirements.txt Gemfile.lock go.sum"

has_project_file() {
    [ -f "$ROOT_DIR/$1" ]
}

# Installs mise from its signed apt repository (extrepo), never from a piped script, then the project's tools.
install_tool_versions() {
    has_project_file mise.toml || has_project_file .mise.toml || has_project_file .tool-versions || return 0

    if ! command -v mise >/dev/null; then
        apt_get "$APT_INSTALL_LIMIT" install -y -qq --no-install-recommends extrepo || return 1
        extrepo enable mise || return 1
        apt_get "$APT_UPDATE_LIMIT" update -qq || return 1
        apt_get "$APT_INSTALL_LIMIT" install -y -qq --no-install-recommends mise || return 1
    fi
    mise trust --yes "$ROOT_DIR" >/dev/null 2>&1
    (cd "$ROOT_DIR" && mise install --yes) || return 1
    # Every later shell, the agent's included, finds the project's versions first. lib.sh does the same
    # for the scripts here and the workers.
    grep -q 'mise/shims' /root/.bashrc 2>/dev/null || echo "export PATH=\"$MISE_SHIMS:\$PATH\"" >>/root/.bashrc
    export PATH="$MISE_SHIMS:$PATH"
}

# Runs the package manager of each lock file the project has. A project replaces this function when
# it needs something else.
install_dependencies() {
    cd "$ROOT_DIR" || return 1
    local failed=0

    install_tool_versions || failed=1
    if has_project_file package-lock.json; then
        npm ci --no-audit --no-fund || failed=1
    elif has_project_file pnpm-lock.yaml; then
        pnpm install --frozen-lockfile || failed=1
    elif has_project_file yarn.lock; then
        yarn install --frozen-lockfile || failed=1
    fi
    if has_project_file uv.lock; then
        uv sync --frozen || failed=1
    elif has_project_file poetry.lock; then
        poetry install --no-interaction || failed=1
    elif has_project_file requirements.txt; then
        { [ -d .venv ] || python3 -m venv .venv; } && .venv/bin/pip install --quiet -r requirements.txt || failed=1
    fi
    if has_project_file Gemfile.lock; then
        bundle install || failed=1
    fi
    if has_project_file go.sum; then
        go mod download || failed=1
    fi

    return "$failed"
}

# Fills the application database: the project's migrations and seed. Runs with the services up.
install_application() {
    return 0
}

install_demo_data() {
    return 0
}

# The project's site and workers, one per line: <name>|<command>|<port>. See stacks/laravel.sh.
background_workers() {
    return 0
}

# A custom project serves its site with a worker: nginx is not configured.
start_web() {
    return 0
}

stop_web() {
    return 0
}

build_frontend() {
    return 0
}

# What cloud-sync runs after a checkout. By default, the dependencies again when a lock file changed,
# then migrate_databases when the project defines it. A project can replace this whole function.
sync_project() {
    local failed=0

    # shellcheck disable=SC2086
    sync_when_changed dependencies "dependencies" "$(fingerprint $DEPENDENCY_FILES)" install_dependencies || failed=1
    if declare -F migrate_databases >/dev/null; then
        sync_when_changed migrations "migrations" "$(migrations_fingerprint)" migrate_databases || failed=1
    fi

    return "$failed"
}
