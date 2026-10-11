\set ON_ERROR_STOP on
BEGIN;
\ir ../schema/01_tables.sql
\ir ../schema/02_triggers.sql
\ir ../functions/03_operations.sql
\ir ../indexes/04_indexes.sql
COMMIT;
