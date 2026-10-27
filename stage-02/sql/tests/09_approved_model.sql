\set ON_ERROR_STOP on
BEGIN;
SET search_path=labreserve,public;
CREATE FUNCTION pg_temp.check_model(condition boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 IF condition IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %',label; END IF;
 RAISE NOTICE 'PASS: %',label;
END $$;
DO $$
DECLARE f bigint; event_id bigint; code text;
BEGIN
 f:=report_fault(1,2,'Проверка согласованной модели');
 event_id:=register_unavailability(2,2,'fault',clock_timestamp()-interval '1 minute',
 NULL,'Техническое событие: неисправность',f);
 PERFORM resolve_unavailability(2,event_id,'Восстановлена работоспособность');
 PERFORM pg_temp.check_model((SELECT work_kind='repair' FROM repair WHERE unavailability_id=event_id),
 'N01 вид работы при устранении неисправности');
 event_id:=register_unavailability(3,2,'maintenance',clock_timestamp()-interval '1 minute',
 clock_timestamp()+interval '1 hour','Техническое событие: плановое ТО');
 PERFORM resolve_unavailability(3,event_id,'Проведено обслуживание');
 PERFORM pg_temp.check_model((SELECT work_kind='maintenance' FROM repair WHERE unavailability_id=event_id),
 'N02 вид работы при завершении ТО');
 BEGIN
  INSERT INTO repair(unavailability_id,performed_by,work_kind,period,result)
  VALUES(event_id,3,' ',tstzrange(now()-interval '1 minute',now(),'[)'),'Неверный вид');
 EXCEPTION WHEN OTHERS THEN code:=SQLSTATE;
 END;
 PERFORM pg_temp.check_model(code='23514','N03 пустой вид работы отклонён');
 code:=NULL;
 BEGIN
  INSERT INTO repair(unavailability_id,performed_by,work_kind,period,result)
  VALUES(event_id,3,NULL,tstzrange(now()-interval '1 minute',now(),'[)'),'Нет вида');
 EXCEPTION WHEN OTHERS THEN code:=SQLSTATE;
 END;
 PERFORM pg_temp.check_model(code='23502','N04 вид работы обязателен');
END $$;
ROLLBACK;
