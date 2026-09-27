#!/usr/bin/env bash
#
# Validate the Backend 1 auth foundation migrations against a throwaway local
# PostgreSQL database. No Docker and no Supabase CLI required, and it never
# touches a cloud project.
#
# What it does:
#   1. creates a scratch database
#   2. installs back/supabase/tests/00_local_auth_shim.sql (fake auth schema +
#      the anon / authenticated / service_role roles that Supabase provides)
#   3. applies every file in back/supabase/migrations in filename order
#   4. applies them a SECOND time to prove they are idempotent
#   5. runs back/supabase/tests/10_authz_regression.sql
#   6. drops the scratch database
#
# Usage:
#   back/scripts/verify-local.sh                 # uses the local socket + $USER
#   PGHOST=... PGUSER=... back/scripts/verify-local.sh
#   KEEP_DB=1 back/scripts/verify-local.sh       # keep the scratch DB for poking
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MIGRATIONS_DIR="${BACK_DIR}/supabase/migrations"
TESTS_DIR="${BACK_DIR}/supabase/tests"

SCRATCH_DB="${SCRATCH_DB:-project300_authz_verify_$$}"
ADMIN_DB="${ADMIN_DB:-postgres}"

PSQL=(psql --no-psqlrc --quiet --set=ON_ERROR_STOP=1)

cleanup() {
  if [[ "${KEEP_DB:-0}" == "1" ]]; then
    echo ""
    echo "KEEP_DB=1 -> leaving scratch database '${SCRATCH_DB}' in place."
    return
  fi
  "${PSQL[@]}" -d "${ADMIN_DB}" \
    -c "drop database if exists \"${SCRATCH_DB}\" with (force)" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> checking prerequisites"
command -v psql >/dev/null 2>&1 || { echo "psql not found on PATH"; exit 1; }
pg_isready >/dev/null 2>&1 || { echo "no PostgreSQL server is accepting connections"; exit 1; }
psql --version

echo ""
echo "==> creating scratch database ${SCRATCH_DB}"
"${PSQL[@]}" -d "${ADMIN_DB}" -c "create database \"${SCRATCH_DB}\"" >/dev/null

run_sql() {
  "${PSQL[@]}" -d "${SCRATCH_DB}" -f "$1"
}

echo ""
echo "==> installing local auth shim (test fixture, never applied to Supabase)"
run_sql "${TESTS_DIR}/00_local_auth_shim.sql" >/dev/null
run_sql "${TESTS_DIR}/01_test_helpers.sql"   >/dev/null

echo ""
echo "==> applying migrations"
shopt -s nullglob
MIGRATIONS=("${MIGRATIONS_DIR}"/*.sql)
shopt -u nullglob
if [[ ${#MIGRATIONS[@]} -eq 0 ]]; then
  echo "no migrations found in ${MIGRATIONS_DIR}"
  exit 1
fi
for migration in "${MIGRATIONS[@]}"; do
  echo "    $(basename "${migration}")"
  run_sql "${migration}" >/dev/null
done

echo ""
echo "==> re-applying migrations to verify idempotency"
for migration in "${MIGRATIONS[@]}"; do
  echo "    $(basename "${migration}")"
  run_sql "${migration}" >/dev/null
done

echo ""
echo "==> running authorization regression suite"
run_sql "${TESTS_DIR}/10_authz_regression.sql"

echo ""
echo "==> OK"
