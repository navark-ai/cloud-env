#!/usr/bin/env bash
# Runs the real setup.sh and session-start.sh of this checkout in a stand-in of the cloud image, once
# per combination, and prints one line per combination. Needs Docker; on an arm Mac it emulates amd64.
#   tests/vm/run-matrix.sh                     # every combination of the README's table
#   tests/vm/run-matrix.sh 8.4/mysql-8.4 django   # some of them
# Logs: tests/vm/results/<combination>/ (git-ignored). About 3 to 5 minutes each, 3 at a time.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
checkout="$(cd "$here/../.." && pwd)"
image="cloud-env-vm-test"

cells=("$@")
if [ "${1:-}" = "--cell" ]; then
    cells=()
elif [ ${#cells[@]} -eq 0 ]; then
    for php in 8.2 8.3 8.4 8.5; do
        for database in mysql-8.0 mysql-8.4; do cells+=("$php/$database"); done
    done
    cells+=(8.4/pgsql-16 8.4/pgsql-17 8.4/pgsql-18 django node-mise version-change)
fi

[ "${1:-}" = "--cell" ] || docker build --platform linux/amd64 -q -t "$image" "$here" >/dev/null || exit 1

run_cell() {
    local cell="$1" php="" database="" fixture="laravel" name out
    case "$cell" in
        */*) php="${cell%%/*}" database="${cell#*/}" ;;
        version-change) fixture="$cell" php="8.3" database="mysql-8.0" ;;
        *) fixture="$cell" ;;
    esac
    name="$(printf '%s' "$fixture-$php-$database" | tr '/' '-' | sed 's/--*/-/g; s/-$//')"
    out="$here/results/$name"
    rm -rf "$out" && mkdir -p "$out"
    docker run --rm --platform linux/amd64 \
        -v "$checkout:/src/cloud-env:ro" -v "$out:/out" -v "$here/fixtures:/fixtures:ro" -v "$here/inside.sh:/inside.sh:ro" \
        -e CELL_PHP="$php" -e CELL_DATABASE="$database" -e CELL_FIXTURE="$fixture" \
        -e CLOUD_ENV_APT_UPDATE_LIMIT=600 -e CLOUD_ENV_APT_INSTALL_LIMIT=1800 \
        "$image" bash /inside.sh >"$out/run.log" 2>&1
    printf '%-28s %s (setup %s)\n' "$name" "$(tail -n 1 "$out/run.log")" "$(grep -m1 '^setup:' "$out/run.log" | cut -d' ' -f2-)"
}

if [ "${1:-}" = "--cell" ]; then
    run_cell "$2"
    exit 0
fi

printf '%s\n' "${cells[@]}" | xargs -P "${PARALLEL:-3}" -I{} "$0" --cell {}
