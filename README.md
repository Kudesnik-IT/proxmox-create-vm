# KIT-PVMDS: Proxmox VM Deployment Script

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**KIT-PVMDS** (Kudesnik-IT Proxmox VM Deployment Script) — это инструмент для автоматизации создания и настройки виртуальных машин в Proxmox VE. Скрипт выполняет все необходимые шаги для быстрого развертывания виртуальной машины с предустановленным Debian 12, Docker и Docker Compose, а также настраивает SSH-ключи и пользователей.

---

## Основные возможности

- **Автоматическое создание виртуальной машины**:
  - Скачивает образ Debian 12 (genericcloud) с проверкой хэш-суммы образа.
  - Добавляет образ в виртуальную машину.
  - Создает диск `cloud-init` и настраивает его.

- **Генерация SSH-ключей**:
  - Создает новые SSH-ключи для безопасного подключения к виртуальной машине.
  - Копирует публичный ключ в конфигурацию `cloud-init`.

- **Настройка пользователя и сети**:
  - Создает нового пользователя с правами `sudo`.
  - Настраивает статический IP-адрес или DHCP.
  - Настройка шлюза и DNS.

- **Установка Docker и Docker Compose**:
  - Автоматически устанавливает Docker и Docker Compose внутри виртуальной машины.

- **Гибкая настройка**:
  - Возможность задавать параметры через аргументы командной строки.
  - Возможность задавать параметры по умолчанию через переменные в скрипте.

---

## Требования

- **Proxmox VE 8.2+**
- **Bash 5.2+**
- **Coreutils** (для команд `echo`, `curl` и т.д.)
- **SSH-клиент**

---

## Установка и использование

### 1. Сделайте скрипт исполняемым

```bash
chmod +x create_vm.sh
```

### 2. Запустите скрипт

```bash
./create_vm.sh [options]
```

### 3. Доступные опции

| Опция          | Описание                                                                 |
|----------------|-------------------------------------------------------------------------|
| `-h, --help`   | Показать справку по использованию скрипта.                              |
| `-u, --username` | Создать нового пользователя с указанным именем.                        |
| `-p, --password` | Указать хэш пароля для авторизации пользователя.                       |
| `-a, --auth`    | Использовать аутентификацию по паролю (по умолчанию отключено).         |
| `-i, --ip`      | Указать IP-адрес и маску для виртуальной машины (например, `192.168.1.10/24`). |
| `-g, --gateway` | Указать шлюз для сети виртуальной машины.                              |
| `-f, --file`    | Указать имя файла образа Debian (например, `debian-12-genericcloud-amd64.raw`). |

---

## Пример использования

### Создание виртуальной машины с DHCP

```bash
./create_vm.sh --username myuser
```

### Создание виртуальной машины с настройкой статического IP

```bash
./create_vm.sh --username myuser --ip 192.168.1.10/24 --gateway 192.168.1.1
```

### Создание виртуальной машины с указанием имени файла образа

```bash
./create_vm.sh --username myuser --file /path/to/debian-12-genericcloud-amd64.raw
```

---

## Вывод успешного выполнения

После завершения работы скрипта выводится отчет о выполнении:

```plaintext
=== Process completed successfully ===

✓ The virtual machine has been successfully created.

✓ The package docker-compose should be installed on the virtual machine.

✓ A snippet named userdata-1.yaml has been created:
      • Location: /var/lib/vz/snippets/
      • Alternatively, you can view it in the web interface under the Snippets storage.

✓ Network configuration: IP:192.168.1.10/24  GW:192.168.1.1.

✓ Keys for connecting to the virtual machine have been generated:
      • The keys key and key.pub are located in the folder /root/.keys/.
      • The public key has been copied to the virtual machine.

✓ The user for accessing the virtual machine is: myuser.

=== Done! ===
```

---

## Переменные окружения

Вы можете настроить поведение скрипта, изменив значения переменных в начале файла:

| Переменная          | Описание                                                                 |
|---------------------|-------------------------------------------------------------------------|
| `VM_ID`             | ID виртуальной машины (по умолчанию `1`).                               |
| `VM_NAME`           | Имя виртуальной машины (по умолчанию `Debian-Srv`).                     |
| `VM_IP`             | IP-адрес и маска (если пусто, используется DHCP).                       |
| `CI_USER`           | Имя пользователя для доступа к виртуальной машине (по умолчанию `virtman`). |
| `STORAGE_SNIP`      | Хранилище для snippets (по умолчанию `local`).                          |
| `STORAGE_DISK`      | Хранилище для дисков виртуальной машины (по умолчанию `local-lvm`).     |
| `SET_USER_PASS`     | Создавать ли пароль для пользователя (по умолчанию `false`).            |
| `RUN_VM`            | Запускать ли виртуальную машину после создания (по умолчанию `false`).  |

---

## Лицензия

Этот проект распространяется под лицензией **MIT License**. Подробнее см. в файле [LICENSE](LICENSE).

---

## Автор

- **Автор**: Kudesnik-IT
- **GitHub**: [https://github.com/Kudesnik-IT/proxmox-create-vm](https://github.com/Kudesnik-IT/proxmox-create-vm)
- **Дата создания**: 2025-02-06
- **Последнее обновление**: 2025-02-06

---

## Отзывы и предложения

Если у вас есть вопросы, предложения или вы нашли ошибку, пожалуйста, создайте issue в репозитории или свяжитесь с автором напрямую.

---

Спасибо за использование **KIT-PVMDS**!
