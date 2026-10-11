SET search_path=labreserve,public;
-- UPDATE, not just a read lock: stale RR/Serializable snapshots fail with 40001.
CREATE FUNCTION lock_equipment(p_id bigint) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 UPDATE equipment SET schedule_revision=schedule_revision+1 WHERE id=p_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown equipment' USING ERRCODE='23503'; END IF;
END $$;
CREATE FUNCTION has_role(p_user bigint,p_role text) RETURNS boolean LANGUAGE sql STABLE AS $$
 SELECT EXISTS(SELECT 1 FROM app_user u JOIN user_role r ON r.user_id=u.id
 WHERE u.id=p_user AND u.active AND r.role_code=p_role)
$$;
CREATE FUNCTION require_staff(p_user bigint) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 IF NOT (has_role(p_user,'admin') OR has_role(p_user,'technician')) THEN
 RAISE EXCEPTION 'Technician or administrator required' USING ERRCODE='42501'; END IF;
 PERFORM set_config('labreserve.actor_id',p_user::text,true);
END $$;
CREATE FUNCTION check_booking() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Keep booking history' USING ERRCODE='23514'; END IF;
 IF TG_OP='UPDATE' THEN
  IF OLD.status IN ('cancelled','completed') AND NEW IS DISTINCT FROM OLD THEN
   RAISE EXCEPTION 'Terminal booking is immutable' USING ERRCODE='23514'; END IF;
  IF NEW.user_id<>OLD.user_id OR NEW.capability_id<>OLD.capability_id THEN
   RAISE EXCEPTION 'Booking owner and requested function are immutable' USING ERRCODE='23514'; END IF;
  IF (NEW.equipment_id<>OLD.equipment_id OR NEW.period<>OLD.period OR NEW.status='cancelled')
     AND EXISTS(SELECT 1 FROM use_session WHERE booking_id=OLD.id) THEN
   RAISE EXCEPTION 'Session prevents transfer/cancellation' USING ERRCODE='23514'; END IF;
  -- Lock both resources in increasing order for transfers.
  PERFORM lock_equipment(x) FROM (SELECT DISTINCT v AS x FROM
    (VALUES(OLD.equipment_id),(NEW.equipment_id)) t(v) ORDER BY v) ids;
 ELSE
  IF NEW.status<>'confirmed' THEN RAISE EXCEPTION 'New booking must be confirmed' USING ERRCODE='23514'; END IF;
  PERFORM lock_equipment(NEW.equipment_id);
 END IF;
 IF NEW.status='confirmed' THEN
  PERFORM 1 FROM app_user WHERE id=NEW.user_id AND active FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Inactive user' USING ERRCODE='23514'; END IF;
  PERFORM 1 FROM equipment e JOIN equipment_type t ON t.id=e.type_id
    JOIN type_capability c ON c.type_id=e.type_id WHERE e.id=NEW.equipment_id
    AND NOT e.archived AND NOT t.archived AND c.capability_id=NEW.capability_id FOR SHARE OF t,c;
  IF NOT FOUND THEN
   RAISE EXCEPTION 'Unavailable catalog or unsupported function' USING ERRCODE='23514'; END IF;
  PERFORM 1 FROM admission a JOIN equipment e ON e.type_id=a.type_id
    WHERE e.id=NEW.equipment_id AND a.user_id=NEW.user_id AND a.revoked_at IS NULL
    AND a.valid_during @> NEW.period::tstzrange FOR SHARE OF a;
  IF NOT FOUND THEN RAISE EXCEPTION 'No admission covering entire interval' USING ERRCODE='23514'; END IF;
  IF EXISTS(SELECT 1 FROM unavailability WHERE equipment_id=NEW.equipment_id
    AND status<>'cancelled' AND period && NEW.period::tstzrange) THEN
   RAISE EXCEPTION 'Maintenance or fault overlap' USING ERRCODE='23514'; END IF;
 END IF;
 IF NEW.status='completed' AND NOT EXISTS(SELECT 1 FROM use_session
     WHERE booking_id=NEW.id AND ended_at IS NOT NULL) THEN
  RAISE EXCEPTION 'Completion requires closed session' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER booking_guard BEFORE INSERT OR UPDATE OR DELETE ON booking
 FOR EACH ROW EXECUTE FUNCTION check_booking();
CREATE FUNCTION check_unavailability() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE actor bigint;
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Keep technical history' USING ERRCODE='23514'; END IF;
 actor:=NULLIF(current_setting('labreserve.actor_id',true),'')::bigint;
 PERFORM require_staff(actor);
 IF TG_OP='UPDATE' THEN
  IF OLD.status<>'active' OR NEW.equipment_id<>OLD.equipment_id OR NEW.kind<>OLD.kind
    OR NEW.fault_report_id IS DISTINCT FROM OLD.fault_report_id THEN
   RAISE EXCEPTION 'Immutable technical history/identity' USING ERRCODE='23514'; END IF;
 END IF;
 PERFORM lock_equipment(NEW.equipment_id);
 IF NEW.fault_report_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM fault_report
   WHERE id=NEW.fault_report_id AND equipment_id=NEW.equipment_id AND state='confirmed') THEN
  RAISE EXCEPTION 'Confirmed matching fault report required' USING ERRCODE='23514'; END IF;
 IF NEW.status='resolved' AND NEW.resolved_by IS DISTINCT FROM actor THEN
  RAISE EXCEPTION 'Resolver must match actor' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER unavailability_guard BEFORE INSERT OR UPDATE OR DELETE ON unavailability
 FOR EACH ROW EXECUTE FUNCTION check_unavailability();
CREATE FUNCTION impact_bookings() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE b record;
BEGIN
 IF NEW.status='active' THEN
  FOR b IN UPDATE booking SET status='needs_transfer'
    WHERE equipment_id=NEW.equipment_id AND status='confirmed'
    AND lower(period)>clock_timestamp() AND period && NEW.period::tstzrange RETURNING id,user_id LOOP
   INSERT INTO notification(user_id,booking_id,kind,message)
     VALUES(b.user_id,b.id,'transfer_required','Недоступность: '||NEW.reason);
   -- Dynamic call permits definition of alternative search in the next script.
   EXECUTE 'SELECT labreserve.offer_alternatives($1, $2)' USING b.id,interval '30 days';
  END LOOP;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER unavailability_impact AFTER INSERT OR UPDATE ON unavailability
 FOR EACH ROW EXECUTE FUNCTION impact_bookings();
CREATE FUNCTION check_session() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE b booking;
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Keep session history' USING ERRCODE='23514'; END IF;
 SELECT * INTO b FROM booking WHERE id=NEW.booking_id;
 PERFORM lock_equipment(b.equipment_id);
 SELECT * INTO b FROM booking WHERE id=NEW.booking_id FOR UPDATE;
 IF TG_OP='INSERT' THEN
  PERFORM 1 FROM app_user WHERE id=b.user_id AND active FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Inactive user at session start' USING ERRCODE='23514'; END IF;
  PERFORM 1 FROM admission a JOIN equipment e ON e.type_id=a.type_id
       WHERE e.id=b.equipment_id AND a.user_id=b.user_id AND a.revoked_at IS NULL
       AND a.valid_during @> NEW.started_at FOR SHARE OF a;
  IF NOT FOUND THEN RAISE EXCEPTION 'No admission at session start' USING ERRCODE='23514'; END IF;
  IF equipment_state(b.equipment_id,NEW.started_at)='archived'
    OR b.status<>'confirmed' OR NEW.ended_at IS NOT NULL OR NOT (b.period @> NEW.started_at)
    OR EXISTS(SELECT 1 FROM unavailability WHERE equipment_id=b.equipment_id
      AND status<>'cancelled' AND period @> NEW.started_at) THEN
   RAISE EXCEPTION 'Cannot start session' USING ERRCODE='23514'; END IF;
 ELSE
  IF OLD.ended_at IS NOT NULL OR NEW.booking_id<>OLD.booking_id
    OR NEW.started_at<>OLD.started_at OR NEW.ended_at IS NULL THEN
   RAISE EXCEPTION 'Session closes exactly once' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER session_guard BEFORE INSERT OR UPDATE OR DELETE ON use_session
 FOR EACH ROW EXECUTE FUNCTION check_session();
CREATE FUNCTION complete_session() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.ended_at IS NOT NULL THEN UPDATE booking SET status='completed' WHERE id=NEW.booking_id; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER session_complete AFTER UPDATE ON use_session FOR EACH ROW EXECUTE FUNCTION complete_session();
CREATE FUNCTION immutable_history() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Append-only history' USING ERRCODE='23514'; END $$;
CREATE TRIGGER audit_immutable BEFORE UPDATE OR DELETE ON audit_event FOR EACH ROW EXECUTE FUNCTION immutable_history();
CREATE TRIGGER conflict_immutable BEFORE UPDATE OR DELETE ON conflict_event FOR EACH ROW EXECUTE FUNCTION immutable_history();
CREATE TRIGGER repair_immutable BEFORE UPDATE OR DELETE ON repair FOR EACH ROW EXECUTE FUNCTION immutable_history();
CREATE FUNCTION technical_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE actor bigint;
BEGIN
 actor:=NULLIF(current_setting('labreserve.actor_id',true),'')::bigint;
 IF TG_TABLE_NAME='repair' OR (TG_TABLE_NAME='fault_report' AND TG_OP='UPDATE') THEN
  PERFORM require_staff(actor);
 END IF;
 IF TG_TABLE_NAME='repair' THEN
  IF NEW.performed_by IS DISTINCT FROM actor THEN RAISE EXCEPTION 'Repair actor mismatch' USING ERRCODE='42501'; END IF;
 ELSE
  IF TG_OP='UPDATE' AND (OLD.state<>'reported' OR NEW.equipment_id<>OLD.equipment_id
    OR NEW.reported_by<>OLD.reported_by OR NEW.description<>OLD.description) THEN
   RAISE EXCEPTION 'Fault history is immutable' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER repair_guard BEFORE INSERT ON repair FOR EACH ROW EXECUTE FUNCTION technical_guard();
CREATE TRIGGER fault_guard BEFORE INSERT OR UPDATE ON fault_report FOR EACH ROW EXECUTE FUNCTION technical_guard();
CREATE TRIGGER fault_no_delete BEFORE DELETE ON fault_report FOR EACH ROW EXECUTE FUNCTION immutable_history();
CREATE FUNCTION audit_change() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE oldj jsonb; newj jsonb;
BEGIN
 IF TG_OP<>'INSERT' THEN oldj:=to_jsonb(OLD); END IF;
 IF TG_OP<>'DELETE' THEN newj:=to_jsonb(NEW); END IF;
 IF TG_TABLE_NAME='equipment' AND oldj-'schedule_revision'=newj-'schedule_revision' THEN RETURN NEW; END IF;
 -- Credential hashes are excluded from audit snapshots.
 oldj:=oldj-'password_hash'; newj:=newj-'password_hash';
 INSERT INTO audit_event(actor_id,table_name,record_key,action,old_data,new_data)
 VALUES(NULLIF(current_setting('labreserve.actor_id',true),'')::bigint,TG_TABLE_NAME,
   jsonb_build_object('id',COALESCE(newj->'id',oldj->'id'),'key',
     CASE WHEN COALESCE(newj->'id',oldj->'id') IS NULL THEN COALESCE(newj,oldj) END),
   TG_OP,oldj,newj);
 RETURN COALESCE(NEW,OLD);
END $$;
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['app_user','user_role','equipment_type','capability','type_capability',
   'equipment','admission','booking','alternative','unavailability','fault_report','repair','use_session'] LOOP
 EXECUTE format('CREATE TRIGGER audit_%I AFTER INSERT OR UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION audit_change()',t,t);
 END LOOP;
END $$;

CREATE FUNCTION admission_history() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Revoke instead of deleting admission' USING ERRCODE='23514'; END IF;
 IF NEW.user_id<>OLD.user_id OR NEW.type_id<>OLD.type_id OR NEW.valid_during<>OLD.valid_during
 OR NEW.basis<>OLD.basis OR NEW.granted_by<>OLD.granted_by OR OLD.revoked_at IS NOT NULL THEN
  RAISE EXCEPTION 'Issue a new admission; retain old record' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER admission_guard BEFORE UPDATE OR DELETE ON admission FOR EACH ROW EXECUTE FUNCTION admission_history();
