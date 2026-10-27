SET search_path=labreserve,public;
CREATE FUNCTION assert_owner(p_actor bigint,p_owner bigint) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM app_user WHERE id=p_actor AND active) OR
    (p_actor IS DISTINCT FROM p_owner AND NOT has_role(p_actor,'admin')) THEN
  RAISE EXCEPTION 'Owner or administrator required' USING ERRCODE='42501'; END IF;
 PERFORM set_config('labreserve.actor_id',p_actor::text,true);
END $$;
CREATE FUNCTION free_intervals(p_equipment bigint,p_window tstzrange,p_ignore bigint DEFAULT NULL)
RETURNS SETOF tstzrange LANGUAGE plpgsql STABLE AS $$
BEGIN
 IF isempty(p_window) OR lower_inf(p_window) OR upper_inf(p_window)
    OR NOT lower_inc(p_window) OR upper_inc(p_window) THEN
  RAISE EXCEPTION 'Finite [start,end) window required' USING ERRCODE='22023'; END IF;
 RETURN QUERY SELECT unnest(tstzmultirange(p_window) - COALESCE(range_agg(busy), '{}'::tstzmultirange))
 FROM (
  SELECT period::tstzrange * p_window AS busy FROM booking
   WHERE equipment_id=p_equipment AND status='confirmed'
     AND id IS DISTINCT FROM p_ignore AND period && p_window
  UNION ALL
  SELECT period::tstzrange * p_window FROM unavailability
   WHERE equipment_id=p_equipment AND status<>'cancelled' AND period && p_window
 ) s;
END $$;
CREATE FUNCTION equivalent_equipment(p_user bigint,p_capability bigint,p_period tstzrange)
RETURNS SETOF equipment LANGUAGE sql STABLE AS $$
 SELECT e.* FROM equipment e JOIN equipment_type t ON t.id=e.type_id
 JOIN type_capability c ON c.type_id=e.type_id
 WHERE c.capability_id=p_capability AND NOT e.archived AND NOT t.archived
 AND EXISTS(SELECT 1 FROM app_user WHERE id=p_user AND active)
 AND EXISTS(SELECT 1 FROM admission a WHERE a.user_id=p_user AND a.type_id=e.type_id
   AND a.revoked_at IS NULL AND a.valid_during @> p_period)
 AND NOT EXISTS(SELECT 1 FROM booking b WHERE b.equipment_id=e.id AND b.status='confirmed' AND b.period && p_period)
 AND NOT EXISTS(SELECT 1 FROM unavailability u WHERE u.equipment_id=e.id AND u.status<>'cancelled' AND u.period && p_period)
$$;
CREATE FUNCTION find_alternatives(p_user bigint,p_equipment bigint,p_capability bigint,
 p_period tstzrange,p_horizon interval DEFAULT interval '30 days',p_ignore bigint DEFAULT NULL)
RETURNS TABLE(equipment_id bigint,period tstzrange,priority smallint) LANGUAGE plpgsql STABLE AS $$
DECLARE duration interval; win tstzrange;
BEGIN
 IF p_horizon<=interval '0' OR isempty(p_period) OR upper_inf(p_period)
    OR lower_inf(p_period) OR NOT lower_inc(p_period) OR upper_inc(p_period) THEN
  RAISE EXCEPTION 'Invalid alternative search window' USING ERRCODE='22023'; END IF;
 duration:=upper(p_period)-lower(p_period);
 win:=tstzrange(lower(p_period),upper(p_period)+p_horizon,'[)');
 RETURN QUERY
 WITH candidates AS (
 SELECT DISTINCT e.id, tstzrange(s,s+duration,'[)') AS slot,
   (CASE WHEN e.id=p_equipment THEN 1 WHEN s=lower(p_period) THEN 2 ELSE 3 END)::smallint AS rank
 FROM equipment e JOIN equipment_type t ON t.id=e.type_id
 JOIN type_capability c ON c.type_id=e.type_id
 JOIN admission a ON a.type_id=e.type_id AND a.user_id=p_user AND a.revoked_at IS NULL
 CROSS JOIN LATERAL free_intervals(e.id,win,p_ignore) gap
 CROSS JOIN LATERAL (SELECT gap * a.valid_during::tstzrange AS allowed) g
 CROSS JOIN LATERAL generate_series(lower(g.allowed),upper(g.allowed)-duration,duration) s
 WHERE c.capability_id=p_capability AND NOT e.archived AND NOT t.archived
 AND EXISTS(SELECT 1 FROM app_user WHERE id=p_user AND active)
 AND NOT (e.id=p_equipment AND s=lower(p_period))
 AND EXISTS(SELECT 1 FROM admission a WHERE a.user_id=p_user AND a.type_id=e.type_id
  AND a.revoked_at IS NULL AND a.valid_during @> tstzrange(s,s+duration,'[)'))
 ) SELECT id,slot,rank FROM candidates ORDER BY rank,lower(slot),id LIMIT 12;
END $$;
CREATE FUNCTION offer_alternatives(p_booking bigint,p_horizon interval DEFAULT interval '30 days')
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE b booking; n integer;
BEGIN
 SELECT * INTO STRICT b FROM booking WHERE id=p_booking;
 UPDATE alternative SET state='obsolete' WHERE booking_id=b.id AND state='offered';
 INSERT INTO alternative(booking_id,equipment_id,period,priority)
 SELECT b.id,a.equipment_id,a.period,a.priority FROM
  find_alternatives(b.user_id,b.equipment_id,b.capability_id,b.period,p_horizon,b.id) a
 ON CONFLICT(booking_id,equipment_id,period) DO UPDATE SET state='offered',priority=EXCLUDED.priority,
   created_at=clock_timestamp();
 GET DIAGNOSTICS n=ROW_COUNT;
 RETURN n;
END $$;
CREATE FUNCTION create_booking(p_user bigint,p_equipment bigint,p_capability bigint,
 p_start timestamptz,p_end timestamptz,p_purpose text) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE n bigint;
BEGIN
 PERFORM assert_owner(p_user,p_user);
 IF p_start<=clock_timestamp() THEN RAISE EXCEPTION 'Future booking required' USING ERRCODE='23514'; END IF;
 INSERT INTO booking(user_id,equipment_id,capability_id,period,purpose)
 VALUES(p_user,p_equipment,p_capability,tstzrange(p_start,p_end,'[)'),p_purpose) RETURNING id INTO n;
 RETURN n;
END $$;
-- Catching inside a subtransaction allows conflict statistics to survive a rejected request.
CREATE FUNCTION request_booking(p_user bigint,p_equipment bigint,p_capability bigint,
 p_start timestamptz,p_end timestamptz,p_purpose text)
RETURNS TABLE(booking_id bigint,error_code text) LANGUAGE plpgsql AS $$
BEGIN
 BEGIN
  booking_id:=create_booking(p_user,p_equipment,p_capability,p_start,p_end,p_purpose);
 EXCEPTION WHEN exclusion_violation OR check_violation THEN
  error_code:=SQLSTATE;
  IF p_end>p_start THEN
   INSERT INTO conflict_event(user_id,equipment_id,requested_period,error_code)
   VALUES(p_user,p_equipment,tstzrange(p_start,p_end,'[)'),error_code);
  END IF;
 END;
 RETURN NEXT;
END $$;
CREATE FUNCTION cancel_booking(p_actor bigint,p_booking bigint,p_reason text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE b booking;
BEGIN
 SELECT * INTO STRICT b FROM booking WHERE id=p_booking;
 PERFORM assert_owner(p_actor,b.user_id); PERFORM lock_equipment(b.equipment_id);
 SELECT * INTO STRICT b FROM booking WHERE id=p_booking FOR UPDATE;
 IF b.status NOT IN ('confirmed','needs_transfer') OR lower(b.period)<=clock_timestamp() THEN
  RAISE EXCEPTION 'Only future active booking can be cancelled' USING ERRCODE='23514'; END IF;
 UPDATE booking SET status='cancelled',cancelled_at=clock_timestamp(),cancel_reason=p_reason WHERE id=b.id;
 INSERT INTO notification(user_id,booking_id,kind,message) VALUES(b.user_id,b.id,'cancelled',p_reason);
END $$;
CREATE FUNCTION select_alternative(p_actor bigint,p_alternative bigint) RETURNS void LANGUAGE plpgsql AS $$
DECLARE a alternative; b booking; e bigint;
BEGIN
 SELECT * INTO STRICT a FROM alternative WHERE id=p_alternative;
 SELECT * INTO STRICT b FROM booking WHERE id=a.booking_id;
 PERFORM assert_owner(p_actor,b.user_id);
 FOR e IN SELECT DISTINCT x FROM (VALUES(b.equipment_id),(a.equipment_id)) ids(x) ORDER BY x LOOP
  PERFORM lock_equipment(e);
 END LOOP;
 SELECT * INTO STRICT b FROM booking WHERE id=b.id FOR UPDATE;
 SELECT * INTO STRICT a FROM alternative WHERE id=a.id FOR UPDATE;
 IF a.state<>'offered' OR b.status NOT IN ('confirmed','needs_transfer')
    OR lower(a.period)<=clock_timestamp() THEN RAISE EXCEPTION 'Stale alternative' USING ERRCODE='23514'; END IF;
 UPDATE booking SET equipment_id=a.equipment_id,period=a.period,status='confirmed' WHERE id=b.id;
 UPDATE alternative SET state=CASE WHEN id=a.id THEN 'chosen' ELSE 'obsolete' END
  WHERE booking_id=b.id AND state='offered';
 INSERT INTO notification(user_id,booking_id,kind,message) VALUES(b.user_id,b.id,'transferred','Перенос подтверждён');
END $$;
CREATE FUNCTION report_fault(p_actor bigint,p_equipment bigint,p_description text)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE n bigint;
BEGIN
 PERFORM assert_owner(p_actor,p_actor);
 INSERT INTO fault_report(equipment_id,reported_by,description)
 VALUES(p_equipment,p_actor,p_description) RETURNING id INTO n; RETURN n;
END $$;
CREATE FUNCTION register_unavailability(p_actor bigint,p_equipment bigint,p_kind text,
 p_start timestamptz,p_end timestamptz,p_reason text,p_report bigint DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE n bigint;
BEGIN
 PERFORM require_staff(p_actor); PERFORM lock_equipment(p_equipment);
 IF p_report IS NOT NULL THEN UPDATE fault_report SET state='confirmed' WHERE id=p_report AND state='reported'; END IF;
 INSERT INTO unavailability(equipment_id,kind,period,reason,fault_report_id,created_by)
 VALUES(p_equipment,p_kind,tstzrange(p_start,p_end,'[)'),p_reason,p_report,p_actor) RETURNING id INTO n;
 RETURN n;
END $$;
CREATE FUNCTION edit_maintenance(p_actor bigint,p_unavailability bigint,p_start timestamptz,
 p_end timestamptz,p_reason text,p_cancel boolean DEFAULT false) RETURNS void LANGUAGE plpgsql AS $$
DECLARE u unavailability;
BEGIN
 PERFORM require_staff(p_actor);
 SELECT * INTO STRICT u FROM unavailability WHERE id=p_unavailability;
 PERFORM lock_equipment(u.equipment_id);
 SELECT * INTO STRICT u FROM unavailability WHERE id=u.id FOR UPDATE;
 IF u.kind<>'maintenance' OR u.status<>'active' THEN RAISE EXCEPTION 'Active maintenance required' USING ERRCODE='23514'; END IF;
 UPDATE unavailability SET period=tstzrange(p_start,p_end,'[)'),reason=p_reason,
 status=CASE WHEN p_cancel THEN 'cancelled' ELSE 'active' END WHERE id=u.id;
 -- No automatic reconfirmation of bookings after cancellation.
END $$;
CREATE FUNCTION equipment_state(p_equipment bigint,p_at timestamptz DEFAULT clock_timestamp())
RETURNS text LANGUAGE sql STABLE AS $$
 SELECT CASE WHEN e.archived OR t.archived THEN 'archived'
 WHEN EXISTS(SELECT 1 FROM unavailability u WHERE u.equipment_id=e.id AND u.status<>'cancelled'
   AND u.kind='fault' AND u.period @> p_at) THEN 'fault'
 WHEN EXISTS(SELECT 1 FROM unavailability u WHERE u.equipment_id=e.id AND u.status<>'cancelled'
   AND u.period @> p_at) THEN 'maintenance' ELSE 'available' END
 FROM equipment e JOIN equipment_type t ON t.id=e.type_id WHERE e.id=p_equipment
$$;
CREATE FUNCTION resolve_unavailability(p_actor bigint,p_unavailability bigint,p_result text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE u unavailability; stop_at timestamptz;
BEGIN
 PERFORM require_staff(p_actor);
 SELECT * INTO STRICT u FROM unavailability WHERE id=p_unavailability;
 PERFORM lock_equipment(u.equipment_id);
 SELECT * INTO STRICT u FROM unavailability WHERE id=u.id FOR UPDATE;
 IF u.status<>'active' THEN RAISE EXCEPTION 'Already resolved' USING ERRCODE='23514'; END IF;
 stop_at:=clock_timestamp();
 IF lower(u.period)>=stop_at THEN RAISE EXCEPTION 'Cannot finish before start' USING ERRCODE='23514'; END IF;
 INSERT INTO repair(unavailability_id,performed_by,work_kind,period,result)
 VALUES(u.id,p_actor,CASE WHEN u.kind='maintenance' THEN 'maintenance' ELSE 'repair' END,
 tstzrange(lower(u.period),stop_at,'[)'),p_result);
 UPDATE unavailability SET period=tstzrange(lower(u.period),LEAST(upper(u.period),stop_at),'[)'),
 status='resolved',resolved_by=p_actor,resolved_at=stop_at WHERE id=u.id;
 RETURN equipment_state(u.equipment_id,stop_at);
END $$;
CREATE FUNCTION open_session(p_actor bigint,p_booking bigint) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE b booking; n bigint;
BEGIN
 SELECT * INTO STRICT b FROM booking WHERE id=p_booking;
 PERFORM assert_owner(p_actor,b.user_id); PERFORM lock_equipment(b.equipment_id);
 INSERT INTO use_session(booking_id) VALUES(b.id) RETURNING id INTO n; RETURN n;
END $$;
CREATE FUNCTION close_session(p_actor bigint,p_session bigint,p_comment text DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
DECLARE b booking; s use_session;
BEGIN
 SELECT * INTO STRICT s FROM use_session WHERE id=p_session;
 SELECT * INTO STRICT b FROM booking WHERE id=s.booking_id;
 PERFORM assert_owner(p_actor,b.user_id); PERFORM lock_equipment(b.equipment_id);
 IF p_actor<>b.user_id AND COALESCE(length(trim(p_comment)),0)=0 THEN
  RAISE EXCEPTION 'Administrative closure requires comment' USING ERRCODE='23514'; END IF;
 UPDATE use_session SET ended_at=clock_timestamp(),close_comment=p_comment WHERE id=s.id;
END $$;
CREATE FUNCTION create_reminders(p_until timestamptz) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE n integer;
BEGIN
 INSERT INTO notification(user_id,booking_id,kind,message)
 SELECT user_id,id,'reminder','Приближается бронирование' FROM booking b
 WHERE status='confirmed' AND lower(period)>clock_timestamp() AND lower(period)<=p_until
 ON CONFLICT DO NOTHING;
 GET DIAGNOSTICS n=ROW_COUNT; RETURN n;
END $$;
CREATE FUNCTION equipment_metrics(p_window tstzrange)
RETURNS TABLE(equipment_id bigint,planned_seconds numeric,actual_seconds numeric,
 downtime_seconds numeric,utilization_percent numeric,conflicts bigint)
LANGUAGE plpgsql STABLE AS $$
BEGIN
 IF isempty(p_window) OR lower_inf(p_window) OR upper_inf(p_window) THEN
  RAISE EXCEPTION 'Finite reporting window required' USING ERRCODE='22023'; END IF;
 RETURN QUERY SELECT e.id,
 COALESCE((SELECT sum(extract(epoch FROM upper(g)-lower(g))) FROM
 (SELECT unnest(range_agg(b.period::tstzrange*p_window)) g FROM booking b
 WHERE b.equipment_id=e.id AND b.status IN ('confirmed','completed') AND b.period && p_window) q),0),
 COALESCE(a.seconds,0), COALESCE(d.seconds,0),
 round(100*COALESCE(a.seconds,0)/extract(epoch FROM upper(p_window)-lower(p_window)),2),
 (SELECT count(*) FROM conflict_event c WHERE c.equipment_id=e.id AND p_window @> c.occurred_at)
 FROM equipment e
 LEFT JOIN LATERAL (SELECT sum(extract(epoch FROM upper(g)-lower(g))) seconds FROM
  (SELECT unnest(range_agg(tstzrange(s.started_at,COALESCE(s.ended_at,statement_timestamp()),'[)')*p_window)) g
   FROM use_session s JOIN booking b ON b.id=s.booking_id WHERE b.equipment_id=e.id
   AND tstzrange(s.started_at,COALESCE(s.ended_at,statement_timestamp()),'[)') && p_window) q) a ON true
 LEFT JOIN LATERAL (SELECT sum(extract(epoch FROM upper(g)-lower(g))) seconds FROM
  (SELECT unnest(range_agg(u.period::tstzrange*p_window)) g FROM unavailability u
   WHERE u.equipment_id=e.id AND u.status<>'cancelled' AND u.period && p_window) q) d ON true
 ORDER BY e.id;
END $$;
CREATE FUNCTION grant_admission(p_actor bigint,p_user bigint,p_type bigint,p_start timestamptz,
 p_end timestamptz,p_basis text) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE n bigint;
BEGIN
 IF NOT has_role(p_actor,'admin') THEN RAISE EXCEPTION 'Administrator required' USING ERRCODE='42501'; END IF;
 PERFORM set_config('labreserve.actor_id',p_actor::text,true);
 INSERT INTO admission(user_id,type_id,valid_during,basis,granted_by)
 VALUES(p_user,p_type,tstzrange(p_start,p_end,'[)'),p_basis,p_actor) RETURNING id INTO n; RETURN n;
END $$;
CREATE FUNCTION revoke_admission(p_actor bigint,p_admission bigint) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 IF NOT has_role(p_actor,'admin') THEN RAISE EXCEPTION 'Administrator required' USING ERRCODE='42501'; END IF;
 PERFORM set_config('labreserve.actor_id',p_actor::text,true);
 UPDATE admission SET revoked_at=clock_timestamp() WHERE id=p_admission AND revoked_at IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'Admission missing/already revoked' USING ERRCODE='23514'; END IF;
END $$;
DO $$ DECLARE f record; BEGIN
 FOR f IN SELECT p.oid::regprocedure AS signature,p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='labreserve' LOOP
  EXECUTE format('ALTER FUNCTION %s SET search_path = labreserve, pg_catalog, pg_temp',f.signature);
  IF f.proname IN ('create_booking','request_booking','cancel_booking','select_alternative',
    'report_fault','register_unavailability','edit_maintenance','resolve_unavailability',
    'open_session','close_session','offer_alternatives','create_reminders','grant_admission','revoke_admission') THEN
   EXECUTE format('ALTER FUNCTION %s SECURITY DEFINER',f.signature);
  END IF;
 END LOOP;
END $$;
REVOKE ALL ON SCHEMA labreserve FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA labreserve FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA labreserve FROM PUBLIC;
