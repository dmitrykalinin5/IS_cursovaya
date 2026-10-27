#!/usr/bin/env python3
"""Build an additive migration from the recorded 13 October Helios deployment."""
import argparse,re
from pathlib import Path
import build
OLD='4e8d1ab392deb1a9dd7421b32eeee882bf6fa613f17297ba29744456c8a50fed'
p=argparse.ArgumentParser(description=__doc__);p.add_argument('output',type=Path);args=p.parse_args()
build.build(args.output)
new=re.search(r'\\set source_hash (\w+)',(args.output/'version.sql').read_text()).group(1)
operation=re.search(r'CREATE FUNCTION resolve_unavailability\(.*?END \$\$;',build.SOURCES['functions/03_operations.sql'],re.S).group()
operation=build.adapt(operation.replace('CREATE FUNCTION','CREATE OR REPLACE FUNCTION',1))
text=r'''\set ON_ERROR_STOP on
\ir preflight.sql
BEGIN;
SET LOCAL lock_timeout='10s';
SELECT pg_advisory_xact_lock(hashtext('LabReserve:s466088'),1);
\ir fingerprint.sql
SET LOCAL search_path=s466088,pg_catalog,pg_temp;
SELECT count(*)=1 AND bool_and(source_hash='NEW_HASH' AND seeded AND catalog_hash=pg_temp.lr_catalog_fingerprint()) AS already_current FROM lr_deployment \gset
\if :already_current
\echo PASS: approved model migration already applied
\else
DO $$ BEGIN
 IF current_database()<>'studs' OR current_user<>'s466088' THEN RAISE EXCEPTION 'Unexpected target'; END IF;
 IF NOT EXISTS(SELECT 1 FROM lr_deployment WHERE source_hash='OLD_HASH' AND seeded
   AND catalog_hash=pg_temp.lr_catalog_fingerprint()) THEN
  RAISE EXCEPTION 'Unrecognised source or changed catalogue; migration refused';
 END IF;
END $$;
LOCK TABLE lr_repair,lr_unavailability IN ACCESS EXCLUSIVE MODE;
ALTER TABLE lr_repair ADD COLUMN work_kind text;
ALTER TABLE lr_repair DISABLE TRIGGER lr_repair_immutable;
UPDATE lr_repair r SET work_kind=CASE WHEN u.kind='maintenance' THEN 'maintenance' ELSE 'repair' END
 FROM lr_unavailability u WHERE u.id=r.unavailability_id;
ALTER TABLE lr_repair ENABLE TRIGGER lr_repair_immutable;
ALTER TABLE lr_repair ALTER COLUMN work_kind SET NOT NULL;
ALTER TABLE lr_repair ADD CONSTRAINT lr_repair_work_kind_check CHECK(length(trim(work_kind))>0);
OPERATION
ALTER FUNCTION lr_resolve_unavailability(bigint,bigint,text) SECURITY DEFINER;
ALTER FUNCTION lr_resolve_unavailability(bigint,bigint,text) SET search_path=s466088,pg_catalog,pg_temp;
REVOKE ALL ON FUNCTION lr_resolve_unavailability(bigint,bigint,text) FROM PUBLIC;
UPDATE lr_deployment SET source_hash='NEW_HASH',catalog_hash=pg_temp.lr_catalog_fingerprint();
\echo PASS: approved model migrated without deleting tables or reseeding
\endif
COMMIT;
'''.replace('OLD_HASH',OLD).replace('NEW_HASH',new).replace('OPERATION',operation)
(args.output/'migrate_approved.sql').write_text(text)
(args.output/'approved-model-tests.sql').write_text(build.adapt((build.ROOT/'sql/tests/09_approved_model.sql').read_text()))
(args.output/'defense.sql').write_text(build.adapt((build.ROOT/'sql/demo/defense.sql').read_text()))
