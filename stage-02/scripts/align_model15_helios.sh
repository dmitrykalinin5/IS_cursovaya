#!/usr/bin/env bash
# Run only for the user's existing LabReserve installation; no schema/database drops.
set -euo pipefail
cd "$(dirname "$0")/.."
export PGHOST="${PGHOST:-pg}" PGDATABASE="${PGDATABASE:-studs}" PGUSER="${PGUSER:-s466088}"
[[ "$PGDATABASE" == studs && "$PGUSER" == s466088 ]] || { echo 'Only studs / s466088 allowed' >&2; exit 2; }
mkdir -p output
bundle=$(mktemp -d "${TMPDIR:-/tmp}/labreserve-model15.XXXXXXXX")
trap 'rm -rf "$bundle"' EXIT
bash scripts/helios_python.sh sql/helios/migrate_model15.py "$bundle"
legacy=$(psql -X -qAt -v ON_ERROR_STOP=1 -c "SELECT to_regclass('s466088.lr_deployment') IS NOT NULL")
if [[ "$legacy" == t ]]; then
 backup="output/model15-backup-$(date +%Y%m%d-%H%M%S).dump"
 (umask 077; pg_dump -Fc -t s466088.lr_audit_event -t s466088.lr_conflict_event -t s466088.lr_deployment -f "$backup")
 echo "Saved old journals and installation table: $backup"
fi
psql -X -v ON_ERROR_STOP=1 -f "$bundle/migrate_model15.sql"
psql -X -v ON_ERROR_STOP=1 -f "$bundle/approved-model-tests.sql"
psql -X -v ON_ERROR_STOP=1 -f "$bundle/smoke_tests.sql"
echo 'PASS: exactly 15 model tables; migration and checks complete'
