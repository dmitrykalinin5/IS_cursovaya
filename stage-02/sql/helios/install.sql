\set ON_ERROR_STOP on
\ir version.sql
\ir preflight.sql
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='60s';
SELECT pg_advisory_xact_lock(hashtext('LabReserve:s466088'),1);
\ir fingerprint.sql
\ir manifest.sql
SELECT pg_temp.lr_manifest() IS NOT NULL AS installed \gset
\if :installed
SELECT COALESCE((pg_temp.lr_manifest()->>'source_hash'=:'source_hash')
 AND (pg_temp.lr_manifest()->>'catalog_hash'=pg_temp.lr_catalog_fingerprint())
 AND (pg_temp.lr_manifest()->>'seeded')::boolean,false) AS unchanged \gset
\if :unchanged
\echo PASS: same source and intact objects; existing data preserved, seed skipped
\else
\echo Refusing install: source changed, incomplete marker or modified objects. Use a reviewed migration.
DO $$ BEGIN RAISE EXCEPTION 'Helios check refused; see diagnostics above'; END $$;
\endif
\else
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='s466088' AND c.relname LIKE 'lr\_%' ESCAPE '\')
 OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='s466088' AND p.proname LIKE 'lr\_%' ESCAPE '\')
 OR EXISTS(SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace
   WHERE n.nspname='s466088' AND (t.typname LIKE 'lr\_%' ESCAPE '\' OR t.typname LIKE '\_lr\_%' ESCAPE '\'))
 OR EXISTS(SELECT 1 FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace
   WHERE n.nspname='s466088' AND c.conname LIKE 'lr\_%' ESCAPE '\') THEN
  RAISE EXCEPTION 'Existing lr_ objects without deployment marker; refusing overwrite';
 END IF;
END $$;
SET LOCAL search_path=s466088,pg_catalog,:"extension_schema";
\if :use_gist
\echo Installing EXCLUDE / btree_gist variant (existing extension only)
\ir gist.sql
\else
\echo Installing serialized overlap trigger variant (no extension privileges needed)
\ir trigger.sql
\endif
SET LOCAL search_path=s466088,pg_catalog;
\ir seed.sql
SELECT format('COMMENT ON TABLE s466088.lr_app_user IS %L',E'LabReserve manifest v2\n'||jsonb_build_object(
 'source_hash',:'source_hash','overlap_mode',CASE WHEN :'use_gist'::boolean THEN 'gist' ELSE 'trigger' END,
 'seeded',true,'catalog_hash',pg_temp.lr_catalog_fingerprint(),'installed_at',clock_timestamp())::text) \gexec
\endif
COMMIT;
\ir smoke_tests.sql
