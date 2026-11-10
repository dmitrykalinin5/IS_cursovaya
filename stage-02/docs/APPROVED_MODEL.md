# Соответствие согласованной модели PostgreSQL

Согласованный источник: `../ER-модель_final.drawio.xml/png`. Редактируемая даталогическая схема: `../diagrams/logical.xml`. Исходная компоновка сохранена; XML не перезаписывается генератором.

| Сущность | Таблица | Основные атрибуты |
|---|---|---|
| Пользователь | app_user | id, login, full_name, active |
| Роль | app_role | code |
| Допуск | admission | id, valid_during, basis, revoked_at |
| Тип оборудования | equipment_type | id, name, archived |
| Единица оборудования | equipment | id, inventory_no, name, characteristics |
| Функция оборудования | capability | id, name |
| Бронирование | booking | id, period, purpose, status |
| Предложение переноса | alternative | id, period, priority, state |
| Сеанс использования | use_session | id, started_at, ended_at, close_comment |
| Уведомление | notification | id, kind, message, created_at, read_at |
| Сообщение о неисправности | fault_report | id, description, reported_at, state |
| Техническое событие | unavailability | id, kind, period, reason, status |
| Техническая работа | repair | id, work_kind, period, result |

M:N раскрыты таблицами user_role(user_id,role_code) и type_capability(type_id,capability_id). Итого 15 таблиц, 24 FK. Все поля и ключи из фактического экспорта PostgreSQL показаны в DATA_DICTIONARY.md.

Общий аудит и журнал отказов удалены из реализации по указанию пользователя 09.11.2026. Таблица установки также удалена: метаданные версии перенесены в комментарий PostgreSQL к lr_app_user. Поэтому на Helios имеется ровно 15 таблиц с префиксом lr_. Старые журналы сохраняются перед миграцией в отдельном резервном архиве вне Git; строки 15 таблиц модели при миграции не меняются.
