\set ON_ERROR_STOP on
\if :{?commit_bulk}
\else
\set commit_bulk off
\endif

BEGIN;
SET LOCAL search_path=s466088,pg_catalog,pg_temp;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
DO $$
BEGIN
 IF current_database()<>'studs' OR current_user<>'s466088' THEN
  RAISE EXCEPTION 'Expected database studs and role s466088';
 END IF;
END $$;
SELECT pg_advisory_xact_lock(hashtext('LabReserve:s466088'),1);

SELECT EXISTS (SELECT 1 FROM lr_app_user WHERE login LIKE 'bulk-lr-%')
    OR EXISTS (SELECT 1 FROM lr_equipment WHERE inventory_no LIKE 'BULK-LR-%') AS bulk_present
\gset
\if :bulk_present
\echo Test data already present. Skipping inserts.
\else
CREATE TEMP TABLE bulk_catalogue ON COMMIT DROP AS
SELECT ref.catalogue_no, e.type_id, tc.capability_id
FROM (VALUES (0,'FDM-002','Печать PLA'),
             (1,'LAS-001','Раскрой листа'),
             (2,'CNC-001','Фрезерование'),
             (3,'MET-001','Измерение геометрии')) AS ref(catalogue_no,inventory_no,capability)
JOIN lr_equipment e ON e.inventory_no=ref.inventory_no
JOIN lr_equipment_type t ON t.id=e.type_id AND NOT t.archived
JOIN lr_type_capability tc ON tc.type_id=e.type_id
JOIN lr_capability c ON c.id=tc.capability_id AND c.name=ref.capability;

DO $$
BEGIN
 IF (SELECT count(DISTINCT type_id) FROM bulk_catalogue)<>4
    OR NOT EXISTS (SELECT 1 FROM lr_app_user WHERE login='admin' AND lr_has_role(id,'admin')) THEN
  RAISE EXCEPTION 'Expected four demo equipment types and an active admin';
 END IF;
END $$;

INSERT INTO lr_app_user(login,full_name)
SELECT 'bulk-lr-'||lpad((n+1)::text,3,'0'), 'Тестовый пользователь '||(n+1)
FROM generate_series(0,239) AS g(n);

INSERT INTO lr_user_role(user_id,role_code)
SELECT id,'user' FROM lr_app_user WHERE login LIKE 'bulk-lr-%';

INSERT INTO lr_equipment(type_id,inventory_no,name,characteristics)
SELECT t.id,'BULK-LR-'||lpad((n+1)::text,3,'0'), t.name||' (тест '||(n+1)||')',
       jsonb_build_object('dataset','bulk-lr','unit',n+1)
FROM generate_series(0,119) AS g(n)
JOIN bulk_catalogue c ON c.catalogue_no=n%4
JOIN lr_equipment_type t ON t.id=c.type_id;

INSERT INTO lr_admission(user_id,type_id,valid_during,basis,granted_by)
SELECT u.id,c.type_id,tstzrange(now()-interval '1 day',now()+interval '1 year','[)'),
       'Массовый тестовый набор BULK-LR',admin.id
FROM lr_app_user u CROSS JOIN bulk_catalogue c
CROSS JOIN lr_app_user admin
WHERE u.login LIKE 'bulk-lr-%' AND admin.login='admin';

CREATE TEMP TABLE bulk_booking_plan ON COMMIT DROP AS
SELECT e.id AS equipment_id, u.id AS user_id, c.capability_id,
       tstzrange(s.start_at,s.start_at+((n+k)%3+1)*interval '30 minutes','[)') AS period,
       (n+k)%10=0 AS cancel
FROM generate_series(0,119) AS device(n)
CROSS JOIN generate_series(0,49) AS slot(k)
JOIN bulk_catalogue c ON c.catalogue_no=n%4
JOIN lr_equipment e ON e.inventory_no='BULK-LR-'||lpad((n+1)::text,3,'0')
JOIN lr_app_user u ON u.login='bulk-lr-'||lpad(((n*31+k*17)%240+1)::text,3,'0')
CROSS JOIN LATERAL (
 SELECT date_trunc('day',now())+interval '7 days 9 hours'
        +k/5*interval '1 day'+(k%5)*interval '2 hours'+(n%3)*interval '10 minutes' AS start_at
) AS s;

INSERT INTO lr_booking(user_id,equipment_id,capability_id,period,purpose)
SELECT user_id,equipment_id,capability_id,period,'Массовый тестовый набор BULK-LR'
FROM bulk_booking_plan
ORDER BY equipment_id,lower(period);

DO $$
DECLARE item record;
BEGIN
 FOR item IN
  SELECT b.id,b.user_id FROM bulk_booking_plan p
  JOIN lr_booking b ON b.equipment_id=p.equipment_id AND b.period=p.period
  WHERE p.cancel
 LOOP
  PERFORM lr_cancel_booking(item.user_id,item.id,'Тестовая отмена BULK-LR');
 END LOOP;
END $$;
\endif

CREATE TEMP VIEW bulk_counts AS
SELECT
 (SELECT count(*) FROM lr_app_user WHERE login LIKE 'bulk-lr-%') AS users,
 (SELECT count(*) FROM lr_user_role r JOIN lr_app_user u ON u.id=r.user_id
    WHERE u.login LIKE 'bulk-lr-%') AS user_roles,
 (SELECT count(*) FROM lr_equipment WHERE inventory_no LIKE 'BULK-LR-%') AS equipment,
 (SELECT count(*) FROM lr_admission WHERE basis='Массовый тестовый набор BULK-LR') AS admissions,
 (SELECT count(*) FROM lr_booking WHERE purpose='Массовый тестовый набор BULK-LR') AS bookings,
 (SELECT count(*) FROM lr_notification WHERE kind='cancelled' AND message='Тестовая отмена BULK-LR') AS cancellation_notices;

DO $$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM bulk_counts WHERE users=240 AND user_roles>=240
   AND equipment=120 AND admissions>=960 AND bookings=6000 AND cancellation_notices=600) THEN
  RAISE EXCEPTION 'Bulk dataset counts differ from the expected fixture';
 END IF;
END $$;

TABLE bulk_counts;
SELECT status,count(*) FROM lr_booking
WHERE purpose='Массовый тестовый набор BULK-LR' GROUP BY status ORDER BY status;

\if :commit_bulk
COMMIT;
\else
ROLLBACK;
\endif
