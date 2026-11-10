#!/usr/bin/env python3
"""Build a transactional migration from the recorded 17-table deployment to the approved 15 tables."""
import argparse,re
from pathlib import Path
import build
OLD='c7a0904040e4e0342f9f3cbff2a9dad7b7ffdd20e62382fea08f705f8667f12d'
p=argparse.ArgumentParser(description=__doc__);p.add_argument('output',type=Path);args=p.parse_args()
build.build(args.output)
new=re.search(r'\\set source_hash (\w+)',(args.output/'version.sql').read_text()).group(1)
ops=build.operations().replace('CREATE FUNCTION ','CREATE OR REPLACE FUNCTION ')
text=r'''\set ON_ERROR_STOP on
\ir preflight.sql
BEGIN;
SET LOCAL lock_timeout='10s';
SELECT pg_advisory_xact_lock(hashtext('LabReserve:s466088'),1);
\ir fingerprint.sql
\ir manifest.sql
SET LOCAL search_path=s466088,pg_catalog,pg_temp;
SELECT COALESCE(pg_temp.lr_manifest()->>'source_hash'='NEW_HASH'
 AND pg_temp.lr_manifest()->>'catalog_hash'=pg_temp.lr_catalog_fingerprint(),false) AS already_current \gset
\if :already_current
\echo PASS: 15-table migration already applied
\else
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='s466088.lr_deployment'::regclass
  AND relowner=(SELECT oid FROM pg_roles WHERE rolname=current_user)
  AND obj_description(oid,'pg_class')='LabReserve deployment manifest v1') THEN
  RAISE EXCEPTION 'Unknown installation marker';
 END IF;
 IF (SELECT count(*) FROM lr_deployment)<>1 OR NOT EXISTS(SELECT 1 FROM lr_deployment
  WHERE source_hash='OLD_HASH' AND seeded AND catalog_hash=pg_temp.lr_catalog_fingerprint()) THEN
  RAISE EXCEPTION 'Unrecognised source or changed catalogue; migration refused';
 END IF;
END $$;
SELECT overlap_mode AS old_mode,installed_at::text AS old_installed FROM lr_deployment \gset
LOCK TABLE lr_app_user,lr_user_role,lr_equipment_type,lr_capability,lr_type_capability,
 lr_equipment,lr_admission,lr_booking,lr_alternative,lr_unavailability,lr_fault_report,
 lr_repair,lr_use_session,lr_notification IN ACCESS EXCLUSIVE MODE;
DROP_AUDIT_TRIGGERS
DROP FUNCTION lr_equipment_metrics(tstzrange);
OPERATIONS
DROP TABLE lr_audit_event;
DROP TABLE lr_conflict_event;
DROP FUNCTION lr_audit_change();
DROP TABLE lr_deployment;
SELECT format('COMMENT ON TABLE s466088.lr_app_user IS %L',E'LabReserve manifest v2\n'||jsonb_build_object(
 'source_hash','NEW_HASH','overlap_mode',:'old_mode','seeded',true,
 'catalog_hash',pg_temp.lr_catalog_fingerprint(),'installed_at',:'old_installed')::text) \gexec
\echo PASS: 15 model tables; journals removed; installation metadata stored as comment
\endif
COMMIT;
'''.replace('OLD_HASH',OLD).replace('NEW_HASH',new).replace('OPERATIONS',ops)
audited=['app_user','user_role','equipment_type','capability','type_capability','equipment','admission','booking','alternative','unavailability','fault_report','repair','use_session']
text=text.replace('DROP_AUDIT_TRIGGERS','\n'.join(f'DROP TRIGGER lr_audit_{t} ON lr_{t};' for t in audited))
(args.output/'migrate_model15.sql').write_text(text)
(args.output/'approved-model-tests.sql').write_text(build.adapt((build.ROOT/'sql/tests/09_approved_model.sql').read_text()))
(args.output/'defense.sql').write_text(build.adapt((build.ROOT/'sql/demo/defense.sql').read_text()))
