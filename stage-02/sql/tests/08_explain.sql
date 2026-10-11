\set ON_ERROR_STOP on
BEGIN;
SET search_path=labreserve,public;
-- Representative synthetic catalogue: 1,000 machines, 20,000 nonoverlapping bookings.
INSERT INTO equipment(type_id,inventory_no,name)
 SELECT 1,'BENCH-'||g,'Benchmark FDM '||g FROM generate_series(1,1000) g;
INSERT INTO booking(user_id,equipment_id,capability_id,period,purpose)
 SELECT 1,e.id,1,tstzrange(date_trunc('day',now())+interval '100 days'+g*interval '2 hours',
 date_trunc('day',now())+interval '100 days'+g*interval '2 hours'+interval '1 hour'),'Benchmark'
 FROM equipment e CROSS JOIN generate_series(0,19) g WHERE inventory_no LIKE 'BENCH-%';
ANALYZE equipment; ANALYZE booking; ANALYZE admission; ANALYZE unavailability;
\echo Q1 overlap (GiST enforced partial index)
EXPLAIN (ANALYZE,BUFFERS) SELECT id FROM booking
 WHERE equipment_id=(SELECT id FROM equipment WHERE inventory_no='BENCH-500')
 AND status='confirmed' AND period && tstzrange(date_trunc('day',now())+interval '100 days 10 hours',date_trunc('day',now())+interval '100 days 11 hours');
\echo Q2 future bookings by owner (partial B-tree)
EXPLAIN (ANALYZE,BUFFERS) SELECT id,period FROM booking
 WHERE user_id=1 AND status IN ('confirmed','needs_transfer') AND lower(period)>now() ORDER BY lower(period) LIMIT 20;
\echo Q3 type/function catalogue (B-tree)
EXPLAIN (ANALYZE,BUFFERS) SELECT e.id FROM equipment e JOIN type_capability c ON c.type_id=e.type_id
 WHERE c.capability_id=1 AND NOT e.archived ORDER BY e.id LIMIT 20;
\echo Q4 admission coverage (small relation may favor sequential scan)
EXPLAIN (ANALYZE,BUFFERS) SELECT id FROM admission WHERE user_id=1 AND type_id=1 AND revoked_at IS NULL
 AND valid_during @> tstzrange(now()+interval '1 day',now()+interval '2 days');
\echo Q5 audit history
EXPLAIN (ANALYZE,BUFFERS) SELECT id FROM audit_event WHERE table_name='booking' AND record_key->>'id'='1' ORDER BY occurred_at DESC LIMIT 20;
\echo Q1 comparison without secondary query index (EXCLUDE still exists)
DROP INDEX ix_booking_equipment_period;
EXPLAIN (ANALYZE,BUFFERS) SELECT id FROM booking WHERE equipment_id=(SELECT id FROM equipment WHERE inventory_no='BENCH-500')
 AND status='confirmed' AND period && tstzrange(date_trunc('day',now())+interval '100 days 10 hours',date_trunc('day',now())+interval '100 days 11 hours');
ROLLBACK;
