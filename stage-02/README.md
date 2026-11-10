# ЛабРезерв — второй этап

Основа — согласованная `ER-модель_final.drawio.xml/png`. PostgreSQL точно соответствует модели: **13 сущностей + 2 таблицы M:N = 15 таблиц**. 24 FK, 31 функция (19 внешних, 12 внутренних), 10 триггеров; 11 явных и 23 автоматических индекса, всего 34.

Общего аудита и журнала конфликтов нет. История сохраняется в предметных таблицах; причины отказов возвращаются вызывающему коду. Версия установки на Helios хранится в комментарии к lr_app_user, а не в дополнительной таблице.

## Файлы

| Путь | Назначение |
|---|---|
| ER-модель_final.drawio.xml/png | Единственный согласованный исходник инфологической модели |
| diagrams/logical.xml | Актуальная даталогическая модель, 15 таблиц; ручные правки сохраняются |
| diagrams/conceptual.tex/pdf, logical.tex/pdf | Используемые отчётом исходники и схемы |
| report.tex/pdf | Самостоятельный отчёт этапа 2 |
| sql/schema/, functions/, indexes/, seeds/ | DDL, триггеры, API, индексы, тестовые данные |
| sql/scripts/ | Создание/удаление только выделенной учебной БД, установка, экспорт и проверки |
| sql/tests/ | 60 основных + 4 дополнительных SQL-проверки, конкуренция и EXPLAIN |
| sql/demo/defense.sql | Ручной/пошаговый сценарий защиты с ROLLBACK |
| sql/helios/ | Адаптер и проверка студенческой схемы |
| scripts/align_model15_helios.sh | Резервная копия старых журналов и миграция существующего Helios к 15 таблицам |
| scripts/deploy_helios.sh, check_helios.sh | Новая/повторная установка, диагностика и проверки |
| docs/DATA_DICTIONARY.md, datalogical.json | Фактический словарь БД и машинный экспорт |
| docs/FUNCTIONS.md, INDEXES.md, INTEGRITY.md | Контракты, индексы и целостность |
| docs/DEFENSE.md | Подключение, команды показа и следующие этапы |
| docs/model15-*.json | Результаты текущей проверки |
| output/ | Локальные сборки, журналы и резервные копии, исключены из Git |

## Локальная проверка на Fedora

Нужны PostgreSQL 14+, contrib/btree_gist, Python 3, XeLaTeX/latexmk и Poppler. Пример отдельного локального кластера с отключённым TCP:

```bash
initdb -D /tmp/labreserve-stage02-pg --auth=trust --no-locale -E UTF8
pg_ctl -D /tmp/labreserve-stage02-pg -l /tmp/labreserve-stage02-pg/server.log -o '-k /tmp -p 55432 -h ""' start
export PGHOST=/tmp PGPORT=55432
psql -d postgres -f sql/scripts/create_database.sql
export PGDATABASE=labreserve_stage02_test
bash sql/scripts/run_checks.sh
psql -X -qAt -f sql/scripts/export_model.sql > docs/datalogical.json
psql -X -f sql/demo/defense.sql
```

Runner пересоздаёт только учебную схему в labreserve_stage02_test. На общей studs его не запускают. T58–T60 используют временную NOLOGIN-роль внутри откатываемой транзакции; в локальном initdb-кластере для этого есть необходимые права. Скрипты clean/drop не предназначены для реальных пользовательских БД.

## Helios

```bash
ssh -p 2222 s466088@helios.cs.ifmo.ru
cd ~/labreserve-stage02-20261109
export PGHOST=pg PGDATABASE=studs PGUSER=s466088
bash scripts/align_model15_helios.sh
bash scripts/helios_python.sh sql/helios/migrate_model15.py output/helios-model15
psql -X -h pg -U s466088 -d studs -f output/helios-model15/defense.sql
```

Для новой пустой установки — `bash scripts/deploy_helios.sh install`; для существующей редакции от 27 октября — миграция выше. Проверка: `bash scripts/check_helios.sh --concurrency`. Без btree_gist пересечения защищает сериализующий триггер; административные права не нужны. Все объекты имеют префикс lr_. Пароли и резервные копии не включаются в Git.

## Сборка отчёта

```bash
python3 docs/generate_models.py
python3 docs/generate_report_tables.py
python3 docs/verify_approved_model.py
mkdir -p output/model-build
(cd diagrams && FONTCONFIG_FILE="$PWD/fonts.conf" xelatex -halt-on-error -interaction=nonstopmode -output-directory=../output/model-build conceptual.tex)
(cd diagrams && FONTCONFIG_FILE="$PWD/fonts.conf" xelatex -halt-on-error -interaction=nonstopmode -output-directory=../output/model-build logical.tex)
cp output/model-build/conceptual.pdf diagrams/conceptual.pdf
cp output/model-build/logical.pdf diagrams/logical.pdf
FONTCONFIG_FILE="$PWD/diagrams/fonts.conf" latexmk -xelatex -halt-on-error -interaction=nonstopmode -outdir=output report.tex
cp output/report.pdf report.pdf
```

Генератор читает текущий logical.xml и не перезаписывает ручную компоновку. Доступ приложения на этапе 3 — Spring Data JPA/Hibernate; критические операции вызывают функции PostgreSQL. Spring JDBC не используется.
