# A stand-in for the Claude Code cloud image: Ubuntu 24.04 with its own PHP 8.3, MySQL 8.0 and
# PostgreSQL 16, Redis, Node 22 under /opt/node22, Composer, Python. Only for testing cloud-env's
# setup.sh: see run-matrix.sh. The real image has more (Ruby, Go, Rust, Java, Chrome).
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
      ca-certificates curl gnupg git jq unzip xz-utils python3 python3-pip procps \
      php8.3-cli php8.3-mbstring php8.3-xml php8.3-curl php8.3-zip php8.3-mysql php8.3-sqlite3 php8.3-intl php8.3-bcmath \
      mysql-server-8.0 postgresql-16 redis-server python3-venv >/dev/null \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://nodejs.org/dist/v22.21.1/node-v22.21.1-linux-x64.tar.xz | tar -xJ -C /opt \
    && mv /opt/node-v22.21.1-linux-x64 /opt/node22 \
    && ln -s /opt/node22/bin/node /opt/node22/bin/npm /opt/node22/bin/npx /usr/local/bin/
RUN curl -fsSL https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
ENV COMPOSER_ALLOW_SUPERUSER=1
# A Laravel 12 skeleton whose lock fits PHP 8.2 to 8.5.
RUN composer create-project --no-interaction --no-scripts --no-install laravel/laravel:^12.0 /opt/fixtures/laravel \
    && cd /opt/fixtures/laravel \
    && composer config platform.php 8.2.0 && composer update --no-install --no-scripts --no-interaction --no-progress \
    && npm install --package-lock-only --no-audit --no-fund >/dev/null
