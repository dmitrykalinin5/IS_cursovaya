# Даталогическая модель: словарь данных

Экспорт фактической PostgreSQL-схемы. Все FK: RESTRICT при удалении и обновлении.

## `app_user` — Учётная запись человека; активность и профиль

| Столбец | Тип | NULL | Значение по умолчанию |
|---|---|---|---|
| `id` | `bigint` | NO | `IDENTITY` |
| `login` | `text` | NO | `—` |
| `full_name` | `text` | NO | `—` |
| `password_hash` | `text` | YES | `—` |
| `active` | `boolean` | NO | `true` |
| `created_at` | `timestamptz` | NO | `clock_timestamp()` |

Ограничения:

- `app_user_login_check`: `CHECK ((length(TRIM(BOTH FROM login)) > 0))`.
- `app_user_id_not_null`: `NOT NULL id`.
- `app_user_login_not_null`: `NOT NULL login`.
- `app_user_full_name_not_null`: `NOT NULL full_name`.
- `app_user_active_not_null`: `NOT NULL active`.
- `app_user_created_at_not_null`: `NOT NULL created_at`.
- `app_user_pkey`: `PRIMARY KEY (id)`.
- `app_user_login_key`: `UNIQUE (login)`.

## `app_role` — Три внешние роли предметной области

| Столбец | Тип | NULL | Значение по умолчанию |
|---|---|---|---|
| `code` | `text` | NO | `—` |

Ограничения:

- `app_role_code_check`: `CHECK ((code = ANY (ARRAY['user'::text, 'admin'::text, 'technician'::text])))`.
- `app_role_code_not_null`: `NOT NULL code`.
- `app_role_pkey`: `PRIMARY KEY (code)`.

## `user_role` — Назначение ролей пользователям (M:N)

| Столбец | Тип | NULL | Значение по умолчанию |
|---|---|---|---|
| `user_id` | `bigint` | NO | `—` |
| `role_code` | `text` | NO | `—` |

Ограничения:

- `user_role_user_id_not_null`: `NOT NULL user_id`.
- `user_role_role_code_not_null`: `NOT NULL role_code`.
- `user_role_pkey`: `PRIMARY KEY (user_id, role_code)`.
- `user_role_user_id_fkey`: `FOREIGN KEY (user_id) REFERENCES labreserve.app_user(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `user_role_role_code_fkey`: `FOREIGN KEY (role_code) REFERENCES labreserve.app_role(code) ON UPDATE RESTRICT ON DELETE RESTRICT`.

## `equipment_type` — Тип оборудования и архивирование

| Столбец | Тип | NULL | Значение по умолчанию |
|---|---|---|---|
| `id` | `bigint` | NO | `IDENTITY` |
| `name` | `text` | NO | `—` |
| `archived` | `boolean` | NO | `false` |

Ограничения:

- `equipment_type_id_not_null`: `NOT NULL id`.
- `equipment_type_name_not_null`: `NOT NULL name`.
- `equipment_type_archived_not_null`: `NOT NULL archived`.
- `equipment_type_pkey`: `PRIMARY KEY (id)`.
- `equipment_type_name_key`: `UNIQUE (name)`.

## `capability` — Справочник требуемых функций

| Столбец | Тип | NULL | Значение по умолчанию |
|---|---|---|---|
| `id` | `bigint` | NO | `IDENTITY` |
| `name` | `text` | NO | `—` |

Ограничения:

- `capability_id_not_null`: `NOT NULL id`.
- `capability_name_not_null`: `NOT NULL name`.
- `capability_pkey`: `PRIMARY KEY (id)`.
- `capability_name_key`: `UNIQUE (name)`.

## `type_capability` — Поддерживаемые типом функции (M:N)

| Столбец | Тип | NULL | Значение по умолчанию |
|---|---|---|---|
| `type_id` | `bigint` | NO | `—` |
| `capability_id` | `bigint` | NO | `—` |

Ограничения:

- `type_capability_type_id_not_null`: `NOT NULL type_id`.
- `type_capability_capability_id_not_null`: `NOT NULL capability_id`.
- `type_capability_pkey`: `PRIMARY KEY (type_id, capability_id)`.
- `type_capability_type_id_fkey`: `FOREIGN KEY (type_id) REFERENCES labreserve.equipment_type(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `type_capability_capability_id_fkey`: `FOREIGN KEY (capability_id) REFERENCES labreserve.capability(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.

## `equipment` — Инвентарная единица, характеристики, архив

| Столбец | Тип | NULL | Значение по умолчанию |
|---|---|---|---|
| `id` | `bigint` | NO | `IDENTITY` |
| `type_id` | `bigint` | NO | `—` |
| `inventory_no` | `text` | NO | `—` |
| `name` | `text` | NO | `—` |
| `characteristics` | `jsonb` | NO | `'{}'::jsonb` |
| `archived` | `boolean` | NO | `false` |
| `schedule_revision` | `bigint` | NO | `0` |

Ограничения:

- `equipment_characteristics_check`: `CHECK ((jsonb_typeof(characteristics) = 'object'::text))`.
- `equipment_id_not_null`: `NOT NULL id`.
- `equipment_type_id_not_null1`: `NOT NULL type_id`.
- `equipment_inventory_no_not_null`: `NOT NULL inventory_no`.
- `equipment_name_not_null`: `NOT NULL name`.
- `equipment_characteristics_not_null`: `NOT NULL characteristics`.
- `equipment_archived_not_null`: `NOT NULL archived`.
- `equipment_schedule_revision_not_null`: `NOT NULL schedule_revision`.
- `equipment_pkey`: `PRIMARY KEY (id)`.
- `equipment_inventory_no_key`: `UNIQUE (inventory_no)`.
- `equipment_type_id_fkey`: `FOREIGN KEY (type_id) REFERENCES labreserve.equipment_type(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.

## `admission` — Допуск к типу; период, основание, автор и отзыв

| Столбец | Тип | NULL | Значение по умолчанию |
|---|---|---|---|
| `id` | `bigint` | NO | `IDENTITY` |
| `user_id` | `bigint` | NO | `—` |
| `type_id` | `bigint` | NO | `—` |
| `valid_during` | `time_window` | NO | `—` |
| `basis` | `text` | NO | `—` |
| `granted_by` | `bigint` | NO | `—` |
| `revoked_at` | `timestamptz` | YES | `—` |
| `created_at` | `timestamptz` | NO | `clock_timestamp()` |

Ограничения:

- `admission_id_not_null`: `NOT NULL id`.
- `admission_user_id_not_null`: `NOT NULL user_id`.
- `admission_type_id_not_null`: `NOT NULL type_id`.
- `admission_valid_during_not_null`: `NOT NULL valid_during`.
- `admission_basis_not_null`: `NOT NULL basis`.
- `admission_granted_by_not_null`: `NOT NULL granted_by`.
- `admission_created_at_not_null`: `NOT NULL created_at`.
- `admission_pkey`: `PRIMARY KEY (id)`.
- `admission_user_id_fkey`: `FOREIGN KEY (user_id) REFERENCES labreserve.app_user(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `admission_type_id_fkey`: `FOREIGN KEY (type_id) REFERENCES labreserve.equipment_type(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `admission_granted_by_fkey`: `FOREIGN KEY (granted_by) REFERENCES labreserve.app_user(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.

## `booking` — Плановый интервал, владелец, цель и жизненный цикл

| Столбец | Тип | NULL | Значение по умолчанию |
|---|---|---|---|
| `id` | `bigint` | NO | `IDENTITY` |
| `user_id` | `bigint` | NO | `—` |
| `equipment_id` | `bigint` | NO | `—` |
| `capability_id` | `bigint` | NO | `—` |
| `period` | `time_window` | NO | `—` |
| `purpose` | `text` | NO | `—` |
| `status` | `text` | NO | `'confirmed'::text` |
| `cancelled_at` | `timestamptz` | YES | `—` |
| `cancel_reason` | `text` | YES | `—` |
| `created_at` | `timestamptz` | NO | `clock_timestamp()` |

Ограничения:

- `booking_period_check`: `CHECK ((NOT upper_inf((period)::tstzrange)))`.
- `booking_status_check`: `CHECK ((status = ANY (ARRAY['confirmed'::text, 'needs_transfer'::text, 'cancelled'::text, 'completed'::text])))`.
- `ck_booking_cancel`: `CHECK (((status = 'cancelled'::text) = ((cancelled_at IS NOT NULL) AND (cancel_reason IS NOT NULL))))`.
- `booking_id_not_null`: `NOT NULL id`.
- `booking_user_id_not_null`: `NOT NULL user_id`.
- `booking_equipment_id_not_null`: `NOT NULL equipment_id`.
- `booking_capability_id_not_null`: `NOT NULL capability_id`.
- `booking_period_not_null`: `NOT NULL period`.
- `booking_purpose_not_null`: `NOT NULL purpose`.
- `booking_status_not_null`: `NOT NULL status`.
- `booking_created_at_not_null`: `NOT NULL created_at`.
- `booking_pkey`: `PRIMARY KEY (id)`.
- `ex_booking_overlap`: `EXCLUDE USING gist (equipment_id WITH =, ((period)::tstzrange) WITH &&) WHERE ((status = 'confirmed'::text))`.
- `booking_user_id_fkey`: `FOREIGN KEY (user_id) REFERENCES labreserve.app_user(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `booking_equipment_id_fkey`: `FOREIGN KEY (equipment_id) REFERENCES labreserve.equipment(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `booking_capability_id_fkey`: `FOREIGN KEY (capability_id) REFERENCES labreserve.capability(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.

## `alternative` — Историческое предложение переноса и выбор

| Столбец | Тип | NULL | Значение по умолчанию |
|---|---|---|---|
| `id` | `bigint` | NO | `IDENTITY` |
| `booking_id` | `bigint` | NO | `—` |
| `equipment_id` | `bigint` | NO | `—` |
| `period` | `time_window` | NO | `—` |
| `priority` | `smallint` | NO | `—` |
| `state` | `text` | NO | `'offered'::text` |
| `created_at` | `timestamptz` | NO | `clock_timestamp()` |

Ограничения:

- `alternative_booking_id_not_null`: `NOT NULL booking_id`.
- `alternative_equipment_id_not_null`: `NOT NULL equipment_id`.
- `alternative_period_not_null`: `NOT NULL period`.
- `alternative_priority_not_null`: `NOT NULL priority`.
- `alternative_state_not_null`: `NOT NULL state`.
- `alternative_period_check`: `CHECK ((NOT upper_inf((period)::tstzrange)))`.
- `alternative_priority_check`: `CHECK (((priority >= 1) AND (priority <= 3)))`.
- `alternative_state_check`: `CHECK ((state = ANY (ARRAY['offered'::text, 'chosen'::text, 'obsolete'::text])))`.
- `alternative_id_not_null`: `NOT NULL id`.
- `alternative_created_at_not_null`: `NOT NULL created_at`.
- `alternative_pkey`: `PRIMARY KEY (id)`.
- `alternative_booking_id_equipment_id_period_key`: `UNIQUE (booking_id, equipment_id, period)`.
- `alternative_booking_id_fkey`: `FOREIGN KEY (booking_id) REFERENCES labreserve.booking(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `alternative_equipment_id_fkey`: `FOREIGN KEY (equipment_id) REFERENCES labreserve.equipment(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.

## `fault_report` — Первичное сообщение и результат проверки

| Столбец | Тип | NULL | Значение по умолчанию |
|---|---|---|---|
| `id` | `bigint` | NO | `IDENTITY` |
| `equipment_id` | `bigint` | NO | `—` |
| `reported_by` | `bigint` | NO | `—` |
| `description` | `text` | NO | `—` |
| `reported_at` | `timestamptz` | NO | `clock_timestamp()` |
| `state` | `text` | NO | `'reported'::text` |

Ограничения:

- `fault_report_state_check`: `CHECK ((state = ANY (ARRAY['reported'::text, 'confirmed'::text, 'dismissed'::text])))`.
- `fault_report_id_not_null`: `NOT NULL id`.
- `fault_report_equipment_id_not_null`: `NOT NULL equipment_id`.
- `fault_report_reported_by_not_null`: `NOT NULL reported_by`.
- `fault_report_description_not_null`: `NOT NULL description`.
- `fault_report_reported_at_not_null`: `NOT NULL reported_at`.
- `fault_report_state_not_null`: `NOT NULL state`.
- `fault_report_pkey`: `PRIMARY KEY (id)`.
- `fault_report_equipment_id_fkey`: `FOREIGN KEY (equipment_id) REFERENCES labreserve.equipment(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `fault_report_reported_by_fkey`: `FOREIGN KEY (reported_by) REFERENCES labreserve.app_user(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.

## `unavailability` — Период ТО либо подтверждённой неисправности

| Столбец | Тип | NULL | Значение по умолчанию |
|---|---|---|---|
| `id` | `bigint` | NO | `IDENTITY` |
| `equipment_id` | `bigint` | NO | `—` |
| `kind` | `text` | NO | `—` |
| `period` | `time_window` | NO | `—` |
| `reason` | `text` | NO | `—` |
| `fault_report_id` | `bigint` | YES | `—` |
| `created_by` | `bigint` | NO | `—` |
| `status` | `text` | NO | `'active'::text` |
| `resolved_by` | `bigint` | YES | `—` |
| `resolved_at` | `timestamptz` | YES | `—` |
| `created_at` | `timestamptz` | NO | `clock_timestamp()` |

Ограничения:

- `unavailability_kind_check`: `CHECK ((kind = ANY (ARRAY['maintenance'::text, 'fault'::text])))`.
- `unavailability_status_check`: `CHECK ((status = ANY (ARRAY['active'::text, 'resolved'::text, 'cancelled'::text])))`.
- `unavailability_check`: `CHECK (((kind = 'fault'::text) = (fault_report_id IS NOT NULL)))`.
- `unavailability_check1`: `CHECK (((kind <> 'maintenance'::text) OR (NOT upper_inf((period)::tstzrange))))`.
- `unavailability_check2`: `CHECK (((status = 'resolved'::text) = ((resolved_by IS NOT NULL) AND (resolved_at IS NOT NULL))))`.
- `unavailability_id_not_null`: `NOT NULL id`.
- `unavailability_equipment_id_not_null`: `NOT NULL equipment_id`.
- `unavailability_kind_not_null`: `NOT NULL kind`.
- `unavailability_period_not_null`: `NOT NULL period`.
- `unavailability_reason_not_null`: `NOT NULL reason`.
- `unavailability_created_by_not_null`: `NOT NULL created_by`.
- `unavailability_status_not_null`: `NOT NULL status`.
- `unavailability_created_at_not_null`: `NOT NULL created_at`.
- `unavailability_pkey`: `PRIMARY KEY (id)`.
- `unavailability_fault_report_id_key`: `UNIQUE (fault_report_id)`.
- `unavailability_equipment_id_fkey`: `FOREIGN KEY (equipment_id) REFERENCES labreserve.equipment(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `unavailability_fault_report_id_fkey`: `FOREIGN KEY (fault_report_id) REFERENCES labreserve.fault_report(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `unavailability_created_by_fkey`: `FOREIGN KEY (created_by) REFERENCES labreserve.app_user(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `unavailability_resolved_by_fkey`: `FOREIGN KEY (resolved_by) REFERENCES labreserve.app_user(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.

## `repair` — Исполнитель и результат технической работы

| Столбец | Тип | NULL | Значение по умолчанию |
|---|---|---|---|
| `id` | `bigint` | NO | `IDENTITY` |
| `unavailability_id` | `bigint` | NO | `—` |
| `performed_by` | `bigint` | NO | `—` |
| `period` | `time_window` | NO | `—` |
| `result` | `text` | NO | `—` |

Ограничения:

- `repair_period_check`: `CHECK ((NOT upper_inf((period)::tstzrange)))`.
- `repair_id_not_null`: `NOT NULL id`.
- `repair_unavailability_id_not_null`: `NOT NULL unavailability_id`.
- `repair_performed_by_not_null`: `NOT NULL performed_by`.
- `repair_period_not_null`: `NOT NULL period`.
- `repair_result_not_null`: `NOT NULL result`.
- `repair_pkey`: `PRIMARY KEY (id)`.
- `repair_unavailability_id_fkey`: `FOREIGN KEY (unavailability_id) REFERENCES labreserve.unavailability(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `repair_performed_by_fkey`: `FOREIGN KEY (performed_by) REFERENCES labreserve.app_user(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.

## `use_session` — Фактические начало и окончание работы

| Столбец | Тип | NULL | Значение по умолчанию |
|---|---|---|---|
| `id` | `bigint` | NO | `IDENTITY` |
| `booking_id` | `bigint` | NO | `—` |
| `started_at` | `timestamptz` | NO | `clock_timestamp()` |
| `ended_at` | `timestamptz` | YES | `—` |
| `close_comment` | `text` | YES | `—` |

Ограничения:

- `use_session_check`: `CHECK (((ended_at IS NULL) OR (ended_at > started_at)))`.
- `use_session_id_not_null`: `NOT NULL id`.
- `use_session_booking_id_not_null`: `NOT NULL booking_id`.
- `use_session_started_at_not_null`: `NOT NULL started_at`.
- `use_session_pkey`: `PRIMARY KEY (id)`.
- `use_session_booking_id_key`: `UNIQUE (booking_id)`.
- `use_session_booking_id_fkey`: `FOREIGN KEY (booking_id) REFERENCES labreserve.booking(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.

## `notification` — Внутрисистемное уведомление и прочтение

| Столбец | Тип | NULL | Значение по умолчанию |
|---|---|---|---|
| `id` | `bigint` | NO | `IDENTITY` |
| `user_id` | `bigint` | NO | `—` |
| `booking_id` | `bigint` | YES | `—` |
| `kind` | `text` | NO | `—` |
| `message` | `text` | NO | `—` |
| `created_at` | `timestamptz` | NO | `clock_timestamp()` |
| `read_at` | `timestamptz` | YES | `—` |

Ограничения:

- `notification_kind_check`: `CHECK ((kind = ANY (ARRAY['transfer_required'::text, 'transferred'::text, 'cancelled'::text, 'reminder'::text])))`.
- `notification_id_not_null`: `NOT NULL id`.
- `notification_user_id_not_null`: `NOT NULL user_id`.
- `notification_kind_not_null`: `NOT NULL kind`.
- `notification_message_not_null`: `NOT NULL message`.
- `notification_created_at_not_null`: `NOT NULL created_at`.
- `notification_pkey`: `PRIMARY KEY (id)`.
- `notification_user_id_fkey`: `FOREIGN KEY (user_id) REFERENCES labreserve.app_user(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `notification_booking_id_fkey`: `FOREIGN KEY (booking_id) REFERENCES labreserve.booking(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.

## `audit_event` — Неизменяемый журнал значимых изменений

| Столбец | Тип | NULL | Значение по умолчанию |
|---|---|---|---|
| `id` | `bigint` | NO | `IDENTITY` |
| `actor_id` | `bigint` | YES | `—` |
| `table_name` | `text` | NO | `—` |
| `record_key` | `jsonb` | NO | `—` |
| `action` | `text` | NO | `—` |
| `old_data` | `jsonb` | YES | `—` |
| `new_data` | `jsonb` | YES | `—` |
| `occurred_at` | `timestamptz` | NO | `clock_timestamp()` |
| `transaction_id` | `bigint` | NO | `txid_current()` |

Ограничения:

- `audit_event_id_not_null`: `NOT NULL id`.
- `audit_event_table_name_not_null`: `NOT NULL table_name`.
- `audit_event_record_key_not_null`: `NOT NULL record_key`.
- `audit_event_action_not_null`: `NOT NULL action`.
- `audit_event_occurred_at_not_null`: `NOT NULL occurred_at`.
- `audit_event_transaction_id_not_null`: `NOT NULL transaction_id`.
- `audit_event_pkey`: `PRIMARY KEY (id)`.
- `audit_event_actor_id_fkey`: `FOREIGN KEY (actor_id) REFERENCES labreserve.app_user(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.

## `conflict_event` — Отклонённый запрос для статистики конфликтов

| Столбец | Тип | NULL | Значение по умолчанию |
|---|---|---|---|
| `id` | `bigint` | NO | `IDENTITY` |
| `user_id` | `bigint` | NO | `—` |
| `equipment_id` | `bigint` | NO | `—` |
| `requested_period` | `time_window` | NO | `—` |
| `error_code` | `text` | NO | `—` |
| `occurred_at` | `timestamptz` | NO | `clock_timestamp()` |

Ограничения:

- `conflict_event_requested_period_check`: `CHECK ((NOT upper_inf((requested_period)::tstzrange)))`.
- `conflict_event_id_not_null`: `NOT NULL id`.
- `conflict_event_user_id_not_null`: `NOT NULL user_id`.
- `conflict_event_equipment_id_not_null`: `NOT NULL equipment_id`.
- `conflict_event_requested_period_not_null`: `NOT NULL requested_period`.
- `conflict_event_error_code_not_null`: `NOT NULL error_code`.
- `conflict_event_occurred_at_not_null`: `NOT NULL occurred_at`.
- `conflict_event_pkey`: `PRIMARY KEY (id)`.
- `conflict_event_user_id_fkey`: `FOREIGN KEY (user_id) REFERENCES labreserve.app_user(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `conflict_event_equipment_id_fkey`: `FOREIGN KEY (equipment_id) REFERENCES labreserve.equipment(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
