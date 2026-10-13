#!/usr/bin/env bash
# Run ON Helios after SSH login, or against a local restricted-role simulation.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v psql >/dev/null || { echo 'psql is required' >&2; exit 2; }
export PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-10}"
export PGHOST="${PGHOST:-pg}" PGDATABASE="${PGDATABASE:-studs}" PGUSER="${PGUSER:-s466088}"
[[ "$PGDATABASE" == studs && "$PGUSER" == s466088 ]] || { echo 'Only studs / s466088 allowed' >&2; exit 2; }
case "${1:-install}" in
 preflight) exec psql -X -v ON_ERROR_STOP=1 -f sql/helios/preflight.sql ;;
 smoke) exec psql -X -v ON_ERROR_STOP=1 -f sql/helios/smoke_tests.sql ;;
 install) ;;
 *) echo 'Usage: deploy_helios.sh [preflight|install|smoke]' >&2; exit 2 ;;
esac
bundle=$(mktemp -d "${TMPDIR:-/tmp}/labreserve-helios.XXXXXXXX")
trap 'rm -rf "$bundle"' EXIT
bash scripts/helios_python.sh sql/helios/build.py "$bundle"
psql -X -v ON_ERROR_STOP=1 -f "$bundle/install.sql"
echo 'PASS: installation and smoke checks completed'
