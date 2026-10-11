\set ON_ERROR_STOP on
SET search_path=labreserve,public;
SELECT e.inventory_no,e.name,equipment_state(e.id) AS state FROM equipment e ORDER BY id;
SELECT id,user_id,equipment_id,period,status FROM booking ORDER BY id;
SELECT booking_id,equipment_id,period,priority,state FROM alternative ORDER BY booking_id,priority,lower(period);
SELECT * FROM equipment_metrics(tstzrange(date_trunc('day',now())-interval '7 days',date_trunc('day',now())+interval '7 days'));
-- Returns no rows when future confirmed bookings do not intersect downtime.
SELECT b.id,u.id FROM booking b JOIN unavailability u USING(equipment_id)
WHERE b.status='confirmed' AND lower(b.period)>now() AND u.status<>'cancelled' AND b.period && u.period::tstzrange;
