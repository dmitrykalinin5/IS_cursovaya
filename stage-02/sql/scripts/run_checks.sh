#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${PGDATABASE:?Set PGDATABASE=labreserve_stage02_test}"
[[ "$PGDATABASE" == labreserve_stage02_test ]] || { echo 'Only dedicated test DB allowed'; exit 2; }
mkdir -p output
psql -X -v ON_ERROR_STOP=1 -f sql/scripts/clean_schema.sql >output/clean.log
psql -X -v ON_ERROR_STOP=1 -f sql/scripts/install.sql >output/install.log
psql -X -v ON_ERROR_STOP=1 -f sql/seeds/05_demo.sql >output/seed.log
psql -X -v ON_ERROR_STOP=1 -f sql/tests/06_assertions.sql >output/assertions.log 2>&1
psql -X -v ON_ERROR_STOP=1 -f sql/tests/07_controls.sql >output/controls.log
python3 sql/tests/concurrency.py | tee output/concurrency.log
psql -X -v ON_ERROR_STOP=1 -f sql/tests/08_explain.sql >output/explain.log
psql -X -v ON_ERROR_STOP=1 -f sql/scripts/clean_schema.sql >output/recreate.log
psql -X -v ON_ERROR_STOP=1 -f sql/scripts/install.sql >>output/recreate.log
psql -X -v ON_ERROR_STOP=1 -f sql/seeds/05_demo.sql >>output/recreate.log
psql -X -v ON_ERROR_STOP=1 -f sql/tests/06_assertions.sql >output/assertions-recreated.log 2>&1
printf 'PASS: clean install, SQL assertions, concurrency, EXPLAIN, clean rebuild\n'
