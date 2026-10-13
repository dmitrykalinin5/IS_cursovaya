\set ON_ERROR_STOP on
\echo Helios PostgreSQL diagnostics
SELECT version();
SELECT current_user, current_database();
SELECT e.extname,n.nspname AS extension_schema FROM pg_extension e
 JOIN pg_namespace n ON n.oid=e.extnamespace WHERE e.extname='btree_gist';
SELECT name,default_version,installed_version FROM pg_available_extensions WHERE name='btree_gist';
SELECT has_database_privilege(current_database(),'CREATE') AS database_create,
 has_database_privilege(current_database(),'TEMP') AS temporary_objects;
SELECT n.nspname,has_schema_privilege(n.oid,'CREATE') AS can_create,
 has_schema_privilege(n.oid,'USAGE') AS can_use FROM pg_namespace n WHERE n.nspname='s466088';
SELECT rolsuper,rolcreaterole FROM pg_roles WHERE rolname=current_user;
SELECT current_database()='studs' AND current_user='s466088'
 AND current_setting('server_version_num')::integer>=140000
 AND has_database_privilege(current_database(),'TEMP')
 AND EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='s466088'
   AND has_schema_privilege(oid,'CREATE') AND has_schema_privilege(oid,'USAGE')) AS ready \gset
\if :ready
\echo PASS: studs / s466088, PostgreSQL 14+, schema CREATE/USAGE and TEMP
\else
\echo Refusing install: expected studs / s466088, PostgreSQL 14+, schema CREATE/USAGE and TEMP
DO $$ BEGIN RAISE EXCEPTION 'Helios check refused; see diagnostics above'; END $$;
\endif
SELECT EXISTS(SELECT 1 FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace
 WHERE e.extname='btree_gist' AND has_schema_privilege(n.oid,'USAGE')) AS use_gist,
 COALESCE((SELECT n.nspname FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace
 WHERE e.extname='btree_gist' AND has_schema_privilege(n.oid,'USAGE')), 'pg_catalog') AS extension_schema \gset
