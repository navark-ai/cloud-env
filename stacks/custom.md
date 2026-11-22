## Stack
- Repository: `__ROOT_DIR__`. This is not a Laravel project: the VM installed what `.claude/cloud.sh` and the project's lock files ask for (mise, npm, pnpm, yarn, uv, poetry, pip, bundler, Go modules). The image also has Python, Node 20 to 22, Ruby, Go, Rust and Java.
- Site: `__SITE_URL__`, served by the project's own worker when `.claude/cloud.sh` declares one. No nginx or PHP site is configured.
- Also running: __DATABASE__, Redis, Mailpit (`http://localhost:8025`, SMTP on 127.0.0.1:1025) and the workers of this project.
- After any `git checkout`, `pull` or `rebase`: run `cloud-sync`. It installs dependencies again when a lock file changed, runs the project's migrations when `.claude/cloud.sh` defines them, and restarts the workers.
- Does not work here: an integration with no key, a host outside the allowlist, real client data. A failure caused by a missing key is not a finding: report it as not verified, with the reason. `This project` below can add to this list.

## Checks
- Run the checks this project defines: the rules in `CLAUDE.md` when it exists, and the scripts of its manifest (`package.json`, `pyproject.toml`, `Makefile`, `Rakefile`, ...). Report a script that does not exist as not run.
- Run the relevant tests by default. Run the full suite only when a person, a skill or the ticket flow you follow asks for it, and in the background.
