#!/usr/bin/env python3
"""Adapter safety checks, without a database or external packages."""
import tempfile
import unittest
from pathlib import Path
import build


class AdapterTest(unittest.TestCase):
    def test_setting_and_messages_are_not_schema_names(self):
        source = "SELECT set_config('labreserve.actor_id','1',true); -- booking\nRAISE EXCEPTION 'Keep booking history'; SELECT * FROM booking;"
        result = build.adapt(source)
        self.assertIn("'labreserve.actor_id'", result)
        self.assertIn("'Keep booking history'", result)
        self.assertIn('-- booking', result)
        self.assertIn('FROM lr_booking', result)

    def test_nested_dynamic_sql_and_table_name_literals(self):
        source = "DO $$ BEGIN EXECUTE 'SELECT labreserve.offer_alternatives($1,$2)'; IF TG_TABLE_NAME='repair' THEN SELECT * FROM booking; END IF; END $$;"
        result = build.adapt(source)
        self.assertIn("'SELECT s466088.lr_offer_alternatives($1,$2)'", result)
        self.assertIn("TG_TABLE_NAME='lr_repair'", result)
        self.assertIn('FROM lr_booking', result)

    def test_quoted_commands_keep_escaped_literals(self):
        result = build.adapt("SELECT pg_temp.reject('UPDATE booking SET purpose=''booking history''','23514','booking failed')")
        self.assertIn("'UPDATE lr_booking SET purpose=''booking history'''", result)
        self.assertIn("'booking failed'", result)

    def test_unknown_names_are_not_prefixed(self):
        self.assertEqual(build.adapt('SELECT equipment_id FROM other_lab;'), 'SELECT equipment_id FROM other_lab;')

    def test_both_modes_have_complete_owned_objects(self):
        for mode in [True, False]:
            text = build.schema(mode) + build.triggers(mode) + build.operations() + build.indexes(mode)
            self.assertEqual(text.count('CREATE TABLE lr_'), 17)
            self.assertEqual(text.count('CREATE FUNCTION lr_'), 32)
            self.assertEqual(text.count('CREATE TRIGGER lr_'), 25)
            self.assertEqual(text.count('SET search_path=s466088,pg_catalog,pg_temp;'), 32)
            for forbidden in ['CREATE SCHEMA', 'CREATE EXTENSION', 'ON ALL TABLES', 'ON ALL FUNCTIONS', 'REVOKE ALL ON SCHEMA']:
                self.assertNotIn(forbidden, text)
            if mode:
                self.assertIn('lr_ex_booking_overlap EXCLUDE', text)
            else:
                self.assertNotIn('EXCLUDE USING', text)
                self.assertIn("ERRCODE='23P01'", text)
                self.assertIn('b.id IS DISTINCT FROM NEW.id', text)
                self.assertNotIn('USING gist(equipment_id', text)

    def test_source_change_requires_adapter_review(self):
        with self.assertRaises(ValueError):
            build.once('unexpected source', 'known fragment', '')

    def test_bundle_is_deterministic_and_has_no_role_creation(self):
        with tempfile.TemporaryDirectory() as directory:
            one, two = Path(directory)/'one', Path(directory)/'two'
            build.build(one); build.build(two)
            self.assertEqual({p.name:p.read_bytes() for p in one.iterdir()}, {p.name:p.read_bytes() for p in two.iterdir()})
            self.assertNotIn('CREATE ROLE', (one/'assertions.sql').read_text())
            self.assertIn('ROLLBACK;', (one/'assertions.sql').read_text())


if __name__ == '__main__':
    unittest.main()
