# Развёртывание текущей модели на Helios

Текущая редакция: 15 таблиц, 24 FK, 31 функция, 10 триггеров. В studs используется собственная схема s466088 и префикс lr_. Владелец не требует SUPERUSER/CREATEROLE/CREATE DATABASE.

## Перенос файлов

Из корня проекта:

```bash
tar -czf /tmp/labreserve-model15.tar.gz -C stage-02 sql scripts README.md docs/DEFENSE.md
scp -P 2222 /tmp/labreserve-model15.tar.gz s466088@helios.cs.ifmo.ru:~/
ssh -p 2222 s466088@helios.cs.ifmo.ru
mkdir -p ~/labreserve-stage02-20261109
cd ~/labreserve-stage02-20261109
tar -xzf ~/labreserve-model15.tar.gz
export PGHOST=pg PGDATABASE=studs PGUSER=s466088
```

Пароли вводятся в запросе SSH/psql либо используются из личного .pgpass с правами 0600. Секреты не записываются в файлы проекта.

## Существующая установка от 27 октября

```bash
bash scripts/align_model15_helios.sh
```

До изменения БД создаётся приватный pg_dump трёх удаляемых таблиц: два журнала и старый манифест установки. Скрипт проверяет старый source_hash и fingerprint каталога. В одной транзакции удаляет только три лишние таблицы и зависимую логику, обновляет API и переносит метаданные установки в комментарий к lr_app_user. DROP SCHEMA/DATABASE и CASCADE не используются. Все строки 15 таблиц модели сохраняются. Неизвестная версия или изменённый каталог вызывают отказ и откат.

## Новая пустая установка и повторы

```bash
bash scripts/deploy_helios.sh install
bash scripts/check_helios.sh --concurrency
```

Повтор проверяет хеш исходников и каталог по комментарию к lr_app_user и не запускает seed. Комментарий не входит в fingerprint, поэтому циклического хеша нет. Подмена/отсутствие маркера и посторонние lr_-объекты приводят к отказу; чужие объекты не перезаписываются.

Без установленного btree_gist используется сериализующий триггер, сохраняющий SQLSTATE 23P01/40001 и защиту прямого DML. При существующем расширении допустим EXCLUDE-вариант.

## Показ

```bash
bash scripts/helios_python.sh sql/helios/migrate_model15.py output/helios-model15
psql -X -h pg -U s466088 -d studs
```

```sql
\dt s466088.lr_*
\d s466088.lr_booking
\i output/helios-model15/defense.sql
```

В списке ровно 15 таблиц. Метаданные установки:

```sql
SELECT obj_description('s466088.lr_app_user'::regclass,'pg_class');
```

Сценарий показывает бронирование, отказы, поломку, перенос, ремонт, сеанс, уведомления и аналитику, затем откатывает изменения. Локальные скрипты create/drop/clean/run_checks на общей studs не запускаются.
