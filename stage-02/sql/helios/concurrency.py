#!/usr/bin/env python3
"""Small real two-connection probes for Helios; no CREATEROLE or load benchmark.
Commits only uniquely labelled probe fixtures, then cancels/archives them.
"""
import argparse
import json
import subprocess
import time
import uuid
from pathlib import Path

PSQL = ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose']


def sql(query):
    result = subprocess.run(PSQL + ['-c', query], text=True, capture_output=True, timeout=30)
    if result.returncode:
        raise RuntimeError(result.stderr)
    return result.stdout.strip()


def run(output):
    if sql("SELECT current_database()='studs' AND current_user='s466088'") != 't':
        raise RuntimeError('Only studs / s466088 allowed')
    tag = 'LR-PROBE-' + uuid.uuid4().hex[:12]
    setup = f"""BEGIN;
    WITH x AS (INSERT INTO s466088.lr_app_user(login,full_name) VALUES('{tag}','Concurrency probe') RETURNING id)
      INSERT INTO s466088.lr_user_role SELECT id,'user' FROM x;
    WITH x AS (INSERT INTO s466088.lr_app_user(login,full_name) VALUES('{tag}-staff','Probe staff') RETURNING id)
      INSERT INTO s466088.lr_user_role SELECT id,'admin' FROM x;
    INSERT INTO s466088.lr_equipment_type(name) VALUES('{tag}');
    INSERT INTO s466088.lr_capability(name) VALUES('{tag}');
    INSERT INTO s466088.lr_type_capability SELECT t.id,c.id FROM s466088.lr_equipment_type t,
      s466088.lr_capability c WHERE t.name='{tag}' AND c.name='{tag}';
    INSERT INTO s466088.lr_equipment(type_id,inventory_no,name)
      SELECT id,'{tag}','Concurrency probe' FROM s466088.lr_equipment_type WHERE name='{tag}';
    SELECT s466088.lr_grant_admission(a.id,u.id,t.id,now()-interval '1 day',now()+interval '1 year','Probe')
      FROM s466088.lr_app_user a,s466088.lr_app_user u,s466088.lr_equipment_type t
      WHERE a.login='{tag}-staff' AND u.login='{tag}' AND t.name='{tag}';
    COMMIT;
    SELECT u.id,a.id,e.id,c.id FROM s466088.lr_app_user u,s466088.lr_app_user a,
      s466088.lr_equipment e,s466088.lr_capability c
      WHERE u.login='{tag}' AND a.login='{tag}-staff' AND e.inventory_no='{tag}' AND c.name='{tag}';"""
    user, staff, equipment, capability = map(int, sql(setup).splitlines()[-1].split('|'))
    results = []
    base = "date_trunc('day',now())+interval '70 days'"
    def bounds(offset):
        return f"{base}+interval '{offset} hours'", f"{base}+interval '{offset+1} hours'"
    def book(offset):
        start, end = bounds(offset)
        return f"SELECT s466088.lr_create_booking({user},{equipment},{capability},{start},{end},'{tag}')"
    def raw(offset):
        start, end = bounds(offset)
        return f"INSERT INTO s466088.lr_booking(user_id,equipment_id,capability_id,period,purpose) VALUES({user},{equipment},{capability},tstzrange({start},{end}),'{tag}')"
    def block(offset):
        start, end = bounds(offset)
        return f"SELECT s466088.lr_register_unavailability({staff},{equipment},'maintenance',{start},{end},'{tag}')"
    invariant = f"""SELECT NOT EXISTS(SELECT 1 FROM s466088.lr_booking a JOIN s466088.lr_booking b
      ON a.equipment_id=b.equipment_id AND a.id<b.id AND a.status='confirmed' AND b.status='confirmed'
      AND a.period && b.period::tstzrange WHERE a.equipment_id={equipment})
      AND NOT EXISTS(SELECT 1 FROM s466088.lr_booking b JOIN s466088.lr_unavailability u USING(equipment_id)
      WHERE b.equipment_id={equipment} AND b.status='confirmed' AND u.status<>'cancelled' AND b.period && u.period::tstzrange)"""

    def race(label, first, second, expected, isolation='READ COMMITTED', commit=True):
        app_a, app_b = tag + '-a', tag + '-b'
        a = subprocess.Popen(PSQL + ['-c', f"BEGIN ISOLATION LEVEL {isolation}; SET LOCAL application_name='{app_a}'; SET LOCAL statement_timeout='15s'; {first}; SELECT pg_sleep(1.5); {'COMMIT' if commit else 'ROLLBACK'};"], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        b = None
        try:
            deadline = time.monotonic() + 10
            while sql(f"SELECT count(*) FROM pg_stat_activity WHERE application_name='{app_a}' AND wait_event='PgSleep'") != '1':
                if a.poll() is not None or time.monotonic() > deadline:
                    raise RuntimeError('First connection did not hold the lock: ' + str(a.communicate()))
                time.sleep(.02)
            b = subprocess.Popen(PSQL + ['-c', f"BEGIN ISOLATION LEVEL {isolation}; SET LOCAL application_name='{app_b}'; SET LOCAL statement_timeout='15s'; {second}; COMMIT;"], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            blocked = False
            while a.poll() is None and b.poll() is None:
                if sql(f"SELECT count(*) FROM pg_stat_activity WHERE application_name='{app_b}' AND wait_event_type='Lock'") == '1':
                    blocked = True
                    break
                time.sleep(.02)
            out_a, err_a = a.communicate(timeout=20)
            out_b, err_b = b.communicate(timeout=20)
            if a.returncode or not blocked:
                raise RuntimeError(label + ': missing lock overlap ' + err_a + err_b)
            if expected == 'ok':
                if b.returncode: raise RuntimeError(err_b)
            elif not (b.returncode and expected in err_b):
                raise RuntimeError(label + ': expected ' + expected + ', got ' + err_b)
            if sql(invariant) != 't': raise RuntimeError(label + ': invariant failed')
            results.append({'test': label, 'isolation': isolation, 'first': 'commit' if commit else 'rollback',
                            'second': expected, 'observed_lock_wait': blocked, 'invariant': 'PASS'})
            print('PASS:', label, isolation, expected)
        finally:
            for process in [a, b]:
                if process is not None and process.poll() is None:
                    process.kill(); process.communicate()

    try:
        race('HC01 API overlap', book(0), book(0), '23P01')
        race('HC02 direct INSERT overlap', raw(3), raw(3), '23P01')
        race('HC03 API stale snapshot', book(6), book(6), '40001', 'REPEATABLE READ')
        race('HC04 direct INSERT stale snapshot', raw(9), raw(9), '40001', 'REPEATABLE READ')
        sql(book(12))
        moving = sql(f"SELECT id FROM s466088.lr_booking WHERE equipment_id={equipment} AND lower(period)={bounds(12)[0]}")
        update = f"UPDATE s466088.lr_booking SET period=tstzrange({bounds(15)[0]},{bounds(15)[1]}) WHERE id={moving}"
        race('HC05 direct UPDATE overlap', raw(15), update, '23P01')
        race('HC06 direct UPDATE stale snapshot', raw(18), update.replace('15 hours', '18 hours').replace('16 hours', '19 hours'), '40001', 'REPEATABLE READ')
        race('HC07 outage before booking', block(21), raw(21), '23514')
        race('HC08 booking before outage', raw(24), block(24), 'ok')
        race('HC09 rollback releases slot', raw(27), raw(27), 'ok', commit=False)
        # One multi-row statement must also see and reject its own first row.
        first = raw(30)
        multi = first + ',(' + first.split(' VALUES(', 1)[1]
        p = subprocess.run(PSQL + ['-c', 'BEGIN; ' + multi + '; COMMIT;'], text=True, capture_output=True)
        if not (p.returncode and '23P01' in p.stderr and sql(invariant) == 't'):
            raise RuntimeError('HC10 multi-row overlap: ' + p.stderr)
        results.append({'test':'HC10 multi-row INSERT overlap','second':'23P01','invariant':'PASS'})
        print('PASS: HC10 multi-row INSERT overlap 23P01')
    finally:
        # Append-only history is retained; no DELETE, CASCADE or schema reset.
        sql(f"""BEGIN;
        SELECT s466088.lr_cancel_booking({user},id,'Concurrency probe cleanup') FROM s466088.lr_booking
          WHERE equipment_id={equipment} AND status IN ('confirmed','needs_transfer');
        SELECT s466088.lr_edit_maintenance({staff},id,lower(period),upper(period),'Concurrency probe cleanup',true)
          FROM s466088.lr_unavailability WHERE equipment_id={equipment} AND kind='maintenance' AND status='active';
        UPDATE s466088.lr_equipment SET archived=true WHERE id={equipment};
        UPDATE s466088.lr_equipment_type SET archived=true WHERE name='{tag}';
        UPDATE s466088.lr_app_user SET active=false WHERE login IN ('{tag}','{tag}-staff');
        COMMIT;""")
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps({'fixture':tag,'cleanup':'cancelled and archived; audited history retained','results':results}, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('helios-concurrency.json'))
    run(parser.parse_args().output)
