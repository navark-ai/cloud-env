#!/usr/bin/env bash
# SessionStart hook of the cloud VM, on a new session and on a resume. A snapshot keeps files,
# not processes, so this starts the services, then brings the code in line with the checkout.
# Its stdout reaches the agent as session context.

[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"
if [ -z "$ROOT_DIR" ]; then
    echo "WARNING: no repository was found under /home/user, so nothing was installed in this VM: no database, no site, no workers. The guard is on. Report this before you rely on the stack."
    exit 0
fi

cd "$ROOT_DIR" || exit 0

started=$(date +%s)

if [ ! -f "$STATE_DIR/setup-finished-at" ]; then
    echo "WARNING: the setup script did not finish in this VM, so tools may be missing. Read $LOG_DIR/. Fix or report this before you rely on the stack."
fi

problems=""
version_notes=""

# The snapshot keeps the packages of its setup, and a push can ask for others (README, "Versions after a
# push"). PHP holds no data, so this session installs the one asked; the database only gets a warning.
if [ -f "$INSTALLED_FILE" ]; then
    read -r wanted_stack wanted_php wanted_engine wanted_mysql wanted_postgres <<<"$(wanted_versions)"
    if [ "$STACK" = "laravel" ] && [ "$wanted_stack" = "laravel" ] && [ -n "$wanted_php" ] && [ "$wanted_php" != "$PHP_VERSION" ]; then
        source "$CLOUD_DIR/packages.sh"
        snapshot_php="$PHP_VERSION"
        if switch_php_version "$wanted_php" >"$LOG_DIR/session-php.log" 2>&1; then
            version_notes="$version_notes
- WARNING: the checkout asks for PHP $wanted_php, and this snapshot has PHP $snapshot_php. This session installed PHP $wanted_php, which costs about a minute at each new VM until a new snapshot has it: change the number in the environment's setup script (README, \"Change it\")."
        else
            PHP_VERSION="$snapshot_php"
            update-alternatives --set php "/usr/bin/php$PHP_VERSION" >/dev/null 2>&1
            configure_nginx >/dev/null 2>&1
            version_notes="$version_notes
- WARNING: the checkout asks for PHP $wanted_php, and this snapshot has PHP $snapshot_php. Installing PHP $wanted_php failed (see $LOG_DIR/session-php.log), so this session runs PHP $snapshot_php. A new snapshot installs it: change the number in the environment's setup script (README, \"Change it\")."
            problems="$problems php-$wanted_php"
        fi
    fi
    while IFS= read -r line; do
        [ -n "$line" ] && version_notes="$version_notes
- $line"
    done <<<"$(version_warnings "$wanted_stack" "$wanted_php" "$wanted_engine" "$wanted_mysql" "$wanted_postgres")"
fi

# The tools of the flow read these values (README, "The flow").
write_flow_values || problems="$problems values($VALUES_FILE)"
start_database || problems="$problems $DATABASE_ENGINE"
start_redis || problems="$problems redis"
start_web || problems="$problems web"
repair_mailpit
start_mailpit

sync_output="$("$CLOUD_DIR/bin/cloud-sync" --no-restart 2>&1)"
start_workers
for worker in $(workers_not_up); do
    problems="$problems $worker"
done

if [ -n "$SITE_CHECK_PATH" ]; then
    site_status="$(curl -s -L -o /dev/null -m 20 -w '%{http_code}' "$SITE_URL$SITE_CHECK_PATH")"
    [ "$site_status" = "200" ] || problems="$problems site(http-$site_status)"
fi

# Mailpit is optional and repaired above: its own line below says whether it is there.
failed_steps="$(awk '$2 != 0 && $1 != "install-mailpit" {print $1}' "$STATE_DIR/steps" 2>/dev/null | tr '\n' ' ')"

sed \
    -e "/^__STACK_CONTEXT__\$/{r $CLOUD_DIR/stacks/$STACK.md" -e "d;}" \
    "$CLOUD_DIR/session-context.md" | sed \
    -e "s#__ROOT_DIR__#$ROOT_DIR#g" \
    -e "s#__SITE_URL__#$SITE_URL#g" \
    -e "s#__PHP_VERSION__#$PHP_VERSION#g" \
    -e "s#__DATABASE__#$(database_summary)#g"

echo
echo "## This project"
if [ -n "$SITE_LOGIN_EMAIL" ]; then
    echo "- Sign in at \`$SITE_LOGIN_PATH\` as \`$SITE_LOGIN_EMAIL\` / \`$SITE_LOGIN_PASSWORD\`. The landing path is \`$SITE_LANDING_PATH\`."
else
    if [ "$STACK" = "laravel" ]; then
        echo "- No seeded login was found. Read the install command and the seeders to find one. The landing path is \`$SITE_LANDING_PATH\`."
    else
        echo "- No login is set for the site: \`SITE_LOGIN_EMAIL\` and \`SITE_LOGIN_PASSWORD\` in \`.claude/cloud.sh\` give one. Read the seeds or fixtures to find one."
    fi
fi
worker_names="$(background_workers | cut -d'|' -f1 | paste -sd, - | sed 's/,/, /g')"
[ -n "$worker_names" ] && echo "- Workers: $worker_names."
has_worker 'reverb|websockets' || echo "- No WebSocket server runs here, so a failed WebSocket in the browser console is expected. It is not a finding."
project_context

echo
echo "## State of this VM"
echo "- Started in $(($(date +%s) - started)) s. Snapshot made at $(cat "$STATE_DIR/setup-finished-at" 2>/dev/null || echo unknown)."
echo "- Checkout: $(git rev-parse --short HEAD) on $(git branch --show-current 2>/dev/null | grep . || echo 'detached HEAD')."
[ -n "$sync_output" ] && echo "- Sync: $sync_output"
[ -n "$version_notes" ] && echo "${version_notes#?}"
command -v mailpit >/dev/null || echo "- Mailpit could not be downloaded (see $LOG_DIR/repair-mailpit.log), so the site writes its mail to storage/logs (MAIL_MAILER=log). The next session start tries again. Nothing else depends on it: go on."
[ -n "$problems" ] && echo "- PROBLEM, not up:$problems. Logs in $LOG_DIR/."
[ -n "$failed_steps" ] && echo "- PROBLEM, setup steps that failed: $failed_steps. Logs in $LOG_DIR/."
[ -z "$problems$failed_steps" ] && echo "- All services answer."
[ -n "$version_notes" ] && echo "- Versions: say the WARNING above in your report when a check depends on that version."

exit 0
