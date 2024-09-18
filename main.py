import datetime
import os
import sys
import subprocess


def is_valid_date(date_str: str) -> bool:
    try:
        datetime.datetime.strptime(date_str, "%Y-%m-%d")
        return True
    except ValueError:
        return False


def mysql_login():
    mysql_login_string=""

    if os.getenv('DB_USER'):
        mysql_login_string += f" --user={os.getenv('DB_USER')}"

    if os.getenv('DB_PASSWORD'):
        mysql_login_string += f" --password={os.getenv('DB_PASSWORD')}"

    if os.getenv('DB_HOST'):
        mysql_login_string += f" --host={os.getenv('DB_HOST')}"

    if os.getenv('DB_PORT'):
        mysql_login_string += f" --port={os.getenv('DB_PORT')}"

    return mysql_login_string


def s3_login() -> str:
    s3_login = f"--access_key={os.getenv('S3_ACCESS_KEY')}"
    s3_login += f" --secret_key={os.getenv('S3_SECRET_KEY')}"
    s3_login += f" --host={os.getenv('S3_HOST')}"
    s3_login += f" --host-bucket={os.getenv('S3_HOST_BUCKET')}"
    s3_login += f" --region={os.getenv('S3_REGION')}"

    use_ssl = os.getenv("S3_SSL")
    if use_ssl != None and use_ssl == "false":
        s3_login += " --no-ssl"
    else:
        s3_login += " --ssl"
        ssl_check_cert = os.getenv("S3_SSL_CHECK_CERT")
        ssl_check_host = os.getenv("S3_SSL_CHECK_HOST")

        if ssl_check_cert != None and ssl_check_cert == "false":
            s3_login += " --no-check-certificate"
        else:
            s3_login += " --check-certificate"
        
        if ssl_check_host != None and ssl_check_host == "false":
            s3_login += " --no-check-hostname"
        else:
            s3_login += " --check-hostname"

    return s3_login


def download_from_s3(file_name: str) -> str:
    file_path = f"/tmp/{file_name}"
    download_command = f"s3cmd -q {s3_login()} get s3://{os.getenv('S3_CONTAINER_NAME')}/{file_name} {file_path}"
    result = subprocess.call(download_command, stdout=subprocess.DEVNULL, shell=True)
    if result != 0 or os.path.isfile(file_path) == False:
        print(f"Ошибка: неудалось скачать файл '{file_name}' из хранилища")
        exit(1)
    
    return file_path


def restore_database(file: str, target_db_name: str):
    result = subprocess.call(f"mysql {mysql_login()} {target_db_name} < {file}", stdout=subprocess.DEVNULL, shell=True)
    if result != 0:
        print(f"Ошибка: неудалось восстановить базу данных '{target_db_name}' из {file}")
        exit(1)


def restore(db_name: str, date: str = None, target_db_name: str = None):
    if date != None and is_valid_date(str(date)) == False:
        print(f"Ошибка: '{date}' не является допустимой датой в формате YYYY-MM-DD")
        exit(1)
    else:
        date = datetime.datetime.today().strftime('%Y-%m-%d')
    
    if target_db_name == None:
        target_db_name = db_name
    
    print(f"Будет произведено восстановление БД '{target_db_name}' из дампа '{date}.{db_name}'")

    file = download_from_s3(f"{date}.{db_name}.sql.gz")
    result_gzip = subprocess.call(f"gzip -d {file}", stdout=subprocess.DEVNULL, shell=True)
    file = file.rstrip(".gz")

    if result_gzip != 0 or os.path.isfile(file) == False:
        print("Ошибка: неудалось распаковать архив")
        exit(1)

    restore_database(file, target_db_name)
    subprocess.call(f"rm {file}", stdout=subprocess.DEVNULL, shell=True)

    print(f"Дамп '{file.lstrip('/tmp/')}' записан в базу данных '{target_db_name}'")


def database_list() -> list:
    if os.getenv("DB_IGNORE_DATABASE_REGEX"):
        ignore_regex = os.getenv("DB_IGNORE_DATABASE_REGEX")
    else:
        ignore_regex = "(^mysql|_schema$|^sys$)"

    mysql_command = f"mysql {mysql_login()} --batch -e \"SHOW DATABASES WHERE \\`Database\\` NOT REGEXP '{ignore_regex}'\""

    process = subprocess.Popen(mysql_command, stdout=subprocess.PIPE, shell=True, text=True)
    output, _ = process.communicate()

    databases = [line for line in output.splitlines()[1:]]

    return databases


def backup_database(db_name: str) -> str:
    backup_file = f"/tmp/{datetime.datetime.today().strftime('%Y-%m-%d')}.{db_name}.sql.gz"
    ignored_tables = ""
    
    if os.getenv('DB_IGNORE_TABLES'):
        ignored_tables = f" --ignore-table={db_name}." + os.getenv('DB_IGNORE_TABLES').replace(",", f" --ignore-table={db_name}.")

    dump_command = f"mysqldump --single-transaction {mysql_login()} {db_name} {ignored_tables} | gzip -9 > {backup_file}"
    result = subprocess.call(dump_command, stdout=subprocess.DEVNULL, shell=True)

    if result != 0 or os.path.isfile(backup_file) == False:
        print(f"Ошибка: неудалось выполнить дамп БД '{db_name}'")
        exit(1)
    
    return backup_file


def upload_to_s3(file: str):
    upload_command = f"s3cmd -q {s3_login()} put {file} s3://{os.getenv('S3_CONTAINER_NAME')}"
    result = subprocess.call(upload_command, stdout=subprocess.DEVNULL, shell=True)
    if result != 0:
        print(f"Ошибка: неудалось загрузить файл '{file.lstrip('/tmp/')}' в хранилище")
        exit(1)


def backup(db_name: str = None):
    if db_name == None:
        print("Имя БД не передано. Будут экспортированы все БД с именами не совпадающими с паттерном из переменной окружения DB_IGNORE_DATABASE_REGEX")
        databases = database_list()
    else:
        print(f"Указана БД '{db_name}'. Будет произведен экспорт только этой БД")
        databases = [db_name]
    
    for database in databases:
        file = backup_database(database)
        upload_to_s3(file)
        subprocess.call(f"rm {file}", stdout=subprocess.DEVNULL, shell=True)
        print(f"Дамп базы данных '{database}' успешно выполнен в файл {file.lstrip('/tmp/')} и загружен в хранилище")


# Запуск скрипта


if len(sys.argv) < 2:
    print("Ошибка: требуется указать первый аргумент 'restore' или 'backup'")
    exit(1)

if sys.argv[1] == "restore":
    if len(sys.argv) < 3 or sys.argv[2] is None:
        print("Ошибка: для операции 'restore' требуется передать имя БД вторым аргументом")
        exit(1)

    db_name = sys.argv[2]
    date = sys.argv[3] if len(sys.argv) > 3 else None
    target_db_name = sys.argv[4] if len(sys.argv) > 4 else None
    restore(db_name, date, target_db_name)

elif sys.argv[1] == "backup":
    db_name = sys.argv[2] if len(sys.argv) > 2 else None
    backup(db_name)

else:
    print(f"Ошибка: недопустимый аргумент '{sys.argv[1]}'. Возможные значения: 'restore' или 'backup'")
    exit(1)