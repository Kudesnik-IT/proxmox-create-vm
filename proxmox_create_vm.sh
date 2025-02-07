#!/bin/bash
#===============================================================================
# Название: Kudesnik-IT - Proxmox VM Deployment Script (KIT-PVMDS)
#
# Описание: Этот скрипт автоматизирует создание виртуальной машины в Proxmox:
#   - Скачивает образ Debian 12 (genericcloud).
#   - Добавляет образ в виртуальную машину.
#   - Создает диск cloud-init и настраивает его.
#   - Генерирует SSH-ключи на сервере Proxmox и добавляет публичный ключ в cloud-init.
#   - В виртуальной машине через cloud-init:
#     - Создает нового пользователя.
#     - Настраивает сеть.
#     - Устанавливает Docker и Docker Compose.
#  _  __              _                        _   _              ___   _____ 
# | |/ /  _   _    __| |   ___   ___   _ __   (_) | | __         |_ _| |_   _|
# | ' /  | | | |  / _` |  / _ \ / __| | '_ \  | | | |/ /  _____   | |    | |  
# | . \  | |_| | | (_| | |  __/ \__ \ | | | | | | |   <  |_____|  | |    | |  
# |_|\_\  \__,_|  \__,_|  \___| |___/ |_| |_| |_| |_|\_\         |___|   |_|  
#                                                                             
# Автор: Kudesnik-IT <kudesnik.it@gmail.com>
# GitHub: https://github.com/Kudesnik-IT
# Версия: 1.0
# Дата создания: 2025-06-02
# Последнее обновление: 2025-06-02
#===============================================================================

# Лицензия: MIT License
# Copyright (c) 2025 Kudesnik-IT
#
# Разрешается свободное использование, копирование, модификация, объединение,
# публикация, распространение, сублицензирование и/или продажа копий ПО.

# Зависимости:
# - Bash (тестировано на версии 5.2+)
# - Proxmox VE 8.2+
# - Coreutils (для команды echo, curl и т.д.)
# - SSH-клиент

# Инструкции по использованию:
# 1. Сделайте скрипт исполняемым: chmod +x create_vm.sh
# 2. Запустите скрипт: ./create_vm.sh
# 3. Следуйте инструкциям на экране.

# История изменений:
# v1.0 (2023-10-15): Первая версия скрипта.
#===============================================================================



set -e                    # automatically terminate execution on first error
set -u                    # prevent use of undefined variables
set -o pipefail           # handle errors in pipelines


##########################
# --- DEFINE VARIABLES ---
##########################

VM_ID="1"                 # VM ID = ${VM_ID}{value 1st argument}
VM_NAME="Debian-Srv"      # VM name = ${VM_NAME}{value 1st argument}

VM_IP=""                  # VM IPv4 value format "<IPv4/Mask>; If empty string, then there will be DHCP setting."
VM_GATEWAY=""             # VM network gateway, only if set VM_IP address
VM_BRIDGE="vmbr0"         # VM bridge name

CI_USER="virtman"         # username
CI_PASS=""                # hash of the user's password if password authentication is used

STORAGE_SNIP=local        # storage for snippets (usually the same as the iso images storage)
STORAGE_DISK=local-lvm    # storage for virtual machine disk images

SNIP_PATH=/var/lib/vz/snippets/       # snippets storage directory
ISO_PATH=/var/lib/vz/template/iso/    # iso image storage directory

FILE_RAW="debian-12-genericcloud-amd64.raw"    # name image debian genericcloud

URL_RAW="https://cdimage.debian.org/images/cloud/bookworm/latest/"                 # url image debianm  
URL_RAW_SHA="https://cdimage.debian.org/images/cloud/bookworm/latest/SHA512SUMS"   # url hash sums images debian

KEYS_PATH=/root/.keys/    # directory where keys for ssh access will be located
KEY_NAME="vm-"            # prefix for creating key name

SET_KEY_PASS=false        # set a secret phrase for the key
SET_USER_PASS=false       # create a password for the user        
RUN_VM=false              # start the virtual machine after it is created
SET_FILE_RAW_IMG=true     # adds the extension ".img" to FILE_RAW, then the file will be visible if it is in the iso image directory
DEL_FILE_RAW=false        # delete file after creating virtual machine
SET_IP_FROM_ID=false      # if the IP address is specified, then the value of the 1st argument will be added to the 4th octet


###################
# --- FUNCTIONS ---
###################

# Function to output messages with indentation
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function view help message
help() {
  cat <<EOF

  Usage: $(basename "$0") <num> [options]

    <num>              <string>
                       The number used to create the VM ID.  

  Options:
    -h, --help         show this help message and exit
    -u, --username     creating a new user with the set name
    -p, --password    hash user password for authorization
    -a, --auth         <yes | no> use password authentication
    -i, --ip           <xxx.xxx.xxx.xxx/xx> ip address and mask for VM
    -g, --gateway      <xxx.xxx.xxx.xxx> ip address gateway for VM
    -f, --file         name image debian genericcloud

EOF
  exit
}

# Function to download data to a file or variable
download_data() {
  local URL="$1"          # Url file
  local DEST="$2"         # File path
  local MODE="$3"         # Type destination ("file" or "variable")
  local MAX_ATTEMPTS=3    # Maximum number of attempts
  local TIMEOUT=30        # Timeout waiting for server response

  log "Downloading data from '$URL'..."
  for attempt in $(seq 1 $MAX_ATTEMPTS); do
    log "Attempt $attempt of $MAX_ATTEMPTS..."
    if [[ "$MODE" == "file" ]]; then
      # load to file
      if wget --timeout="$TIMEOUT" --tries=1 --progress=bar:force -O "$DEST" "$URL"; then
        log "Data successfully downloaded to file '$DEST'."
        return 0
      else
        log "Attempt $attempt failed."
      fi
    elif [[ "$MODE" == "variable" ]]; then
      # load to variable
      DOWNLOADED_DATA=$(wget --timeout="$TIMEOUT" --tries=1 -qO- "$URL")
      if [[ $? -eq 0 && -n "$DOWNLOADED_DATA" ]]; then
        log "Data successfully downloaded into variable."
		DOWNLOADED_CONTENT="$DOWNLOADED_DATA"   #  save data to global variable DOWNLOADED_CONTENT
        return 0
      else
        log "Attempt $attempt failed."
      fi
    else
      log "Error: Invalid mode specified. Use 'file' or 'variable'."
      return 1
    fi
    
    if [[ $attempt -lt $MAX_ATTEMPTS ]]; then
      log "Retrying in 5 seconds..."
      sleep 5
    else
      log "No more retries left."
    fi
  done

  log "Error: Failed to download data from '$URL' after $MAX_ATTEMPTS attempts."
  return 1
}

# Function to verify file integrity
verify_hash() {
  local FILE="$1"          # Path to file
  local EXPECTED_HASH="$2" # Hash from file

  # Check if the file exists
  if [[ ! -f "$FILE" ]]; then
    log "Error: File '$FILE' not found."
    return 1
  fi

  # Calculate the hash of the file
  log "Calculating hash for '$FILE'..."
  CALCULATED_HASH=$(sha512sum "$FILE" | awk '{print $1}')
  log "Calculated hash: $CALCULATED_HASH"

  # Compare hashes
  if [[ "$CALCULATED_HASH" == "$EXPECTED_HASH" ]]; then
    log "File integrity verified successfully."
    return 0
  else
    log "Error: File integrity check failed."
    return 1
  fi
}

# Function to update the 4th octet of an IP address
update_ip() {
    local ip_mask="$1"
    local id_num="$2"

    IFS='/' read -r ip mask <<< "$ip_mask"
    IFS='.' read -r octet1 octet2 octet3 octet4 <<< "$ip"
    new_octet4=$((octet4 + id_num))

    if (( new_octet4 < 0)); then
        new_octet4=0
    else
      if ((new_octet4 > 255 )); then
          new_octet4=255
      fi
    fi

    new_ip="${octet1}.${octet2}.${octet3}.${new_octet4}"
    echo "${new_ip}/${mask}"
}

# Function view report
view_report() {
  # ANSI color codes
  local GREEN='\033[0;32m'   # Green
  local YELLOW='\033[1;33m'  # Yellow
  local BLUE='\033[0;34m'    # Blue
  local MAGENTA='\033[0;35m' # Magenta (optional for variety)
  local CYAN='\033[0;36m'    # Cyan
  local NC='\033[0m'         # No Color

  echo ""

  # Output information
  echo -e "${GREEN}=== Process completed successfully ===${NC}\n"

  # Virtual machine creation
  echo -e " ${GREEN}✓ ${NC}The virtual machine has been successfully created.\n"

  # Docker-compose installation
  echo -e " ${GREEN}✓ ${NC}The package ${CYAN}docker-compose${NC} should be installed on the virtual machine.\n"

  # Snippet creation
  echo -e " ${GREEN}✓ ${NC}A snippet named ${CYAN}${FILE_NAME}${NC} has been created:"
  echo -e "      • Location: ${CYAN}${SNIP_PATH}${NC}"
  echo -e "      • Alternatively, you can view it in the web interface under the ${CYAN}Snippets${NC} storage.\n"

  # Network configuration
  if [[ -n "$VM_IP" ]]; then
    local NETWORK="IP:${VM_IP}  GW:${VM_GATEWAY}"
  else
    local NETWORK="DHCP"
  fi
  echo -e " ${GREEN}✓ ${NC}Network configuration: ${CYAN}${NETWORK}${NC}.\n"

  # SSH keys
  echo -e " ${GREEN}✓ ${NC}Keys for connecting to the virtual machine have been generated:"
  echo -e "      • The keys ${CYAN}key${NC} and ${CYAN}key.pub${NC} are located in the folder ${CYAN}${KEYS_PATH}${NC}."
  echo -e "      • The public key has been copied to the virtual machine.\n"

  # User access
  echo -e " ${GREEN}✓ ${NC}The user for accessing the virtual machine is: ${CYAN}${CI_USER}${NC}.\n"

  # Final message
  echo -e "${GREEN}=== Done! ===${NC}"
}


##############
# --- MAIN ---
##############

cat <<EOF

██╗  ██╗██╗   ██╗██████╗ ███████╗███████╗███╗   ██╗██╗██╗  ██╗     ██╗████████╗
██║ ██╔╝██║   ██║██╔══██╗██╔════╝██╔════╝████╗  ██║██║██║ ██╔╝     ██║╚══██╔══╝
█████╔╝ ██║   ██║██║  ██║█████╗  ███████╗██╔██╗ ██║██║█████╔╝█████╗██║   ██║   
██╔═██╗ ██║   ██║██║  ██║██╔══╝  ╚════██║██║╚██╗██║██║██╔═██╗╚════╝██║   ██║   
██║  ██╗╚██████╔╝██████╔╝███████╗███████║██║ ╚████║██║██║  ██╗     ██║   ██║   
╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═╝     ╚═╝   ╚═╝   
..............................................
   Proxmox VM Deployment Script (KIT-PVMDS)
''''''''''''''''''''''''''''''''''''''''''''''
This script creates a virtual machine in Proxmox...



EOF


# reading arguments

# Checking if at least one argument is present
if [[ "$#" -lt 1 ]]; then
    echo -e "ERROR: Virtual machine ID required.\n"
    help
fi

ID_NUM="$1"               # Parse 1 argument - VM number for creating ID
shift
if ! [[ "$ID_NUM" =~ ^[0-9]+$ ]]; then
  if [[ "$ID_NUM" != "--help" && "$ID_NUM" != "-h" ]]; then
    echo -e "ERROR: Incorrect number for creating VM ID. The value num must contain only numbers\n"
  fi
  help
fi

FULL_PATH="${ISO_PATH}${FILE_RAW}"

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -u|--username)
            if [[ -z "$2" || "$2" =~ ^- ]]; then
                echo "Error: No value for argument '$1'"
                help
            fi
            CI_USER="$2"
            shift 2
            ;;
        -p|--password)
            if [[ -z "$2" || "$2" =~ ^- ]]; then
                echo "Error: No value for argument '$1'"
                help
            fi
            CI_PASS="$2"
            shift 2
            ;;
        -a|--auth)
            if [[ -z "$2" || "$2" =~ ^- ]]; then
                echo "Error: No value for argument '$1'"
                help
            fi
            if [[ "$2" == "yes" ]]; then
                SET_USER_PASS=true
            elif [[ "$2" == "no" ]]; then
                SET_USER_PASS=false
            else
                echo "Error: Invalid value for argument '$1'. Valid values: yes/no."
                help
            fi
            shift 2
            ;;
        -i|--ip)
            if [[ -z "$2" || "$2" =~ ^- ]]; then
                echo "Error: No value for argument '$1'"
                help
            fi
            if [[ "$2" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
                # Separate IP address and mask
                IFS='/' read -r ip mask <<< "$2"
                
                # Check IP address
                IFS='.' read -r -a ip_parts <<< "$ip"
                for part in "${ip_parts[@]}"; do
                    if (( part < 0 || part > 255 )); then
                        echo "Error: Invalid IP address format ('$ip')."
                        help
                    fi
                done

                # Check mask
                if (( mask < 0 || mask > 32 )); then
                    echo "Error: Invalid mask value ('$mask'). Valid range: 0-32."
                    help
                fi

                VM_IP="$2"
            else
                echo "Error: Invalid IP address format with mask ('$2'). Expected CIDR format (e.g. 10.0.0.1/24)."
                help
            fi
            shift 2
            ;;
        -g|--gateway)
            if [[ -z "$2" || "$2" =~ ^- ]]; then
                echo "Error: No value for argument '$1'"
                help
            fi
            if [[ "$2" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                # check IP <= 255
                IFS='.' read -r -a ip_parts <<< "$2"
                for part in "${ip_parts[@]}"; do
                    if (( part < 0 || part > 255 )); then
                        echo "Error: Invalid IP address format ('$2')."
                        help
                    fi
                done
                VM_GATEWAY="$2"
            else
                echo "Error: Invalid IP address format ('$2')."
                help
            fi
            shift 2
            ;;
        -f|--file)
            if [[ -z "$2" || "$2" =~ ^- ]]; then
                echo "Error: No value for argument '$1'"
                help
            fi
            if [[ "$2" == */* ]]; then
                ISO_PATH=$(dirname "$2")
                FILE_RAW=$(basename "$2")
            else
                FILE_RAW="$2"
            fi
            FULL_PATH="${ISO_PATH}${FILE_RAW}"
            shift 2
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

VM_ID=$((10#${VM_ID}${ID_NUM}))
VM_NAME="Debian-Srv${ID_NUM}"
URL_RAW="${URL_RAW}${FILE_RAW}"
KEY_NAME="${KEY_NAME}${VM_ID}"
KEYS="${KEYS_PATH}${KEY_NAME}"
FILE_NAME="userdata-${VM_ID}.yaml"


log "Virtual machine ID $VM_ID creation starting"

# Check if the VM creation
if qm status "$VM_ID" &>/dev/null; then
  log "Virtual machine with ID $VM_ID already exists."
  exit 1
fi

if ! [[ -f "${FULL_PATH}" ]] && $SET_FILE_RAW_IMG; then
  log "The extension .img is added to the file name file.raw, the resulting file will be file.raw.img"
  FULL_PATH="${FULL_PATH}.img"
fi


# --- STEP 1: Creating keys ---
log "STEP 1: Creating keys"

# Create the directory for keys if it doesn't exist
mkdir -p "$KEYS_PATH"

# Check if the keys already exist
if [[ -f "${KEYS}" && -f "${KEYS}.pub" ]]; then
  log "Keys for VM ID $VM_ID already exist at '$KEYS' and '${KEYS}.pub'. Skipping generation."
else
  # Generate new SSH keys
  log "Generating new SSH keys for VM ID $VM_ID..."
  if $SET_KEY_PASS ; then
    KEY_PASS=""
  else
    KEY_PASS='-N ""'
  fi 
  log "KEY_PASS: ${KEY_PASS}"
  ssh-keygen -t ed25519 -f "$KEYS" -C "${KEY_NAME}" ${KEY_PASS}

  # Verify that the keys were created successfully
  if [[ -f "${KEYS}" && -f "${KEYS}.pub" ]]; then
    log "SSH keys successfully generated:"
    log "Private key: ${KEYS}"
    log "Public key: ${KEYS}.pub"
  else
    log "Error: Failed to generate SSH keys."
    exit 1
  fi
fi


# --- STEP 2: Creating cloud config ---
log "STEP 2: Creating cloud config"

if [[ ! -n "$CI_USER" ]]; then
  log "Error: There is no username in the initial configuration or in the arguments."
  exit 1
fi

CHPASSWD=""
if $SET_USER_PASS ; then  
  # Check if CI_PASS is empty and generate a hashed password if necessary
  if [[ -z "$CI_PASS" ]]; then
    log "CI_PASS is not provided. Generating a new hashed password using openssl..."
    CI_PASS=$(openssl passwd -6)
    
    # Check if the command was successful
    if [[ $? -ne 0 || -z "$CI_PASS" ]]; then
      log "Error: Failed to generate hashed password using openssl."
      exit 1
    fi

    CHPASSWD="
chpasswd:
  expire: false
  users:    
    - name: ${CI_USER}
      password: ${CI_PASS}
      type: hash
"
  fi
fi

# Create the directory if it doesn't exist
mkdir -p "$SNIP_PATH"

# Creating a yaml file with initial configuration
cat <<EOF > "${SNIP_PATH}${FILE_NAME}"
#cloud-config
#############


## Main settings
#
hostname: Debian-Srv${ID_NUM}
manage_etc_hosts: true

#locale: en_US
#timezone: Asia/Yekaterinburg
#keyboard:
#  layout: us
#
##


## Access settings
#
users:
  - name: ${CI_USER}
    lock_passwd: false
    shell: /bin/bash
    groups: sudo
    ssh_authorized_keys:
      - $(cat "${KEYS}.pub")

${CHPASSWD}
disable_root: true       # /etc/ssh/sshd_config -> PermitRootLogin no
ssh_pwauth: false        # /etc/ssh/sshd_config -> PasswordAuthentication no
#
##


## Services install and starting
#
runcmd:
  - ['apt', 'update']
  - ['apt', 'upgrade', '-y']
  - ['apt', 'install', '-y', 'apt-transport-https', 'ca-certificates', 'curl', 'gnupg']
  - ['mkdir', '-p', '/usr/share/keyrings']
  - curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  - echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian \$(grep -oP '(?<=VERSION_CODENAME=)[^ ]+' /etc/os-release) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  - ['apt', 'update']
  - ['apt-cache', 'policy', 'docker-ce']
  - ['apt', 'install', '-y', 'docker-ce', 'docker-ce-cli', 'containerd.io', 'docker-compose-plugin']
  - ['systemctl', 'enable', 'docker']
  - ['systemctl', 'start', 'docker']
#
##


final_message: "Completing system run up."
EOF

# Check if the file was created successfully
if [[ -f "${SNIP_PATH}${FILE_NAME}" ]]; then
  log "File '${SNIP_PATH}${FILE_NAME}' has been successfully created."
else
  log "Error: File '${SNIP_PATH}${FILE_NAME}' was not created."
  exit 1
fi

chmod 644 "${SNIP_PATH}${FILE_NAME}"


# --- STEP 3: Creating virtual machine ---
log "STEP 3: Creating virtual machine with ID $VM_ID..."

log "Creating configuration"

IPCONFIG="ip=dhcp"
if [[ -n "$VM_IP" ]]; then
  if $SET_IP_FROM_ID ; then 
    VM_IP=$(update_ip "$VM_IP" "$ID_NUM")
  fi
  IPCONFIG="ip=${VM_IP},gw=${VM_GATEWAY}"
fi

if ! qm create "$VM_ID" \
  --name "${VM_NAME}" \
  --memory 8196 \
  --machine q35 \
  --cores 4 \
  --sockets 1 \
  --ostype l26 \
  --net0 virtio,bridge=${VM_BRIDGE},queues=4 \
  --ipconfig0 "${IPCONFIG}" \
  --nameserver 8.8.8.8 \
  --searchdomain srv \
  --cpu host \
  --numa 0 \
  --boot order=sata0 \
  --balloon 0 \
  --cicustom "user=${STORAGE_SNIP}:snippets/${FILE_NAME}" \
  ; then
  log "Error: Failed to create virtual machine with ID $VM_ID."
  exit 1
fi
#  --agent enabled=1
  
# Check if the VM creation
if qm status "$VM_ID" &>/dev/null; then
  log "Virtual machine with ID $VM_ID has been created."
else
  log "Error: Failed to create virtual machine with ID $VM_ID."
  exit 1
fi
  
log "Creating cloud-init from VM ID $VM_ID..."
qm set "$VM_ID" --scsi3 "${STORAGE_DISK}:cloudinit"

# Check if the Cloud-Init disk was created successfully
if qm config "$VM_ID" | grep -q "scsi3.*vm-${VM_ID}-cloudinit"; then
  log "Cloud-Init disk 'vm-${VM_ID}-cloudinit' successfully created and attached to VM ID $VM_ID."
else
  log "Error: Failed to create or attach Cloud-Init disk 'vm-${VM_ID}-cloudinit' to VM ID $VM_ID."
  exit 1
fi

log "Creating system disk SCSI"
# Check if the file exists
if [[ -f "$FULL_PATH" ]]; then
  log "File '$FULL_PATH' already exists. Skipping download."
else
  log "File '$FULL_PATH' not found."
  mkdir -p "$ISO_PATH"
  
  log "Downloading RAW image '$FILE_RAW'"
  if ! download_data "$URL_RAW" "$FULL_PATH" "file"; then
    log "Critical error: Failed to download RAW image. Exiting."
    exit 1
  fi
  
  log "Downloading SHA512SUMS"
  if ! download_data "$URL_RAW_SHA" "" "variable"; then
    log "Critical error: Failed to download SHA512SUMS content. Exiting."
    exit 1
  fi
  
  log "Extracting hash for '$FILE_RAW'..."
  TARGET_LINE=$(echo "$DOWNLOADED_CONTENT" | grep "$FILE_RAW")
  if [[ -z "$TARGET_LINE" ]]; then
    log "Error: Target file '$FILE_RAW' not found in SHA512SUMS."
    exit 1
  fi
  
  FILE_RAW_HASH=$(echo "$TARGET_LINE" | awk '{print $1}')
  log "Downloaded hash: $FILE_RAW_HASH"
  
  if verify_hash "$FULL_PATH" "$FILE_RAW_HASH"; then
    log "File integrity check passed."
  else
    log "File integrity check failed. Exiting."
    exit 1
  fi
fi

# Check if the disk exists
DISK_NAME="vm-${VM_ID}-disk-0"
if qm config "$VM_ID" | grep -q "${STORAGE_DISK}:${DISK_NAME}"; then
  log "Error: Disk '${STORAGE_DISK}:${DISK_NAME}' already exists."
  exit 1
else
  # Import the disk into Proxmox
  log "Importing disk '$FILE_RAW' into storage '$STORAGE_DISK'..."
  qm importdisk "$VM_ID" "$FULL_PATH" "$STORAGE_DISK"
  
  # Check if the disk was imported successfully
  if ! qm config "$VM_ID" | grep -q "${STORAGE_DISK}:${DISK_NAME}"; then
    log "Error: Raw disk failed to import '${STORAGE_DISK}:${DISK_NAME}'."
    exit 1
  fi

  log "Configuring SCSI disk for VM ID $VM_ID..."
  qm set "$VM_ID" --scsihw virtio-scsi-pci --scsi0 "${STORAGE_DISK}:${DISK_NAME},backup=0,discard=on,iothread=1,ssd=1"
fi

# Verify that the SCSI disk was added
if qm config "$VM_ID" | grep -q "scsi0.*${STORAGE_DISK}:${DISK_NAME}"; then
  log "SCSI disk '${STORAGE_DISK}:${DISK_NAME}' successfully added to VM ID $VM_ID."
else
  log "Error: Failed to add SCSI disk '${STORAGE_DISK}:${DISK_NAME}' to VM ID $VM_ID."
  exit 1
fi

# Set boot order to boot from scsi0
log "Setting boot order to boot from scsi0..."
#qm set "$VM_ID" --boot c --bootdisk scsi0
qm set "$VM_ID" --boot order=scsi0

# Verify boot order
if qm config "$VM_ID" | grep -q "boot.*order=scsi0"; then
  log "Boot order successfully set to boot from scsi0."
else
  log "Error: Failed to set boot order to boot from scsi0."
  exit 1
fi

if $DEL_FILE_RAW ; then
  rm -f "$FULL_PATH"
  log "File '$FULL_PATH' has been removed."
fi

log "Virtual machine creation ending"

if $RUN_VM ; then
  if qm start "$VM_ID"; then
    log "Виртуальная машина $VM_ID ($VM_NAME) успешно запущена."
  else
    log "Ошибка при запуске виртуальной машины $VM_ID ($VM_NAME)."
  fi
fi

view_report

#---
# Автор: Kudesnik-IT <kudesnik.it@gmail.com>
# GitHub: https://github.com/Kudesnik-IT
#---
