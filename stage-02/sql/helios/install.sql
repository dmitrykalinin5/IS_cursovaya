\set ON_ERROR_STOP on
\ir version.sql
\ir preflight.sql
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='60s';
SELECT pg_advisory_xact_lock(hashtext('LabReserve:s466088'),1);
\ir fingerprint.sql
SELECT to_regclass('s466088.lr_deployment') IS NOT NULL AS installed \gset
\if :installed
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='s466088.lr_deployment'::regclass
   AND relkind='r' AND relowner=(SELECT oid FROM pg_roles WHERE rolname=current_user)
   AND obj_description(oid,'pg_class')='LabReserve deployment manifest v1') THEN
  RAISE EXCEPTION 'Unknown lr_deployment object; refusing overwrite';
 END IF;
END $$;
SELECT count(*)=1 AND COALESCE(bool_and(source_hash=:'source_hash'
 AND catalog_hash=pg_temp.lr_catalog_fingerprint() AND seeded),false) AS unchanged
 FROM s466088.lr_deployment \gset
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
CREATE TABLE s466088.lr_deployment (
 source_hash text NOT NULL, overlap_mode text NOT NULL CHECK(overlap_mode IN ('gist','trigger')),
 seeded boolean NOT NULL, catalog_hash text NOT NULL, installed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
COMMENT ON TABLE s466088.lr_deployment IS 'LabReserve deployment manifest v1';
REVOKE ALL ON TABLE s466088.lr_deployment FROM PUBLIC;
SET LOCAL search_path=s466088,pg_catalog;
\ir seed.sql
INSERT INTO s466088.lr_deployment(source_hash,overlap_mode,seeded,catalog_hash)
 VALUES(:'source_hash',CASE WHEN :'use_gist'::boolean THEN 'gist' ELSE 'trigger' END,true,pg_temp.lr_catalog_fingerprint());
\endif
COMMIT;
\ir smoke_tests.sql
