#!/usr/bin/env bash
# apt sources, packages and the PHP site, for setup.sh and for session-start.sh, which installs another PHP
# when the checkout asks for one the snapshot does not have. Sourced after lib.sh.

IMAGE_PHP_VERSION="8.3"
IMAGE_MYSQL_VERSION="8.0"
IMAGE_POSTGRES_VERSION="16"
ONDREJ_PHP_KEY_URL="https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xB8DC7E53946656EFBCE4C1DD71DAEAAB4AD4CAB6"
MYSQL_KEY_URL="https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xBCA43417C3B485DD128EC6D4B7B3B788A8D3785C"
PGDG_KEY_URL="https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xB97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8"

php_at_least() {
    [ "$(printf '%s\n%s\n' "$1" "$PHP_VERSION" | sort -V | head -n 1)" = "$1" ]
}

php_packages() {
    [ "$STACK" = "laravel" ] || return 0
    local extension extensions="$PHP_EXTENSIONS"

    [ "$DATABASE_ENGINE" = "pgsql" ] && extensions="$extensions pgsql"
    for extension in $extensions; do
        # OPcache is part of PHP itself from 8.5, with no package of its own.
        [ "$extension" = "opcache" ] && php_at_least 8.5 && continue
        printf 'php%s-%s ' "$PHP_VERSION" "$extension"
    done
    echo nginx
}

add_apt_source() {
    local name="$1" key_url="$2" source="$3"

    curl -fsSL "$key_url" | gpg --dearmor --yes -o "/usr/share/keyrings/$name.gpg" || return 1
    echo "deb [signed-by=/usr/share/keyrings/$name.gpg] $source" >"/etc/apt/sources.list.d/$name.list"
}

add_version_sources() {
    if [ "$STACK" = "laravel" ] && [ "$PHP_VERSION" != "$IMAGE_PHP_VERSION" ]; then
        add_apt_source ondrej-php "$ONDREJ_PHP_KEY_URL" "https://ppa.launchpadcontent.net/ondrej/php/ubuntu noble main" || return 1
    fi
    if [ "$DATABASE_ENGINE" = "mysql" ] && [ "$MYSQL_VERSION" != "$IMAGE_MYSQL_VERSION" ]; then
        add_apt_source mysql "$MYSQL_KEY_URL" "http://repo.mysql.com/apt/ubuntu noble mysql-$MYSQL_VERSION-lts" || return 1
    fi
    if [ "$DATABASE_ENGINE" = "pgsql" ] && [ "$POSTGRES_VERSION" != "$IMAGE_POSTGRES_VERSION" ]; then
        add_apt_source pgdg "$PGDG_KEY_URL" "https://apt.postgresql.org/pub/repos/apt noble-pgdg main" || return 1
    fi
}

database_packages() {
    case "$DATABASE_ENGINE" in
        mysql)
            if [ "$MYSQL_VERSION" = "$IMAGE_MYSQL_VERSION" ]; then
                echo "mysql-server-$MYSQL_VERSION"
            else
                echo "mysql-community-server"
            fi
            ;;
        pgsql)
            echo "postgresql-$POSTGRES_VERSION postgresql-client-$POSTGRES_VERSION"
            ;;
    esac
}

configure_php() {
    local directory

    for directory in "/etc/php/$PHP_VERSION/cli/conf.d" "/etc/php/$PHP_VERSION/fpm/conf.d"; do
        cp "$CLOUD_DIR/config/php.ini" "$directory/99-cloud.ini"
    done

    sed -i -E \
        -e 's/^user = .*/user = root/' \
        -e 's/^group = .*/group = root/' \
        -e 's/^listen\.owner = .*/listen.owner = root/' \
        -e 's/^listen\.group = .*/listen.group = root/' \
        -e 's/^pm\.max_children = .*/pm.max_children = 16/' \
        "/etc/php/$PHP_VERSION/fpm/pool.d/www.conf"
    mkdir -p /run/php
}

configure_nginx() {
    sed -e "s#__ROOT_DIR__#$ROOT_DIR#" -e "s#__PHP_VERSION__#$PHP_VERSION#" "$CLOUD_DIR/config/nginx-site.conf" >/etc/nginx/sites-available/cloud
    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/cloud /etc/nginx/sites-enabled/cloud
    sed -i 's/^user www-data;/user root;/' /etc/nginx/nginx.conf
    nginx -t
}

# Installs the PHP a checkout asks for when the snapshot has another one, for this VM only: about a
# minute at each new VM, until a new snapshot has it. The database is never touched. Prints nothing; the
# caller reports. Usage: switch_php_version <version>
switch_php_version() {
    local wanted="$1" previous="$PHP_VERSION"

    [[ "$wanted" =~ ^8\.[0-9]{1,2}$ ]] || return 1
    PHP_VERSION="$wanted"
    if [ ! -x "/usr/sbin/php-fpm$wanted" ]; then
        add_version_sources || return 1
        apt-get update -qq || return 1
        # shellcheck disable=SC2046
        apt-get install -y -qq --no-install-recommends $(php_packages) || return 1
    fi
    update-alternatives --set php "/usr/bin/php$wanted" || return 1
    ln -sf /usr/bin/php "/usr/local/bin/php${wanted//./}"
    configure_php || return 1
    configure_nginx || return 1

    pkill -x "php-fpm$previous" 2>/dev/null
    pkill -x nginx 2>/dev/null
    write_installed_versions
}
