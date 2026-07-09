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

# All migrations, applied in timestamp order (same order tinbase uses at
# boot in scripts/dev_server.mjs and test_db.sh uses for test databases).
SCHEMA_FILES=("$ROOT_DIR"/supabase/migrations/*.sql)
if [ ${#SCHEMA_FILES[@]} -eq 0 ] || [ ! -f "${SCHEMA_FILES[0]}" ]; then
  echo "No migrations found in supabase/migrations/" >&2
  exit 1
fi

# -1: migration files carry no BEGIN/COMMIT of their own (tinbase wraps
# migrations in a transaction), so psql provides one transaction per file.
echo "Applying OpenComps schema..."
for schema_file in "${SCHEMA_FILES[@]}"; do
  psql "$DB" -v ON_ERROR_STOP=1 -1 -f "$schema_file"
done
echo "Schema applied."
