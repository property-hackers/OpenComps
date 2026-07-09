#!/usr/bin/env bash
# Run the pgTAP suite against a dedicated, throwaway test database.
#
# Backends (auto-detected, or forced with OPENCOMPS_TEST_BACKEND=docker|pglite|local):
#   docker  - if the compose pg service is running: drop/recreate opencomps_test,
#             migrate it, run the suite with the container's pg_prove.
#   pglite  - if node_modules/@electric-sql/pglite is installed: boot a fresh
#             in-memory PGlite (PostGIS + pgTAP) with the schema applied, serve
#             it over TCP with pglite-socket, run each test file with local psql.
#             PGlite has no CREATE DATABASE; the fresh instance per run is the
#             equivalent of the drop/recreate. Tests run sequentially - PGlite
#             is a single-writer database.
#   local   - fallback: a manually managed Postgres over TCP, like docker but
#             with local psql and no pg_prove.
#
# The schema is applied from supabase/migrations/*_opencomps.sql on every run,
# so tests always exercise the current schema and never touch dev data.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DB="${POSTGRES_TEST_DB:-opencomps_test}"
POSTGRES_USER_NAME="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD_VALUE="${POSTGRES_PASSWORD:-postgres}"
POSTGRES_HOST_NAME="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT_NUM="${POSTGRES_PORT:-5432}"

# TEST_DB is interpolated into DROP/CREATE DATABASE statements - keep it a
# plain identifier so a hostile/typo'd env var can't smuggle SQL.
if ! [[ "$TEST_DB" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
  echo "POSTGRES_TEST_DB must be a plain identifier, got: ${TEST_DB}" >&2
  exit 1
fi

# NOTE: the exactly-one glob below and scripts/migrate.sh apply a single
# schema file, while scripts/dev_server.mjs applies every
# supabase/migrations/*.sql in order via tinbase. If a second migration file
# is ever added, update this script and migrate.sh in lockstep.
SCHEMA_FILES=("$ROOT_DIR"/supabase/migrations/*_opencomps.sql)
if [ ${#SCHEMA_FILES[@]} -ne 1 ] || [ ! -f "${SCHEMA_FILES[0]}" ]; then
  echo "Expected exactly one supabase/migrations/*_opencomps.sql, found: ${SCHEMA_FILES[*]}" >&2
  exit 1
fi
SCHEMA_FILE="${SCHEMA_FILES[0]}"

BACKEND="${OPENCOMPS_TEST_BACKEND:-}"
if [ -z "$BACKEND" ]; then
  if command -v docker >/dev/null 2>&1 && [ -n "$(docker compose ps --status running -q pg 2>/dev/null)" ]; then
    BACKEND=docker
  elif [ -d "$ROOT_DIR/node_modules/@electric-sql/pglite" ]; then
    BACKEND=pglite
  else
    BACKEND=local
  fi
fi

# Run every test file with psql and fail on pgTAP failures. pgTAP assertions
# are plain result rows ("not ok ...", "# Looks like you failed/planned ..."),
# not SQL errors, so ON_ERROR_STOP alone would exit 0 on a failed test - the
# TAP output has to be inspected. (The docker backend gets this for free from
# pg_prove.)
run_tap_files() {
  local db="$1" failed=0 out
  for test_file in "$ROOT_DIR"/supabase/tests/database/*.sql; do
    echo ""
    echo "Running: $test_file"
    out="$(psql "$db" -v ON_ERROR_STOP=1 -qAt -f "$test_file")" || failed=1
    printf '%s\n' "$out"
    if printf '%s\n' "$out" | grep -qE '^(not ok|# Looks like you (failed|planned))'; then
      echo "pgTAP failures detected in ${test_file}" >&2
      failed=1
    fi
  done
  return "$failed"
}

case "$BACKEND" in
docker)
  echo "Preparing test database ${TEST_DB}..."
  docker compose exec -T pg psql -U "$POSTGRES_USER_NAME" -d postgres -v ON_ERROR_STOP=1 -q \
    -c "DROP DATABASE IF EXISTS ${TEST_DB};" -c "CREATE DATABASE ${TEST_DB};"
  docker compose exec -T pg psql -U "$POSTGRES_USER_NAME" -d "$TEST_DB" -v ON_ERROR_STOP=1 -1 -q -f - \
    < "$SCHEMA_FILE"

  echo "Running pgTAP tests with container pg_prove..."
  docker compose exec -T \
    -e TEST_DB="$TEST_DB" \
    -e POSTGRES_USER="$POSTGRES_USER_NAME" \
    -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD_VALUE" \
    pg sh -lc 'PGPASSWORD="$POSTGRES_PASSWORD" pg_prove -U "$POSTGRES_USER" -d "$TEST_DB" /tests/database/*.sql'
  ;;

pglite)
  PORT="${PGLITE_TEST_PORT:-55433}"
  DB="postgres://postgres@127.0.0.1:${PORT}/postgres"

  echo "Booting in-memory PGlite test server on port ${PORT}..."
  node "$ROOT_DIR/scripts/test_server.mjs" --schema "$SCHEMA_FILE" --port "$PORT" &
  SERVER_PID=$!
  trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT

  ready=""
  for _ in $(seq 1 120); do
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
      echo "PGlite test server exited before becoming ready" >&2
      exit 1
    fi
    if psql "$DB" -qAt -c 'SELECT 1' >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 0.5
  done
  if [ -z "$ready" ]; then
    echo "PGlite test server did not become ready in time" >&2
    exit 1
  fi

  echo "Running pgTAP tests against PGlite (tinbase engine)..."
  run_tap_files "$DB"
  ;;

local)
  ADMIN_DB="postgres://${POSTGRES_USER_NAME}:${POSTGRES_PASSWORD_VALUE}@${POSTGRES_HOST_NAME}:${POSTGRES_PORT_NUM}/postgres"
  DB="postgres://${POSTGRES_USER_NAME}:${POSTGRES_PASSWORD_VALUE}@${POSTGRES_HOST_NAME}:${POSTGRES_PORT_NUM}/${TEST_DB}"

  echo "Preparing test database ${TEST_DB}..."
  psql "$ADMIN_DB" -v ON_ERROR_STOP=1 -q \
    -c "DROP DATABASE IF EXISTS ${TEST_DB};" -c "CREATE DATABASE ${TEST_DB};"
  psql "$DB" -v ON_ERROR_STOP=1 -1 -q -f "$SCHEMA_FILE"

  echo "Running pgTAP tests with local psql..."
  run_tap_files "$DB"
  ;;

*)
  echo "Unknown OPENCOMPS_TEST_BACKEND: ${BACKEND} (expected docker, pglite, or local)" >&2
  exit 1
  ;;
esac
