\set ON_ERROR_STOP on
SELECT current_database()='labreserve_stage02_test' AS safe \gset
\if :safe
DROP SCHEMA IF EXISTS labreserve CASCADE;
\else
\echo Refusing cleanup outside labreserve_stage02_test
\quit 3
\endif
