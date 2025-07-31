#!/usr/bin/env bash
#
# resize_disk.sh - Redimensionar um disco LVM existente
#
# Autor:        José Enilson Mota Silva
# Manutenção:   José Enilson Mota Silva
#
# ------------------------------------------------------------------------ #
# Este programa irá redimensionar um disco LVM existente.
# Ele espera que o disco já tenha sido estendido no nível do hypervisor
# e que a partição LVM seja a última ou única partição no disco.
#
# Exemplo de execução (executar como root):
#       # sudo ./resize_disk_sem_interacao_com_usuario.sh
#
# -----------------PACKAGE REQUIRED ----------------------------------------#
# - cloud-utils-growpart (ou outro pacote que forneça 'growpart')
# ------------------------------------------------------------------------ #

# Configuração de ambiente para garantir consistência
export LANG=C
export LC_ALL=C

# --- Diretório para os arquivos de log ---
mkdir -p /var/log/resize_disk/

# --- Variáveis Globais ---
LOG_FILE="/var/log/resize_disk/disk_resize_$(date +%Y%m%d_%H%M).log" # Log individual por execução
LVM_LOG_FILE="/var/log/resize_disk/lvm_$(date +%Ym%d_%H%M).log" # Log específico para operações LVM

# --- Funções Auxiliares ---

# Função para exibir mensagem de sucesso (saída apenas para o log)
sucesso() {
    echo -e "\n***** CONFIGURAÇÃO EXECUTADA COM SUCESSO *****\n" >> "$LOG_FILE"
}

# Função para exibir mensagens de erro e sair (saída apenas para o log)
erro() {
    local message="${1:-"Erro desconhecido"}"
    # Redireciona a mensagem de erro para o log
    echo -e "\nERRO: $message" >> "$LOG_FILE"
    echo -e "CONSULTE OS ARQUIVOS DE LOGS: $LVM_LOG_FILE e/ou $LOG_FILE\n" >> "$LOG_FILE"
    exit 1
}

# Função para registrar informações detalhadas nos logs (saída apenas para o log)
registrar_logs() {
    local log_output="$1"
    echo -e "\n--- [ $(date) ] ---" >> "$log_output"
    echo -e "\n--- LSBLK ---\n" >> "$log_output"
    lsblk >> "$log_output"
    echo -e "\n--- DF -HT ---\n" >> "$log_output"
    df -hT >> "$log_output"
    echo -e "\n-------------------------------------------------\n" >> "$log_output"
}

# Função para verificar a existência de pacotes
check_package() {
    local package_name="$1"
    if ! command -v "$package_name" &>/dev/null; then
        erro "O pacote '$package_name' não está instalado. Por favor, instale-o para continuar."
    fi
}

# Função para realizar o rescan dos discos SCSI (saída apenas para o log)
rescan_disks() {
    echo "Realizando rescan dos discos SCSI..." >> "$LOG_FILE"
    local scsidev_list
    scsidev_list=$(ls /sys/class/scsi_device/ 2>/dev/null)

    if [[ -z "$scsidev_list" ]]; then
        echo "Aviso: Nenhum dispositivo SCSI encontrado para rescan." >> "$LOG_FILE"
        return 0
    fi

    for dev in $scsidev_list; do
        echo "   Rescan em /sys/class/scsi_device/$dev/device/rescan..." >> "$LOG_FILE"
        echo "1" > "/sys/class/scsi_device/$dev/device/rescan" 2>/dev/null || \
        echo "Aviso: Falha ao rescanear $dev. Pode ser necessário um reboot ou rescan manual." >> "$LOG_FILE"
    done
    echo "Rescan de discos concluído." >> "$LOG_FILE"
}

# Função principal de redimensionamento LVM
perform_resize() {
    local partition_name_input="$1"
    local partition_path="/dev/${partition_name_input}"
    local parent_disk_name
    local partition_number
    local vg_name
    local lv_name
    local lv_mapper_path

    parent_disk_name=$(echo "$partition_name_input" | grep -io "sd[a-z]\+" | head -n1)
    partition_number=$(echo "$partition_name_input" | grep -o "[0-9]\+$" | head -n1)

    if [[ -z "$parent_disk_name" || -z "$partition_number" ]]; then
        erro "Não foi possível extrair o nome do disco pai ou número da partição de '$partition_name_input'. Formato esperado: sdXN (ex: sda1)."
    fi

    echo "Redimensionando partição: ${partition_name_input} com growpart..." >> "$LOG_FILE"
    growpart "/dev/$parent_disk_name" "$partition_number" >> "$LVM_LOG_FILE" 2>&1
    if [[ $? -ne 0 ]]; then
        erro "Falha ao redimensionar a partição ${partition_name_input} com growpart. Verifique se o disco foi estendido no hypervisor e se a partição é a última."
    fi

    sleep 2
    echo -e "Partição redimensionada com sucesso.\n" >> "$LOG_FILE"

    echo "Redimensionando Volume Físico (PV) LVM: $partition_path..." >> "$LOG_FILE"
    pvresize "$partition_path" >> "$LVM_LOG_FILE" 2>&1 || erro "Falha ao redimensionar o Volume Físico (PV) $partition_path."

    sleep 2
    echo -e "Volume Físico (PV) redimensionado com sucesso.\n" >> "$LOG_FILE"

    vg_name=$(pvs -o vg_name --noheadings "$partition_path" 2>/dev/null | tr -d ' ')
    if [[ -z "$vg_name" ]]; then
        erro "Não foi possível encontrar o Grupo de Volumes (VG) associado a '$partition_path'."
    fi

    lv_name=$(lvs -o lv_name --noheadings "$vg_name" 2>/dev/null | tr -d ' ')
    if [[ -z "$lv_name" ]]; then
        erro "Nenhum Volume Lógico (LV) encontrado para o Grupo de Volumes '$vg_name'."
    fi

    lv_mapper_path="/dev/mapper/${vg_name}-${lv_name}"

    echo "Estendendo Volume Lógico (LV) '$lv_mapper_path' para usar 100% do espaço livre..." >> "$LOG_FILE"
    lvextend -l +100%free "$lv_mapper_path" >> "$LVM_LOG_FILE" 2>&1
    if [[ $? -ne 0 && $? -ne 5 ]]; then
        erro "Falha ao estender o Volume Lógico (LV) '$lv_mapper_path'."
    fi

    sleep 2
    echo -e "Volume Lógico (LV) estendido com sucesso.\n" >> "$LOG_FILE"

    echo "Redimensionando sistema de arquivos em '$lv_mapper_path'..." >> "$LOG_FILE"
    resize2fs "$lv_mapper_path" >> "$LVM_LOG_FILE" 2>&1 || erro "Falha ao redimensionar o sistema de arquivos em '$lv_mapper_path'."

    sucesso
    registrar_logs "$LOG_FILE"
}

# --- Função para encontrar a primeira partição com tamanho diferente do disco ---
function find_inconsistent_partition() {
    local partition_name_output=""
    local current_disk_name=""
    local current_disk_size=""

    lsblk -n -o KNAME,TYPE,SIZE,MOUNTPOINT | grep -v "sda" | while read kname type size mountpoint; do

        if [[ "$type" == "disk" ]]; then
            current_disk_name="$kname"
            current_disk_size="$size"
        elif [[ "$type" == "part" ]]; then
            local partition_number=$(echo "$kname" | grep -o "[0-9]\+$")

            if [[ "$kname" =~ ^"$current_disk_name"[0-9]+$ ]]; then
                
                if [[ "$partition_number" -le 4 && ( "$mountpoint" == "/boot" || "$mountpoint" == "/" || "$mountpoint" == "[SWAP]" ) ]]; then
                    continue
                fi

                if [[ "$current_disk_size" != "$size" ]]; then
                    partition_name_output="$kname"
                    echo "$partition_name_output"
                    break
                fi
            fi
        fi
    done
}


# ------------------------------- EXECUCAO ------------------------------- #

if [[ "$EUID" -ne 0 ]]; then
    erro "Este script precisa ser executado como root. Use 'sudo ./resize_disk.sh'."
fi

check_package "growpart"

echo -e "\nOpção selecionada: Redimensionar um disco LVM\n" >> "$LOG_FILE"

echo -e "\nRealizando rescan dos discos. Por favor, aguarde...\n" >> "$LOG_FILE"
rescan_disks &
wait

echo -e "\nATENÇÃO!!! -> CERTIFIQUE-SE DE QUE O DISCO FOI ESTENDIDO NO VMWARE!\n" >> "$LOG_FILE"
echo -e "\nLista de discos e partições disponíveis:\n" >> "$LOG_FILE"
lsblk >> "$LOG_FILE"
echo " " >> "$LOG_FILE"

PARTITION_NAME_INPUT="$(find_inconsistent_partition)"

if [[ -z "$PARTITION_NAME_INPUT" ]]; then
    erro "Nenhum disco elegível tem espaço livre para ser configurado. Encerrando."
fi

FULL_PARTITION_PATH="/dev/${PARTITION_NAME_INPUT}"

if ! lsblk -n "$FULL_PARTITION_PATH" &>/dev/null; then
    erro "O dispositivo '$FULL_PARTITION_PATH' (correspondente a '$PARTITION_NAME_INPUT') não existe. Verifique 'lsblk'."
fi

if ! pvs -o pv_name --noheadings "$FULL_PARTITION_PATH" &>/dev/null; then
    erro "A partição '$PARTITION_NAME_INPUT' não parece ser um Volume Físico (PV) LVM válido. Por favor, selecione uma partição LVM."
fi

perform_resize "$PARTITION_NAME_INPUT"