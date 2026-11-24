#!/usr/bin/env python3
"""Compare each explicit index on a disposable Unix-socket clone of Helios."""
import json
import os
from pathlib import Path
from statistics import median
import subprocess
import sys

WARMUP = 3
SAMPLES = 21
TABLES = ('equipment', 'type_capability', 'admission', 'booking', 'unavailability',
          'alternative', 'fault_report', 'repair', 'notification')
PSQL = ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1']

if len(sys.argv) != 2 or not os.environ.get('PGHOST', '').startswith('/tmp/'):
    sys.exit('Usage: PGHOST=/tmp/<local socket> PGDATABASE=studs PGUSER=s466088 python3 '
             '11_index_benchmark.py <result.json>')

GUARD = """
DO $$ BEGIN
 IF inet_server_addr() IS NOT NULL OR current_database()<>'studs' OR current_user<>'s466088'
    OR (SELECT count(*) FROM s466088.lr_equipment WHERE inventory_no LIKE 'BULK-LR-%')<>120 THEN
  RAISE EXCEPTION 'Expected the disposable Unix-socket Helios clone with BULK-LR data';
 END IF;
END $$;
SET search_path=s466088,pg_catalog,pg_temp;
"""


def psql(sql):
    return subprocess.run(PSQL, input=GUARD + sql, text=True, check=True,
                          stdout=subprocess.PIPE).stdout.splitlines()


def literal(value):
    return "'" + value.replace("'", "''") + "'"


def nodes(plan):
    yield plan
    for child in plan.get('Plans', []):
        yield from nodes(child)


row = psql("""
SELECT jsonb_build_object(
 'server',current_setting('server_version'),
 'usr',(SELECT id FROM lr_app_user WHERE login='bulk-lr-001'),
 'unit',(SELECT id FROM lr_equipment WHERE inventory_no='BULK-LR-001'),
 'type',(SELECT type_id FROM lr_equipment WHERE inventory_no='BULK-LR-001'),
 'cap',(SELECT id FROM lr_capability WHERE name='Печать PLA'),
 'booking',(SELECT b.id FROM lr_booking b JOIN lr_equipment e ON e.id=b.equipment_id
    WHERE e.inventory_no='BULK-LR-001' AND b.status='confirmed' AND lower(b.period)>now()
    ORDER BY lower(b.period) LIMIT 1),
 'period',(SELECT b.period FROM lr_booking b JOIN lr_equipment e ON e.id=b.equipment_id
    WHERE e.inventory_no='BULK-LR-001' AND b.status='confirmed' AND lower(b.period)>now()
    ORDER BY lower(b.period) LIMIT 1),
 'future',now(),
 'alt',(SELECT min(booking_id) FROM lr_alternative WHERE state='offered'),
 'event',(SELECT min(unavailability_id) FROM lr_repair),
 'fault_unit',(SELECT min(equipment_id) FROM lr_fault_report));
""")
args = json.loads(row[0])
if any(v is None for v in args.values()):
    sys.exit('Missing benchmark fixtures; install the base demo and load BULK-LR first.')
args['period'], args['future'] = map(literal, (args['period'], args['future']))
cases = [
    ('ix_equipment_type_active', 'equipment', 'SELECT id FROM lr_equipment WHERE type_id={type} AND NOT archived ORDER BY id LIMIT 10'),
    ('ix_type_capability_reverse', 'type_capability', 'SELECT type_id FROM lr_type_capability WHERE capability_id={cap} ORDER BY type_id'),
    ('ix_admission_valid', 'admission', 'SELECT id FROM lr_admission WHERE user_id={usr} AND type_id={type} AND revoked_at IS NULL AND valid_during @> {period}::tstzrange'),
    ('ix_booking_user_future', 'booking', "SELECT id,period FROM lr_booking WHERE user_id={usr} AND status IN ('confirmed','needs_transfer') AND lower(period)>{future}::timestamptz ORDER BY lower(period) LIMIT 10"),
    ('ix_booking_equipment_period', 'booking', 'SELECT id FROM lr_booking WHERE equipment_id={unit} AND period && {period}::tstzrange'),
    ('ix_unavailability_period', 'unavailability', "SELECT id FROM lr_unavailability WHERE equipment_id={fault_unit} AND status<>'cancelled' AND period && {period}::tstzrange"),
    ('ix_alternative_booking_rank', 'alternative', "SELECT id,period FROM lr_alternative WHERE booking_id={alt} AND state='offered' ORDER BY priority,lower(period) LIMIT 12"),
    ('ix_fault_equipment_time', 'fault_report', 'SELECT id,reported_at FROM lr_fault_report WHERE equipment_id={fault_unit} ORDER BY reported_at DESC LIMIT 10'),
    ('ix_repair_unavailability', 'repair', 'SELECT id FROM lr_repair WHERE unavailability_id={event} ORDER BY lower(period) DESC LIMIT 10'),
    ('ix_notification_unread', 'notification', 'SELECT id,created_at FROM lr_notification WHERE user_id={usr} AND read_at IS NULL ORDER BY created_at LIMIT 10'),
    ('ux_notification_reminder', 'notification', "SELECT id FROM lr_notification WHERE booking_id={booking} AND kind='reminder'"),
]

sql = ["""
BEGIN;
SELECT lr_create_reminders(now()+interval '20 days') AS ignored \\gset
CREATE FUNCTION pg_temp.samples(statement text, warmup int, n int) RETURNS SETOF jsonb
LANGUAGE plpgsql AS $$
DECLARE result json;
BEGIN
 FOR i IN 1..warmup+n LOOP
  EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, TIMING OFF, FORMAT JSON) '||statement INTO result;
  IF i>warmup THEN RETURN NEXT (result->0)::jsonb; END IF;
 END LOOP;
END $$;
"""]
for table in TABLES:
    sql.append(f'ANALYZE lr_{table};')
    sql.append(f"SELECT jsonb_build_object('table','{table}','rows',count(*)) FROM lr_{table};")
for index, _, query in cases:
    query = literal(query.format(**args))
    sql.append('SAVEPOINT benchmark;')
    for mode in ('with', 'without'):
        if mode == 'without':
            sql.append(f'DROP INDEX s466088.lr_{index};')
        sql.append(f"SELECT jsonb_build_object('index','{index}','mode','{mode}','plan',p) "
                   f'FROM pg_temp.samples({query},{WARMUP},{SAMPLES}) p;')
    sql.append('ROLLBACK TO SAVEPOINT benchmark; RELEASE SAVEPOINT benchmark;')
sql.append('ROLLBACK;')

counts, samples = {}, {}
for line in psql('\n'.join(sql)):
    data = json.loads(line)
    if 'table' in data:
        counts[data['table']] = data['rows']
    else:
        samples.setdefault((data['index'], data['mode']), []).append(data['plan'])

output = {'postgresql': args['server'], 'warmups': WARMUP, 'samples_per_mode': SAMPLES,
          'table_rows': counts, 'indexes': []}
for index, table, query in cases:
    result = {'name': index, 'table': table, 'query': query.format(**args)}
    for mode in ('with', 'without'):
        plans = samples[(index, mode)]
        assert len(plans) == SAMPLES
        times = [float(p['Execution Time']) for p in plans]
        used = [any(n.get('Index Name') == 'lr_' + index for n in nodes(p['Plan'])) for p in plans]
        assert mode == 'with' or not any(used)
        result[mode] = {
            'median_ms': median(times), 'times_ms': times, 'target_used': sum(used),
            'execution_plan': sorted(plans, key=lambda p: p['Execution Time'])[SAMPLES // 2],
        }
    assert result['with']['execution_plan']['Plan']['Actual Rows'] == result['without']['execution_plan']['Plan']['Actual Rows']
    output['indexes'].append(result)
Path(sys.argv[1]).write_text(json.dumps(output, ensure_ascii=False, indent=2) + '\n')
