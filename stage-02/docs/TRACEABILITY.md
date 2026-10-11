# Матрица трассируемости

| UC/FR/BR | Объект/ограничение | Функция/триггер | Проверка и граница покрытия |
|---|---|---|---|
| UC-01 | booking, admission, alternative, use_session | create/select/open/close | T01–11,16–19,30–34,44,52–53; C01,C04 |
| UC-02 | unavailability, fault_report, repair, notification | register/edit/resolve; impact | T12–29; C02,C03,C05 |
| UC-03 | catalogue, admission, audit, conflict | grant/revoke; metrics | T35–40,45–50,56; Q3–Q5 |
| FR-01 | app_user, user_role | assert_owner, require_staff | T11,25,45,58–60; аутентификация — этап 3 |
| FR-02 | equipment_type, equipment, type_capability | DDL, audit_change | seed; интерфейс администратора — этап 3 |
| FR-03 | equipment, unavailability | equipment_state | T22,27,29 |
| FR-04 | admission | grant/revoke_admission | T45–50 |
| FR-05 | equipment, booking, unavailability | free_intervals | T42; Q1–Q3 |
| FR-06 | booking, capability | create_booking | T01,09 |
| FR-07 | admission, booking, unavailability | check_booking | T02–04,15,24,47–49 |
| FR-08 | booking, equipment | create_booking; EXCLUDE | C01,C04,C05 |
| FR-09 | booking, notification | cancel_booking | T06,07,11 |
| FR-10 | booking, unavailability | free_intervals, find_alternatives | T42,46 |
| FR-11 | type_capability, admission | equivalent_equipment | T40 |
| FR-12 | alternative | find/offer_alternatives | T13,19,26,28 |
| FR-13 | booking, alternative | select_alternative | T16–18,44 |
| FR-14 | unavailability | register/edit_maintenance | T12,20 |
| FR-15 | booking, alternative | impact_bookings | T12–15 |
| FR-16 | fault_report, unavailability | report_fault, register_unavailability | T21–25 |
| FR-17 | alternative, notification | impact_bookings | T23,26,28 |
| FR-18 | repair, unavailability | resolve_unavailability | T27,29 |
| FR-19 | use_session, booking | open/close_session | T30–34,52,53 |
| FR-20 | booking, use_session | equipment_metrics | T57 |
| FR-21 | notification | cancel/select/impact/reminders | T14,43 |
| FR-22 | booking, use_session, conflict_event | equipment_metrics | T38,39,56 |
| FR-23 | equipment_metrics result | export_report.sql | CSV выполнен; UI-фильтры — этап 3/4 |
| FR-24 | audit_event | audit_change; audit_immutable | T35,36 |
| BR-1 | admission, app_user | check_booking; grant/revoke | T02,03,47–49 |
| BR-2 | ex_booking_overlap | EXCLUDE + lock_equipment | T04,05; C01,C04 |
| BR-3 | unavailability | booking_guard; impact | T15,24,27; C02,C03 |
| BR-4 | time_window | CHECK + диапазон | T08,54 |
| BR-5 | type_capability | equivalent/find; check_booking | T09,40 |
| BR-6 | alternative.priority | find_alternatives | T19 |
| BR-7 | booking.status | impact; select_alternative | T12,20,23 |
| BR-8 | audit, booking, admission | history guards | T07,34–36,41,50,51 |
| BR-9 | use_session | session guards; open/close | T10,30–33,52,53 |
| BR-10 | timestamptz, tstzrange | time_window; TZ отображения | T05,37 |
