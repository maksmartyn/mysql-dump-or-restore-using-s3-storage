#!/bin/bash

# Функция чтения значения переменной из окружения или из dotenv-файла
function read_var() {
  if [ -z "$1" ]; then
    echo ""
  fi

  local env_file='.env'
  local var

  if [[ -z "${!1}" ]]; then
    if [[ -f "$env_file" ]]; then
      # Достаем переменную из dotenv-файла
      local from_file
      from_file=$(grep -E "^$1=" "$env_file" | awk -F " " '{if (NR=1) print $1}')
      IFS="=" read -ra from_file <<< "$from_file"
      var="${from_file[1]}"
      IFS=" "
    fi
  else
    # Достаем переменную из переменной окружения
    var="${!1}"
  fi

  echo "$var"
}

# Функция создания строки с параметрами подключения к БД
function mysql_login() {
  local mysql_login_string=""

  local user_name
  user_name=$(read_var DB_USER)
  if [ -n "$user_name" ]; then
    local mysql_login_string+=" --user=$user_name"
  fi

  local password
  password=$(read_var DB_PASSWORD)
  if [ -n "$password" ]; then
    local mysql_login_string+=" --password=$password"
  fi

  local host
  host=$(read_var DB_HOST)
  if [ -n "$host" ]; then
    local mysql_login_string+=" --host=$host"
  fi

  local port
  port=$(read_var DB_PORT)
  if [ -n "$port" ]; then
    local mysql_login_string+=" --port=$port"
  fi

  echo "$mysql_login_string"
}

# Функция возвращающая список доступных БД
function database_list() {
  local show_databases_sql
  local ignore_regex
  ignore_regex=$(read_var DB_IGNORE_DATABASE_REGEX)

  if [ -n "$ignore_regex" ]; then
      ignore_regex="(^mysql|_schema$|^sys$)"
  fi

  show_databases_sql="SHOW DATABASES WHERE \`Database\` NOT REGEXP '$ignore_regex'"
  echo $(mysql $(mysql_login) --batch -e "$show_databases_sql" | awk -F " " '{if (NR!=1) print $1}')
}

# Функция бэкапа конкретной БД
function backup_database() {
  local db
  db="$1"

  local timestamp
  # YYYY-MM-DD
  timestamp=$(date +%F)

  local backup_file="/tmp/$timestamp.$db.sql"

  local ignored_tables_list
  ignored_tables_list=$(read_var DB_IGNORE_TABLES)

  local ignored_tables
  ignored_tables=""

  if [ -n "$ignored_tables_list" ]; then
    ignored_tables=" --ignore-table=$db."
    ignored_tables+="${ignored_tables_list//,/ --ignore-table=$db.}"
  fi

  local dump_command
  dump_command="mysqldump --single-transaction $(mysql_login) ${db} ${ignored_tables}"
  $dump_command | gzip -9 > "$backup_file".gz

  echo "$backup_file.gz"
}

# Функция создания строки с параметрами подключения к хранилищу
function s3_login() {
  local s3_login
  s3_login="--access_key=$(read_var S3_ACCESS_KEY)"
  s3_login+=" --secret_key=$(read_var S3_SECRET_KEY)"
  s3_login+=" --host=$(read_var S3_HOST)"
  s3_login+=" --host-bucket=$(read_var S3_HOST_BUCKET)"
  s3_login+=" --region=$(read_var S3_REGION)"

  local use_ssl
  use_ssl=$(read_var S3_SSL)
  if [ -n "$use_ssl" ] && [ "$ssl_check_cert" = "false" ]; then
    s3_login+=" --no-ssl"
  else
    s3_login+=" --ssl"

    local ssl_check_cert
    ssl_check_cert=$(read_var S3_SSL_CHECK_CERT)
    if [ -n "$ssl_check_cert" ] && [ "$ssl_check_cert" = "false" ]; then
      s3_login+=" --no-check-certificate"
    else
      s3_login+=" --check-certificate"
    fi

    local ssl_check_host
    ssl_check_host=$(read_var S3_SSL_CHECK_HOST)
    if [ -n "$ssl_check_host" ] && [ "$ssl_check_host" = "false" ]; then
      s3_login+=" --no-check-hostname"
    else
      s3_login+=" --check-hostname"
    fi
  fi

  echo "$s3_login"
}

# Функция загрузки файла в хранилище
function upload_to_s3() {
  local upload_command
  upload_command="s3cmd -q $(s3_login) put $1 s3://$(read_var S3_CONTAINER_NAME)"
  $upload_command
}

# Главная функция бэкапа
function backup() {
  local databases

  if [[ -z "$1" ]]; then
    echo "Имя БД не передано. Будут экспортированы все БД с именами не совпадающими с паттерном из переменной окружения DB_IGNORE_DATABASE_REGEX"
    printf "\n"
    databases=$(database_list)
  else
    echo "Указана БД '$1'. Будет произведен экспорт только этой БД"
    printf "\n"
    databases="$1"
  fi

  for database in $databases; do
    local file
    file=$(backup_database "$database")
    upload_to_s3 "$file"
    rm "$file"
    echo "Дамп базы данных '$database' успешно выполнен в файл ${file//\/tmp\//} и загружен в хранилище."
    printf "\n"
  done
}

# Проверка, является ли аргумент датой в формате YYYY-MM-DD
is_valid_date() {
    local date="$1"
    if [[ $date =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        date -d "$date" "+%Y-%m-%d" > /dev/null 2>&1
        return $?
    else
        return 1
    fi
}

function download_from_s3() {
  local download_command
  local file
  file="/tmp/$1"
  download_command="s3cmd -q $(s3_login) get s3://$(read_var S3_CONTAINER_NAME)/$1 $file"
  $download_command

  echo "$file"
}

# Функция записи в БД
function restore_database() {
  local restore_command
  restore_command="mysql $(mysql_login) $2"
  $restore_command < "$1"
}

# Главная функция восстановления из дампа
function restore() {
  local db
  db=$1
  local timestamp

  if [[ -z "$2" ]]; then
    # YYYY-MM-DD
    timestamp=$(date +%F)
    echo "Дата не передана. Используем $timestamp"
    printf "\n"
  else
    if is_valid_date "$2"; then
      timestamp=$2
    else
      echo "Ошибка: '$2' не является допустимой датой в формате YYYY-MM-DD."
      printf "\n"
      return 1
    fi
  fi

  local target_db
  target_db=$3
  if [[ -z "$target_db" ]]; then
    target_db="$db"
  fi

  echo "Будет произведено восстановление БД '$target_db' из дампа '$timestamp.$db'"
  printf "\n"

  local file
  file=$(download_from_s3 "$timestamp.$db.sql.gz")

  if [[ -f "$file" ]]; then
    gzip -d "$file"
    file=${file//.gz/}
    restore_database "$file" "$target_db"
    rm "$file"

    echo "Дамп '${file//\/tmp\//}' записан в базу данных '$target_db'"
    printf "\n"
  else
    echo "Ошибка: не удалось скачать файл дампа из хранилища"
    printf "\n"
    return 1
  fi
}

# Запуск скрипта

# Проверяем, был ли передан первый аргумент
if [ -z "$1" ]; then
    echo "Ошибка: требуется указать первый аргумент 'restore' или 'backup'."
    exit 1
fi

# Обрабатываем значение первого аргумента
case $1 in
    restore)
        # Проверяем, был ли передан второй аргумент
        if [ -z "$2" ]; then
            echo "Ошибка: для операции 'restore' требуется передать имя БД вторым аргументом."
            exit 1
        fi
        restore "$2" "$3" "$4" || exit 1
        ;;
    backup)
        backup "$2"
        ;;
    *)
        echo "Ошибка: недопустимый аргумент '$1'. Возможные значения: 'restore' или 'backup'."
        exit 1
        ;;
esac

