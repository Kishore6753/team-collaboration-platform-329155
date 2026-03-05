#!/bin/bash
set -euo pipefail

# Runs schema migrations (and optional seed) against the task tracker Postgres database.
#
# Contract:
# - Inputs:
#   - Reads connection string from ./db_connection.txt (required).
#   - MIGRATIONS_DIR (optional): directory containing migration .sql files (default: ./migrations/sql)
#   - SEED_FILE (optional): path to seed .sql file (default: ./migrations/seed.sql)
#   - RUN_SEED (optional): "true" to run seed after migrations (default: "false")
# - Outputs:
#   - Applies each migration exactly once (tracked by public.schema_migrations).
# - Errors:
#   - Exits non-zero if db_connection.txt missing, psql fails, or migration fails.
# - Side effects:
#   - Creates public.schema_migrations table.
#   - Executes SQL from migration files on the database.

echo "[migrations] starting"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_CONNECTION_FILE="${ROOT_DIR}/db_connection.txt"

if [ ! -f "${DB_CONNECTION_FILE}" ]; then
  echo "[migrations] ERROR: db_connection.txt not found at ${DB_CONNECTION_FILE}"
  exit 1
fi

DB_URL="$(cat "${DB_CONNECTION_FILE}" | tr -d '\n' | sed -E 's/^psql[[:space:]]+//')"
if [ -z "${DB_URL}" ]; then
  echo "[migrations] ERROR: db_connection.txt is empty or invalid"
  exit 1
fi

MIGRATIONS_DIR="${MIGRATIONS_DIR:-${ROOT_DIR}/migrations/sql}"
SEED_FILE="${SEED_FILE:-${ROOT_DIR}/migrations/seed.sql}"
RUN_SEED="${RUN_SEED:-false}"

if [ ! -d "${MIGRATIONS_DIR}" ]; then
  echo "[migrations] ERROR: MIGRATIONS_DIR does not exist: ${MIGRATIONS_DIR}"
  exit 1
fi

run_psql() {
  local sql="$1"
  # Use ON_ERROR_STOP to fail fast and keep deterministic behavior.
  psql "${DB_URL}" -v ON_ERROR_STOP=1 -X -q -c "${sql}"
}

run_file() {
  local file_path="$1"
  psql "${DB_URL}" -v ON_ERROR_STOP=1 -X -f "${file_path}"
}

# Ensure migrations table exists.
run_psql "CREATE TABLE IF NOT EXISTS public.schema_migrations (version TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now());"

# Apply migrations in lexical order.
shopt -s nullglob
migration_files=("${MIGRATIONS_DIR}"/*.sql)
shopt -u nullglob

if [ ${#migration_files[@]} -eq 0 ]; then
  echo "[migrations] no migrations found in ${MIGRATIONS_DIR} (skipping)"
else
  echo "[migrations] found ${#migration_files[@]} migration(s) in ${MIGRATIONS_DIR}"
fi

for file_path in "${migration_files[@]}"; do
  version="$(basename "${file_path}")"

  already_applied="$(psql "${DB_URL}" -X -q -t -A -c "SELECT 1 FROM public.schema_migrations WHERE version='${version}' LIMIT 1;" || true)"
  if [ "${already_applied}" = "1" ]; then
    echo "[migrations] skip (already applied): ${version}"
    continue
  fi

  echo "[migrations] apply: ${version}"
  run_file "${file_path}"
  run_psql "INSERT INTO public.schema_migrations(version) VALUES ('${version}');"
done

if [ "${RUN_SEED}" = "true" ]; then
  if [ -f "${SEED_FILE}" ]; then
    echo "[migrations] seeding from ${SEED_FILE}"
    run_file "${SEED_FILE}"
  else
    echo "[migrations] seed requested but seed file not found: ${SEED_FILE}"
    exit 1
  fi
else
  echo "[migrations] seed disabled (RUN_SEED=${RUN_SEED})"
fi

echo "[migrations] complete"
