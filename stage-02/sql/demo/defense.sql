\set ON_ERROR_STOP on
\pset pager off
\pset null 'NULL'
SET TIME ZONE 'Europe/Moscow';
BEGIN;
SET LOCAL search_path=labreserve,public;
CREATE FUNCTION pg_temp.demo_check(condition boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 IF condition IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %',label; END IF;
 RAISE NOTICE 'PASS: %',label;
END $$;
SELECT id AS owner FROM app_user WHERE login='student' \gset
SELECT id AS staff FROM app_user WHERE login='tech' \gset
SELECT id AS novice FROM app_user WHERE login='novice' \gset
SELECT id AS machine FROM equipment WHERE inventory_no='FDM-002' \gset
SELECT id AS function FROM capability WHERE name='Печать PLA' \gset
\echo '1. Каталог: тип, функции и допуски'
SELECT e.inventory_no,e.name,t.name AS equipment_type,equipment_state(e.id) AS state
FROM equipment e JOIN equipment_type t ON t.id=e.type_id ORDER BY e.id;
SELECT u.login,t.name,a.valid_during FROM admission a
JOIN app_user u ON u.id=a.user_id JOIN equipment_type t ON t.id=a.type_id WHERE u.id=:owner;
\echo '2. Создаём бронь; повторная бронь и отсутствие допуска отклоняются'
SELECT create_booking(:owner,:machine,:function,date_trunc('day',now())+interval '80 days 10 hours',
 date_trunc('day',now())+interval '80 days 11 hours','Защита: учебная печать') AS booking \gset
SELECT id,equipment_id,period,status FROM booking WHERE id=:booking;
SELECT * FROM request_booking(:owner,:machine,:function,date_trunc('day',now())+interval '80 days 10 hours',
 date_trunc('day',now())+interval '80 days 11 hours','Защита: конфликт') \gset overlap_
SELECT pg_temp.demo_check(:'overlap_error_code'='23P01','пересечение отклонено: 23P01');
SELECT * FROM request_booking(:novice,:machine,:function,date_trunc('day',now())+interval '81 days 10 hours',
 date_trunc('day',now())+interval '81 days 11 hours','Защита: нет допуска') \gset admission_
SELECT pg_temp.demo_check(:'admission_error_code'='23514','нет допуска: 23514');
\echo '3. Пользователь сообщает о неисправности; техник подтверждает техническое событие'
SELECT report_fault(:owner,:machine,'Защита: не нагревается сопло') AS report \gset
SELECT equipment_state(:machine) AS before_confirmation;
SELECT register_unavailability(:staff,:machine,'fault',clock_timestamp()-interval '1 minute',NULL,
 'Защита: неисправность подтверждена',:report) AS event \gset
SELECT equipment_state(:machine) AS after_confirmation;
SELECT id,status FROM booking WHERE id=:booking;
SELECT pg_temp.demo_check((SELECT status='needs_transfer' FROM booking WHERE id=:booking),'бронь требует переноса');
\echo '4. Показываем предложения и явно выбираем перенос'
SELECT id,equipment_id,period,priority,state FROM alternative WHERE booking_id=:booking ORDER BY priority,id;
SELECT id AS proposal FROM alternative WHERE booking_id=:booking AND state='offered' ORDER BY priority,id LIMIT 1 \gset
SELECT select_alternative(:owner,:proposal);
SELECT id,equipment_id,period,status FROM booking WHERE id=:booking;
SELECT pg_temp.demo_check((SELECT status='confirmed' AND equipment_id<>:machine FROM booking WHERE id=:booking),
 'перенос подтверждён на другой аппарат');
\echo '5. Завершаем ремонт и проверяем вид технической работы'
SELECT resolve_unavailability(:staff,:event,'Защита: заменён нагреватель, выполнена проверка') AS state_after_repair;
SELECT work_kind,period,result FROM repair WHERE unavailability_id=:event;
SELECT pg_temp.demo_check(equipment_state(:machine)='available','аппарат снова доступен');
\echo '6. Фактический сеанс: начало, завершение, защита от повторного закрытия'
SELECT create_booking(:owner,:machine,:function,clock_timestamp()+interval '0.3 seconds',
 clock_timestamp()+interval '1 hour','Защита: фактическая работа') AS current_booking \gset
SELECT pg_sleep(0.4);
SELECT open_session(:owner,:current_booking) AS session \gset
SELECT pg_sleep(0.01);
SELECT close_session(:owner,:session,'Защита: работа выполнена');
SELECT b.status,s.started_at,s.ended_at FROM booking b JOIN use_session s ON s.booking_id=b.id WHERE s.id=:session;
SELECT set_config('demo.owner',:'owner',true),set_config('demo.session',:'session',true);
DO $$ DECLARE code text; BEGIN
 BEGIN
  PERFORM close_session(current_setting('demo.owner')::bigint,current_setting('demo.session')::bigint);
 EXCEPTION WHEN OTHERS THEN code:=SQLSTATE; END;
 PERFORM pg_temp.demo_check(code='23514','повторное закрытие отклонено');
END $$;
\echo '7. Уведомления, аудит и аналитика'
SELECT kind,message FROM notification WHERE booking_id=:booking ORDER BY id;
SELECT table_name,action,occurred_at FROM audit_event ORDER BY id DESC LIMIT 8;
SELECT * FROM equipment_metrics(tstzrange(now()-interval '1 day',now()+interval '90 days','[)'));
ROLLBACK;
\echo 'Демонстрация завершена. Изменения отменены; счётчики идентификаторов могут иметь пропуски.'
