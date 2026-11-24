\set ON_ERROR_STOP on
\ir version.sql
\ir preflight.sql
BEGIN;
SET LOCAL lock_timeout='10s';
SELECT pg_advisory_xact_lock(hashtext('LabReserve:s466088'),1);
\ir fingerprint.sql
\ir manifest.sql
SET LOCAL search_path=s466088,pg_catalog,pg_temp;
SELECT COALESCE((pg_temp.lr_manifest()->>'seeded')::boolean
 AND pg_temp.lr_manifest()->>'catalog_hash'=pg_temp.lr_catalog_fingerprint()
 AND pg_temp.lr_manifest()->>'overlap_mode' IN ('gist','trigger'),false) AS intact,
 COALESCE(pg_temp.lr_manifest()->>'source_hash'=:'source_hash',false) AS current_version,
 COALESCE(pg_temp.lr_manifest()->>'source_hash'=
  '0cbca75192457629be4c4526c8fe5cfba6fd839b9191b16d6c07dba8fdcbc387',false) AS previous_version,
 COALESCE(pg_temp.lr_manifest()->>'overlap_mode'='gist',false) AS installed_gist
\gset
\if :intact
\else
DO $$ BEGIN RAISE EXCEPTION 'Missing deployment manifest or changed catalogue'; END $$;
\endif
\if :current_version
\echo PASS: booking request already installed
\elif :previous_version
\if :installed_gist
\ir booking-guard-gist.sql
\else
\ir booking-guard-trigger.sql
\endif
\ir booking-request.sql
SELECT format('COMMENT ON TABLE s466088.lr_app_user IS %L',
 E'LabReserve manifest v2\n'||(pg_temp.lr_manifest()||jsonb_build_object(
 'source_hash',:'source_hash','catalog_hash',pg_temp.lr_catalog_fingerprint()))::text)
\gexec
\echo PASS: booking request installed
\else
DO $$ BEGIN RAISE EXCEPTION 'Unsupported source version for this upgrade'; END $$;
\endif
COMMIT;
