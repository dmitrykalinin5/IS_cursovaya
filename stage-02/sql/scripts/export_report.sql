\set ON_ERROR_STOP on
-- Окно демо: неделя до/после текущего дня. В backend границы передаются параметрами.
\copy (SELECT * FROM labreserve.equipment_metrics(tstzrange(date_trunc('day',now())-interval '7 days',date_trunc('day',now())+interval '7 days'))) TO STDOUT WITH (FORMAT csv, HEADER true)
