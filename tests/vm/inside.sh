#!/usr/bin/env bash
# Inside the stand-in VM: install cloud-env as the environment's setup script would, set up the
# project, run setup.sh then the SessionStart hook, and check what came up. run-matrix.sh calls it.
set -u
cp -a /src/cloud-env /opt/cloud-env
rm -rf /opt/cloud-env/.git /opt/cloud-env/tests/vm/results

engine="${CELL_DATABASE%%-*}"
version="${CELL_DATABASE#*-}"

case "$CELL_FIXTURE" in
    laravel | version-change)
        mkdir -p /home/user && cp -a /opt/fixtures/laravel /home/user/laravel-app
        root=/home/user/laravel-app
        mkdir -p "$root/.claude"
        {
            echo "PHP_VERSION=\"$CELL_PHP\""
            if [ "$engine" = mysql ]; then
                echo "DATABASE_ENGINE=\"mysql\""
                echo "MYSQL_VERSION=\"$version\""
            else
                echo "DATABASE_ENGINE=\"pgsql\""
                echo "POSTGRES_VERSION=\"$version\""
            fi
            echo 'SITE_CHECK_PATH="/"'
        } >"$root/.claude/cloud.sh"
        ;;
    *)
        mkdir -p /home/user && cp -a "/fixtures/$CELL_FIXTURE" "/home/user/$CELL_FIXTURE"
        root="/home/user/$CELL_FIXTURE"
        # The example of the README is what runs here.
        [ -f "$root/.claude/cloud.sh" ] || { mkdir -p "$root/.claude" && cp "/opt/cloud-env/templates/custom-$CELL_FIXTURE.sh" "$root/.claude/cloud.sh"; }
        ;;
esac

cd "$root" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init && cd /

started=$(date +%s)
bash /opt/cloud-env/setup.sh
echo "setup: $(($(date +%s) - started)) s"
echo "--- steps"; cat /var/lib/cloud-env/steps
echo "--- detected"; cat /var/lib/cloud-env/detected.sh 2>/dev/null

if [ "$CELL_FIXTURE" = version-change ]; then
    # A push after the snapshot: the project now asks for PHP 8.4 and MySQL 8.4.
    sed -i -e 's/^PHP_VERSION=.*/PHP_VERSION="8.4"/' -e 's/^MYSQL_VERSION=.*/MYSQL_VERSION="8.4"/' "$root/.claude/cloud.sh"
    git -C "$root" -c user.email=t@t -c user.name=t commit -qam "Move to PHP 8.4 and MySQL 8.4"
fi

echo "--- session start"
CLAUDE_CODE_REMOTE=true bash /opt/cloud-env/session-start.sh >/out/session-start.txt
sed -n '/## This project/,$p' /out/session-start.txt

echo "--- checks"
fail=0
check() { if eval "$2" >/tmp/check.out 2>&1; then echo "ok   $1"; else echo "FAIL $1: $(head -c 400 /tmp/check.out)"; fail=1; fi; }

failed_steps="$(awk '$2 != 0 {print $1}' /var/lib/cloud-env/steps | tr '\n' ' ')"
check "every setup step passed" "[ -z '$failed_steps' ] || { echo '$failed_steps'; false; }"

if [ "$CELL_FIXTURE" = version-change ]; then
    check "php 8.4 replaced the snapshot's 8.3" "php -r 'echo PHP_MAJOR_VERSION.\".\".PHP_MINOR_VERSION;' | grep -qx 8.4 && pgrep -x php-fpm8.4 && ! pgrep -x php-fpm8.3"
    check "the site answers 200 on php 8.4" "[ \"\$(curl -s -o /dev/null -w '%{http_code}' http://localhost/)\" = 200 ]"
    check "the session warns about php in english" "grep -q 'WARNING: the checkout asks for PHP 8.4, and this snapshot has PHP 8.3. This session installed PHP 8.4' /out/session-start.txt"
    check "the session warns about mysql" "grep -q 'WARNING: the checkout asks for MySQL 8.4, and this snapshot has MySQL 8.0, which this session uses' /out/session-start.txt"
    check "the context names the server that runs" "grep -q 'Also running: MySQL 8.0' /out/session-start.txt && mysql -uroot -h127.0.0.1 -N -e 'SELECT VERSION()' | grep -q '^8\.0\.'"
    check "the switch is kept for a resume" "grep -qx \"INSTALLED_PHP_VERSION='8.4'\" /var/lib/cloud-env/installed.sh"
    CLAUDE_CODE_REMOTE=true bash /opt/cloud-env/session-start.sh >/out/session-resume.txt
    check "a resume does not install php again, and still warns about mysql" "! grep -q 'PHP 8.4, and this snapshot' /out/session-resume.txt && grep -q 'asks for MySQL 8.4' /out/session-resume.txt && grep -q 'All services answer' /out/session-resume.txt"
fi

if [ "$CELL_FIXTURE" = laravel ]; then
    check "php is $CELL_PHP" "php -r 'echo PHP_MAJOR_VERSION.\".\".PHP_MINOR_VERSION;' | grep -qx '$CELL_PHP'"
    check "php-fpm $CELL_PHP runs" "pgrep -x php-fpm$CELL_PHP"
    check "cloud-sync runs clean" "cloud-sync | grep -qx 'cloud-sync: ok'"
    check "extensions load" "php -r 'foreach ([\"redis\",\"imagick\",\"intl\",\"bcmath\",\"gd\",\"zip\",\"soap\",\"mbstring\",\"gmp\",\"pdo_sqlite\",\"Zend OPcache\"] as \$e) if (!extension_loaded(\$e)) { echo \"missing \$e\"; exit(1); }'"
    check "no php startup warning" "! php -v 2>&1 | grep -iE 'warning|unable to load'"
    if [ "$engine" = mysql ]; then
        check "mysql is $version" "mysql -uroot -h127.0.0.1 -N -e 'SELECT VERSION()' | grep -q '^$version\.'"
        check "pdo_mysql loads" "php -r 'exit(extension_loaded(\"pdo_mysql\") ? 0 : 1);'"
    else
        check "postgres is $version" "psql -h 127.0.0.1 -U postgres -tAc 'SHOW server_version' | grep -q '^$version\.'"
        check "pdo_pgsql loads" "php -r 'exit(extension_loaded(\"pdo_pgsql\") ? 0 : 1);'"
    fi
    check "migrations ran on the app database" "cd $root && php artisan migrate:status --no-interaction | grep -q create_users_table"
    check "migrations ran on the test database" "cd $root && DB_DATABASE=test APP_ENV=testing php artisan migrate:status --no-interaction | grep -q create_users_table"
    check "the cache goes through redis" "cd $root && php artisan tinker --execute='Cache::put(\"cloud\", \"ok\", 60); echo Cache::get(\"cloud\");' | grep -qx ok && redis-cli --scan | grep -q cloud"
    check "site answers 200" "[ \"\$(curl -s -o /dev/null -w '%{http_code}' http://localhost/)\" = 200 ]"
    check "a session survives a request (redis sessions)" "curl -s -c /tmp/jar http://localhost/ >/dev/null && grep -q -- '-session' /tmp/jar && redis-cli --scan | grep -q ."
    check "assets built" "[ -f $root/public/build/manifest.json ]"
fi

if [ "$CELL_FIXTURE" = django ]; then
    check "postgres 16 answers" "psql -h 127.0.0.1 -U postgres -tAc 'SHOW server_version' | grep -q '^16\\.'"
    check "the venv has django" "$root/.venv/bin/python -c 'import django'"
    check "migrations ran on both databases" "psql -h 127.0.0.1 -U postgres -d django -tAc 'SELECT count(*) FROM django_migrations' | grep -qv '^0$' && psql -h 127.0.0.1 -U postgres -d test -tAc 'SELECT count(*) FROM django_migrations' | grep -qv '^0$'"
    check "the worker serves the admin login" "[ \"\$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8000/admin/login/)\" = 200 ]"
    check "the seeded admin signs in" "cd $root && .venv/bin/python manage.py shell -c 'from django.contrib.auth import authenticate; import sys; sys.exit(0 if authenticate(username=\"admin\", password=\"cloud-admin\") else 1)'"
    check "the values file names the site" "grep -qx \"SITE_URL='http://localhost:8000'\" /var/lib/cloud-env/values.sh"
    check "no php or nginx was installed" "! command -v nginx && ! dpkg -l | grep -q 'php8.3-fpm'"
    check "cloud-sync migrates after a new migration" "mkdir -p $root/shop/migrations && touch $root/shop/migrations/__init__.py && cloud-sync | grep -q 'migrations: done'"
fi

if [ "$CELL_FIXTURE" = node-mise ]; then
    check "mise installed node 20 for the agent's shells, in the repository" "cd $root && bash -ic 'node --version' 2>/dev/null | grep -qx v20.19.5"
    # Not checked: the session's worker check. Under Docker's amd64 emulation on an arm Mac, node shows
    # other arguments in `ps` until it boots, which takes longer than the check waits (fixtures/node-mise).
    check "the worker runs on that node" "[ \"\$(curl -s http://localhost:3000/)\" = v20.19.5 ]"
fi

cp -a /var/log/cloud-env /out/logs 2>/dev/null
[ "$fail" = 0 ] && echo "RESULT pass" || echo "RESULT FAIL"
