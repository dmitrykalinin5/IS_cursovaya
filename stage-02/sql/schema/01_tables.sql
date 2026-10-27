CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE SCHEMA labreserve;
SET search_path = labreserve, public;
CREATE DOMAIN time_window AS tstzrange CHECK (
  NOT isempty(VALUE) AND NOT lower_inf(VALUE) AND isfinite(lower(VALUE))
  AND lower_inc(VALUE) AND NOT upper_inc(VALUE)
  AND (upper_inf(VALUE) OR isfinite(upper(VALUE))));
CREATE TABLE app_user (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 login text NOT NULL UNIQUE CHECK (length(trim(login)) > 0),
 full_name text NOT NULL, password_hash text, active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE app_role (code text PRIMARY KEY CHECK (code IN ('user','admin','technician')));
CREATE TABLE user_role (
 user_id bigint NOT NULL REFERENCES app_user ON DELETE RESTRICT ON UPDATE RESTRICT,
 role_code text NOT NULL REFERENCES app_role ON DELETE RESTRICT ON UPDATE RESTRICT,
 PRIMARY KEY(user_id,role_code)
);
CREATE TABLE equipment_type (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 name text NOT NULL UNIQUE, archived boolean NOT NULL DEFAULT false
);
CREATE TABLE capability (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, name text NOT NULL UNIQUE
);
CREATE TABLE type_capability (
 type_id bigint NOT NULL REFERENCES equipment_type ON DELETE RESTRICT ON UPDATE RESTRICT,
 capability_id bigint NOT NULL REFERENCES capability ON DELETE RESTRICT ON UPDATE RESTRICT,
 PRIMARY KEY(type_id, capability_id)
);
CREATE TABLE equipment (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 type_id bigint NOT NULL REFERENCES equipment_type ON DELETE RESTRICT ON UPDATE RESTRICT,
 inventory_no text NOT NULL UNIQUE, name text NOT NULL,
 characteristics jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(characteristics)='object'),
 archived boolean NOT NULL DEFAULT false,
 schedule_revision bigint NOT NULL DEFAULT 0
);
CREATE TABLE admission (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 user_id bigint NOT NULL REFERENCES app_user ON DELETE RESTRICT ON UPDATE RESTRICT,
 type_id bigint NOT NULL REFERENCES equipment_type ON DELETE RESTRICT ON UPDATE RESTRICT,
 valid_during time_window NOT NULL, basis text NOT NULL,
 granted_by bigint NOT NULL REFERENCES app_user ON DELETE RESTRICT ON UPDATE RESTRICT,
 revoked_at timestamptz, created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE booking (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 user_id bigint NOT NULL REFERENCES app_user ON DELETE RESTRICT ON UPDATE RESTRICT,
 equipment_id bigint NOT NULL REFERENCES equipment ON DELETE RESTRICT ON UPDATE RESTRICT,
 capability_id bigint NOT NULL REFERENCES capability ON DELETE RESTRICT ON UPDATE RESTRICT,
 period time_window NOT NULL CHECK (NOT upper_inf(period)), purpose text NOT NULL,
 status text NOT NULL DEFAULT 'confirmed' CHECK (status IN ('confirmed','needs_transfer','cancelled','completed')),
 cancelled_at timestamptz, cancel_reason text,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CONSTRAINT ck_booking_cancel CHECK ((status='cancelled') = (cancelled_at IS NOT NULL AND cancel_reason IS NOT NULL)),
 CONSTRAINT ex_booking_overlap EXCLUDE USING gist
   (equipment_id WITH =, (period::tstzrange) WITH &&) WHERE (status='confirmed')
);
CREATE TABLE alternative (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 booking_id bigint NOT NULL REFERENCES booking ON DELETE RESTRICT ON UPDATE RESTRICT,
 equipment_id bigint NOT NULL REFERENCES equipment ON DELETE RESTRICT ON UPDATE RESTRICT,
 period time_window NOT NULL CHECK (NOT upper_inf(period)),
 priority smallint NOT NULL CHECK (priority BETWEEN 1 AND 3),
 state text NOT NULL DEFAULT 'offered' CHECK (state IN ('offered','chosen','obsolete')),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(booking_id,equipment_id,period)
);
CREATE TABLE fault_report (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 equipment_id bigint NOT NULL REFERENCES equipment ON DELETE RESTRICT ON UPDATE RESTRICT,
 reported_by bigint NOT NULL REFERENCES app_user ON DELETE RESTRICT ON UPDATE RESTRICT,
 description text NOT NULL, reported_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 state text NOT NULL DEFAULT 'reported' CHECK (state IN ('reported','confirmed','dismissed'))
);
CREATE TABLE unavailability (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 equipment_id bigint NOT NULL REFERENCES equipment ON DELETE RESTRICT ON UPDATE RESTRICT,
 kind text NOT NULL CHECK (kind IN ('maintenance','fault')),
 period time_window NOT NULL, reason text NOT NULL,
 fault_report_id bigint UNIQUE REFERENCES fault_report ON DELETE RESTRICT ON UPDATE RESTRICT,
 created_by bigint NOT NULL REFERENCES app_user ON DELETE RESTRICT ON UPDATE RESTRICT,
 status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','resolved','cancelled')),
 resolved_by bigint REFERENCES app_user ON DELETE RESTRICT ON UPDATE RESTRICT,
 resolved_at timestamptz, created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK ((kind='fault') = (fault_report_id IS NOT NULL)),
 CHECK (kind <> 'maintenance' OR NOT upper_inf(period)),
 CHECK ((status='resolved') = (resolved_by IS NOT NULL AND resolved_at IS NOT NULL))
);
CREATE TABLE repair (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 unavailability_id bigint NOT NULL REFERENCES unavailability ON DELETE RESTRICT ON UPDATE RESTRICT,
 performed_by bigint NOT NULL REFERENCES app_user ON DELETE RESTRICT ON UPDATE RESTRICT,
 work_kind text NOT NULL CHECK (length(trim(work_kind)) > 0),
 period time_window NOT NULL CHECK (NOT upper_inf(period)), result text NOT NULL
);
CREATE TABLE use_session (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 booking_id bigint NOT NULL UNIQUE REFERENCES booking ON DELETE RESTRICT ON UPDATE RESTRICT,
 started_at timestamptz NOT NULL DEFAULT clock_timestamp(), ended_at timestamptz, close_comment text,
 CHECK (ended_at IS NULL OR ended_at > started_at)
);
CREATE TABLE notification (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 user_id bigint NOT NULL REFERENCES app_user ON DELETE RESTRICT ON UPDATE RESTRICT,
 booking_id bigint REFERENCES booking ON DELETE RESTRICT ON UPDATE RESTRICT,
 kind text NOT NULL CHECK (kind IN ('transfer_required','transferred','cancelled','reminder')),
 message text NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp(), read_at timestamptz
);
CREATE TABLE audit_event (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 actor_id bigint REFERENCES app_user ON DELETE RESTRICT ON UPDATE RESTRICT,
 table_name text NOT NULL, record_key jsonb NOT NULL, action text NOT NULL,
 old_data jsonb, new_data jsonb, occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 transaction_id bigint NOT NULL DEFAULT txid_current()
);
CREATE TABLE conflict_event (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 user_id bigint NOT NULL REFERENCES app_user ON DELETE RESTRICT ON UPDATE RESTRICT,
 equipment_id bigint NOT NULL REFERENCES equipment ON DELETE RESTRICT ON UPDATE RESTRICT,
 requested_period time_window NOT NULL CHECK (NOT upper_inf(requested_period)),
 error_code text NOT NULL, occurred_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
