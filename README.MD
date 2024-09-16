# MySQL dump/restore Docker-image

[🇷🇺 Russian docs](README_RU.MD)

------

## What is it?

An image for backing up or restoring MySQL databases using S3 storage.

## What for?

To facilitate the automation of backing up data from MySQL or deploying backups in related environments.

## How to use?

### Fill in the environment variables

#### MySQL connection parameters:

```dotenv
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USER=root
DB_PASSWORD=
```

If your MySQL runs in a Docker container, you can specify the MySQL service name in Docker in the DB_HOST variable.

> **IMPORTANT**: If your MySQL is running in a Docker container and is not accessible from outside the Docker network, you should run this image on the same network as the MySQL container.

#### S3 storage connection parameters

```dotenv
S3_ACCESS_KEY=12345qwerty
S3_SECRET_KEY=12345qwerty
S3_REGION=ru-1
S3_HOST=s3.ru-1.storage.selcdn.ru
S3_HOST_BUCKET=s3.ru-1.storage.selcdn.ru
S3_CONTAINER_NAME=myfiles
```

> Depending on your S3 storage provider, the value for S3_HOST_BUCKET may vary. For example, in Selectel, domains like {bucket_id}.selcdn.ru/{container_name} were once used, where the bucket_id was a numeric identifier for the storage, and container_name was the container's name in that storage. However, later it was recommended to use the universal domain s3.ru-1.storage.selcdn.ru.

#### Additional parameters

By default, when calling the backup command without parameters, all databases and tables will be dumped. To exclude any databases and/or tables, appropriate variables can be used:
```dotenv
# The names of excluded tables are separated by commas (,)
DB_IGNORE_TABLES=table1,table2

# default (^mysql|_schema$|^sys$)
DB_IGNORE_DATABASE_REGEX=(^mysql|_schema$|^sys$|^test_)
```

Also, if you are quite daring and do not worry about the lack of SSL when transferring data to the storage, or if your storage is only accessible within the internal network, you can disable SSL (entirely or only for specific checks):
```dotenv
S3_SSL=true
S3_SSL_CHECK_CERT=true
S3_SSL_CHECK_HOST=false
```

### Running

#### Without a private container registry

```bash
docker build -t my-dumper . && docker run --rm --env-file /path/to/env-file --network my_project_network my-dumper backup my_db_name
```

or if using Docker Compose:

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

```bash
docker compose -f my-compose.yml build my-dumper-service && docker compose -f my-compose.yml run --rm my-dumper-service
```

#### With a container registry

Of course, you need to build and push the image to the registry.

```bash
docker pull registry.your-domain/path/to/image && docker run --rm --env-file /path/to/env-file --network my_project_network registry.your-domain/path/to/image backup my_db_name
```

or if using Docker Compose:

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

```bash
docker compose -f my-compose.yml pull my-dumper-service && docker compose -f my-compose.yml run --rm my-dumper-service
```

### Commands

**Backup:**
```bash
backup [DB_NAME]
```

The backup command can take the name of a specific database; otherwise, a dump of all available databases will be performed.

**Restore:**
```bash
restore DB_NAME [DATE] [TARGET_DB_NAME]
```

The restore command requires the database name as a mandatory argument.

If you need a dump for a specific date, you can pass it in the format YYYY-MM-DD; otherwise, the current date will be used.

You can also specify a target database name – in this case, the dump of the database DB_NAME will be downloaded from the storage, but it will be applied to the database TARGET_DB_NAME.
