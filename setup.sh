#!/usr/bin/env bash
# Provisions the cloud VM. The environment's setup script calls this once per snapshot, before
# Claude Code starts. Anthropic then keeps the disk, so later sessions start with all of this in place.
#
# It exits 0 whatever fails but the system packages: a non-zero exit stops the session from starting. A
# step that fails is recorded in /var/lib/cloud-env/steps and session-start.sh reports it to the agent.
# Without the system packages nothing else can work, and an exit 0 would keep that VM as the project's
# snapshot for a week: there the script exits 1, the platform keeps nothing and the next session tries again.
# The snapshot is only kept when this finishes in about five minutes, so what can run together does, and
# every download has a time limit.

set -uo pipefail

CLOUD_ENV_SETUP=1
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"
source "$CLOUD_DIR/packages.sh"

: >"$STATE_DIR/steps"
rm -f "$INSTALLED_FILE"
date -u +%FT%TZ >"$STATE_DIR/setup-started-at"

install_system_packages() {
    # dpkg fsyncs every file by default. The VM has nothing to protect at this point.
    echo force-unsafe-io >/etc/dpkg/dpkg.cfg.d/unsafe-io
    printf 'path-exclude=/usr/share/doc/*\npath-exclude=/usr/share/man/*\n' >/etc/dpkg/dpkg.cfg.d/no-docs

    add_version_sources || return 1
    apt_get "$APT_UPDATE_LIMIT" update -qq || return 1
    # shellcheck disable=SC2046,SC2086
    apt_get "$APT_INSTALL_LIMIT" install -y -qq --no-install-recommends $(php_packages) $(database_packages) $SYSTEM_PACKAGES $EXTRA_SYSTEM_PACKAGES || return 1
    # An image can hold another PHP, and the project's version must answer to `php`.
    if [ "$STACK" = "laravel" ]; then
        update-alternatives --set php "/usr/bin/php$PHP_VERSION" || return 1
    fi

    # Debian blocks PDF reads by default; spatie/pdf-to-image needs them.
    sed -i 's/rights="none" pattern="PDF"/rights="read|write" pattern="PDF"/' /etc/ImageMagick-*/policy.xml 2>/dev/null || true
}

configure_mysql() {
    cp "$CLOUD_DIR/config/mysql.cnf" /etc/mysql/mysql.conf.d/zz-cloud.cnf
    stop_mysql_server
    start_mysql || { rm -f /etc/mysql/mysql.conf.d/zz-cloud.cnf; start_mysql; } || return 1

    # The site and the tests connect as root with no password over TCP.
    mysql -uroot <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '';
CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED WITH caching_sha2_password BY '';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
CREATE DATABASE IF NOT EXISTS \`$APP_DATABASE\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS \`$TEST_DATABASE\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
FLUSH PRIVILEGES;
SQL
}

configure_postgres() {
    local version cluster directory="/etc/postgresql/$POSTGRES_VERSION/main" marker="# cloud-env"

    # Only the cluster of POSTGRES_VERSION stays, on the default port: the image ships 16, and a newer
    # package creates its own cluster on 5433.
    while read -r version cluster _; do
        [ "$version" = "$POSTGRES_VERSION" ] && [ "$cluster" = "main" ] && continue
        pg_dropcluster --stop "$version" "$cluster" || return 1
    done < <(pg_lsclusters -h 2>/dev/null)
    [ -d "$directory" ] || pg_createcluster "$POSTGRES_VERSION" main || return 1
    pg_conftool "$POSTGRES_VERSION" main set port 5432 || return 1
    mkdir -p "$directory/conf.d"
    cp "$CLOUD_DIR/config/postgresql.conf" "$directory/conf.d/zz-cloud.conf"

    # The site and the tests connect as postgres with no password, like root on MySQL.
    if ! grep -q "^$marker" "$directory/pg_hba.conf"; then
        { printf '%s\nlocal all all trust\nhost all all 127.0.0.1/32 trust\nhost all all ::1/128 trust\n' "$marker"; cat "$directory/pg_hba.conf"; } >"$directory/pg_hba.conf.new"
        mv "$directory/pg_hba.conf.new" "$directory/pg_hba.conf"
        chown postgres:postgres "$directory/pg_hba.conf"
    fi

    service postgresql stop >/dev/null 2>&1
    start_postgres || return 1

    local database
    for database in "$APP_DATABASE" "$TEST_DATABASE"; do
        [ -n "$(database_query "SELECT 1 FROM pg_database WHERE datname = '$database'" postgres)" ] && continue
        createdb -h 127.0.0.1 -U postgres -E UTF8 -T template0 "$database" || return 1
    done
}

configure_database() {
    case "$DATABASE_ENGINE" in
        mysql) configure_mysql ;;
        pgsql) configure_postgres ;;
        *) return 0 ;;
    esac
}

install_browser_tools() {
    local failed=0

    npm install -g --no-audit --no-fund @playwright/mcp@0.0.84 || failed=1
    pip install --quiet --break-system-packages yt-dlp pyyaml || failed=1

    return "$failed"
}

link_commands() {
    local name

    for name in herd cloud-sync composer-install; do
        chmod +x "$CLOUD_DIR/bin/$name"
        ln -sf "$CLOUD_DIR/bin/$name" "/usr/local/bin/$name"
    done
    ln -sf /usr/bin/php "/usr/local/bin/php${PHP_VERSION//./}"
    chmod +x "$CLOUD_DIR"/git-hooks/*
    git config --system core.hooksPath "$CLOUD_DIR/git-hooks"
}

link_skill() {
    local directory="$1" name

    name="$(basename "$directory")"
    # The repository's own skills load anyway and win on a name collision.
    [ -e "$ROOT_DIR/.claude/skills/$name" ] && return 0
    [ -e "/root/.claude/skills/$name" ] && return 0
    ln -s "$directory" "/root/.claude/skills/$name"
}

install_skills() {
    local entry repository folders folder directory target failed=0

    mkdir -p /root/.claude/skills

    for entry in $SKILL_REPOSITORIES; do
        repository="${entry%%|*}"
        folders="${entry##*|}"
        target="/opt/skills/$repository"

        rm -rf "$target"
        git clone --quiet --depth 1 "https://github.com/$repository" "$target" || { failed=1; continue; }

        for folder in ${folders//,/ }; do
            while IFS= read -r directory; do
                link_skill "$directory"
            done < <(find "$target/$folder" -mindepth 2 -maxdepth 4 -name SKILL.md -not -path '*/node_modules/*' -not -path '*/deprecated/*' -not -path '*/in-progress/*' -printf '%h\n')
        done
    done

    return "$failed"
}

# ~/.claude holds what only the VM needs, so the repository's settings stay the same on a Mac.
configure_claude() {
    python3 -I - "$CLOUD_DIR" <<'PYTHON'
import json, os, sys

cloud_dir = sys.argv[1]
settings_path = '/root/.claude/settings.json'
os.makedirs(os.path.dirname(settings_path), exist_ok=True)
existing = json.load(open(settings_path)) if os.path.exists(settings_path) else {}
wanted = json.load(open(f'{cloud_dir}/config/claude-settings.json'))

for key, value in wanted.items():
    if key == 'hooks':
        hooks = existing.setdefault('hooks', {})
        for event, entries in value.items():
            hooks.setdefault(event, []).extend(entries)
    elif key == 'permissions':
        existing.setdefault('permissions', {}).setdefault('allow', []).extend(value.get('allow', []))
    elif key == 'env':
        existing.setdefault('env', {}).update(value)
    else:
        existing[key] = value

text = json.dumps(existing, indent=2).replace('__CLOUD_DIR__', cloud_dir)
open(settings_path, 'w').write(text)

config_path = '/root/.claude.json'
config = json.load(open(config_path)) if os.path.exists(config_path) else {}
config.setdefault('mcpServers', {})['playwright'] = json.load(open(f'{cloud_dir}/config/mcp-playwright.json'))
json.dump(config, open(config_path, 'w'), indent=2)
PYTHON
}

# Project lines come first, and only the first line of a key stays.
write_env_file() {
    local title

    title="$(printf '%s' "$APP_TITLE" | sed 's/[&#\\]/\\&/g')"

    {
        project_env
        [ "$USES_REVERB" = "true" ] && sed -e "s#__APP_DATABASE__#$APP_DATABASE#" "$CLOUD_DIR/env.reverb"
        # With no worker on the queue, nothing reads a Redis queue.
        has_worker 'horizon|queue:' || echo "QUEUE_CONNECTION=sync"
        database_env
        sed -e "s#__SITE_URL__#$SITE_URL#" -e "s#__APP_DATABASE__#$APP_DATABASE#" -e "s#__APP_TITLE__#$title#" "$CLOUD_DIR/env.defaults"
    } | awk -F= '/^[A-Za-z_][A-Za-z0-9_]*=/ { if (seen[$1]++) next } { print }' >"$ROOT_DIR/.env"
}

# Installed packages and databases follow these values, so a later checkout must not change them.
detect_project() {
    python3 -I "$CLOUD_DIR/detect.py" "$ROOT_DIR" >"$DETECTED_FILE"
}

# The first user is the one the install command creates. An agent gets a login only when the
# password was proven against this user's hash.
detect_login() {
    local email hash password

    IFS=$'\t' read -r email hash < <(database_query "SELECT email, password FROM users ORDER BY id LIMIT 1" 2>/dev/null)
    [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+$ ]] || return 0

    password="$(php "$CLOUD_DIR/find-seeded-password.php" "$hash")" || return 0
    printf "SITE_LOGIN_EMAIL='%s'\nSITE_LOGIN_PASSWORD='%s'\n" "$email" "$password" >>"$DETECTED_FILE"
}

install_php_dependencies() {
    "$CLOUD_DIR/bin/composer-install" --setup
}

install_js_dependencies() {
    npm ci --no-audit --no-fund
}

prepare_application() {
    cd "$ROOT_DIR" || return 1

    command -v mailpit >/dev/null || use_mail_log
    php artisan key:generate --force --no-interaction
    # Passport signs personal access tokens and OAuth tokens with these keys; without them, creating a token or
    # calling an API with one fails with "Invalid key supplied". The files are git-ignored.
    # The list is read whole before it is matched: with pipefail, `grep -q` closing the pipe early can make
    # artisan fail on the broken pipe, and the check would then skip the keys silently.
    local commands
    commands=$(php artisan list --raw 2>/dev/null)
    if grep -q '^passport:keys' <<<"$commands"; then
        [ -f storage/oauth-private.key ] || php artisan passport:keys --no-interaction >/dev/null
    fi

    install_application || return 1
    detect_login
    DB_DATABASE="$TEST_DATABASE" APP_ENV=testing php artisan migrate:fresh --force --no-interaction
}

seed_demo_data() {
    cd "$ROOT_DIR" || return 1
    install_demo_data
}

build_assets() {
    cd "$ROOT_DIR" || return 1
    rm -f public/hot
    build_frontend
}

step_succeeded() {
    grep -q "^$1 0 " "$STATE_DIR/steps"
}

# A step that failed keeps no fingerprint, so cloud-sync repairs it. Composer is the exception:
# a repair through git takes about 13 minutes on every session start, and the agent sees the failed step.
remember_fingerprints() {
    remember_state composer "$(fingerprint composer.lock composer.json)"
    remember_state frontend "$(frontend_fingerprint)"
    step_succeeded install-js-dependencies && remember_state npm "$(fingerprint package-lock.json)"
    step_succeeded prepare-application && remember_state migrations "$(migrations_fingerprint)"
    return 0
}

# The custom stack: the project's functions, from stacks/custom.sh or its .claude/cloud.sh.
install_project_dependencies() {
    cd "$ROOT_DIR" || return 1
    install_dependencies
}

prepare_custom_application() {
    cd "$ROOT_DIR" || return 1
    install_application
}

remember_custom_fingerprints() {
    # shellcheck disable=SC2086
    step_succeeded install-dependencies && remember_state dependencies "$(fingerprint $DEPENDENCY_FILES)"
    step_succeeded prepare-application && remember_state migrations "$(migrations_fingerprint)"
    return 0
}

# Stops cleanly so the snapshot holds a consistent data directory.
stop_services() {
    stop_database
    service redis-server stop
    stop_web
    return 0
}

if [ -n "$ROOT_DIR" ]; then
    step detect-project detect_project
    load_project_values
fi

# The guard comes first: a VM with no project must still have it.
step link-commands link_commands
step configure-claude configure_claude

if [ -z "$ROOT_DIR" ]; then
    # The snapshot stays bare until the environment's setup script changes, and session-start.sh
    # tells the agent.
    echo "cloud-env: no repository under /home/user, so no project was installed." | tee "$LOG_DIR/no-project.log"
    exit 0
fi

printf '%s\n' "$ROOT_DIR" >"$ROOT_DIR_FILE"

cd "$ROOT_DIR" || exit 0

# Agents keep their scratch work here, and a project's .gitignore may not know it.
grep -qx '.scratch/' .git/info/exclude 2>/dev/null || echo '.scratch/' >>.git/info/exclude

step install-browser-tools install_browser_tools &
step install-skills install_skills &
step install-mailpit install_mailpit &
step install-system-packages install_system_packages
if ! step_succeeded install-system-packages; then
    # See the top of this file. The session page shows the setup output, so the log goes there: its start
    # names the source that did not answer, its end the package apt stopped at.
    wait
    log "install-system-packages failed: no snapshot is kept, and the next session runs the setup again"
    { head -n 12; echo "..."; tail -n 8; } <"$LOG_DIR/install-system-packages.log"
    exit 1
fi
write_installed_versions
if [ "$STACK" = "laravel" ]; then
    step configure-php configure_php
    step configure-nginx configure_nginx
fi
[ "$DATABASE_ENGINE" = "none" ] || step configure-database configure_database
step start-redis start_redis
wait

if [ "$STACK" = "custom" ]; then
    step install-dependencies install_project_dependencies
    step build-assets build_assets &
    step prepare-application prepare_custom_application && step seed-demo-data seed_demo_data
    wait

    step remember-fingerprints remember_custom_fingerprints
    step stop-services stop_services

    date -u +%FT%TZ >"$STATE_DIR/setup-finished-at"
    git -C "$ROOT_DIR" status --short >"$LOG_DIR/git-status-after-setup.log" 2>&1
    exit 0
fi

# .env must exist before composer: its post-install script boots the framework.
[ -f .env ] || step write-env-file write_env_file
step install-php-dependencies install_php_dependencies &
step install-js-dependencies install_js_dependencies &
wait

step build-assets build_assets &
step prepare-application prepare_application && step seed-demo-data seed_demo_data
wait

step remember-fingerprints remember_fingerprints
step stop-services stop_services

date -u +%FT%TZ >"$STATE_DIR/setup-finished-at"
git -C "$ROOT_DIR" status --short >"$LOG_DIR/git-status-after-setup.log" 2>&1

exit 0
