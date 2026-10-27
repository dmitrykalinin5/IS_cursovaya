# Согласованная модель и её реализация

Основа второго этапа — `../../ER-модель_final.drawio.xml` и соответствующая PNG из корня проекта. Пользователь подтвердил согласование с преподавателем 27.10.2026. Оригиналы не изменяются.

Для показа в draw.io: `../diagrams/conceptual_approved.drawio` или `conceptual_approved.xml` — точные копии исходного XML. PNG — точная копия исходного изображения. На модели 13 сущностей, 20 линий и две M:N.

| Сущность | Таблица PostgreSQL | Атрибуты и реализация |
|---|---|---|
| Пользователь | app_user | id, login, full_name, active; password_hash и created_at — детали реализации |
| Роль | app_role | code — первичный ключ |
| Допуск | admission | id, valid_during, basis, revoked_at; user_id и type_id реализуют связи; granted_by фиксирует выдавшего |
| Тип оборудования | equipment_type | id, name, archived |
| Единица оборудования | equipment | id, inventory_no, name, characteristics; type_id, archived и schedule_revision — связи и технические поля |
| Функция оборудования | capability | id, name |
| Бронирование | booking | id, period, purpose, status; ссылки user_id, equipment_id, capability_id |
| Предложение переноса | alternative | id, period, priority, state; booking_id и equipment_id |
| Сеанс использования оборудования | use_session | id, started_at, ended_at, close_comment; уникальный booking_id |
| Уведомление | notification | id, kind, message, created_at, read_at; user_id и необязательный booking_id |
| Сообщение о неисправности | fault_report | id, description, reported_at, state; equipment_id и reported_by |
| Техническое событие | unavailability | id, kind, period, reason, status; equipment_id, fault_report_id, created_by, resolved_by |
| Техническая работа | repair | id, work_kind, period, result; unavailability_id и performed_by |

## Преобразование связей

- Пользователь ↔ Роль M:N раскрывается `user_role(user_id, role_code)` с составным PK.
- Тип ↔ Функция M:N раскрывается `type_capability(type_id, capability_id)` с составным PK.
- Остальные связи реализуются FK. UNIQUE на `use_session.booking_id` и `unavailability.fault_report_id` обеспечивает максимумы 1:1.
- Необязательность уточняется NULL: будущая бронь не имеет сеанса; отклонённое сообщение не имеет технического события; ТО не связано с сообщением. Согласованные максимальные кратности сохраняются.
- Авторы выдачи допуска и завершения события уточняют роли участников на физическом уровне.

## Почему 17 таблиц при 13 сущностях

13 предметных + 2 связующие M:N + 2 служебных журнала = 17 таблиц. `audit_event` сохраняет историю изменений, `conflict_event` — неудачные попытки для статистики первого этапа. Это вспомогательные структуры реализации, а не дополнительные согласованные предметные сущности. Они описаны в словаре данных; на основной даталогической диаграмме сохранена расстановка согласованных сущностей без служебных журналов.

SQL-имена `unavailability`, `alternative`, `repair` сохранены для совместимости существующих функций и базы на Helios. Русские названия в модели не требуют буквального совпадения с английскими идентификаторами.

`repair.work_kind` добавлен по согласованной модели. При завершении события функция сохраняет `maintenance` (обслуживание) либо `repair` (ремонт); произвольная непустая классификация допустима на уровне таблицы. Ранее установленная версия на Helios этого поля не имела; для неё подготовлена и 27.10.2026 применена отдельная миграция без удаления данных. Результаты — `approved-helios-remote/summary.json`.
