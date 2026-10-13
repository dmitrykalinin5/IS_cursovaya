\set ON_ERROR_STOP on
SELECT current_database()='studs' AND current_user='s466088' AS safe \gset
\if :safe
\else
\echo Refusing checks outside studs / s466088
DO $$ BEGIN RAISE EXCEPTION 'Helios check refused; see diagnostics above'; END $$;
\endif
BEGIN;
SET LOCAL statement_timeout='30s';
SET LOCAL lock_timeout='10s';
SET LOCAL search_path=pg_catalog;
CREATE FUNCTION pg_temp.ok(condition boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF condition IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %',label; END IF;
 RAISE NOTICE 'PASS: %',label; END $$;
CREATE FUNCTION pg_temp.reject(command text,expected text,label text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE code text;
BEGIN
 BEGIN EXECUTE command; EXCEPTION WHEN OTHERS THEN code:=SQLSTATE; END;
 PERFORM pg_temp.ok(code=expected,label||' SQLSTATE='||COALESCE(code,'no error'));
END $$;
DO $$
DECLARE u bigint; staff bigint; typ bigint; cap bigint; e bigint; e2 bigint;
 b bigint; b2 bigint; fault bigint; outage bigint; sess bigint; choice bigint;
 base timestamptz:=date_trunc('day',now())+interval '60 days';
 tag text:='probe-'||txid_current();
BEGIN
 PERFORM pg_temp.ok((SELECT count(*)=17 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='s466088' AND c.relkind='r' AND c.relname LIKE 'lr\_%' ESCAPE '\' AND c.relname<>'lr_deployment'),'H01 17 tables');
 PERFORM pg_temp.ok((SELECT count(*)=32 AND bool_and('search_path=s466088, pg_catalog, pg_temp'=ANY(p.proconfig))
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='s466088' AND p.proname LIKE 'lr\_%' ESCAPE '\'),'H02 32 functions / fixed search_path');
 PERFORM pg_temp.ok((SELECT count(*)=27 AND bool_and(convalidated) FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace
  WHERE n.nspname='s466088' AND c.contype='f' AND c.conname LIKE 'lr\_%' ESCAPE '\'),'H03 27 validated FK');
 PERFORM pg_temp.ok((SELECT count(*)=25 AND bool_and(t.tgenabled='O') FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='s466088' AND c.relname LIKE 'lr\_%' ESCAPE '\' AND NOT t.tgisinternal),'H04 25 enabled triggers');
 INSERT INTO s466088.lr_app_user(login,full_name) VALUES(tag,'Probe user') RETURNING id INTO u;
 INSERT INTO s466088.lr_app_user(login,full_name) VALUES(tag||'-staff','Probe staff') RETURNING id INTO staff;
 INSERT INTO s466088.lr_user_role VALUES(u,'user'),(staff,'admin'),(staff,'technician');
 INSERT INTO s466088.lr_equipment_type(name) VALUES(tag) RETURNING id INTO typ;
 INSERT INTO s466088.lr_capability(name) VALUES(tag) RETURNING id INTO cap;
 INSERT INTO s466088.lr_type_capability VALUES(typ,cap);
 INSERT INTO s466088.lr_equipment(type_id,inventory_no,name) VALUES(typ,tag,'Probe A') RETURNING id INTO e;
 INSERT INTO s466088.lr_equipment(type_id,inventory_no,name) VALUES(typ,tag||'-B','Probe B') RETURNING id INTO e2;
 PERFORM s466088.lr_grant_admission(staff,u,typ,now()-interval '1 day',base+interval '10 days','Probe');
 PERFORM pg_temp.ok((SELECT count(*)=2 FROM s466088.lr_equivalent_equipment(u,cap,tstzrange(base,base+interval '1 hour'))),'H05 catalogue and admission');
 b:=s466088.lr_create_booking(u,e,cap,base,base+interval '1 hour','Probe');
 PERFORM pg_temp.ok(b IS NOT NULL,'H06 create booking without session search_path');
 PERFORM pg_temp.reject(format('INSERT INTO s466088.lr_booking(user_id,equipment_id,capability_id,period,purpose) VALUES(%s,%s,%s,tstzrange(%L,%L),%L)',u,e,cap,base,base+interval '1 hour','Direct overlap'),'23P01','H07 direct overlap blocked');
 PERFORM pg_temp.ok((SELECT count(*)>0 FROM s466088.lr_find_alternatives(u,e,cap,tstzrange(base,base+interval '1 hour'),'1 day')),'H08 alternatives');
 outage:=s466088.lr_register_unavailability(staff,e,'maintenance',base,base+interval '2 hours','Probe maintenance');
 PERFORM pg_temp.ok((SELECT status='needs_transfer' FROM s466088.lr_booking WHERE id=b),'H09 outage and notifications');
 SELECT id INTO choice FROM s466088.lr_alternative WHERE booking_id=b AND state='offered' ORDER BY priority,lower(period) LIMIT 1;
 PERFORM s466088.lr_select_alternative(u,choice);
 PERFORM pg_temp.ok((SELECT status='confirmed' FROM s466088.lr_booking WHERE id=b),'H10 transfer');
 PERFORM s466088.lr_cancel_booking(u,b,'Probe cleanup');
 PERFORM pg_temp.ok((SELECT status='cancelled' FROM s466088.lr_booking WHERE id=b),'H11 cancellation');
 fault:=s466088.lr_report_fault(u,e2,'Probe fault');
 outage:=s466088.lr_register_unavailability(staff,e2,'fault',now()-interval '1 minute',NULL,'Probe fault confirmed',fault);
 PERFORM pg_temp.ok(s466088.lr_equipment_state(e2)='fault','H12 fault confirmation');
 PERFORM pg_temp.ok(s466088.lr_resolve_unavailability(staff,outage,'Probe repaired')='available','H13 repair');
 INSERT INTO s466088.lr_booking(user_id,equipment_id,capability_id,period,purpose)
  VALUES(u,e2,cap,tstzrange(clock_timestamp(),clock_timestamp()+interval '1 hour'),'Probe session') RETURNING id INTO b2;
 sess:=s466088.lr_open_session(u,b2);
 PERFORM pg_sleep(0.01);
 PERFORM s466088.lr_close_session(u,sess);
 PERFORM pg_temp.ok((SELECT status='completed' FROM s466088.lr_booking WHERE id=b2),'H14 actual session');
 PERFORM pg_temp.ok((SELECT count(*)>=1 FROM s466088.lr_notification WHERE booking_id=b)
  AND (SELECT count(*)>=1 FROM s466088.lr_audit_event WHERE table_name='lr_booking' AND record_key->>'id'=b::text),'H15 notifications and audit');
 PERFORM pg_temp.ok((SELECT actual_seconds>0 FROM s466088.lr_equipment_metrics(tstzrange(now()-interval '1 day',base+interval '1 day')) WHERE equipment_id=e2),'H16 analytics');
 PERFORM pg_temp.reject(format('INSERT INTO s466088.lr_booking(user_id,equipment_id,capability_id,period,purpose) VALUES(%s,-1,%s,tstzrange(%L,%L),%L)',u,cap,base,base+interval '1 hour','Bad FK'),'23503','H17 unknown equipment rejected');
 PERFORM pg_temp.ok(current_setting('labreserve.actor_id',true) IS NOT NULL,'H18 actor setting retained');
END $$;
ROLLBACK;
\echo PASS: smoke checks rolled back (identity sequences can advance)
