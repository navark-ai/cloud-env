# Navark cloud environment

A Claude Code cloud session on this environment has what a MacBook has: PHP, MySQL or PostgreSQL, Redis, Mailpit, nginx, built assets, the project's workers, Laravel Boost, headless Chromium with video. Navark's cloud agents run their tickets there.

A standard Laravel project needs no file: the VM reads what it needs from the project's own files, and everything else is here. A multi-tenant project needs a file: see below. A project on another stack (Python, Node, Ruby, Go, ...) gets the same guard, hooks, browser, Redis, Mailpit and database, and says in one file how to install and run it: see "Stacks". Claude Code has no built-in way to share this: [cloud sessions do not install plugins, the base image cannot be replaced, and the environment's variables do not exist yet when the setup script runs](https://code.claude.com/docs/en/cloud-environments). So the setup script clones this public repository at a fixed version.

This repository is public so the setup script can reach it. Keep it free of secrets and of client data.

## What is here, and what is in Navark

This repository prepares the VM: the stack, the services, the guard, and the small contract that the ticket flow counts on (see "The flow"). Everything about the tickets themselves is in Navark:

- **Setting up a project's worker**, its routine prompt and its token: the agent setup of the project in Navark (**Set up agent**).
- **Starting a run** (the label `agent:ready`, Navark's check every minute), **what a run does** (the pull request, the report, the videos, the hand-off to the lead) and **the labels that change it** (`agent:auto-merge`, `agent:model:fable`, `agent:effort:<level>`, `agent:ultracode`, `agent:adaptive`): the flow that Navark serves, readable in Settings › Flow.

Only a change of the VM needs a release here.

## How it works

| Part | When it runs |
|---|---|
| `environment-setup.sh` | Pasted in the environment dialog. Runs before Claude Code starts, when no snapshot exists. Clones this repository at a version, then calls `setup.sh` |
| `detect.py`, `find-seeded-password.php` | Same, once per snapshot. Read the project's stack and values from its own files |
| `setup.sh`, `packages.sh`, `defaults.sh`, `stacks/`, `env.defaults`, `env.reverb` | Same. Install packages, dependencies, databases, demo data, assets and skills, for the project's stack (`stacks/<stack>.sh`). The platform then snapshots the disk. About 3.5 minutes on a large project |
| `stacks.json` | Read by Navark's setup wizard: the stacks, versions and databases of this version, and the references for the stacks it does not cover |
| `session-start.sh`, `session-context.md` | A hook in the VM's `~/.claude/settings.json`, at every session start and resume. Writes the values file of the flow, compares the versions the checkout asks for with the snapshot's ("Versions after a push"), starts the services, runs `cloud-sync`, gives the agent its context, which says how to get the ticket flow |
| `bin/cloud-sync` | After every checkout. Updates only what changed: Composer, npm, migrations, assets. Then restarts the workers, checks that they are up, and says `FAILED` for a step or a worker that did not work |
| `hooks/flow-hook.py` | At seven hook events of Claude Code (`SessionStart`, `Stop`, `SubagentStart`, `SubagentStop`, `PreCompact`, `PostCompact`, `SessionEnd`). Runs the common part of the flow's hook for that event, if there is one, and never changes the session. See "The flow" |
| `hooks/guard-bash.py`, `git-hooks/pre-push` | Before every command and every push. Refuse a merge, a push to a release branch, a branch deletion, and every tool of the remote session server except the pull request subscription. Let through one merge: a pull request from a `feat/` or `fix/` branch into `dev` whose checks all passed, for the auto-merge |
| The ticket flow, not in this repository | Navark serves it at each run (`get_flow`). See "The flow" |
| `config/` | PHP, MySQL, PostgreSQL, nginx and Claude Code settings. These exist only in the VM, so nothing changes on a Mac |
| `tests/vm/` | Not in the VM. Runs `setup.sh` and `session-start.sh` in a stand-in of the image with Docker, once per combination of "Stacks" |

### What the VM reads from a project

| Value | Rule | Otherwise |
|---|---|---|
| `STACK` | `laravel` when the repository has `artisan`, `custom` for any other repository (see "Stacks") | `laravel` |
| `DATABASE_ENGINE` | `DB_CONNECTION` of `.env.example` (`pgsql`, or `mysql` for `mysql` and `mariadb`), then the first `mysql:` or `postgres:` image in `.github/workflows` | `mysql`; `none` for a custom project |
| `PHP_VERSION` | The newest `8.x` in `require.php` of `composer.json`, or a higher floor that a package in `composer.lock` needs | 8.3 |
| `MYSQL_VERSION` | The first `mysql:x.y` in `.github/workflows`, files in name order, when it is 8.0 or 8.4 | 8.0 |
| `POSTGRES_VERSION` | The first `postgres:NN` (or `postgis/postgis:NN`) in `.github/workflows`, when it is 16, 17 or 18 | 16 |
| `APP_DATABASE` | The repository's name, with `_` for what is not a letter or a digit | `app` |
| `APP_TITLE`, for `APP_NAME` | The repository's name, in words, then `Cloud` | `Cloud VM` |
| `install_application` | `artisan install --seed` when the install command has the signature `install {--seed}` | `artisan migrate --seed` |
| `install_demo_data` | `db:seed --class=DemoSeeder` when `database/seeders/DemoSeeder.php` exists | Nothing |
| `background_workers` | Horizon and Reverb when `require` of `composer.json` has them | None |
| `QUEUE_CONNECTION` | `redis` when a worker reads the queue | `sync`: nothing would read a Redis queue |
| Broadcast `.env` lines | `env.reverb` when `require` has `laravel/reverb` | `BROADCAST_CONNECTION=log`, and placeholder Pusher values |
| `SITE_LANDING_PATH` | `/admin` when `routes/admin.php` exists, or for a Filament panel | `/` |
| `SITE_CHECK_PATH`, `SITE_LOGIN_PATH` | `/admin/login` when `require` has `filament/filament` and `routes/admin.php` does not exist | `/login` |
| `SITE_LOGIN_EMAIL` | The first user, after the install | No login |
| `SITE_LOGIN_PASSWORD` | The string in the install command, the seeders or `UserFactory` that matches this user's hash. It stays in the project, not in this public repository | No login, and the agent is told so |

The values are kept in `/var/lib/cloud-env/detected.sh`, so a later checkout does not change them, and what `setup.sh` installed (stack, PHP, database server) in `/var/lib/cloud-env/installed.sh`. The session context shows the login, the landing path and the workers. `PROBLEM` there names a step or a service that failed.

An optional `.claude/cloud.sh` in the project replaces any value of `defaults.sh` or function of its stack (`stacks/laravel.sh`), and adds notes for the agent: see `templates/cloud.sh`. It is not needed on every branch, because a copy stays in the VM.

A multi-tenant project needs this file. A typical one has a seeder that cannot run outside a tenant, central routes bound to one host, and an install command that takes a name, an email and a password. So its file sets `project_env`, `install_application`, the login and the landing path.

The snapshot lasts about 7 days and is per repository and per branch, so one environment serves every project: a live test ran Statim in the environment Portal used, Statim got its own setup, and Portal kept its snapshot after it. The snapshot follows new commits on its branch: the agent gets the new code, and `cloud-sync` catches up. So start sessions from `dev` and let the agent switch branch.

Three things in this design come from how the VM works:

- **Composer.** In a session, `api.github.com` and `codeload.github.com` answer 403 for a repository that is not attached, and `composer install` falls back to git for each package, about 13 minutes. The setup script is not behind that proxy, so `bin/composer-install --setup` uses `codeload` and takes about 20 seconds. A later lock change in a session uses git, for the changed packages only.
- **GitHub.** The proxy refuses GraphQL, so `gh pr` and `gh issue` fail. Agents use the `mcp__github__*` tools and `gh api repos/...`.
- **Skills.** Cloud sessions install no plugin. The ticket flow is not a skill and does not live here: Navark serves it (see "The flow"), so it changes with a Navark deploy, not with `CLOUD_ENV_VERSION`. `setup.sh` clones the public skill repositories (`SKILL_REPOSITORIES`) and links them in `~/.claude/skills`, for the project conventions they hold. A project adds its own with `SKILL_REPOSITORIES` in `.claude/cloud.sh`. The project's own skills win on a name collision. Private repositories are not reachable there.

## Stacks

One environment serves every stack: the VM reads the stack of each repository (`STACK`, "What the VM reads from a project"), and the snapshot is per repository and per branch. `stacks.json` says the same as this section for a program, such as Navark's setup wizard.

| Stack | Detected by | Project file | What the VM sets up |
|---|---|---|---|
| `laravel` | `artisan` at the root | Optional, `templates/cloud.sh` | PHP 8.2 to 8.5 with php-fpm and nginx, Composer and npm dependencies, built assets, MySQL or PostgreSQL with migrations and seeds, Horizon and Reverb when the project has them |
| `custom` | Any other repository | `.claude/cloud.sh`, from `templates/custom.sh` | The database, the dependencies of each lock file, the tools of a `mise.toml`, then what the project's file says: install, migrations, workers, site |

Both get the guard, the hooks of the flow, Chromium with Playwright, Redis, Mailpit, the skills and the values file of the flow.

### Laravel: PHP and database

| PHP | MySQL 8.0 | MySQL 8.4 | PostgreSQL 16 | PostgreSQL 17 | PostgreSQL 18 |
|---|---|---|---|---|---|
| 8.2 | Passes | Passes | Not run | Not run | Not run |
| 8.3, the image's | Passes | Passes | Not run | Not run | Not run |
| 8.4 | Passes | Passes | Passes | Passes | Passes |
| 8.5 | Passes | Passes | Not run | Not run | Not run |

`tests/vm` ran each combination marked here on 2026-11-22, in a stand-in of the image (Ubuntu 24.04 amd64 with PHP 8.3, MySQL 8.0, PostgreSQL 16 and Redis, under Docker) with a Laravel 12 project. A combination passes when every setup step exits 0, `php` and php-fpm are the version asked, the extensions load, the server is the version asked, the migrations ran on both databases, the cache and the sessions go through Redis, the site answers 200, the assets are built and `cloud-sync` says `ok`. In the real image, only the projects of the earlier live tests have run (PHP 8.3 and MySQL 8.0 by default): try another combination in a second environment first ("Change it"). Under emulation the setup took 2 to 14 minutes, which says nothing about the real VM, but each version from another source adds about a minute there: a large project on PHP 8.5 and MySQL 8.4 can pass the five minutes after which the platform keeps no snapshot. `setup-started-at` and the times in `steps` show it.

- **PHP.** 8.3 is the image's. 8.2, 8.4 and 8.5 come from the Ondřej Surý source, about a minute more. PHP 8.5 has OPcache built in, with no `php8.5-opcache` package: `setup.sh` leaves it out from 8.5.
- **MySQL.** 8.0 is the image's. 8.4 comes from the MySQL LTS source, and replaces the image's server.
- **PostgreSQL.** 16 is the image's. 17 and 18 come from the PostgreSQL source (PGDG), and `setup.sh` drops the image's cluster so the one asked listens on 5432. The site and the tests connect as `postgres` with no password, like `root` on MySQL, and `setup.sh` adds `pgsql` to the PHP extensions. A Laravel project on PostgreSQL says so in `.env.example` (`DB_CONNECTION=pgsql`) or with a `postgres:NN` image in its CI; otherwise `DATABASE_ENGINE="pgsql"` in `.claude/cloud.sh`.

### Versions after a push

A push does not make a new snapshot: the platform makes one only when the environment's setup script or its allowed hosts change, or after about 7 days. So a session on a new commit has the new code (`cloud-sync` catches up Composer, npm, migrations and assets) and the packages of the last snapshot. A session always runs on what the snapshot installed (`installed.sh`), whatever the checkout asks for. At every session start, `session-start.sh` reads again what the checkout asks for (a new detection, then `.claude/cloud.sh`) and compares:

| The checkout asks for another | This session | The agent reads |
|---|---|---|
| PHP | Installs it and serves the site with it, about a minute at each new VM, until a new snapshot has it. If that fails, it stays on the snapshot's PHP | `WARNING: the checkout asks for PHP 8.4, and this snapshot has PHP 8.3. This session installed PHP 8.4, ...` |
| Database engine or version | Keeps the snapshot's server, and names it in the context: a server is never replaced in a session, its data would not follow | `WARNING: the checkout asks for MySQL 8.4, and this snapshot has MySQL 8.0, which this session uses. ...` |
| Stack | Keeps the snapshot's | `WARNING: the checkout is a custom project, and this snapshot was set up for the laravel stack. ...` |

Each warning ends with the way out: a new snapshot, by changing the number in the environment's setup script ("Change it"). That rebuilds the snapshot of every project, so do it once the change is merged into the branch the sessions start from. `tests/vm` runs this case (`version-change`): a snapshot on PHP 8.3 and MySQL 8.0, then a commit that asks for PHP 8.4 and MySQL 8.4. Every warning of this repository is in English, like the rest of the session context.

### Another stack

A repository with no `artisan` is a `custom` project. The VM does not guess how to run it: its `.claude/cloud.sh` says so, on the branch the sessions start from, since `setup.sh` reads it before the snapshot. Copy `templates/custom.sh`; `templates/custom-django.sh` is a complete example, the one `tests/vm` runs (Django on PostgreSQL 16, its admin as the site).

| In `.claude/cloud.sh` | What it is | Otherwise |
|---|---|---|
| `DATABASE_ENGINE`, `MYSQL_VERSION`, `POSTGRES_VERSION` | `mysql`, `pgsql` or `none`, and the version, as for Laravel. `APP_DATABASE` and `TEST_DATABASE` are created empty | Read from the CI's database image, else `none` |
| `EXTRA_SYSTEM_PACKAGES` | apt packages on top of the image | None |
| `install_dependencies` | Installs the dependencies | The package manager of each lock file: `npm`, `pnpm`, `yarn`, `uv`, `poetry`, `pip` with `requirements.txt` into `.venv`, `bundle`, `go mod download`. First, with a `mise.toml`, `.mise.toml` or `.tool-versions`, mise and its tools |
| `install_application`, `install_demo_data` | Fill the database once per snapshot, with the services up | Nothing |
| `migrate_databases`, `MIGRATION_PATHS` | Migrations on both databases; `cloud-sync` runs them again when a path of `MIGRATION_PATHS` changes | No migration |
| `background_workers` | The site and the workers, `<name>\|<command>\|<port>` per line, as for Laravel. The site is a worker: no nginx or PHP is installed | None |
| `SITE_URL`, `SITE_CHECK_PATH`, `SITE_LOGIN_*`, `SITE_LANDING_PATH` | The site for the session check, the videos and the agent | No site check and no login |
| `build_frontend` | Builds assets once per snapshot | Nothing |
| `sync_project` | Replaces what `cloud-sync` does: by default the dependencies again when a lock file changed, then `migrate_databases` | |
| `project_context` | Notes for the agent: how to run the tests, what does not work | |

The image already holds Python 3 with pip, uv and poetry, Node 20 to 22, Ruby 3.1 to 3.3 with bundler, Go, Rust and Java 21. mise covers any other version: it is installed from its signed apt repository (`extrepo`), never through a piped script, and its shims go first in the agent's `PATH`. `tests/vm` runs two custom projects: the Django example, and a Node site whose `.tool-versions` asks for Node 20 through mise. Ruby, Go and the package managers other than npm and pip have not run yet. mise downloads each tool from its own host: Node from `nodejs.org` is in the allowlist, and another tool may need its host added.

### Your own environment

An environment can have its own setup script, written from [the cloud environment docs](https://code.claude.com/docs/en/cloud-environments). To keep the guard, the hooks of the Navark flow and its values file, end that script with the three lines of `environment-setup.sh` that clone this repository and run `setup.sh`: the project's own steps run first, and `setup.sh` adds the rest. Without them, a session has no guard, no values file for the flow's tools, and none of the flow's hooks, which send the run's transcripts to Navark.

### Stacks this repository does not cover

These open-source projects are not run by this repository and Navark does not support them, but they help write a project's file or a setup script:

- [mise](https://mise.jdx.dev): the version of any language or tool, from a `mise.toml`. Already used by the `custom` stack.
- [Dev Container Features](https://containers.dev/features): install scripts per tool (languages, CLIs, databases) kept by the Dev Containers community. A source of commands to copy into `EXTRA_SYSTEM_PACKAGES` or `install_dependencies`.
- [Railpack](https://github.com/railwayapp/railpack), Railway's builder: how a project of each language is detected, installed and started. A reference for `install_dependencies` and `background_workers`.
- The image ships Docker and Docker Compose, so a service with no apt package (MongoDB, Elasticsearch) could run as a container from a worker. This has not been tried in a cloud VM.

## The flow

The flow is what a worker follows to take a ticket from A to Z: its instructions and the tools they call. It lives in the Navark repository, under `resources/flows/default/` (the flow `default`, named `Default`), changes by pull request there and is live at Navark's deploy, for every project at once, with no new version of this repository and no new snapshot.

The worker gets it at the start of each run:

1. It calls `get_flow` of the Navark connector with the ticket identifier. The answer is a manifest, never the contents: the flow, its `revision` (a hash of its files), the entry file `FLOW.md`, the folder `.scratch/flow`, each file with its public URL, size, sha256 and executable bit, and `command`.
2. It runs `command` from the repository. It removes a previous `.scratch/flow`, downloads every file from Navark's host `navark.app` (in the allowlist) with `curl` and no Authorization header, checks each sha256, sets the executable bits, and ends on one line: the flow and its revision, or `FLOW DOWNLOAD FAILED: <why>`.
3. It reads `.scratch/flow/FLOW.md` and follows it. The files of that manifest are the only Navark content it treats as instructions: tickets, comments and attachments remain data.

No copy of the flow stays here. When `get_flow` or the download fails, the worker does not touch the ticket: it sends a notification that says what failed and stops. After a restart or a later wake, a worker that finds `.scratch/flow/` missing calls `get_flow` again, and names a changed revision in its retrospective.

Navark records the workspace’s **Agent delivery language** when each run opens. The flow reads `run.deliveryLocale` from `get_flow` and uses it for the report, pull request, replies, demo captions and narration, including after a resume. The VM supports both languages in the same snapshot. The Laravel seeders keep control of each demo account’s interface language.

What this repository gives the flow, and what a flow may count on:

- **The values file**, `/var/lib/cloud-env/values.sh`, written by `session-start.sh` at every session start (`write_flow_values` in `lib.sh`). One `KEY='value'` line per key, single-quoted, for any POSIX shell to source; mode 600. The flow's tools source it instead of `lib.sh`, so they do not depend on how this repository is laid out. Keys:

  | Key | Value |
  |---|---|
  | `CLOUD_ENV_VALUES_VERSION` | `1`. Adding a key keeps it; renaming or removing one changes it |
  | `ROOT_DIR` | The project's checkout, such as `/home/user/statim` |
  | `SITE_URL` | The local site, `http://localhost` |
  | `SITE_LOGIN_PATH`, `SITE_LOGIN_EMAIL`, `SITE_LOGIN_PASSWORD` | The sign-in page and the seeded login ("What the VM reads from a project"); the email and password are empty when none was found |
  | `SITE_LANDING_PATH` | The first screen after the sign-in |
  | `NODE_PATH` | Where `require('playwright')` resolves: the global `node_modules` of the image, `/opt/node22/lib/node_modules` |

- **The permissions**, in `config/claude-settings.json`: run `.scratch/flow/bin/*` and `.scratch/flow/core/bin/*` (and the same with `./` in front) without an approval, the `Navark` connector, the `Workflow` tool (for `agent:ultracode`) and the pull request subscription of `Claude_Code_Remote`. Nothing else of the flow is allowed by name.
- **The binaries**: `gh`, `git`, `curl`, `sha256sum`, `python3`, `node` with Playwright and its Chromium, `ffmpeg` and `ffprobe`, `jq`, and the stack of the session context. The optional `kokoro-tts <fr|en> <output-directory>` reads a JSON array of captions on stdin and writes `0.wav`, `1.wav` and so on (mono 16-bit PCM at 24 kHz). Setup installs Kokoro-82M before the snapshot. French uses `ff_siwis` and English uses `af_heart`. Existing callers can still use `kokoro-fr <output-directory>` for French. Synthesis runs locally on the CPU with no credentials or network access. A setup failure is logged by the `install-kokoro` step and the flow can still make captioned videos.
- **The hooks.** Claude Code reads its hooks from the VM's settings when the session starts, so they are registered here, and their logic comes from Navark. Navark serves, with every flow, a common part that no flow can change, downloaded with it into the reserved folder `.scratch/flow/core/`. Its hook for an event is the executable file `.scratch/flow/core/hooks/<EventName>`. `config/claude-settings.json` calls `hooks/flow-hook.py <EventName>` for exactly seven events, without a matcher: `SessionStart` (after `session-start.sh`, which runs first, unchanged), `Stop`, `SubagentStart`, `SubagentStop`, `PreCompact`, `PostCompact` and `SessionEnd`. Never `PreToolUse` or `PostToolUse`: the guard is the only hook on tools. The dispatcher finds the project (`$CLAUDE_PROJECT_DIR`, else the root `setup.sh` saved), and when that file is a regular, executable file it runs it from the project root with the hook's JSON on stdin. It always exits 0 and prints nothing, whatever the script does: the script's output is discarded (a `SessionStart` hook's output would become the agent's context, a `Stop` hook that exits 2 would keep the agent going). The script gets 10 seconds, 1 second for `SessionEnd` (Claude Code gives all `SessionEnd` hooks 1.5 seconds), then its process group is killed: long work goes in the background, detached from its stdin, stdout and stderr. A failure or a timeout is one line in `/var/log/cloud-env/flow-hooks.log`. Any other name or file is ignored, so the files of a flow cannot register other hooks or events.
- **The guard stays here.** `hooks/guard-bash.py`, `git-hooks/pre-push` and `config/` are installed by `setup.sh` outside the checkout, and every command a flow's tool runs goes through the guard like any other. A flow cannot change or replace them; a flow that needs another permission or binary needs a release here. The guard lets through one merge, for the flow's `agent:auto-merge`: a pull request from a `feat/` or `fix/` branch into `dev` whose checks all passed.
- **The notes of `agent:adaptive`**: two optional lines of `.claude/cloud.sh` (`templates/cloud.sh`), read by the flow.

## Create the environment

Once for all projects, on claude.ai/code: environment selector, then **New environment**. A project then needs no file here: its worker is set up in Navark, and `.claude/cloud.sh` is optional for a Laravel project (see "What the VM reads from a project") and required for another stack (see "Stacks").

- **Name**: `Navark`. The name does not matter to the VM: an environment made before v3.1.0, named `Navark Laravel`, only needs the new setup script.
- **Network access**: `Limited` (`Custom` in older apps), keep "Allow package managers" on, and paste `allowed-domains.txt` in **Allowed domains**.
- **Setup script**: paste `environment-setup.sh`.
- No variable and no secret.

When the clone of this repository fails, the setup script exits 1 and the session does not start: that is safer than a snapshot with no guard. It does the same when the system packages cannot be installed (an apt source that is down, or slower than the limits of `apt_get` in `lib.sh`): nothing else can work without them, the platform keeps no snapshot of a script that failed, and the next session runs the setup again. Any other step that fails is reported to the agent as a `PROBLEM`, in a snapshot that is kept.

## Change it

To publish a VM version (for example, `v3.2.2`):

1. Pick an unused tag with `git ls-remote --tags origin`. Set `CLOUD_ENV_VERSION` in `environment-setup.sh` and `version` in `stacks.json` to that tag in the same pull request.
2. Run the repository checks below and merge the pull request into `main`. Copy its merge commit SHA from GitHub.
3. Tag that exact commit and push the tag. Replace `MERGE_SHA` with the SHA from step 2.

   ```sh
   git fetch origin main --tags
   git tag -a v3.2.2 MERGE_SHA -m "cloud-env v3.2.2"
   git push origin refs/tags/v3.2.2
   git ls-remote --tags origin 'refs/tags/v3.2.2^{}'
   ```

4. Check that the last command prints the merge SHA. On claude.ai/code, edit the Navark environment, paste the tagged `environment-setup.sh` in **Setup script**, and save. A new session builds a snapshot with that version.

- **The flow:** a pull request on Navark, in `resources/flows/default/`. It reaches every worker at Navark's next deploy: no version here, no new snapshot. A run that already downloaded the flow keeps its copy.
- **A new version:** change `CLOUD_ENV_VERSION` in the environment's setup script. That text change also forces a new snapshot, for every project. There is no API for it, so a person or a browser agent edits the dialog. One environment means a release reaches every project at once: to try one first, create a second environment with the new version and run one session of a project there.
- **A project value:** edit `.claude/cloud.sh`. Each session reads it at start. What only `setup.sh` uses, such as packages, needs a new snapshot: change the number in the setup script, which rebuilds every project's snapshot. A new snapshot also detects the values again, so do the same after a change of PHP or database version or a new worker package. Until then, a session installs a new PHP itself and warns about the rest ("Versions after a push").
- **This repository:** run `python3 -m unittest discover tests`, then `tests/vm/run-matrix.sh` (Docker) for a change of `setup.sh`, `lib.sh`, `stacks/` or a version. Keep `stacks.json` in step with the "Stacks" section: `tests/test_manifest.py` checks the versions.
- **A new host:** edit **Allowed domains**. It opens the host to every project. Keep third-party systems that act on real accounts blocked: billing, payment, SMS and production APIs.

## Limits

- 4 vCPU, 16 GB, 30 GB. The VM is reclaimed when idle: push before waiting.
- The image's apt sources ship PHP 8.3, MySQL 8.0 and PostgreSQL 16. For another version, `setup.sh` adds the Ondřej Surý source for PHP, the MySQL LTS source for MySQL, or the PostgreSQL source (PGDG). The PHP source has two hosts, and the first that answers is used (`ONDREJ_PHP_SOURCES` in `packages.sh`); the two others have one, so when it is down the setup fails within about five minutes and the session does not start.
- No preview URL for a person: the videos replace it.
- Sub-agents share one VM and one `test` database, so implement sub-agents run one after another. A sub-agent cannot start another sub-agent.

## Security

The agent reads untrusted text (tickets, PDFs, web pages, and the comments, reviews, bot comments and CI output of its pull request) with a person's GitHub and Navark identity. A comment from a person who is not an owner, a member or a collaborator of the repository gets at most a reply, never a code change. Codex and other bots are judged as evidence, and their findings can be fixed whatever their role. The guard and the network allowlist stop mistakes and casual injections. They run in a VM where the agent is root, so these are not hard limits. Each project must settle these itself:

- **Self-hosted CI.** A workflow on a self-hosted runner runs code pushed from the cloud with no review, outside the network allowlist. Prefer `ubuntu-latest`.
- **Branch protection.** Only GitHub can really refuse a push to `dev` or `main`. Require a pull request there, with no bypass for admins.
- **Auto-merge.** The guard lets the agent merge into `dev` a pull request whose checks all passed. It cannot see the Navark label, so an agent that ignores its flow could merge a green pull request without it. To keep a project out of the auto-merge, require an approving review on `dev`: the agent acts as the author of the pull request, so it cannot approve it itself.
- **The flow.** A worker follows the files Navark serves at the start of its run. Whoever can deploy Navark, or merge into its deployed branch, changes what every worker does: review a change of `resources/flows/` like a CI change. The files are public, so they never hold a secret or client data. The guard and the settings stay in this repository and a flow cannot replace them.
- **Worker tokens.** They live only in Navark, never in a VM. Each ticket gets its own VM, and of the `Claude_Code_Remote` connector the guard lets the agent use only the pull request subscription, not `create_session`, `create_trigger` or `send_message`.
- **The bucket host.** `fls-a3376286-0fef-4456-962b-b00b2b1f17c9.367be3a2035528943240074d0096e0cd.r2.cloudflarestorage.com`, the Laravel Cloud bucket of Navark (confirmed on a live upload), is in the allowlist for the video uploads, whose pre-signed URLs point at it, and for the attachment downloads, which Navark redirects to it. Only that bucket: not `*.r2.cloudflarestorage.com`, which would open every R2 bucket to a file leaving the VM. If Navark moves to another bucket, the `upload.url` that `create_upload` returns names the new host: put it here in place of this one.
- **The seeded password.** The session context holds the first user's password, read from the project. An install command must use a random password outside `local`.
- **Keys in tracked files.** Every tracked file is in the VM, and the agent can read it. `.env` comes from `env.defaults`, `env.reverb` and `project_env`, and `.env.example` is not copied to it, but it is in the checkout: keep it free of real keys.
