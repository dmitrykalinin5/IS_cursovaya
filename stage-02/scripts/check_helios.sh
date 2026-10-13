#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-10}"
export PGHOST="${PGHOST:-pg}" PGDATABASE="${PGDATABASE:-studs}" PGUSER="${PGUSER:-s466088}"
[[ "$PGDATABASE" == studs && "$PGUSER" == s466088 ]] || { echo 'Only studs / s466088 allowed' >&2; exit 2; }
psql -X -v ON_ERROR_STOP=1 -f sql/helios/preflight.sql
psql -X -v ON_ERROR_STOP=1 -f sql/helios/smoke_tests.sql
case "${1:-}" in
 '') echo 'PASS: diagnostics and transactional smoke checks' ;;
 --concurrency)
  mkdir -p output
  bash scripts/helios_python.sh sql/helios/concurrency.py --output output/helios-concurrency.json
  echo 'PASS: concurrent probes cancelled/archived; audited probe history retained' ;;
 *) echo 'Usage: check_helios.sh [--concurrency]' >&2; exit 2 ;;
esac
