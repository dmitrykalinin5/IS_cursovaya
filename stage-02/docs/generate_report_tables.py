#!/usr/bin/env python3
import json,re
from pathlib import Path
root=Path(__file__).resolve().parents[1]
m=json.loads((root/'docs/datalogical.json').read_text())
purposes=json.loads((root/'docs/entities.json').read_text())
def tx(s):
 return str(s).replace('\\',r'\textbackslash{}').replace('_',r'\_\allowbreak{}').replace('/',r'/\allowbreak{}').replace('%',r'\%').replace('&',r'\&').replace('#',r'\#')
def table(headers,rows,widths):
 out=[r'\begin{singlespace}\small',r'\begin{longtable}{'+''.join(r'>{\raggedright\arraybackslash}p{'+str(w)+r'\textwidth}' for w in widths)+'}',r'\toprule '+' & '.join(headers)+r'\\\midrule\endfirsthead',r'\toprule '+' & '.join(headers)+r'\\\midrule\endhead']
 out += [' & '.join(tx(c) for c in r)+r' \\' for r in rows]
 out += [r'\bottomrule\end{longtable}\end{singlespace}']
 return '\n'.join(out)
(root/'docs/entities.tex').write_text(table(['Таблица','Назначение'],list(purposes.items()),[.32,.6]))
api={
'free_intervals':('Максимальные свободные диапазоны в конечном окне; можно исключить переносимую бронь.','SETOF tstzrange','22023: некорректное окно.','Предварительный снимок; объединение броней и технических периодов.','UC-01; FR-05,10; BR-2,3,10; T42'),
'equivalent_equipment':('Свободные единицы с требуемой функцией и допуском на весь интервал.','SETOF equipment','Пустое множество при отсутствии вариантов.','Не резервирует найденные слоты.','UC-01; FR-11; BR-1,5; T40'),
'find_alternatives':('До 12 вариантов в горизонте; пересекает свободные интервалы со сроками допусков.','equipment_id, period, priority','22023: неверный диапазон или горизонт.','Сортировка BR-6: 1,2,3; затем время и id.','UC-01/02; FR-10–12; BR-5,6; T13,19,26,28,46'),
'offer_alternatives':('Сохраняет предложения к существующей брони; прежние предложения устаревают.','integer: число предложений','P0002: бронь отсутствует.','Выбор пользователя не имитируется; предложения не занимают слот.','UC-01/02; FR-12,15,17; BR-7; T13,20'),
'create_booking':('Подтверждает будущую бронь; p_user — удостоверенный пользователь.','bigint: id брони','23514: допуск/архив/недоступность; 23P01: пересечение; 22000: обратный диапазон.','Атомарный INSERT, триггер и EXCLUDE.','UC-01; FR-06–08; BR-1–4; T01–09; C01,C04'),
'request_booking':('Обёртка создания: сохраняет причину отклонения без исключения для ожидаемого конфликта.','booking_id либо error_code','Ожидаемые 23514/23P01 возвращаются; прочие исключения передаются выше.','Запись отказа сохранится только при COMMIT внешней транзакции.','UC-01/03; FR-08,22; T38'),
'cancel_booking':('Владелец либо администратор отменяет будущую активную бронь с причиной.','void','42501: чужая бронь; 23514: прошлая/терминальная бронь или существующий сеанс.','Отмена и уведомление атомарны; история сохраняется.','UC-01; FR-09,21; BR-8; T06,07,11'),
'select_alternative':('Владелец либо администратор подтверждает сохранённое предложение.','void','23514: устаревший вариант; 23P01: конкурентная бронь; 42501: нет прав.','Блокировка обеих единиц; повторная проверка допуска, функции и календаря.','UC-01/02; FR-13; BR-5–7; T16–18,44'),
'report_fault':('Активный человек сообщает о неисправности без автоматического изменения доступности.','bigint: id сообщения','42501: неактивный автор; 23503: нет оборудования.','Сохраняется сообщение и аудит.','UC-02; FR-16; T21'),
'register_unavailability':('Техник либо администратор регистрирует ТО или подтверждает поломку. NULL p_end — неизвестный конец поломки.','bigint: id периода','42501: роль; 23514: несоответствие сообщения/периода; 23503: ссылки.','Период, маркировка будущих броней, варианты и уведомления в одной транзакции.','UC-02; FR-14–17; BR-3,7; T12–15,22–25; C02,C03,C05'),
'edit_maintenance':('Изменение периода и причины активного ТО либо его отмена.','void','23514: неактивное ТО/иная причина; 42501: роль.','Новые затронутые брони маркируются; отмена не подтверждает их сама.','UC-02; FR-14,15; BR-7,8; T20'),
'equipment_state':('Состояние на момент p_at: archived, fault, maintenance, available.','text','NULL при неизвестной единице.','Единый вычисляемый источник состояния по всем причинам.','UC-02/03; FR-03; T22,27,29'),
'resolve_unavailability':('Техник либо администратор записывает результат и закрывает активную причину.','text: итоговое состояние','23514: причина уже закрыта/ещё не началась; 42501: роль.','Сохраняется вид работы work_kind (maintenance/repair); остальные события продолжают блокировать.','UC-02; FR-18; BR-3,8; T27,29'),
'open_session':('Владелец либо администратор открывает фактическую работу в плановом интервале.','bigint: id сеанса','23514: бронь/допуск/время/доступность; 23505: сеанс уже есть.','Один сеанс; блокировка оборудования и проверка начала.','UC-01; FR-19,20; BR-9; T10,30,31'),
'close_session':('Закрывает работу. p_comment обязателен при действии администратора за владельца.','void','23514: повторное закрытие/нет комментария; 42501: нет прав.','Фактический конец, комментарий и completed сохраняются атомарно.','UC-01; FR-19,20; BR-8,9; T32–34,52,53,57'),
'create_reminders':('Создаёт напоминания о будущих подтверждённых бронях до p_until; запускается планировщиком.','integer: число новых уведомлений','Нет ожидаемых бизнес-ошибок.','Частичный UNIQUE и ON CONFLICT: идемпотентность.','UC-01; FR-21; T43'),
'equipment_metrics':('Плановая и фактическая загрузка, объединённый простой, процент утилизации и число отказов за окно.','equipment_id, planned_seconds, actual_seconds, downtime_seconds, utilization_percent, conflicts','22023: окно не конечное/пустое.','Сначала union диапазонов, затем пересечение с окном; без двойного счёта.','UC-03; FR-22,23; T39,56,57'),
'grant_admission':('Администратор назначает допуск с основанием и сроком.','bigint: id допуска','42501: нет роли admin; 23514: интервал; 23503: ссылки.','Допуск и аудит сохраняются в транзакции.','UC-03; FR-04; BR-1; T45–48'),
'revoke_admission':('Администратор отзывает допуск без удаления истории.','void','42501: роль; 23514: уже отозван/не найден.','При повторном подтверждении и начале работы отзыв учитывается.','UC-03; FR-04; BR-1,8; T49,50')}
md=['# Контракты SQL API','', '19 внешних функций; 13 внутренних функций и триггерных обработчиков. SQL-протокол ошибок: 40001/40P01 требуют повтора всей транзакции; P0002 — объект не найден; 23503 — FK.', '']
out=[]
for name in api:
 desc,result,error,guarantee,trace=api[name]
 # Param names are authoritative in source rather than regprocedure which omits names.
 sql=(root/'sql/functions/03_operations.sql').read_text()
 sig=re.search(r'CREATE FUNCTION '+name+r'\((.*?)\)\s*RETURNS',sql,re.S).group(1).replace('\n',' ')
 md += [f'## `{name}`','',desc,'',f'- Параметры: `{sig}`.',f'- Результат: `{result}`.',f'- Ошибки: {error}',f'- Гарантии: {guarantee}',f'- Покрытие: {trace}','']
 out += [r'\subsection{'+tx(name)+'}',tx(desc),r'\begin{itemize}',r'\item Вход: '+tx(sig)+'.',r'\item Выход: '+tx(result)+'.',r'\item Ошибки: '+tx(error),r'\item Гарантии: '+tx(guarantee),r'\item Трассировка: '+tx(trace)+'.',r'\end{itemize}']
(root/'docs/FUNCTIONS.md').write_text('\n'.join(md));(root/'docs/functions.tex').write_text('\n'.join(out))
indices={
'ix_equipment_type_active':('B-tree, частичный','Фильтр активного каталога по типу; компактнее полного индекса.','Архивирование меняет состав; для всех строк не используется.'),
'ix_type_capability_reverse':('B-tree, составной','Поиск типов по функции; PK начинается с type_id.','Дополнительная запись при изменении M:N.'),
'ix_admission_valid':('GiST, частичный','Пользователь, тип и покрытие временного диапазона.','GiST дороже B-tree; отзыв обновляет индекс; на 12 строках Seq Scan дешевле.'),
'ix_booking_user_future':('B-tree, частичный','Календарь владельца, нижняя граница и LIMIT по времени.','Предикат по статусу, не по now(); завершение удаляет индексную запись.'),
'ix_booking_equipment_period':('GiST, полный','Историческая аналитика и периоды всех статусов.','Для confirmed дублирует часть возможностей EXCLUDE, но нужен для истории.'),
'ix_unavailability_period':('GiST, частичный','Пересечение ТО/поломок с запросом и состояние на момент времени.','Цена записи диапазонов; исключает только отменённые причины, включает resolved.'),
'ix_alternative_booking_rank':('B-tree, частичный','Список предложений по броне, приоритету и времени.','После выбора требуется менять индексный состав; варианты не резервируют время.'),
'ix_fault_equipment_time':('B-tree, составной','Последние сообщения по оборудованию.','Занимает память; ускорение не измерено на малом журнале.'),
'ix_repair_unavailability':('B-tree, составной','История работ по причине недоступности.','Дополнительная стоимость append-only вставки.'),
'ix_audit_record_time':('B-tree, выражение','История объекта по имени таблицы, id и времени.','JSONB ключ вычисляется на вставке; для связующих пар id NULL, нужен иной запрос.'),
'ix_notification_unread':('B-tree, частичный','Непрочитанные уведомления владельца.','Прочтение удаляет индексную запись.'),
'ux_notification_reminder':('B-tree, UNIQUE, частичный','Идемпотентный запуск планировщика.','Одна запись reminder на бронь; после переноса повторная политика требует уточнения.'),
'ix_conflict_equipment_time':('B-tree, составной','Отказы по оборудованию и времени события.','Статистика отражает только API request_booking.')}
md=['# Индексы','', '13 явных индексов; 25 автоматически созданных для PK/UNIQUE/EXCLUDE, всего 38. Каждый индекс требует места, WAL и обновления при записи. FK сами не создают индекс. Полные определения ниже.', '']
rows=[]
for i in m['indexes']:
 if i['name'] not in indices:continue
 kind,query,cost=indices[i['name']]
 md += [f"## `{i['name']}`",'', '```sql',i['definition']+';','```','',f'- Тип: {kind}.',f'- Запрос: {query}',f'- Цена/ограничения: {cost}','']
 rows.append((i['name']+'; '+kind,query,cost))
md += ['## Автоматические индексы','', '`ex_booking_overlap` — составной частичный GiST. Помимо целостности ускоряет confirmed-overlap; PK/UNIQUE дают B-tree для ссылок и точного поиска.', '', 'Результаты EXPLAIN на 1 000 дополнительных единицах и 20 000 бронях: см. TESTING.md и explain-results.txt. Измерение единичное, прогретый локальный кэш; ускорение относительно системы без индексов не доказано. Для Q1 планировщик выбрал EXCLUDE даже при наличии полного GiST.']
(root/'docs/INDEXES.md').write_text('\n'.join(md));(root/'docs/indexes.tex').write_text(table(['Индекс и тип','Ожидаемый запрос','Цена и ограничения'],rows,[.3,.31,.31]))
rows=[('UC-01','booking, admission, alternative, use_session','create/select/open/close','T01–11,16–19,30–34,44,52–53; C01,C04'),('UC-02','unavailability, fault_report, repair, notification','register/edit/resolve; impact','T12–29; C02,C03,C05'),('UC-03','catalogue, admission, audit, conflict','grant/revoke; metrics','T35–40,45–50,56; Q3–Q5')]
fr=[
('app_user, user_role','assert_owner, require_staff','T11,25,45,58–60; аутентификация — этап 3'),
('equipment_type, equipment, type_capability','DDL, audit_change','seed; интерфейс администратора — этап 3'),
('equipment, unavailability','equipment_state','T22,27,29'),
('admission','grant/revoke_admission','T45–50'),
('equipment, booking, unavailability','free_intervals','T42; Q1–Q3'),
('booking, capability','create_booking','T01,09'),
('admission, booking, unavailability','check_booking','T02–04,15,24,47–49'),
('booking, equipment','create_booking; EXCLUDE','C01,C04,C05'),
('booking, notification','cancel_booking','T06,07,11'),
('booking, unavailability','free_intervals, find_alternatives','T42,46'),
('type_capability, admission','equivalent_equipment','T40'),
('alternative','find/offer_alternatives','T13,19,26,28'),
('booking, alternative','select_alternative','T16–18,44'),
('unavailability','register/edit_maintenance','T12,20'),
('booking, alternative','impact_bookings','T12–15'),
('fault_report, unavailability','report_fault, register_unavailability','T21–25'),
('alternative, notification','impact_bookings','T23,26,28'),
('repair, unavailability','resolve_unavailability','T27,29'),
('use_session, booking','open/close_session','T30–34,52,53'),
('booking, use_session','equipment_metrics','T57'),
('notification','cancel/select/impact/reminders','T14,43'),
('booking, use_session, conflict_event','equipment_metrics','T38,39,56'),
('equipment_metrics result','export_report.sql','CSV выполнен; UI-фильтры — этап 3/4'),
('audit_event','audit_change; audit_immutable','T35,36')]
for i,(o,f,t) in enumerate(fr,1):rows.append((f'FR-{i:02}',o,f,t))
br=[('admission, app_user','check_booking; grant/revoke','T02,03,47–49'),('ex_booking_overlap','EXCLUDE + lock_equipment','T04,05; C01,C04'),('unavailability','booking_guard; impact','T15,24,27; C02,C03'),('time_window','CHECK + диапазон','T08,54'),('type_capability','equivalent/find; check_booking','T09,40'),('alternative.priority','find_alternatives','T19'),('booking.status','impact; select_alternative','T12,20,23'),('audit, booking, admission','history guards','T07,34–36,41,50,51'),('use_session','session guards; open/close','T10,30–33,52,53'),('timestamptz, tstzrange','time_window; TZ отображения','T05,37')]
for i,(o,f,t) in enumerate(br,1):rows.append((f'BR-{i}',o,f,t))
md=['# Матрица трассируемости','', '| UC/FR/BR | Объект/ограничение | Функция/триггер | Проверка и граница покрытия |','|---|---|---|---|']+['| '+' | '.join(row)+' |' for row in rows]
(root/'docs/TRACEABILITY.md').write_text('\n'.join(md)+'\n');(root/'docs/traceability.tex').write_text(table(['Код','Объекты','Операция','Проверка'],rows,[.1,.24,.26,.3]))
# Exact assertion names, separate row for every scenario.
log=(root/'output/assertions.log').read_text()
checks=re.findall(r'PASS: (T\d+) (.*)',log)
translations=['Корректная бронь', 'Отказ без допуска', 'Неактивный пользователь, прямой DML', 'Пересечение броней', 'Смежные полуоткрытые интервалы', 'Отмена освобождает слот', 'Отменённая бронь неизменяема', 'Пустой интервал отклонён', 'Неподдерживаемая функция', 'Открытие до планового начала отклонено', 'Проверка владельца', 'ТО переводит бронь в needs_transfer', 'Не менее трёх альтернатив', 'Атомарное уведомление', 'Бронь во время ТО отклонена', 'Выбор альтернативы', 'Выбор сохранён в истории', 'Повторный выбор отклонён', 'Приоритет исходного оборудования BR-6', 'Отмена ТО не подтверждает брони', 'Сообщение сохраняется без блокировки', 'Администратор подтверждает причину', 'Поломка затрагивает будущую бронь', 'Неисправное оборудование недоступно', 'Пользователь не подтверждает причину', 'Поломка без конца исключает исходный станок', 'Другие причины сохраняют недоступность', 'Отсутствие альтернатив', 'Техник восстанавливает доступность', 'Корректное открытие сеанса', 'Один сеанс на бронь', 'Закрытие завершает бронь', 'Повторное закрытие отклонено', 'Завершённая бронь неизменяема', 'Аудит неизменяем', 'Значимые изменения отражены в аудите', 'Равные моменты разных зон', 'Отклонённый запрос сохранён', 'Ограничение метрик окном', 'Эквивалентность разных типов', 'Удаление брони запрещено', 'Поиск максимальных свободных интервалов', 'Напоминания идемпотентны', 'Конкурентно занятая альтернатива отклонена', 'Допуск назначает администратор', 'Поиск учитывает будущий срок допуска', 'Не наступивший допуск отклонён', 'Допуск покрывает весь интервал', 'Отозванный допуск отклонён', 'История допуска сохраняется', 'История недоступности сохраняется', 'Администратору нужен комментарий закрытия', 'Комментарий закрытия сохранён', 'Включённый конец диапазона отклонён', 'В схеме 17 таблиц', 'Перекрывающиеся простои считаются объединением', 'Фактическая длительность отделена от плановой', 'Backend не имеет прямого DML расписания', 'Backend не вызывает внутренний guard', 'API работает без session search_path']
(root/'docs/tests.tex').write_text(table(['Тест','Проверяемое поведение','Результат'],[(n,translations[int(n[1:])-1],'PASS') for n,d in checks],[.1,.68,.13]))

# Additional assertions for the agreed work-kind attribute.
checks_new=re.findall(r'PASS: (N\d+) (.*)',(root/'output/approved-model-tests.log').read_text())
with (root/'docs/tests.tex').open('a') as stream:
 stream.write('\n'+table(['Тест','Проверяемое поведение','Результат'],[(n,d,'PASS') for n,d in checks_new],[.1,.68,.13]))
