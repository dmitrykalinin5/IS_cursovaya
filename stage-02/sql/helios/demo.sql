\set ON_ERROR_STOP on
SET search_path=s466088,pg_catalog;
-- Catalogue, current technical status and admission validity.
SELECT e.inventory_no,e.name,t.name AS equipment_type,lr_equipment_state(e.id) AS state
 FROM lr_equipment e JOIN lr_equipment_type t ON t.id=e.type_id WHERE NOT e.archived ORDER BY e.id;
SELECT u.login,t.name,a.valid_during,a.revoked_at FROM lr_admission a
 JOIN lr_app_user u ON u.id=a.user_id JOIN lr_equipment_type t ON t.id=a.type_id ORDER BY a.id;
SELECT b.id,u.login,e.inventory_no,b.period,b.status FROM lr_booking b
 JOIN lr_app_user u ON u.id=b.user_id JOIN lr_equipment e ON e.id=b.equipment_id ORDER BY b.id LIMIT 30;
SELECT booking_id,equipment_id,period,priority,state FROM lr_alternative ORDER BY id LIMIT 30;
SELECT kind,message,created_at FROM lr_notification ORDER BY id DESC LIMIT 10;
SELECT table_name,action,record_key,occurred_at FROM lr_audit_event ORDER BY id DESC LIMIT 10;
SELECT * FROM lr_equipment_metrics(tstzrange(date_trunc('day',now())-interval '7 days',
 date_trunc('day',now())+interval '7 days','[)'));
-- Expected: zero rows.
SELECT a.id,b.id FROM lr_booking a JOIN lr_booking b ON a.equipment_id=b.equipment_id
 AND a.id<b.id AND a.status='confirmed' AND b.status='confirmed' AND a.period && b.period::tstzrange;
SELECT overlap_mode,seeded,installed_at FROM lr_deployment;
