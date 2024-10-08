# MySQL dump/restore Docker-image

[🇺🇸 English docs](README.MD)

------

## Что это?

Образ для бэкапа или восстановления из дампа баз данных MySQL с использованием S3-хранилища

## Для чего?

Для облегчения автоматизации бэкапирования данных из MySQL или разворачивания бэкапов на смежных окружениях

## Как пользоваться?

### Заполнить переменные окружения

#### Параметры подключения к MySQL:

```dotenv
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USER=root
DB_PASSWORD=
```

Если ваш MySQL выполняется в docker-контейнере, то в переменной `DB_HOST` можно указать имя сервиса MySQL в docker

> **ВАЖНО:** если ваш MySQL выполняется в docker-контейнере и не доступен снаружи сети docker'а, то запускать этот образ нужно в той же сети, в которой находится контейнер с MySQL

#### Параметры подключения к S3 хранилищу

```dotenv
S3_ACCESS_KEY=12345qwerty
S3_SECRET_KEY=12345qwerty
S3_REGION=ru-1
S3_HOST=s3.ru-1.storage.selcdn.ru
S3_HOST_BUCKET=s3.ru-1.storage.selcdn.ru
S3_CONTAINER_NAME=myfiles
```

> В зависимости от провайдера вашего S3 хранилища значение для `S3_HOST_BUCKET` может формироваться по-разному.
> Например в Selectel когда-то использовались домены формата {bucket_id}.selcdn.ru/{container_name} 
где в качестве `bucket_id` использовался цифровой идентификатор хранилища, 
а `container_name` уже имя контейнера в этом хранилище. 
Однако позднее было рекомендовано использовать универсальный домен s3.ru-1.storage.selcdn.ru

#### Дополнительные параметры

По умолчанию при вызове команды `backup` без параметров будет выполнен дамп всех БД и таблиц. 
Если нужно исключить какие-либо БД и/или таблицы, то для этого предусмотрены соответствующие переменные:
```dotenv
# The names of excluded tables are separated by commas(,)
DB_IGNORE_TABLES=table1,table2

# default (^mysql|_schema$|^sys$)
DB_IGNORE_DATABASE_REGEX=(^mysql|_schema$|^sys$|^test_)
```

Также если Вы достаточно отчаяный и не переживаете об отсутствии ssl при передаче данных в хранилище
или же ваше хранилище доступно только во внутреннем контуре сети, 
то можно выключить ssl (полностью или только отдельные проверки)
```dotenv
S3_SSL=true
S3_SSL_CHECK_CERT=true
S3_SSL_CHECK_HOST=false
```

### Запуск

#### Без собственного реестра контейнеров

```shell
docker build -t my-dumper . && docker run --rm --env-file /path/to/env-file --network my_project_network my-dumper backup my_db_name
```
или если использовать Docker Compose:
```yaml
# my-compose.yml
networks:
  default:
    name: my_project_network

services:
  my-dumper-service:
    build: .
    env_file: .env
    command: "backup my_db_name"
```
```shell
docker compose -f my-compose.yml build my-dumper-service && docker compose -f my-compose.yml run --rm my-dumper-service
```

#### С реестром контейнеров

Разумеется нужно выполнить сборку и пуш образа в реестр.

```shell
docker pull registry.your-domain/path/to/image && docker run --rm --env-file /path/to/env-file --network my_project_network registry.your-domain/path/to/image backup my_db_name
```
или если использовать Docker Compose:
```yaml
# my-compose.yml
networks:
  default:
    name: my_project_network

services:
  my-dumper-service:
    image: registry.your-domain/path/to/image
    env_file: .env
    command: "backup my_db_name"
```
```shell
docker compose -f my-compose.yml pull my-dumper-service && docker compose -f my-compose.yml run --rm my-dumper-service
```

### Команды

**Бэкап:**
```
backup [DB_NAME]
```
Команде `backup` можно передать имя конкретной БД, иначе будет выполнен дамп всех доступных БД.

**Восстановление:**
```
restore DB_NAME [DATE] [TARGET_DB_NAME]
```
Команда `restore` требует имя БД в качестве обязательного аргумента. 

Так же если Вам нужен дамп за конкретную дату, 
то можно передать ее в формате ГГГГ-ММ-ДД, 
иначе будет использована текущая дата.

Еще можно указать имя целевой БД - в этом случае будет выполнено скачивание дампа базы `DB_NAME` из хранилища, но применен он будет к базе `TARGET_DB_NAME`