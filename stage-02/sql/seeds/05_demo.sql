\set ON_ERROR_STOP on
BEGIN;
SET search_path=labreserve,public;
INSERT INTO app_role VALUES('user'),('admin'),('technician');
INSERT INTO app_user(login,full_name,active) VALUES
 ('student','Анна Петрова',true),('admin','Дмитрий Калинин',true),
 ('tech','Ахмед Рзаев',true),('novice','Иван Сидоров',true),('inactive','Архивный пользователь',false);
INSERT INTO user_role VALUES(1,'user'),(2,'admin'),(2,'user'),(3,'technician'),(4,'user'),(5,'user');
INSERT INTO equipment_type(name) VALUES('3D-принтер FDM'),('Лазерный резак'),('Станок ЧПУ'),('Измерительный прибор');
INSERT INTO capability(name) VALUES('Печать PLA'),('Раскрой листа'),('Фрезерование'),('Измерение геометрии');
INSERT INTO type_capability VALUES(1,1),(2,2),(3,2),(3,3),(4,4);
INSERT INTO equipment(type_id,inventory_no,name,characteristics) VALUES
 (1,'FDM-001','Prusa MK4','{"volume_mm":[250,210,220]}'),
 (1,'FDM-002','Bambu P1S','{"volume_mm":[256,256,256]}'),
 (2,'LAS-001','Лазер 60 Вт','{"power_w":60}'),
 (3,'CNC-001','Фрезер учебный','{"axes":3}'),
 (4,'MET-001','Координатный измеритель','{"accuracy_mm":0.01}');
SELECT set_config('labreserve.actor_id','2',true);
INSERT INTO admission(user_id,type_id,valid_during,basis,granted_by)
 SELECT u,t,tstzrange(clock_timestamp()-interval '1 year',clock_timestamp()+interval '2 years','[)'),
 'Пройден инструктаж',2 FROM generate_series(1,3) u CROSS JOIN generate_series(1,4) t;
-- Seeds are relative to execution time; no expiring hard-coded dates.
SELECT create_booking(1,1,1,date_trunc('day',now())+interval '2 days 10 hours',
 date_trunc('day',now())+interval '2 days 12 hours','Печать учебного корпуса') AS b1 \gset
SELECT create_booking(1,2,1,date_trunc('day',now())+interval '3 days 10 hours',
 date_trunc('day',now())+interval '3 days 12 hours','Отменяемая печать') AS b2 \gset
SELECT cancel_booking(1,:b2,'Изменилось задание');
SELECT register_unavailability(3,1,'maintenance',date_trunc('day',now())+interval '2 days 9 hours',
 date_trunc('day',now())+interval '2 days 13 hours','Замена сопла');
SELECT create_booking(1,3,2,date_trunc('day',now())+interval '4 days 10 hours',
 date_trunc('day',now())+interval '4 days 12 hours','Раскрой макета') AS b3 \gset
SELECT report_fault(1,3,'Нестабильное питание лазера') AS f1 \gset
SELECT register_unavailability(2,3,'fault',clock_timestamp()-interval '1 hour',NULL,'Подтверждён отказ питания',:f1) AS u1 \gset
-- A historical resolved failure and a completed real session.
SELECT report_fault(1,4,'Износ направляющей') AS f2 \gset
SELECT register_unavailability(3,4,'fault',clock_timestamp()-interval '3 days',NULL,'Подтверждён износ',:f2) AS u2 \gset
SELECT resolve_unavailability(2,:u2,'Направляющая заменена, проведена проверка');
SELECT set_config('labreserve.actor_id','1',true);
INSERT INTO booking(user_id,equipment_id,capability_id,period,purpose)
 VALUES(1,5,4,tstzrange(clock_timestamp()-interval '10 minutes',clock_timestamp()+interval '1 hour','[)'),
 'Измерение контрольного образца') RETURNING id AS b4 \gset
SELECT open_session(1,:b4) AS s1 \gset
SELECT pg_sleep(0.01);
SELECT close_session(1,:s1);
SELECT create_reminders(now()+interval '7 days');
COMMIT;
