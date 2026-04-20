# syntax=docker/dockerfile:1
ARG RUBY_VERSION=3.2.0
FROM ruby:${RUBY_VERSION}-alpine AS base

ARG S6_VERSION=3.1.6.2

RUN apk update --no-cache && \
    apk add --no-cache \
    build-base \
    mysql-dev \
    nodejs \
    npm \
    tzdata \
    git \
    bash \
    curl \
    xz \
    redis \
    shared-mime-info

# Install s6-overlay (multi-arch)
RUN ARCH=$(uname -m) && \
    case "$ARCH" in \
      x86_64)  S6_ARCH="x86_64"  ;; \
      aarch64) S6_ARCH="aarch64" ;; \
      armv7l)  S6_ARCH="arm"     ;; \
      *) echo "Unsupported arch: $ARCH" && exit 1 ;; \
    esac && \
    curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_VERSION}/s6-overlay-noarch.tar.xz" \
      | tar -C / -Jxp && \
    curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" \
      | tar -C / -Jxp

WORKDIR /app

# --- Gems layer ---
FROM base AS gems
COPY Gemfile ./
RUN bundle lock
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle install --jobs 4 --retry 3

# --- Final image ---
FROM base AS final

COPY --from=gems /app/vendor/bundle /app/vendor/bundle
COPY --from=gems /usr/local/bundle  /usr/local/bundle
COPY . .

# Carry over the bundle config so `bundle exec` resolves gems from vendor/bundle
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle config set --local path 'vendor/bundle'

# ---------------------------------------------------------------------------
# S6 service definitions — embedded directly, no external s6/ folder needed
# Boot order:
#   init-config (oneshot)
#     └── redis (longrun)
#           └── db-migrate (oneshot)
#                 ├── rails (longrun)
#                 └── sidekiq (longrun)
# ---------------------------------------------------------------------------

# --- init-config: copy *.yml.example → *.yml if target is empty/missing ---
RUN mkdir -p /etc/s6-overlay/s6-rc.d/init-config/dependencies.d && \
    echo "oneshot" > /etc/s6-overlay/s6-rc.d/init-config/type && \
    touch /etc/s6-overlay/s6-rc.d/init-config/dependencies.d/.s6-svscan

# The actual script
RUN cat > /usr/local/bin/init-config.sh <<'EOF'
#!/bin/sh
needs_review=false

for f in database secrets schedule sidekiq; do
  dest="/app/config/${f}.yml"
  src="/app/config/${f}.yml.example"
  if [ ! -s "$dest" ]; then
    echo "[init-config] ${f}.yml is empty or missing — copying from example"
    cat "$src" > "$dest"
    needs_review=true
  else
    echo "[init-config] ${f}.yml already has content — skipping"
  fi
done

if [ "$needs_review" = "true" ]; then
  echo ""
  echo "================================================"
  echo "  CONFIGURATION REQUIRED — CONTAINER WILL EXIT"
  echo "================================================"
  echo ""
  echo "  One or more config files were empty and have"
  echo "  been populated from their .example templates."
  echo ""
  echo "  Please review and update the following files"
  echo "  on your mounted volumes before restarting:"
  echo ""
  echo "    /app/config/database.yml"
  echo "    /app/config/secrets.yml"
  echo "    /app/config/schedule.yml"
  echo "    /app/config/sidekiq.yml"
  echo ""
  echo "  Then restart the container:"
  echo "    docker compose restart"
  echo ""
  echo "================================================"
  echo ""
  exit 1
fi
EOF
RUN chmod +x /usr/local/bin/init-config.sh

# up contains just the path to the script
RUN echo "/usr/local/bin/init-config.sh" > /etc/s6-overlay/s6-rc.d/init-config/up

# --- db-migrate: runs once after redis is up ---
RUN mkdir -p /etc/s6-overlay/s6-rc.d/db-migrate/dependencies.d && \
    echo "oneshot" > /etc/s6-overlay/s6-rc.d/db-migrate/type && \
    touch /etc/s6-overlay/s6-rc.d/db-migrate/dependencies.d/redis

RUN cat > /usr/local/bin/db-migrate.sh <<'EOF'
#!/bin/sh
MYSQL_CONN_FAIL="${MYSQL_CONN_FAIL:-5}"
attempt=0

echo "[db-migrate] Waiting for database at ${MYSQL_HOST}:${MYSQL_PORT:-3306}..."

while ! ruby -e "
  require 'mysql2'
  Mysql2::Client.new(
    host:     ENV['MYSQL_HOST'],
    port:     (ENV['MYSQL_PORT'] || 3306).to_i,
    username: ENV['MYSQL_USER'],
    password: ENV['MYSQL_PASSWORD'],
    database: ENV['MYSQL_DATABASE']
  )
" 2>/dev/null; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge "$MYSQL_CONN_FAIL" ]; then
    echo ""
    echo "================================================"
    echo "  DATABASE UNAVAILABLE — CONTAINER WILL EXIT"
    echo "================================================"
    echo ""
    echo "  Could not connect to MySQL after ${MYSQL_CONN_FAIL} attempts."
    echo ""
    echo "  Please verify the following environment variables:"
    echo ""
    echo "    MYSQL_HOST      = ${MYSQL_HOST}"
    echo "    MYSQL_PORT      = ${MYSQL_PORT:-3306}"
    echo "    MYSQL_DATABASE  = ${MYSQL_DATABASE}"
    echo "    MYSQL_USER      = ${MYSQL_USER}"
    echo "    MYSQL_PASSWORD  = (hidden)"
    echo ""
    echo "  Adjust MYSQL_CONN_FAIL to allow more retries (default: 5)."
    echo "  Each retry waits 15 seconds."
    echo ""
    echo "================================================"
    echo ""
    exit 1
  fi
  echo "[db-migrate] Attempt ${attempt}/${MYSQL_CONN_FAIL} failed — retrying in 15s..."
  sleep 15
done

echo "[db-migrate] Database connection established."
echo "[db-migrate] Running db:migrate..."
cd /app
bundle exec rails db:create db:migrate db:seed
EOF
RUN chmod +x /usr/local/bin/db-migrate.sh

RUN echo "/usr/local/bin/db-migrate.sh" > /etc/s6-overlay/s6-rc.d/db-migrate/up

# --- Redis ---
RUN mkdir -p /etc/s6-overlay/s6-rc.d/redis/dependencies.d && \
    echo "longrun" > /etc/s6-overlay/s6-rc.d/redis/type && \
    touch /etc/s6-overlay/s6-rc.d/redis/dependencies.d/init-config

RUN cat > /etc/s6-overlay/s6-rc.d/redis/run <<'EOF'
#!/bin/sh
exec redis-server --save "" --appendonly no --loglevel notice
EOF

RUN cat > /etc/s6-overlay/s6-rc.d/redis/finish <<'EOF'
#!/bin/sh
echo "[redis] exited with code $1"
EOF

# --- Rails ---
RUN mkdir -p /etc/s6-overlay/s6-rc.d/rails/dependencies.d && \
    echo "longrun" > /etc/s6-overlay/s6-rc.d/rails/type && \
    touch /etc/s6-overlay/s6-rc.d/rails/dependencies.d/db-migrate

RUN cat > /etc/s6-overlay/s6-rc.d/rails/run <<'EOF'
#!/bin/sh
BIND_IP="${BIND_IP:-0.0.0.0}"
BIND_PORT="${BIND_PORT:-3000}"
cd /app
exec bundle exec rails server -b "$BIND_IP" -p "$BIND_PORT"
EOF

RUN cat > /etc/s6-overlay/s6-rc.d/rails/finish <<'EOF'
#!/bin/sh
echo "[rails] exited with code $1"
EOF

# --- Sidekiq ---
RUN mkdir -p /etc/s6-overlay/s6-rc.d/sidekiq/dependencies.d && \
    echo "longrun" > /etc/s6-overlay/s6-rc.d/sidekiq/type && \
    touch /etc/s6-overlay/s6-rc.d/sidekiq/dependencies.d/db-migrate

RUN cat > /etc/s6-overlay/s6-rc.d/sidekiq/run <<'EOF'
#!/bin/sh
cd /app
exec bundle exec sidekiq
EOF

RUN cat > /etc/s6-overlay/s6-rc.d/sidekiq/finish <<'EOF'
#!/bin/sh
echo "[sidekiq] exited with code $1"
EOF

# Make all run/finish scripts executable
RUN find /etc/s6-overlay/s6-rc.d -type f \( -name run -o -name finish \) \
    -exec chmod +x {} +

# Register all services in the boot bundle
RUN mkdir -p /etc/s6-overlay/s6-rc.d/user/contents.d && \
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/init-config \
          /etc/s6-overlay/s6-rc.d/user/contents.d/redis \
          /etc/s6-overlay/s6-rc.d/user/contents.d/db-migrate \
          /etc/s6-overlay/s6-rc.d/user/contents.d/rails \
          /etc/s6-overlay/s6-rc.d/user/contents.d/sidekiq

# Defaults — override via environment variables at runtime
# BIND_IP          (default: 0.0.0.0)
# BIND_PORT        (default: 3000)
# MYSQL_CONN_FAIL  (default: 5  — max DB connection attempts, 15s apart)
EXPOSE 3000

ENTRYPOINT ["/init"]
