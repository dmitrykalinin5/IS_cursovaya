# Индексы

13 явных индексов; 25 автоматически созданных для PK/UNIQUE/EXCLUDE, всего 38. Каждый индекс требует места, WAL и обновления при записи. FK сами не создают индекс. Полные определения ниже.

## `ix_equipment_type_active`

```sql
CREATE INDEX ix_equipment_type_active ON labreserve.equipment USING btree (type_id, id) WHERE (NOT archived);
```

- Тип: B-tree, частичный.
- Запрос: Фильтр активного каталога по типу; компактнее полного индекса.
- Цена/ограничения: Архивирование меняет состав; для всех строк не используется.

## `ix_type_capability_reverse`

```sql
CREATE INDEX ix_type_capability_reverse ON labreserve.type_capability USING btree (capability_id, type_id);
```

- Тип: B-tree, составной.
- Запрос: Поиск типов по функции; PK начинается с type_id.
- Цена/ограничения: Дополнительная запись при изменении M:N.

## `ix_admission_valid`

```sql
CREATE INDEX ix_admission_valid ON labreserve.admission USING gist (user_id, type_id, ((valid_during)::tstzrange)) WHERE (revoked_at IS NULL);
```

- Тип: GiST, частичный.
- Запрос: Пользователь, тип и покрытие временного диапазона.
- Цена/ограничения: GiST дороже B-tree; отзыв обновляет индекс; на 12 строках Seq Scan дешевле.

## `ix_booking_user_future`

```sql
CREATE INDEX ix_booking_user_future ON labreserve.booking USING btree (user_id, lower((period)::tstzrange)) WHERE (status = ANY (ARRAY['confirmed'::text, 'needs_transfer'::text]));
```

- Тип: B-tree, частичный.
- Запрос: Календарь владельца, нижняя граница и LIMIT по времени.
- Цена/ограничения: Предикат по статусу, не по now(); завершение удаляет индексную запись.

## `ix_booking_equipment_period`

```sql
CREATE INDEX ix_booking_equipment_period ON labreserve.booking USING gist (equipment_id, ((period)::tstzrange));
```

- Тип: GiST, полный.
- Запрос: Историческая аналитика и периоды всех статусов.
- Цена/ограничения: Для confirmed дублирует часть возможностей EXCLUDE, но нужен для истории.

## `ix_unavailability_period`

```sql
CREATE INDEX ix_unavailability_period ON labreserve.unavailability USING gist (equipment_id, ((period)::tstzrange)) WHERE (status <> 'cancelled'::text);
```

- Тип: GiST, частичный.
- Запрос: Пересечение ТО/поломок с запросом и состояние на момент времени.
- Цена/ограничения: Цена записи диапазонов; исключает только отменённые причины, включает resolved.

## `ix_alternative_booking_rank`

```sql
CREATE INDEX ix_alternative_booking_rank ON labreserve.alternative USING btree (booking_id, priority, lower((period)::tstzrange)) WHERE (state = 'offered'::text);
```

- Тип: B-tree, частичный.
- Запрос: Список предложений по броне, приоритету и времени.
- Цена/ограничения: После выбора требуется менять индексный состав; варианты не резервируют время.

## `ix_fault_equipment_time`

```sql
CREATE INDEX ix_fault_equipment_time ON labreserve.fault_report USING btree (equipment_id, reported_at DESC);
```

- Тип: B-tree, составной.
- Запрос: Последние сообщения по оборудованию.
- Цена/ограничения: Занимает память; ускорение не измерено на малом журнале.

## `ix_repair_unavailability`

```sql
CREATE INDEX ix_repair_unavailability ON labreserve.repair USING btree (unavailability_id, lower((period)::tstzrange) DESC);
```

- Тип: B-tree, составной.
- Запрос: История работ по причине недоступности.
- Цена/ограничения: Дополнительная стоимость append-only вставки.

## `ix_audit_record_time`

```sql
CREATE INDEX ix_audit_record_time ON labreserve.audit_event USING btree (table_name, ((record_key ->> 'id'::text)), occurred_at DESC);
```

- Тип: B-tree, выражение.
- Запрос: История объекта по имени таблицы, id и времени.
- Цена/ограничения: JSONB ключ вычисляется на вставке; для связующих пар id NULL, нужен иной запрос.

## `ix_notification_unread`

```sql
CREATE INDEX ix_notification_unread ON labreserve.notification USING btree (user_id, created_at) WHERE (read_at IS NULL);
```

- Тип: B-tree, частичный.
- Запрос: Непрочитанные уведомления владельца.
- Цена/ограничения: Прочтение удаляет индексную запись.

## `ux_notification_reminder`

```sql
CREATE UNIQUE INDEX ux_notification_reminder ON labreserve.notification USING btree (booking_id, kind) WHERE (kind = 'reminder'::text);
```

- Тип: B-tree, UNIQUE, частичный.
- Запрос: Идемпотентный запуск планировщика.
- Цена/ограничения: Одна запись reminder на бронь; после переноса повторная политика требует уточнения.

## `ix_conflict_equipment_time`

```sql
CREATE INDEX ix_conflict_equipment_time ON labreserve.conflict_event USING btree (equipment_id, occurred_at);
```

- Тип: B-tree, составной.
- Запрос: Отказы по оборудованию и времени события.
- Цена/ограничения: Статистика отражает только API request_booking.

## Автоматические индексы

`ex_booking_overlap` — составной частичный GiST. Помимо целостности ускоряет confirmed-overlap; PK/UNIQUE дают B-tree для ссылок и точного поиска.

Результаты EXPLAIN на 1 000 дополнительных единицах и 20 000 бронях: см. TESTING.md и explain-results.txt. Измерение единичное, прогретый локальный кэш; ускорение относительно системы без индексов не доказано. Для Q1 планировщик выбрал EXCLUDE даже при наличии полного GiST.