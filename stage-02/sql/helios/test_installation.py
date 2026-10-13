#!/usr/bin/env python3
"""Integration safety probes. ONLY a private disposable test cluster.
Requires PGHOST=/tmp/labreserve-*, PGUSER=lr_test_admin, database studs.
Never run this administrative fixture test on Helios.
"""
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PSQL = ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-d', 'studs']


def sql(query):
    p = subprocess.run(PSQL + ['-c', query], capture_output=True, text=True, timeout=30)
    if p.returncode: raise RuntimeError(p.stderr)
    return p.stdout.strip()


def deploy(expected=None):
    env = dict(os.environ, PGDATABASE='studs', PGUSER='s466088')
    p = subprocess.run(['bash', str(ROOT/'scripts/deploy_helios.sh')], env=env, capture_output=True, text=True, timeout=90)
    if expected:
        if p.returncode == 0 or expected not in p.stdout+p.stderr:
            raise RuntimeError('Expected refusal: ' + expected + '\n' + p.stdout + p.stderr)
    elif p.returncode:
        raise RuntimeError(p.stdout+p.stderr)
    return p


def snapshot():
    return sql("""SELECT jsonb_build_object(
    'tables',(SELECT jsonb_object_agg(relname,cnt) FROM
      (SELECT 'users' relname,count(*) cnt FROM s466088.lr_app_user UNION ALL
       SELECT 'bookings',count(*) FROM s466088.lr_booking UNION ALL
       SELECT 'audit',count(*) FROM s466088.lr_audit_event) s),
    'other_rows',(SELECT jsonb_agg(x) FROM s466088.other_lab x),
    'other_relation',(SELECT row(relowner,relacl)::text FROM pg_class WHERE oid='s466088.other_lab'::regclass),
    'other_function',(SELECT pg_get_functiondef(oid)||COALESCE(proacl::text,'')||proowner FROM pg_proc
      WHERE oid='s466088.other_lab_fn()'::regprocedure),
    'schema_acl',(SELECT nspacl::text FROM pg_namespace WHERE nspname='s466088'))""")


def main():
    if not os.environ.get('PGHOST','').startswith('/tmp/labreserve-') or os.environ.get('PGUSER') != 'lr_test_admin':
        raise RuntimeError('Private test cluster and lr_test_admin required')
    if sql("SELECT current_user='lr_test_admin' AND inet_server_addr() IS NULL") != 't':
        raise RuntimeError('Unexpected server identity')
    results = []
    def passed(label):
        results.append(label); print('PASS:',label)
    before = snapshot()
    deploy()
    if snapshot() != before: raise RuntimeError('Repeat changed data or other objects')
    passed('I01 repeat preserves data, foreign rows, ACL and function definition')
    sql('CREATE TABLE s466088.lr_foreign_collision(id integer)')
    try:
        deploy('modified objects')
        if sql("SELECT to_regclass('s466088.lr_foreign_collision') IS NOT NULL") != 't':
            raise RuntimeError('Collision table removed')
        passed('I02 existing prefix collision retained, install refused')
    finally: sql('DROP TABLE s466088.lr_foreign_collision')
    sql('ALTER TABLE s466088.lr_booking DISABLE TRIGGER lr_booking_guard')
    try:
        deploy('modified objects')
        passed('I03 disabled business trigger detected')
    finally: sql('ALTER TABLE s466088.lr_booking ENABLE TRIGGER lr_booking_guard')
    original_hash = sql('SELECT source_hash FROM s466088.lr_deployment')
    sql("UPDATE s466088.lr_deployment SET source_hash='changed-source'")
    try:
        deploy('source changed')
        passed('I04 changed source marker cannot trigger overwrite')
    finally: sql(f"UPDATE s466088.lr_deployment SET source_hash='{original_hash}'")
    sql('ALTER TABLE s466088.lr_deployment RENAME TO deployment_probe_backup')
    try:
        deploy('Existing lr_ objects without deployment marker')
        passed('I07 objects without manifest are not overwritten')
    finally: sql('ALTER TABLE s466088.deployment_probe_backup RENAME TO lr_deployment')
    # Wrong DB and user must fail before touching a schema.
    for field, value in [('PGDATABASE','postgres'),('PGUSER','lr_test_admin')]:
        env=dict(os.environ, PGDATABASE='studs', PGUSER='s466088'); env[field]=value
        p=subprocess.run(['bash',str(ROOT/'scripts/deploy_helios.sh')],env=env,capture_output=True,text=True)
        if not p.returncode or 'Only studs / s466088 allowed' not in p.stderr:
            raise RuntimeError('Unsafe connection accepted')
    p=subprocess.run(PSQL+['-f',str(ROOT/'sql/helios/preflight.sql')],capture_output=True,text=True)
    if p.returncode != 3 or 'Helios check refused' not in p.stderr:
        raise RuntimeError('SQL preflight did not return an error status')
    passed('I05 wrong database/user refused in shell and SQL')
    deploy()
    if snapshot() != before: raise RuntimeError('Safety probes changed foreign/application data')
    passed('I06 clean install verification succeeds after restoring test fixtures')
    out=Path(os.environ.get('TEST_OUTPUT',str(ROOT/'output/helios')))
    out.mkdir(parents=True,exist_ok=True)
    (out/'installation-safety.json').write_text(json.dumps({'results':results,'before':json.loads(before),'after':json.loads(snapshot())},ensure_ascii=False,indent=2)+'\n')


if __name__ == '__main__':
    main()
