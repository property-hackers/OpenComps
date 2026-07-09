#!/usr/bin/env bash
# Apply the OpenComps schema to an empty database.
#
# Usage:
#   ./scripts/migrate.sh
#   ./scripts/migrate.sh "postgres://postgres:postgres@localhost:5432/opencomps"
#   DATABASE_URL=postgres://... ./scripts/migrate.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DB="${1:-${DATABASE_URL:-postgres://${POSTGRES_USER:-postgres}:${POSTGRES_PASSWORD:-postgres}@${POSTGRES_HOST:-localhost}:${POSTGRES_PORT:-5432}/${POSTGRES_DB:-opencomps}}}"

# NOTE: exactly-one glob, mirrored in scripts/test_db.sh; scripts/dev_server.mjs
# instead applies every supabase/migrations/*.sql via tinbase. Adding a second
# migration file requires updating this script and test_db.sh in lockstep.
SCHEMA_FILES=("$ROOT_DIR"/supabase/migrations/*_opencomps.sql)
if [ ${#SCHEMA_FILES[@]} -ne 1 ] || [ ! -f "${SCHEMA_FILES[0]}" ]; then
  echo "Expected exactly one supabase/migrations/*_opencomps.sql, found: ${SCHEMA_FILES[*]}" >&2
  exit 1
fi

# -1: the migration file carries no BEGIN/COMMIT of its own (tinbase wraps
# migrations in a transaction), so psql provides the single transaction here.
echo "Applying OpenComps schema..."
psql "$DB" -v ON_ERROR_STOP=1 -1 -f "${SCHEMA_FILES[0]}"
echo "Schema applied."
