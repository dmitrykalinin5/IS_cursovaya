# ЛабРезерв — этап 2: проектирование и реализация БД

Материалы второго этапа: модель данных, реализация PostgreSQL, отчёт и проверки.
Основа проектирования — первый этап в `../stage-01/`.

## Результат

- 15 концептуальных сущностей, 17 таблиц, 2 явные M:N (роль–пользователь, тип–функция), 27 FK.
- 19 внешних SQL-функций, 13 внутренних функций/обработчиков, 25 пользовательских триггеров.
- 13 явных индексов + 25 индексов PK/UNIQUE/EXCLUDE.
- 60 утверждающих SQL-тестов, 5 конкурентных сценариев, EXPLAIN на 1 000 дополнительных единицах и 20 000 бронях.
- Отдельные `report.tex` / `report.pdf`, редактируемые TikZ и Mermaid, PDF диаграмм.

## Файлы

| Путь | Назначение |
|---|---|
| `report.tex`, `report.pdf` | Самостоятельный отчёт этапа 2 |
| `diagrams/conceptual.{tex,mmd,pdf}` | ER-модель, три тематических листа; M:N показаны явно |
| `diagrams/logical.{tex,mmd,pdf}` | Все таблицы, столбцы, PK/FK и связи |
| `sql/schema/` | DDL, домен диапазонов, ограничения и триггеры |
| `sql/functions/` | Критические операции PostgreSQL/PLpgSQL |
| `sql/indexes/` | Индексы; обоснование в docs/INDEXES.md |
| `sql/seeds/` | Относительные по дате учебные примеры |
| `sql/tests/` | SQL-утверждения, контрольные запросы, concurrency.py, EXPLAIN |
| `sql/scripts/` | Создание/удаление тестовой БД, установка/очистка, проверки, CSV, экспорт схемы, права backend |
| `docs/MODEL.md` | Нормализация, кратности и проектные решения |
| `docs/DATA_DICTIONARY.md`, `datalogical.json` | Полная фактическая схема, включая типы/NULL/default/ключи/CHECK |
| `docs/INTEGRITY.md`, `FUNCTIONS.md` | Протокол конкурентного доступа и контракты API |
| `docs/TRACEABILITY.md`, `INDEXES.md` | Покрытие всех UC/FR/BR и индексная стратегия |
| `docs/TESTING.md`, `*-results.*` | Проверенное окружение и сохранённые результаты |
| `docs/VISUAL_QA.md` | Проверка отчёта и неизменности первого этапа |
| `docs/generate_models.py`, `generate_report_tables.py` | Воспроизводимые таблицы отчёта и диаграммы по экспорту БД |
| `output/` | Локальные журналы и растровые страницы, исключены из Git |

## Запуск на Fedora

Нужны PostgreSQL 14+ (multirange/range_agg), пакет contrib для btree_gist, Python 3 и psql.
Фактически проверена версия 18.6; другие версии и конфигурация Helios ещё не проверены.
Установка отсутствующих пакетов на личной машине:

```bash
sudo dnf install postgresql-server postgresql-contrib texlive-xetex texlive-collection-langcyrillic texlive-collection-latexextra poppler-utils
```

Используйте отдельный локальный кластер (не существующие пользовательские БД).
Из каталога `stage-02/`:

```bash
initdb -D /tmp/labreserve-stage02-pg --auth=trust --no-locale -E UTF8
pg_ctl -D /tmp/labreserve-stage02-pg -l /tmp/labreserve-stage02-pg/server.log -o '-k /tmp -p 55432 -h ""' start
export PGHOST=/tmp PGPORT=55432
psql -d postgres -f sql/scripts/create_database.sql
export PGDATABASE=labreserve_stage02_test
bash sql/scripts/run_checks.sh
psql -X -qAt -f sql/scripts/export_model.sql > docs/datalogical.json
psql -X -f sql/scripts/export_report.sql > output/analytics.csv
```

Trust допустим только для этого локального учебного кластера с отключённым TCP; рабочая БД использует отдельные роли и аутентификацию. Runner пересоздаёт **только** схему в `labreserve_stage02_test`; запуск на другом имени отклоняется.
Тест T58–T60 создаёт временную NOLOGIN-роль внутри транзакции: для полного набора нужен CREATEROLE, имеющийся у владельца нового initdb-кластера. Установка расширения требует CREATE в БД и наличия contrib.
Чтобы выполнить только установку без удаления: `psql -X -v ON_ERROR_STOP=1 -f sql/scripts/install.sql`, затем `05_demo.sql` (на пустой схеме; seed не идемпотентен).
Скрипт БД создаёт фиксированное имя и откажет, если оно уже существует; не удаляйте такую БД без проверки её назначения.

Остановка и удаление **этой учебной БД** при необходимости:

```bash
psql -d postgres -f sql/scripts/drop_database.sql
pg_ctl -D /tmp/labreserve-stage02-pg stop
```

## Сборка PDF

```bash
python3 docs/generate_models.py
python3 docs/generate_report_tables.py
(cd diagrams && FONTCONFIG_FILE="$PWD/fonts.conf" xelatex -halt-on-error -interaction=nonstopmode conceptual.tex)
(cd diagrams && FONTCONFIG_FILE="$PWD/fonts.conf" xelatex -halt-on-error -interaction=nonstopmode logical.tex)
FONTCONFIG_FILE="$PWD/diagrams/fonts.conf" latexmk -xelatex -halt-on-error -interaction=nonstopmode -outdir=output report.tex
cp output/report.pdf report.pdf
```

`fonts.conf` добавляет DejaVu из каталога TeX Live Fedora; если DejaVu установлен системно, дополнительная конфигурация не нужна. На другом дистрибутиве путь можно изменить.
Временные файлы не включаются в Git. Итоговый PDF, источники, экспорт модели и свидетельства проверок сохраняются.

## Интеграция этапа 3

Передайте существующую служебную SQL-роль DBA-скрипту `psql -v app_role=labreserve_backend -f sql/scripts/grant_application.sql`.
Идентичность человека удостоверяет будущий Spring Security; p_actor не берётся из непроверенных HTTP-данных.
Критические действия вызываются через native JPA-запросы к функциям, с COMMIT/ROLLBACK внешней транзакции; Spring JDBC запрещён.
40001/40P01 требуют ограниченного повтора всей транзакции. 23P01/23514 означают пересчёт доступности и вариантов.
Проектные решения описаны в `docs/MODEL.md`.
