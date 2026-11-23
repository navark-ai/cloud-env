## Stack
- Repository: `__ROOT_DIR__`. Plain `php`, `composer` and `npm` work; `herd php` and `herd composer` also work through a shim.
- Site: `__SITE_URL__` (nginx, php-fpm, PHP __PHP_VERSION__).
- Also running: __DATABASE__, Redis, Mailpit (`http://localhost:8025`) and the workers of this project.
- After any `git checkout`, `pull` or `rebase`: run `cloud-sync`. It installs dependencies, migrates both databases and rebuilds assets, only for what changed, and restarts the workers. A page left open during that restart logs a refused WebSocket: reload it. That does not mean a worker is down, and `cloud-sync` says `FAILED` when one is.
- Assets are built, no Vite server runs. After a Vue change, run `cloud-sync`.
- Does not work here: an integration with no key in `.env`, a host outside the allowlist, real client data. A failure caused by a missing key is not a finding: report it as not verified, with the reason. `This project` below can add to this list.

## Checks
- Run the checks this project defines: the rules in `CLAUDE.md` when it exists, the scripts in `composer.json` and `package.json`, `php artisan test --compact --filter=...` and `vendor/bin/pint --dirty`. Report a script that does not exist as not run.
- Run the relevant tests by default. Run the full suite only when a person, a skill or the ticket flow you follow asks for it, and in the background: `php artisan test --parallel --recreate-databases --compact`.
