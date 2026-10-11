\set ON_ERROR_STOP on
-- DBA supplies an EXISTING backend DB role: psql -v app_role=labreserve_backend ...
-- Web clients never connect directly. Actor IDs come from authenticated server identity.
GRANT USAGE ON SCHEMA labreserve TO :"app_role";
GRANT SELECT ON ALL TABLES IN SCHEMA labreserve TO :"app_role";
SELECT format('GRANT EXECUTE ON FUNCTION %s TO %I',p.oid::regprocedure,:'app_role')
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='labreserve' AND p.proname IN
 ('free_intervals','equivalent_equipment','find_alternatives','equipment_state','equipment_metrics',
 'create_booking','request_booking','cancel_booking','select_alternative','report_fault',
 'register_unavailability','edit_maintenance','resolve_unavailability','open_session','close_session',
 'offer_alternatives','create_reminders','grant_admission','revoke_admission') \gexec
