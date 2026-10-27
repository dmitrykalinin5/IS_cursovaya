# ЛабРезерв — этап 2: проектирование и реализация БД

Материалы второго этапа: модель данных, реализация PostgreSQL, отчёт и проверки.
Основа проектирования — согласованная `ER-модель_final.drawio.xml` (13 сущностей) и требования первого этапа в `../stage-01/`.

[Пункты официального задания и результаты](docs/STAGE02_CHECKLIST.md).

**Защита:** [порядок показа, draw.io и psql](docs/DEFENSE.md). [Соответствие согласованной модели](docs/APPROVED_MODEL.md).

## Результат

- 13 концептуальных сущностей, 17 таблиц (13 предметных + 2 M:N + 2 служебных журнала), 2 явные M:N (роль–пользователь, тип–функция), 27 FK.
- 19 внешних SQL-функций, 13 внутренних функций/обработчиков, 25 пользовательских триггеров.
- 13 явных индексов + 25 индексов PK/UNIQUE/EXCLUDE.
- 60 основных + 4 дополнительных утверждающих SQL-теста, 5 конкурентных сценариев, EXPLAIN на 1 000 дополнительных единицах и 20 000 бронях.
- Отдельные `report.tex` / `report.pdf`, редактируемые draw.io XML и TikZ, PDF диаграмм.

## Файлы

| Путь | Назначение |
|---|---|
| `report.tex`, `report.pdf` | Самостоятельный отчёт этапа 2 |
| `ER-модель_final.drawio.{xml,png}` | Единственный согласованный исходник инфологической модели и его изображение |
| `diagrams/conceptual.{tex,pdf}` | Согласованная ER-модель на одном листе; conceptual.tex использует согласованный PNG |
| `diagrams/logical.xml` | Даталогическая схема с точным расположением согласованных 13 блоков; дополнены две таблицы M:N |
| `sql/demo/defense.sql` | Живой сценарий защиты в psql, с ROLLBACK |
| `sql/helios/migrate_approved_model.py` | Генерация миграции старой Helios-схемы, проверок и демонстрации |
| `diagrams/logical.{tex,pdf}` | Единая предметная схема с исходной расстановкой: 13 согласованных сущностей + 2 таблицы M:N, поля, типы и ключи |
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
| `sql/helios/` | Адаптер общей SQL-реализации, preflight, безопасная установка, smoke и конкурентные тесты |
| `scripts/deploy_helios.sh`, `scripts/check_helios.sh`, `scripts/helios_python.sh` | Установка и проверка в studs.s466088, без управления БД/схемой |
| `docs/HELIOS_DEPLOY.md`, `HELIOS_TESTING.md` | Команды подключения, демонстрации и фактические результаты проверки |
| `output/` | Локальные журналы и растровые страницы, исключены из Git |

## Запуск на Fedora

Нужны PostgreSQL 14+ (multirange/range_agg), пакет contrib для btree_gist, Python 3 и psql.
Исходный LOCAL проверен на 18.6; полный runner также повторно проверен на 16.15. Адаптер Helios испытан локально на 18.6 без расширения и 16.15 с расширением; на реальном Helios PostgreSQL 18.3 вариант без расширения прошёл 57 бизнес-тестов, 18 smoke и 10 конкурентных сценариев.
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

Даталогическую схему редактируйте в `diagrams/logical.xml`. Генераторы читают этот файл и обновляют TEX/PDF; ручные изменения XML сохраняются.

```bash
python3 docs/generate_models.py
python3 docs/generate_report_tables.py
python3 docs/verify_approved_model.py
mkdir -p output/model-build
(cd diagrams && FONTCONFIG_FILE="$PWD/fonts.conf" xelatex -halt-on-error -interaction=nonstopmode -output-directory=../output/model-build conceptual.tex)
cp output/model-build/conceptual.pdf diagrams/conceptual.pdf
(cd diagrams && FONTCONFIG_FILE="$PWD/fonts.conf" xelatex -halt-on-error -interaction=nonstopmode -output-directory=../output/model-build logical.tex)
cp output/model-build/logical.pdf diagrams/logical.pdf
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

## Развёртывание на Helios

На Helios используются существующая `studs.s466088` и префикс `lr_`. Общие SQL-исходники LOCAL сохраняются; адаптер создаёт временный комплект. Если btree_gist недоступно, конкурентные пересечения блокирует сериализующий BEFORE-триггер с SQLSTATE 23P01. Повторная установка проверяет манифест и структуру, сохраняет данные и не повторяет seed.

После передачи файлов и SSH-входа, из каталога stage-02:

```bash
export PGHOST=pg PGDATABASE=studs PGUSER=s466088
bash scripts/deploy_helios.sh preflight
bash scripts/deploy_helios.sh install
bash scripts/check_helios.sh
psql -X -h pg -U s466088 -d studs -f sql/helios/demo.sql
```

Подробная передача файлов, проверка конкуренции и подключение JPA — [HELIOS_DEPLOY.md](docs/HELIOS_DEPLOY.md). Фактические результаты — [HELIOS_TESTING.md](docs/HELIOS_TESTING.md). Локальные cleanup/create/drop/run_checks на Helios не запускаются. На реальном Helios база установлена в `studs.s466088`; вариант `trigger`, PostgreSQL 18.3. Актуальный рабочий каталог: `~/labreserve-stage02-20261027`.


## Актуализация по согласованной модели — 27.10.2026

Рабочая инфологическая модель: `ER-модель_final.drawio.xml`; даталогическая: `diagrams/logical.xml` (обе открываются через draw.io → Файл → Открыть).
Текущая редакция проверена в изолированном PostgreSQL 18.6: 60 + 4 SQL-проверки, 5 конкурентных сценариев и повторное создание схемы.
Реальный Helios обновлён 27.10.2026: добавлен `repair.work_kind`, данные сохранены; 57+4 SQL-проверки, 18 smoke, 10 конкурентных и сценарий защиты прошли. Свидетельства — `docs/approved-helios-remote/`; команды — `docs/DEFENSE.md`.
