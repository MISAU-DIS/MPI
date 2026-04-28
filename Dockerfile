# syntax=docker/dockerfile:1

ARG BASE_IMAGE=ghcr.io/misau-dis/mpi-base:20260420-001

# -- Stage 1: install gems ------------------------------------------------------
FROM ${BASE_IMAGE} AS gems

WORKDIR /app

COPY Gemfile ./

RUN bundle lock && \
    bundle config set --local without 'development test' && \
    bundle install --jobs 4 --retry 3

# -- Stage 2: runtime ----------------------------------------------------------─
FROM ${BASE_IMAGE} 

# -- s6-overlay ----------------------------------------------------------------
ARG S6_VERSION=3.2.2.0

ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_VERSION}/s6-overlay-noarch.tar.xz /tmp/
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_VERSION}/s6-overlay-x86_64.tar.xz /tmp/

RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz && \
    tar -C / -Jxpf /tmp/s6-overlay-x86_64.tar.xz && \
    rm -f /tmp/s6-overlay-*.tar.xz

ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0 \
    S6_CMD_WAIT_FOR_SERVICES=1 \
    S6_LOGGING=0

# -- App ----------------------------------------------------------------------─
WORKDIR /app

COPY --from=gems /usr/local/bundle /usr/local/bundle
COPY --from=gems /app/Gemfile.lock ./
COPY . .

RUN bundle config set --local without 'development test'

# -- Asset precompilation ------------------------------------------------------─
RUN SECRET_KEY_BASE=dummy RAILS_ENV=production \
    bundle exec rails tailwindcss:build assets:precompile

# -- Logging helper ------------------------------------------------------------
RUN cat > /usr/local/bin/log.sh <<'SCRIPT' && chmod +x /usr/local/bin/log.sh
#!/bin/sh
TS=$(date '+%Y-%m-%d %H:%M:%S %z')
case "$1" in
  start)   printf "****** [%s] START: %s\n"          "$TS" "$2" ;;
  end)     printf "*****  [%s] END: %s\n"         "$TS" "$2" ;;
  success) printf "       [%s]  SUCCESS: %s\n"          "$TS" "$2" ;;
  failure) printf "       [%s]  FAILURE: %s\n"          "$TS" "$2" ;;
  *)       printf        "[%s] %s\n"                    "$TS" "$*" ;;
esac
SCRIPT

# -- cont-init: 00 – validate required environment variables ------------------─
RUN mkdir -p /etc/cont-init.d

RUN cat > /etc/cont-init.d/00-validate.sh <<'SCRIPT' && chmod +x /etc/cont-init.d/00-validate.sh
#!/command/with-contenv sh
set -e

# Print a variable name = value, masking the value if it is a secret.
check_var() {
  name="$1"
  value="$2"
  secret="$3"   # pass "secret" to mask

  if [ -z "$value" ]; then
    log.sh failure "  $name = (not set)"
    return 1
  fi

  if [ "$secret" = "secret" ]; then
    masked="$(printf '%s' "$value" | cut -c1-2)***"
    log.sh success "  $name = $masked"
  else
    log.sh success "  $name = $value"
  fi
  return 0
}

log.sh start "Validate required environment variables"

failed=0
check_var "DB_HOST"        "$DB_HOST"            || failed=1
check_var "DB_PORT"        "$DB_PORT"            || failed=1
check_var "DB_NAME"        "$DB_NAME"            || failed=1
check_var "DB_USERNAME"    "$DB_USERNAME"        || failed=1
check_var "DB_PASSWORD"    "$DB_PASSWORD" secret || failed=1
check_var "RAILS_ENV"      "$RAILS_ENV"          || failed=1
check_var "REDIS_URL"      "$REDIS_URL"          || failed=1

if [ "$failed" = "1" ]; then
  log.sh failure "One or more required environment variables are missing — aborting"
  exit 1
fi

log.sh end "Validate required environment variables"
SCRIPT

# -- cont-init: 01 – network reachability checks ------------------------------─
RUN cat > /etc/cont-init.d/01-network.sh <<'SCRIPT' && chmod +x /etc/cont-init.d/01-network.sh
#!/command/with-contenv sh
set -e

PING_MAX=5
PORT_MAX=5

# -- ping check ----------------------------------------------------------------
log.sh start "Ping check: $DB_HOST"

ping_ok=0
i=0
while [ "$i" -lt "$PING_MAX" ]; do
  i=$((i + 1))
  echo "  Pinging $DB_HOST ... attempt $i/$PING_MAX"
  if ping -c1 -W2 "$DB_HOST" >/dev/null 2>&1; then
    log.sh success "Ping check: $DB_HOST is reachable (attempt $i)"
    ping_ok=1
    break
  fi
  log.sh failure "Ping check: $DB_HOST did not respond (attempt $i/$PING_MAX)"
  sleep 1
done

if [ "$ping_ok" = "0" ]; then
  log.sh failure "Ping check: $DB_HOST unreachable after $PING_MAX attempts — aborting"
  exit 1
fi

log.sh end "Ping check: $DB_HOST"

# -- TCP port check ------------------------------------------------------------
log.sh start "TCP port check: $DB_HOST:$DB_PORT"

port_ok=0
i=0
while [ "$i" -lt "$PORT_MAX" ]; do
  i=$((i + 1))
  echo "  Checking $DB_HOST:$DB_PORT ... attempt $i/$PORT_MAX"
  if nc -z "$DB_HOST" "$DB_PORT" 2>/dev/null; then
    log.sh success "TCP port check: $DB_HOST:$DB_PORT is open (attempt $i)"
    port_ok=1
    break
  fi
  log.sh failure "TCP port check: $DB_HOST:$DB_PORT not reachable (attempt $i/$PORT_MAX)"
  sleep 2
done

if [ "$port_ok" = "0" ]; then
  log.sh failure "TCP port check: $DB_HOST:$DB_PORT unreachable after $PORT_MAX attempts — aborting"
  exit 1
fi

log.sh end "TCP port check: $DB_HOST:$DB_PORT"
SCRIPT

# -- cont-init: 02 – inject config files if empty ------------------------------
RUN cat > /etc/cont-init.d/02-config.sh <<'SCRIPT' && chmod +x /etc/cont-init.d/02-config.sh
#!/command/with-contenv sh
set -e

# Resolve the target filename for a given *.yml.example basename.
# CONFIG_RENAMES format (set in .env): "src1.yml.example:tgt1.yml,src2.yml.example:tgt2.yml"
resolve_target() {
  src_base="$1"   # e.g. emr_migration.yml.example
  if [ -n "$CONFIG_RENAMES" ]; then
    match="$(printf '%s' "$CONFIG_RENAMES" | tr ',' '\n' | awk -F: -v s="$src_base" '$1==s{print $2; exit}')"
    [ -n "$match" ] && { echo "$match"; return; }
  fi
  # Default: strip .example
  echo "${src_base%.example}"
}

log.sh start "Inject missing config files from .example templates"

for example in /app/config/*.yml.example; do
  [ -f "$example" ] || continue
  src_base="$(basename "$example")"
  tgt_base="$(resolve_target "$src_base")"
  target="/app/config/$tgt_base"

  if [ ! -s "$target" ]; then
    log.sh success "  $src_base  →  $tgt_base  (populated)"
    cp "$example" "$target"
  else
    echo "         $tgt_base already present — skipping"
  fi
done

log.sh end "Inject missing config files from .example templates"
SCRIPT

# -- cont-init: 03 – database setup --------------------------------------------
RUN cat > /etc/cont-init.d/03-db.sh <<'SCRIPT' && chmod +x /etc/cont-init.d/03-db.sh
#!/command/with-contenv sh
cd /app

# Runs a Rails db task; exits the container on failure when DB_FAIL_EXIT=true.
db_run() {
  label="$1"; shift
  log.sh start "$label"
  if "$@"; then
    log.sh end "$label"
  else
    log.sh failure "$label failed"
    if [ "${DB_FAIL_EXIT:-true}" = "true" ]; then
      log.sh failure "DB_FAIL_EXIT=true — terminating container"
      exit 1
    fi
  fi
}

db_run "Rails database create" bundle exec rails db:create
db_run "Rails database migrate" bundle exec rails db:migrate

if [ "${MASTER:-false}" = "true" ]; then
  db_run "Rails database seed (MASTER mode)" bundle exec rails db:seed
fi
SCRIPT

# -- Service: redis ------------------------------------------------------------
RUN mkdir -p /etc/services.d/redis
RUN cat > /etc/services.d/redis/run <<'SCRIPT' && chmod +x /etc/services.d/redis/run
#!/command/with-contenv sh
log.sh start "Redis server"
exec redis-server --loglevel notice
SCRIPT

# -- Service: sidekiq ----------------------------------------------------------
RUN mkdir -p /etc/services.d/sidekiq
RUN cat > /etc/services.d/sidekiq/run <<'SCRIPT' && chmod +x /etc/services.d/sidekiq/run
#!/command/with-contenv sh
cd /app

log.sh start "Sidekiq: wait for Redis"
until redis-cli ping >/dev/null 2>&1; do
  echo "  Skidekiq: Waiting for Redis..."
  sleep 1
done
log.sh end "Sidekiq: wait for Redis"

log.sh start "Sidekiq worker"
bundle exec sidekiq -C /app/config/sidekiq.yml
log.sh end "Sidekiq worker"
SCRIPT

# -- Service: rails ------------------------------------------------------------
RUN mkdir -p /etc/services.d/rails
RUN cat > /etc/services.d/rails/run <<'SCRIPT' && chmod +x /etc/services.d/rails/run
#!/command/with-contenv sh
cd /app

log.sh start "Rails: wait for Redis"
until redis-cli ping >/dev/null 2>&1; do
  echo "  Rails: Waiting for Redis..."
  sleep 1
done
log.sh end "Rails: wait for Redis"

log.sh start "Rails server"
bundle exec rails server -b "${BIND_IP:-0.0.0.0}" -p "${BIND_PORT:-3000}"
log.sh end "Rails server"
SCRIPT

EXPOSE 3000

ENTRYPOINT ["/init"]
