#!/bin/bash
#===============================================================================
# Название: Kudesnik-IT - SSH Security Configuration Script (KIT-SSCS)
#
# Описание: Этот скрипт автоматизирует настройку безопасности SSH-сервера:
#   - Создает новый конфигурационный файл `sshd_config` с рекомендуемыми параметрами.
#   - Генерирует новые SSH-ключи (Ed25519) для сервера.
#   - Устанавливает права доступа на ключи и конфигурационные файлы.
#   - Настройка баннера для предупреждения пользователей.
#   - Перезапуск и тестирование на соответствие настройкам.
#  _  __              _                        _   _              ___   _____ 
# | |/ /  _   _    __| |   ___   ___   _ __   (_) | | __         |_ _| |_   _|
# | ' /  | | | |  / _` |  / _ \ / __| | '_ \  | | | |/ /  _____   | |    | |  
# | . \  | |_| | | (_| | |  __/ \__ \ | | | | | | |   <  |_____|  | |    | |  
# |_|\_\  \__,_|  \__,_|  \___| |___/ |_| |_| |_| |_|\_\         |___|   |_|  
#                                                                             
# Автор: Kudesnik-IT <kudesnik.it@gmail.com>
# GitHub: https://github.com/Kudesnik-IT/ssh-security-setup
# Версия: 1.0
# Дата создания: 2025-02-11
# Последнее обновление: 2025-02-11
#===============================================================================
# Лицензия: MIT License
# Copyright (c) 2025 Kudesnik-IT
#
# Разрешается свободное использование, копирование, модификация, объединение,
# публикация, распространение, сублицензирование и/или продажа копий ПО.
# Зависимости:
# - Bash (тестировано на версии 5.2+)
# - OpenSSH Server (тестировано на версии 9.2+)
# - Coreutils (для команды grep, awk, sed и т.д.)
# - Logrotate (для настройки ротации логов)
# - Systemd (для управления службой SSH)
# Инструкции по использованию:
# 1. Сделайте скрипт исполняемым: chmod +x ssh_security_setup.sh
# 2. Запустите скрипт: ./ssh_security_setup.sh
# 3. Следуйте инструкциям на экране.
# История изменений:
# v1.0 (2025-02-11): Первая версия скрипта.
#===============================================================================


set -e                    # automatically terminate execution on first error
set -u                    # prevent use of undefined variables
set -o pipefail           # handle errors in pipelines


##########################
# --- DEFINE VARIABLES ---
##########################

SSH_USER="user1"
SSH_PORT="22"
SSH_IP="0.0.0.0"     
TEST_ONLY=false          

###################
# --- FUNCTIONS ---
###################

# Function to output messages with indentation
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Функция для вывода результата теста
test_result() {
    local status="$1"  # "ok" или "fail"
    local message="$2" # Сообщение о тесте
    if [ "$status" == "ok" ]; then
        echo -e "✓ $message"
    else
        echo -e "✗ $message"
    fi
}

# Function view help message
help() {
  cat <<EOF

  Usage: $(basename "$0") [options]

  Options:
    -h, --help         помощь
    -u, --username     пользователь
    -p, --port         порт
    -i, --ip           ip адрес
    -t, --testonly     запустить только тесты

EOF
  exit
}

##############
# --- MAIN ---
##############

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -u|--username)
            if [[ -z "${2+x}" || -z "$2" || "$2" =~ ^- ]]; then
                echo "Error: No value for argument '$1'"
                help
            fi
            SSH_USER="$2"
            shift 2
            ;;
        -p|--port)
            if [[ -z "${2+x}" || -z "$2" || "$2" =~ ^- ]]; then
                echo "Error: No value for argument '$1'"
                help
            fi
            SSH_PORT="$2"
            shift 2
            ;;
        -i|--ip)
            if [[ -z "${2+x}" || -z "$2" || "$2" =~ ^- ]]; then
                echo "Error: No value for argument '$1'"
                help
            fi
            SSH_IP="$2"
            shift 2
            ;;
        -t|--testonly)
            TEST_ONLY="all"
            shift
            ;;
        -h|--help)
            help
            ;;
        *)
            echo "Unknown argument: $1"
            help
            ;;
    esac
done

SSHD_CONFIG="/etc/ssh/sshd_config"
KEY_PATH="/etc/ssh"
CONFIG_ADDRESS_FAMILY=inet
CONFIG_LISTEN_ADDRESS="${SSH_IP}"
#CONFIG_LISTEN_ADDRESS=$(echo "$(ip -4 addr | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "^127\.")" | head -n 1)

cat <<EOF

██╗  ██╗██╗   ██╗██████╗ ███████╗███████╗███╗   ██╗██╗██╗  ██╗     ██╗████████╗
██║ ██╔╝██║   ██║██╔══██╗██╔════╝██╔════╝████╗  ██║██║██║ ██╔╝     ██║╚══██╔══╝
█████╔╝ ██║   ██║██║  ██║█████╗  ███████╗██╔██╗ ██║██║█████╔╝█████╗██║   ██║   
██╔═██╗ ██║   ██║██║  ██║██╔══╝  ╚════██║██║╚██╗██║██║██╔═██╗╚════╝██║   ██║   
██║  ██╗╚██████╔╝██████╔╝███████╗███████║██║ ╚████║██║██║  ██╗     ██║   ██║   
╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═╝     ╚═╝   ╚═╝   
..............................................,,,,
   SSH Security Configuration Script (KIT-SSCS)
''''''''''''''''''''''''''''''''''''''''''''''''''
This script configures ssh security...



EOF


# === Проверка зависимостей ===
log "Проверка зависимостей..."
for cmd in ip ss ssh-keygen sshd systemctl; do
    if ! command -v "$cmd" &>/dev/null; then
        log "Команда $cmd не найдена. Установите её перед выполнением скрипта."
        exit 1
    fi
done

# === Проверка пользователей ===
if ! id "$SSH_USER" >/dev/null 2>&1; then
    log "Пользователь '$SSH_USER' не существует. Создайте его перед выполнением скрипта."
    exit 1
fi

# === Проверка ip адресов ===
if [ "$CONFIG_LISTEN_ADDRESS" != "0.0.0.0" ]; then
    if ! echo "$(ip -4 addr | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || true)" | grep -q "^$CONFIG_LISTEN_ADDRESS\$"; then
        log "Указанный ListenAddress ($CONFIG_LISTEN_ADDRESS) не найден среди доступных IP-адресов."
        exit 1
    fi
fi


if [[ "${TEST_ONLY}" == "all" ]]; then

    # === 1. Создание файла конфигурации sshd_config ===
    log "Создание файла конфигурации"

    # Бэкап существующего конфигурационного файла
    if [ -f "$SSHD_CONFIG" ]; then
        cp "$SSHD_CONFIG" "$SSHD_CONFIG.backup"
        log "Создан бэкап существующего конфигурационного файла: $SSHD_CONFIG.backup"
    fi

    # Создание нового файла конфигурации
    cat > "$SSHD_CONFIG" <<EOF
# === ПАРАМЕТРЫ БЕЗОПАСНОСТИ СОЕДИНЕНИЯ ===

HostKey /etc/ssh/ssh_host_ed25519_key                             # Использование только Ed25519 для HostKey
PubkeyAcceptedKeyTypes=ssh-ed25519                                # Разрешение только Ed25519 для ключей пользователей
HostKeyAlgorithms=ssh-ed25519                                     # Разрешение только Ed25519 для алгоритмов обмена ключами
KexAlgorithms=curve25519-sha256                                   # Алгоритмы обмена ключами (рекомендуется curve25519-sha256)
Ciphers=chacha20-poly1305@openssh.com,aes256-gcm@openssh.com      # Шифры для защиты данных (рекомендуется ChaCha20 и AES-GCM)
MACs=hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com  # Методы аутентификации сообщений (рекомендуется HMAC-SHA2)
RekeyLimit 1G 1h                                                  # Перешифровка соединения каждые 1 ГБ данных или 1 час
HostbasedAuthentication no                                        # Отключение хост-базированной аутентификации


# === НАСТРОЙКИ ПОРТА и СЕТЕВОГО ИНТЕРФЕЙСА ===

Port ${SSH_PORT}                                    # Использование нестандартного порта для снижения автоматических атак
AddressFamily ${CONFIG_ADDRESS_FAMILY}                                  # Разрешение только IPv4 (если IPv6 не требуется)
ListenAddress ${CONFIG_LISTEN_ADDRESS}                         # Ограничение прослушивания только определенного IP-адреса
Protocol 2                                          # Использование только версии протокола 2


# === УПРАВЛЕНИЕ ДОСТУПОМ === 

UsePAM yes                                          # Включение PAM для использования дополнительных методов аутентификации
PermitRootLogin no                                  # Запрет прямого входа под root
PasswordAuthentication no                           # Отключение парольной аутентификации
PermitEmptyPasswords no
PubkeyAuthentication yes                            # Разрешение аутентификации по публичным ключам
AuthenticationMethods publickey                     # Требование использования только SSH-ключей
AuthorizedKeysFile .ssh/authorized_keys             # Путь к файлу с авторизованными ключами (chmod 600 ~/.ssh/authorized_keys && chmod 700 ~/.ssh)
ChallengeResponseAuthentication no                  # Отключение challenge-response аутентификации
AllowUsers ${SSH_USER}                              # Разрешение доступа только указанным пользователям
DenyUsers ALL                                       # Явно запрещаем всем остальным пользователям (защита от ошибок)
KbdInteractiveAuthentication no                     # Отключение клавиатурно-интерактивной аутентификации
Banner /etc/issue.net                               # Отображение баннера при подключении (chmod 644 /etc/issue.net && chown root:root /etc/issue.net)
PermitUserEnvironment no                            # Запрет чтения файла ~/.ssh/environment для установки переменных окружения пользователем


# === НАСТРОЙКИ ПРОИЗВОДИТЕЛЬНОСТИ ===

MaxStartups 10:30:60                                # Защита от DDoS-атак: разрешает максимум 10 одновременных попыток входа
MaxAuthTries 3                                      # Максимум 3 попытки аутентификации
MaxSessions 5                                       # Ограничение максимального количества сессий на пользователя
LoginGraceTime 15                                   # Время на ввод учетных данных ограничено 15 секундами
ClientAliveInterval 60                              # Отправка keepalive пакетов каждые 60 секунд
ClientAliveCountMax 3                               # Разрыв соединения после 3 пропущенных keepalive пакетов


# === ЛОГИРОВАНИЕ и МОНИТОРИНГ ===

LogLevel INFO                                       # Подробное журналирование для обнаружения подозрительной активности (VERBOSE или INFO)
StrictModes yes                                     # Строгая проверка прав доступа к файлам пользователей

# === ДОПОЛНИТЕЛЬНЫЕ ПАРАМЕТРЫ ===

X11Forwarding no                                    # Отключение X11 forwarding для повышения безопасности
PrintMotd no                                        # Отключение вывода MOTD (используйте /etc/motd вместо этого)
AcceptEnv LANG LC_*                                 # Разрешение передачи переменных окружения
Subsystem sftp internal-sftp                        # Использование внутренней реализации SFTP для большей безопасности
IgnoreRhosts yes                                    # Игнорирование файлов .rhosts и ~/.shosts для предотвращения устаревших методов аутентификации
AllowTcpForwarding no                               # Запрет TCP-туннелирования для предотвращения использования сервер
EOF

    log "Файл конфигурации $SSHD_CONFIG успешно создан."

    # === 2. Удаление всех старых ключей ===
    log "Удаление всех старых ключей..."
    rm -f "/etc/ssh/ssh_host_*" 2>/dev/null
    log "Все старые ключи удалены."

    # === 3. Создание нового ключа ssh_host_ed25519_key ===
    log "Создание нового ключа ssh_host_ed25519_key..."
    ssh-keygen -t ed25519 -f "${KEY_PATH}/ssh_host_ed25519_key" -N "" >/dev/null 2>&1
    log "Создан новый ключ ssh_host_ed25519_key."

    # === 4. Проверка и установка прав на все необходимые файлы ===
    log "Установка прав на ключи и конфигурацию"
    chown root:root "${KEY_PATH}/ssh_host_*"
    chmod 600 "${KEY_PATH}/ssh_host_*"
    chmod 644 "${KEY_PATH}/ssh_host_ed25519_key.pub"
    chown root:root /etc/ssh
    chmod 750 /etc/ssh
    chown root:root /etc/ssh/sshd_config
    chmod 600 /etc/ssh/sshd_config
    log "Права на файлы установлены"

    # === 5. Настройка баннера ===
    log "Настройка баннера..."
    for file in /etc/motd /etc/issue /etc/issue.net; do
        if [ -f "$file" ]; then
            chown root:root "$file"
            chmod 644 "$file"
            log "Права на файл $file установлены."
        else
            log "Файл $file не найден, пропускаем."
        fi
    done
    echo "WARNING: Unauthorized access, your actions will be monitored." > /etc/issue.net
    log "Баннер создан и настроен."

    # === 6. Проверка конфигурации ===
    log "Проверка конфигурации SSH..."
    sshd -t
    if [ $? -ne 0 ]; then
        log "Ошибка в конфигурации SSH-сервера. Проверьте файл $SSHD_CONFIG."
        exit
    fi
    log "Конфигурация SSH-сервера корректна."

    # === 7. Перезапуск SSH-сервера ===
    log "Перезапуск ssh сервера..."
    systemctl restart sshd
    log "SSH-сервер перезапущен."


    # === Проверка готовности SSH-сервера ===
    log "Ожидание готовности SSH-сервера..."
    TIMEOUT=30  # Максимальное время ожидания (в секундах)
    SLEEP_INTERVAL=2  # Интервал между проверками (в секундах)
    ELAPSED_TIME=0

    while [ $ELAPSED_TIME -lt $TIMEOUT ]; do
        if systemctl is-active --quiet sshd; then
            log "SSH-сервер успешно запущен."
            break
        fi
        sleep $SLEEP_INTERVAL
        ELAPSED_TIME=$((ELAPSED_TIME + SLEEP_INTERVAL))
    done

    if [ $ELAPSED_TIME -ge $TIMEOUT ]; then
        test_result "fail" "✗ SSH-сервер не запустился за отведенное время ($TIMEOUT секунд)."
        exit 1
    fi
fi

log "Выполнение тестов..."

# Тест: Проверка открытых портов
# Массив для хранения ошибок
errors=()
# Получаем список всех портов, открытых сервисом sshd
OPEN_PORTS=$(ss -tuln -p | grep "sshd" | grep "LISTEN" | awk '{print $4}')
PORT_COUNT=$(echo "$OPEN_PORTS" | wc -l)
# Проверяем, что открыт только один порт
if [ "$PORT_COUNT" -ne 1 ]; then
    errors+=("✗ Сервис sshd слушает $PORT_COUNT портов. Должен быть открыт только один порт.")
fi
# Проверяем каждый открытый порт
EXPECTED_ADDRESS="${CONFIG_LISTEN_ADDRESS}:${SSH_PORT}"
while read -r OPEN_PORT_LINE; do
    # Разделяем адрес и порт
    OPEN_ADDRESS=$(echo "$OPEN_PORT_LINE" | cut -d':' -f1)
    OPEN_PORT=$(echo "$OPEN_PORT_LINE" | cut -d':' -f2)

    # Проверяем, что порт соответствует Port из конфигурации
    if [ "$OPEN_PORT" != "$SSH_PORT" ]; then
        errors+=("✗ Сервис sshd слушает неправильный порт ($OPEN_PORT). Ожидался порт $SSH_PORT.")
    fi

    # Проверяем, что порт открыт только для IPv4 (если AddressFamily inet)
    if [ "$CONFIG_ADDRESS_FAMILY" == "inet" ]; then
        if [[ "$OPEN_ADDRESS" == "["*"]" ]]; then
            errors+=("✗ Сервис sshd слушает порт на IPv6 ($OPEN_ADDRESS:$OPEN_PORT), хотя AddressFamily установлен как inet.")
        fi
    fi

    # Проверяем, что порт открыт только на указанном ListenAddress
    if [ "$OPEN_PORT_LINE" != "$EXPECTED_ADDRESS" ]; then
        errors+=("✗ Сервис sshd слушает порт на неправильном адресе ($OPEN_PORT_LINE). Ожидался адрес: $EXPECTED_ADDRESS")
    fi
done <<< "$OPEN_PORTS"
# Вывод результатов
if [ ${#errors[@]} -eq 0 ]; then
    test_result "ok" "✓ Тест портов: Сервис sshd слушает только один порт ($SSH_PORT) на адресе $CONFIG_LISTEN_ADDRESS."
else
    test_result "fail" "✗ Тест портов не пройден: Обнаружены ошибки в конфигурации открытых портов."
    for error in "${errors[@]}"; do
        echo "$error"
    done
    echo "  Список открытых портов:"
    echo "$OPEN_PORTS" | sed 's/^/    /' # Выводим список портов с отступами
fi

# Тест: Проверка прав на конфигурационный файл
if [ "$(stat -c %a "$SSHD_CONFIG")" == "600" ]; then
    test_result "ok" "Права на файл $SSHD_CONFIG корректны."
else
    test_result "fail" "Некорректные права на файл $SSHD_CONFIG."
fi

# Тест: Проверка прав на ключи
PRIVATE_KEY="${KEY_PATH}/ssh_host_ed25519_key"
PUBLIC_KEY="${KEY_PATH}/ssh_host_ed25519_key.pub"
if [ "$(stat -c %a "$PRIVATE_KEY")" == "600" ]; then
    test_result "ok" "Права на приватный ключ $PRIVATE_KEY корректны."
else
    test_result "fail" "Некорректные права на приватный ключ $PRIVATE_KEY."
fi
if [ "$(stat -c %a "$PUBLIC_KEY")" == "644" ]; then
    test_result "ok" "Права на публичный ключ $PUBLIC_KEY корректны."
else
    test_result "fail" "Некорректные права на публичный ключ $PUBLIC_KEY."
fi

# Тест: Проверка прав на баннер
for file in /etc/motd /etc/issue /etc/issue.net; do
    if [ -f "$file" ]; then
        if [ "$(stat -c %a "$file")" == "644" ]; then
            test_result "ok" "Права на файл $file корректны."
        else
            test_result "fail" "Некорректные права на файл $file."
        fi
    else
        test_result "fail" "Файл $file не найден."
    fi
done

# Тест: Проверка параметров
# Ожидаемые параметры и их значения (те, что создаются скриптом)
declare -A EXPECTED_SETTINGS=(
    # === ПАРАМЕТРЫ БЕЗОПАСНОСТИ СОЕДИНЕНИЯ ===
    ["hostkey"]="/etc/ssh/ssh_host_ed25519_key"                             # Использование только Ed25519 для HostKey
    ["pubkeyacceptedkeytypes"]="ssh-ed25519"                                # Разрешение только Ed25519 для ключей пользователей
    ["hostkeyalgorithms"]="ssh-ed25519"                                     # Разрешение только Ed25519 для алгоритмов обмена ключами
    ["kexalgorithms"]="curve25519-sha256"                                   # Алгоритмы обмена ключами (рекомендуется curve25519-sha256)
    ["ciphers"]="chacha20-poly1305@openssh.com,aes256-gcm@openssh.com"      # Шифры для защиты данных (рекомендуется ChaCha20 и AES-GCM)
    ["macs"]="hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com"  # Методы аутентификации сообщений (рекомендуется HMAC-SHA2)
    ["rekeylimit"]="1G:1h"                                                  # Перешифровка соединения каждые 1 ГБ данных или 1 час
    ["hostbasedauthentication"]="no"                                        # Отключение хост-базированной аутентификации

    # === НАСТРОЙКИ ПОРТА и СЕТЕВОГО ИНТЕРФЕЙСА ===
    ["port"]="50000"                                                        # Использование нестандартного порта для снижения автоматических атак
    ["addressfamily"]="inet"                                                # Разрешение только IPv4 (если IPv6 не требуется)
    ["listenaddress"]="192.168.1.102"                                       # Ограничение прослушивания только определенного IP-адреса
    ["protocol"]="2"                                                        # Использование только версии протокола 2

    # === УПРАВЛЕНИЕ ДОСТУПОМ ===
    ["usepam"]="yes"                                                        # Включение PAM для использования дополнительных методов аутентификации
    ["permitrootlogin"]="no"                                                # Запрет прямого входа под root
    ["passwordauthentication"]="no"                                         # Отключение парольной аутентификации
    ["permitempty passwords"]="no"                                          # Запрет пустых паролей
    ["pubkeyauthentication"]="yes"                                          # Разрешение аутентификации по публичным ключам
    ["authenticationmethods"]="publickey"                                   # Требование использования только SSH-ключей
    ["authorizedkeysfile"]=".ssh/authorized_keys"                           # Путь к файлу с авторизованными ключами
    ["challengeresponseauthentication"]="no"                                # Отключение challenge-response аутентификации
    ["allowusers"]="user1"                                                  # Разрешение доступа только указанным пользователям
    ["denyusers"]="ALL"                                                     # Явно запрещаем всем остальным пользователям (защита от ошибок)
    ["kbdinteractiveauthentication"]="no"                                   # Отключение клавиатурно-интерактивной аутентификации
    ["banner"]="/etc/issue.net"                                             # Отображение баннера при подключении
    ["permituserenvironment"]="no"                                          # Запрет чтения файла ~/.ssh/environment для установки переменных окружения пользователем

    # === НАСТРОЙКИ ПРОИЗВОДИТЕЛЬНОСТИ ===
    ["maxstartups"]="10:30:60"                                              # Защита от DDoS-атак: разрешает максимум 10 одновременных попыток входа
    ["maxauthtries"]="3"                                                    # Максимум 3 попытки аутентификации
    ["maxsessions"]="5"                                                     # Ограничение максимального количества сессий на пользователя
    ["logingracetime"]="15"                                                 # Время на ввод учетных данных ограничено 15 секундами
    ["clientaliveinterval"]="60"                                            # Отправка keepalive пакетов каждые 60 секунд
    ["clientalivecountmax"]="3"                                             # Разрыв соединения после 3 пропущенных keepalive пакетов

    # === ЛОГИРОВАНИЕ и МОНИТОРИНГ ===
    ["loglevel"]="INFO"                                                     # Подробное журналирование для обнаружения подозрительной активности
    ["strictmodes"]="yes"                                                   # Строгая проверка прав доступа к файлам пользователей

    # === ДОПОЛНИТЕЛЬНЫЕ ПАРАМЕТРЫ ===
    ["x11forwarding"]="no"                                                  # Отключение X11 forwarding для повышения безопасности
    ["printmotd"]="no"                                                      # Отключение вывода MOTD
    ["acceptenv"]="LANG LC_*"                                               # Разрешение передачи переменных окружения
    ["subsystem"]="sftp internal-sftp"                                      # Использование внутренней реализации SFTP для большей безопасности
    ["ignorerhosts"]="yes"                                                  # Игнорирование файлов .rhosts и ~/.shosts для предотвращения устаревших методов аутентификации
    ["allowtcpforwarding"]="no"                                             # Запрет TCP-туннелирования для предотвращения использования сервера как прокси
)
# Массив для хранения ошибок
errors=()
# Проверка каждого параметра
for key in "${!EXPECTED_SETTINGS[@]}"; do
    expected_value="${EXPECTED_SETTINGS[$key]}"
    actual_value=$(sshd -T | grep -w "^$key" | awk '{print $2}' | xargs)
    
    if [ "$actual_value" != "$expected_value" ]; then
        errors+=("✗ Параметр '$key' имеет значение '$actual_value', ожидалось '$expected_value'.")
    fi
done
# Вывод результатов
if [ ${#errors[@]} -eq 0 ]; then
    test_result "ok" "✓ Все параметры конфигурации SSH корректны."
else
    test_result "fail" "✗ Обнаружены ошибки в конфигурации SSH:"
    for error in "${errors[@]}"; do
        echo "  $error"
    done
fi

log "Тесты завершены."

log "Настройка безопасности SSH завершена"


#---
# Автор: Kudesnik-IT <kudesnik.it@gmail.com>
# GitHub: https://github.com/Kudesnik-IT/ssh-security-setup
#---