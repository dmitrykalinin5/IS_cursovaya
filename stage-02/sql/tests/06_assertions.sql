\set ON_ERROR_STOP on
BEGIN;
SET search_path=labreserve,public;
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
DECLARE base timestamptz:=date_trunc('day',now())+interval '10 days'; b bigint; c bigint;
 a bigint; u bigint; f bigint; s bigint; r record; p tstzrange;
BEGIN
 b:=create_booking(1,2,1,base,base+interval '1 hour','Test');
 PERFORM pg_temp.ok((SELECT status='confirmed' FROM booking WHERE id=b),'T01 valid booking');
 PERFORM pg_temp.reject(format('SELECT create_booking(4,2,1,%L,%L,%L)',base+interval '2 hours',base+interval '3 hours','No admission'),'23514','T02 missing admission');
 PERFORM pg_temp.reject(format('INSERT INTO booking(user_id,equipment_id,capability_id,period,purpose) VALUES(5,2,1,tstzrange(%L,%L),%L)',base+interval '2 hours',base+interval '3 hours','Inactive'),'23514','T03 inactive user through direct DML');
 PERFORM pg_temp.reject(format('SELECT create_booking(1,2,1,%L,%L,%L)',base,base+interval '1 hour','Overlap'),'23P01','T04 overlap');
 c:=create_booking(1,2,1,base+interval '1 hour',base+interval '2 hours','Adjacent');
 PERFORM pg_temp.ok(c IS NOT NULL,'T05 half-open adjacent intervals');
 PERFORM cancel_booking(1,c,'Test cancelled');
 c:=create_booking(1,2,1,base+interval '1 hour',base+interval '2 hours','Reused');
 PERFORM pg_temp.ok(c IS NOT NULL,'T06 cancelled booking does not block');
 PERFORM pg_temp.reject(format('UPDATE booking SET purpose=%L WHERE status=%L','tamper','cancelled'),'23514','T07 immutable cancelled booking');
 PERFORM pg_temp.reject(format('SELECT create_booking(1,2,1,%L,%L,%L)',base+interval '3 hours',base+interval '3 hours','Empty'),'23514','T08 empty interval');
 PERFORM pg_temp.reject(format('SELECT create_booking(1,2,2,%L,%L,%L)',base+interval '3 hours',base+interval '4 hours','Wrong function'),'23514','T09 unsupported function');
 PERFORM pg_temp.reject(format('SELECT open_session(1,%s)',b),'23514','T10 cannot start before booked interval');
 PERFORM pg_temp.reject(format('SELECT cancel_booking(4,%s,%L)',b,'Foreign'),'42501','T11 owner authorization');
 u:=register_unavailability(3,2,'maintenance',base,base+interval '4 hours','Test maintenance');
 PERFORM pg_temp.ok((SELECT status='needs_transfer' FROM booking WHERE id=b),'T12 maintenance affects future booking');
 PERFORM pg_temp.ok((SELECT count(*)>=3 FROM alternative WHERE booking_id=b AND state='offered'),'T13 at least three alternatives');
 PERFORM pg_temp.ok((SELECT count(*)=1 FROM notification WHERE booking_id=b AND kind='transfer_required'),'T14 transactional notification');
 PERFORM pg_temp.reject(format('SELECT create_booking(1,2,1,%L,%L,%L)',base+interval '3 hours',base+interval '4 hours','During maintenance'),'23514','T15 maintenance blocks booking');
 SELECT id INTO a FROM alternative WHERE booking_id=b AND state='offered' ORDER BY priority,lower(period) LIMIT 1;
 PERFORM select_alternative(1,a);
 PERFORM pg_temp.ok((SELECT status='confirmed' FROM booking WHERE id=b),'T16 explicit alternative selected');
 PERFORM pg_temp.ok((SELECT state='chosen' FROM alternative WHERE id=a),'T17 alternative choice recorded');
 PERFORM pg_temp.reject(format('SELECT select_alternative(1,%s)',a),'23514','T18 alternative cannot be chosen twice');
 PERFORM pg_temp.ok((SELECT min(priority)=1 FROM alternative WHERE booking_id=b),'T19 BR6 same equipment has first rank');
 PERFORM edit_maintenance(3,u,base,base+interval '4 hours','Cancelled test maintenance',true);
 PERFORM pg_temp.ok((SELECT status='needs_transfer' FROM booking WHERE id=c),'T20 no auto-reconfirmation after maintenance cancellation');
 f:=report_fault(1,2,'Test fault');
 PERFORM pg_temp.ok((SELECT state='reported' FROM fault_report WHERE id=f),'T21 report does not itself change availability');
 u:=register_unavailability(2,2,'fault',clock_timestamp()-interval '1 minute',NULL,'Confirmed test fault',f);
 PERFORM pg_temp.ok(equipment_state(2)='fault','T22 administrator confirms technical cause');
 PERFORM pg_temp.ok((SELECT status='needs_transfer' FROM booking WHERE id=b),'T23 fault marks affected booking');
 PERFORM pg_temp.reject(format('SELECT create_booking(1,2,1,%L,%L,%L)',base+interval '7 hours',base+interval '8 hours','Broken'),'23514','T24 broken equipment rejected');
 PERFORM pg_temp.reject(format('SELECT register_unavailability(1,2,%L,%L,NULL,%L,%s)','fault',now(),'Unauthorized',f),'42501','T25 user cannot confirm technical cause');
 PERFORM pg_temp.ok((SELECT bool_and(equipment_id<>2) FROM alternative WHERE booking_id=b AND state='offered'),'T26 infinite fault excludes original equipment alternatives');
 PERFORM register_unavailability(3,2,'maintenance',clock_timestamp()-interval '30 seconds',clock_timestamp()+interval '1 hour','Other active cause');
 PERFORM pg_temp.ok(resolve_unavailability(2,u,'Repaired')='maintenance','T27 other cause prevents available state');
 f:=report_fault(1,5,'No equivalent equipment');
 u:=register_unavailability(3,5,'fault',clock_timestamp()-interval '1 minute',NULL,'Unique broken device',f);
 PERFORM pg_temp.ok((SELECT count(*)=0 FROM find_alternatives(1,5,4,tstzrange(base,base+interval '1 hour'),'1 day')),'T28 absence of alternatives');
 PERFORM pg_temp.ok(resolve_unavailability(3,u,'Checked')='available','T29 technician restores availability');
 INSERT INTO booking(user_id,equipment_id,capability_id,period,purpose)
 VALUES(1,5,4,tstzrange(clock_timestamp(),clock_timestamp()+interval '1 hour'),'Session test') RETURNING id INTO c;
 s:=open_session(1,c);
 PERFORM pg_temp.ok(s IS NOT NULL,'T30 valid session opening');
 PERFORM pg_temp.reject(format('SELECT open_session(1,%s)',c),'23505','T31 duplicate session');
 PERFORM pg_sleep(0.01);
 PERFORM close_session(1,s);
 PERFORM pg_temp.ok((SELECT status='completed' FROM booking WHERE id=c),'T32 session closure completes booking');
 PERFORM pg_temp.reject(format('SELECT close_session(1,%s)',s),'23514','T33 double close rejected');
 PERFORM pg_temp.reject(format('UPDATE booking SET purpose=%L WHERE id=%s','Rewrite',c),'23514','T34 immutable completed booking');
 PERFORM pg_temp.reject('DELETE FROM audit_event','23514','T35 immutable audit');
 PERFORM pg_temp.ok((SELECT count(*)>0 FROM audit_event WHERE table_name='booking' AND action='UPDATE'),'T36 audit records meaningful changes');
 PERFORM pg_temp.ok(tstzrange('2030-01-01 10:00+03','2030-01-01 11:00+03')=tstzrange('2030-01-01 07:00Z','2030-01-01 08:00Z'),'T37 time zone equivalence');
 SELECT * INTO r FROM request_booking(1,3,2,base+interval '7 hours',base+interval '8 hours','Failed request');
 PERFORM pg_temp.ok(r.booking_id IS NULL AND r.error_code='23514' AND EXISTS(SELECT 1 FROM conflict_event WHERE requested_period @> base+interval '7 hours'),'T38 rejected request recorded');
 PERFORM pg_temp.ok((SELECT actual_seconds>=0 AND downtime_seconds<=86400*20 FROM equipment_metrics(tstzrange(base-interval '10 days',base+interval '10 days')) WHERE equipment_id=2),'T39 clipped union downtime metrics');
 PERFORM pg_temp.ok((SELECT count(*)>=1 FROM equivalent_equipment(1,2,tstzrange(base+interval '1 day',base+interval '1 day 1 hour')) WHERE id=4),'T40 equivalent function across types');
 PERFORM pg_temp.reject(format('DELETE FROM booking WHERE id=%s',b),'23514','T41 booking history not deletable');
 PERFORM pg_temp.ok((SELECT count(*)>=1 FROM free_intervals(1,tstzrange(base,base+interval '1 day'))),'T42 maximal free intervals');
 PERFORM pg_temp.ok(create_reminders(now()+interval '20 days')>=0 AND create_reminders(now()+interval '20 days')=0,'T43 reminders idempotent');
 PERFORM offer_alternatives(b,'1 day');
 SELECT id INTO a FROM alternative WHERE booking_id=b AND state='offered' ORDER BY priority,lower(period) LIMIT 1;
 SELECT equipment_id,period INTO r FROM alternative WHERE id=a;
 PERFORM create_booking(1,r.equipment_id,1,lower(r.period),upper(r.period),'Rival took alternative');
 PERFORM pg_temp.reject(format('SELECT select_alternative(1,%s)',a),'23P01','T44 stale candidate rechecked at selection');
 PERFORM pg_temp.reject(format('SELECT grant_admission(3,4,1,%L,%L,%L)',base,base+interval '1 day','Technician'),'42501','T45 administrator grants admissions');
 u:=grant_admission(2,4,1,base+interval '5 hours',base+interval '1 day','Partial future admission');
 PERFORM pg_temp.ok((SELECT count(*)>=3 FROM find_alternatives(4,1,1,tstzrange(base,base+interval '1 hour'),'1 day')),'T46 search intersects future admission validity');
 PERFORM pg_temp.reject(format('SELECT create_booking(4,1,1,%L,%L,%L)',base,base+interval '1 hour','Not yet admitted'),'23514','T47 not-yet-valid admission rejected');
 PERFORM pg_temp.reject(format('SELECT create_booking(4,1,1,%L,%L,%L)',base+interval '23 hours',base+interval '25 hours','Admission expires midway'),'23514','T48 admission must cover whole booking');
 PERFORM revoke_admission(2,u);
 PERFORM pg_temp.reject(format('SELECT create_booking(4,1,1,%L,%L,%L)',base+interval '6 hours',base+interval '7 hours','Revoked'),'23514','T49 revoked admission rejected');
 PERFORM pg_temp.reject(format('DELETE FROM admission WHERE id=%s',u),'23514','T50 admission history retained');
 PERFORM pg_temp.reject('DELETE FROM unavailability','23514','T51 downtime history retained');
 INSERT INTO booking(user_id,equipment_id,capability_id,period,purpose)
 VALUES(1,5,4,tstzrange(clock_timestamp(),clock_timestamp()+interval '1 hour'),'Admin closure test') RETURNING id INTO c;
 s:=open_session(1,c);
 PERFORM pg_temp.reject(format('SELECT close_session(2,%s)',s),'23514','T52 administrative closure needs comment');
 PERFORM close_session(2,s,'Пользователь забыл завершить работу; проверено администратором');
 PERFORM pg_temp.ok((SELECT close_comment IS NOT NULL AND ended_at IS NOT NULL FROM use_session WHERE id=s),'T53 administrative closure comment retained');
 PERFORM pg_temp.reject('SELECT ''[2030-01-01 00:00Z,2030-01-02 00:00Z]''::time_window','23514','T54 inclusive upper bound rejected');
 PERFORM pg_temp.ok((SELECT count(*)=17 FROM information_schema.tables WHERE table_schema='labreserve' AND table_type='BASE TABLE'),'T55 17 physical tables');

 PERFORM register_unavailability(3,1,'maintenance',base+interval '2 days',base+interval '2 days 4 hours','Union A');
 PERFORM register_unavailability(3,1,'maintenance',base+interval '2 days 2 hours',base+interval '2 days 6 hours','Union B');
 PERFORM pg_temp.ok((SELECT downtime_seconds=21600 FROM equipment_metrics(tstzrange(base+interval '2 days',base+interval '3 days')) WHERE equipment_id=1),'T56 overlapping downtime counted as union');
 PERFORM pg_temp.ok((SELECT extract(epoch FROM ended_at-started_at)<3600 FROM use_session WHERE id=s),'T57 actual duration differs from planned hour');

END $$;
CREATE ROLE labreserve_stage02_probe NOLOGIN;
\set app_role labreserve_stage02_probe
\ir ../scripts/grant_application.sql
SET ROLE labreserve_stage02_probe;
SET search_path=public;
SELECT pg_temp.reject('UPDATE labreserve.booking SET purpose=''Forbidden''','42501','T58 backend has no direct schedule DML');
SELECT pg_temp.reject('SELECT labreserve.lock_equipment(1)','42501','T59 backend cannot call internal guard');
SELECT pg_temp.ok(labreserve.create_booking(1,2,1,now()+interval '50 days',now()+interval '50 days 1 hour','Backend API') IS NOT NULL,'T60 qualified API works without session search_path');
RESET ROLE;
ROLLBACK;
