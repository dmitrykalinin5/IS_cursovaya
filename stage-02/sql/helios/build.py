#!/usr/bin/env python3
"""Compile the shared SQL for studs.s466088; no database connection or secrets."""
import argparse
import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FILES = ['schema/01_tables.sql', 'schema/02_triggers.sql',
         'functions/03_operations.sql', 'indexes/04_indexes.sql', 'seeds/05_demo.sql']
SOURCES = {name: (ROOT / 'sql' / name).read_text() for name in FILES}
TABLES = re.findall(r'CREATE TABLE (\w+)', SOURCES[FILES[0]])
FUNCTIONS = re.findall(r'CREATE FUNCTION (\w+)', SOURCES[FILES[1]] + SOURCES[FILES[2]])
NAMES = set(TABLES + FUNCTIONS + ['time_window'])
for text in SOURCES.values():
    NAMES.update(re.findall(r'CREATE (?:UNIQUE )?INDEX (\w+)', text))
    NAMES.update(re.findall(r'CREATE TRIGGER (\w+)', text))
    NAMES.update(re.findall(r'CONSTRAINT (\w+)', text))
MAPPING = {name: 'lr_' + name for name in NAMES}
MAPPING['labreserve'] = 's466088'
# Lexical tokens distinguish identifiers, literals, comments and function bodies.
TOKEN = re.compile(r"(--[^\n]*|/\*.*?\*/|'(?:''|[^'])*'|\$\$.*?\$\$|[A-Za-z_][A-Za-z_0-9]*|.)", re.S)


def adapt(text):
    def token(match):
        value = match.group()
        if value.startswith((' --', '--', '/*')):
            return value
        if value.startswith('$$'):
            return '$$' + adapt(value[2:-2]) + '$$'
        if value.startswith("'"):
            literal = value[1:-1].replace("''", "'")
            if literal in MAPPING:
                literal = MAPPING[literal]
            elif re.match(r'^(SELECT|INSERT|UPDATE|DELETE|ALTER FUNCTION)\b', literal):
                literal = adapt(literal)
            # labreserve.actor_id and arbitrary messages remain untouched.
            return "'" + literal.replace("'", "''") + "'"
        return MAPPING.get(value, value)
    return TOKEN.sub(token, text)


def once(text, old, new):
    if text.count(old) != 1:
        raise ValueError('Shared SQL changed; review Helios adapter: ' + old[:70])
    return text.replace(old, new)


def schema(gist):
    text = SOURCES[FILES[0]]
    text = once(text, 'CREATE EXTENSION IF NOT EXISTS btree_gist;\nCREATE SCHEMA labreserve;\nSET search_path = labreserve, public;\n', '')
    if not gist:
        text = once(text, ",\n CONSTRAINT ex_booking_overlap EXCLUDE USING gist\n   (equipment_id WITH =, (period::tstzrange) WITH &&) WHERE (status='confirmed')", '')
    return adapt(text)


def triggers(gist):
    text = SOURCES[FILES[1]]
    text = once(text, 'SET search_path=labreserve,public;\n', '')
    if not gist:
        text = once(text, " IF NEW.status='confirmed' THEN", """ IF NEW.status='confirmed' THEN
  -- VOLATILE trigger: fresh RC snapshot AFTER lock_equipment's UPDATE.
  IF EXISTS(SELECT 1 FROM booking b WHERE b.equipment_id=NEW.equipment_id
     AND b.status='confirmed' AND b.id IS DISTINCT FROM NEW.id
     AND b.period && NEW.period::tstzrange) THEN
   RAISE EXCEPTION 'Conflicting confirmed booking' USING ERRCODE='23P01';
  END IF;""")
    start = text.index('DO $$ DECLARE t text; BEGIN')
    end = text.index('END $$;', start) + len('END $$;')
    audited = ['app_user', 'user_role', 'equipment_type', 'capability', 'type_capability',
               'equipment', 'admission', 'booking', 'alternative', 'unavailability',
               'fault_report', 'repair', 'use_session']
    # Explicit names avoid a schema-wide loop and dynamic trigger name collisions.
    audit = '\n'.join(f'CREATE TRIGGER lr_audit_{t} AFTER INSERT OR UPDATE OR DELETE ON {t} FOR EACH ROW EXECUTE FUNCTION audit_change();' for t in audited)
    return adapt(text[:start] + audit + text[end:])


def operations():
    text = SOURCES[FILES[2]]
    text = once(text, 'SET search_path=labreserve,public;\n', '')
    # Replace schema-wide ALTER/REVOKE with statements on declared objects only.
    start = text.index('DO $$ DECLARE f record; BEGIN')
    text = text[:start]
    signatures = re.findall(r'CREATE FUNCTION (\w+)\((.*?)\)\s*RETURNS', text, re.S)
    signatures += re.findall(r'CREATE FUNCTION (\w+)\((.*?)\)\s*RETURNS', SOURCES[FILES[1]], re.S)
    definers = {'create_booking', 'request_booking', 'cancel_booking', 'select_alternative',
                'report_fault', 'register_unavailability', 'edit_maintenance',
                'resolve_unavailability', 'open_session', 'close_session',
                'offer_alternatives', 'create_reminders', 'grant_admission', 'revoke_admission'}
    security = []
    for name, args in signatures:
        types = ','.join(arg.strip().split()[1] for arg in args.split(',') if arg.strip())
        signature = f's466088.lr_{name}({types})'
        security.append(f'ALTER FUNCTION {signature} SET search_path=s466088,pg_catalog,pg_temp;')
        if name in definers:
            security.append(f'ALTER FUNCTION {signature} SECURITY DEFINER;')
        security.append(f'REVOKE ALL ON FUNCTION {signature} FROM PUBLIC;')
    security += [f'REVOKE ALL ON TABLE s466088.lr_{t} FROM PUBLIC;' for t in TABLES]
    return adapt(text) + '\n'.join(security) + '\n'


def indexes(gist):
    text = once(SOURCES[FILES[3]], 'SET search_path=labreserve,public;\n', '')
    if not gist:
        # Built-in range GiST; equipment/user filters remain SQL predicates.
        for columns in ['user_id,type_id,(valid_during::tstzrange)', 'equipment_id,(period::tstzrange)']:
            text = text.replace('USING gist(' + columns + ')', 'USING gist(' + columns.split(',')[-1] + ')')
    return adapt(text)


def build(destination):
    destination.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256(Path(__file__).read_bytes() + b''.join(v.encode() for v in SOURCES.values())
                            + b''.join(p.read_bytes() for p in [Path(__file__).parent / n for n in ['preflight.sql', 'install.sql', 'smoke_tests.sql', 'fingerprint.sql']])).hexdigest()
    for mode in ['gist', 'trigger']:
        use_gist = mode == 'gist'
        (destination / f'{mode}.sql').write_text(schema(use_gist) + triggers(use_gist) + operations() + indexes(use_gist))
    seed = SOURCES[FILES[4]]
    seed = once(seed, '\\set ON_ERROR_STOP on\nBEGIN;\nSET search_path=labreserve,public;\n', '')
    seed = once(seed, 'COMMIT;\n', '')
    (destination / 'seed.sql').write_text(adapt(seed))
    # Reuse the 57 business assertions; omit CREATEROLE and local-only ACL tests.
    tests = (ROOT / 'sql/tests/06_assertions.sql').read_text().split('CREATE ROLE labreserve_stage02_probe')[0]
    tests = tests.replace("table_schema='labreserve' AND table_type='BASE TABLE'", "table_schema='labreserve' AND table_type='BASE TABLE' AND table_name LIKE 'lr\\_%' ESCAPE '\\' AND table_name<>'lr_deployment'")
    (destination / 'assertions.sql').write_text(adapt(tests) + 'ROLLBACK;\n')
    for name in ['preflight.sql', 'install.sql', 'smoke_tests.sql', 'fingerprint.sql']:
        (destination / name).write_text((Path(__file__).parent / name).read_text())
    (destination / 'version.sql').write_text(f"\\set source_hash {digest}\n")
    print('Built Helios bundle:', destination, 'source', digest)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    build(parser.parse_args().output)
