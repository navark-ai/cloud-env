#!/usr/bin/env bash
# Functions of the laravel stack: a repository with `artisan`. lib.sh sources this after the detected
# values, so the project's .claude/cloud.sh can replace any of them.

# Videos and captions are for a French reader. The tests use their own database.
use_french_interface() {
    database_query "UPDATE users SET locale = 'fr'" >/dev/null 2>&1 || true
}

# Fills the application database. Runs with the services up and .env in place.
install_application() {
    if [ "$HAS_INSTALL_COMMAND" = "true" ]; then
        php artisan install --seed --no-interaction || return 1
    else
        php artisan migrate --seed --force --no-interaction || return 1
    fi

    php artisan storage:link --no-interaction || true
    use_french_interface
}

# Records for screens to show. The app must be usable without them.
install_demo_data() {
    [ "$HAS_DEMO_SEEDER" = "true" ] || return 0

    timeout 180 php artisan db:seed --class=DemoSeeder --force --no-interaction || return 1
    use_french_interface
}

# Long-running workers, one per line: <name>|<command>|<port>. The command must show in `ps` as written,
# and must not be a part of another worker's command. Give the port of a worker that listens on
# 127.0.0.1: the check waits about 10 s for it. A worker with no port is checked once, 2 s after it starts.
background_workers() {
    [ "$USES_HORIZON" = "true" ] && echo "horizon|php artisan horizon"
    [ "$USES_REVERB" = "true" ] && echo "reverb|php artisan reverb:start --host=127.0.0.1 --port=8080|8080"
    return 0
}

# php-fpm runs as root: the agent and the site write the same storage/ files, and the VM is single-use.
start_web() {
    mkdir -p /run/php
    pgrep -x "php-fpm$PHP_VERSION" >/dev/null || "php-fpm$PHP_VERSION" --allow-to-run-as-root --daemonize
    pgrep -x nginx >/dev/null || nginx
}

stop_web() {
    pkill -x nginx 2>/dev/null
    pkill -x "php-fpm$PHP_VERSION" 2>/dev/null
    return 0
}

# A PWA plugin can refuse the larger files of an unminified build, and only stops the build at the end.
build_frontend() {
    npm run build -- --minify false || npm run build
}
