#!/usr/bin/env bash
#
# resize_disk.sh - Redimensionar um disco LVM existente
#
# Autor:        José Enilson Mota Silva
# Manutenção:   José Enilson Mota Silva
#
# IMPORTANTE: IMPRIMI INFORMAÇÃO NA TELA
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

# --- Cores para saída no terminal ---
GREEN='\033[1;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Diretório para os arquivos de log ---
mkdir -p /var/log/resize_disk/

# --- Variáveis Globais ---
LOG_FILE="/var/log/resize_disk/disk_resize_$(date +%Y%m%d_%H%M).log" # Log individual por execução
LVM_LOG_FILE="/var/log/resize_disk/lvm_$(date +%Y%m%d_%H%M).log" # Log específico para operações LVM

# --- Funções Auxiliares ---

# Função para exibir mensagem de sucesso
sucesso() {
    echo -e "\n${GREEN}***** CONFIGURAÇÃO EXECUTADA COM SUCESSO *****${NC}\n" | tee -a "$LOG_FILE"
}

# Função para exibir mensagens de erro e sair
erro() {
    local message="${1:-"Erro desconhecido"}"
    echo -e "\n${RED}ERRO: $message${NC}" | tee -a "$LOG_FILE"
    echo -e "\n${RED}CONSULTE OS ARQUIVOS DE LOGS: $LVM_LOG_FILE e/ou $LOG_FILE${NC}\n" | tee -a "$LOG_FILE"
    exit 1
}

# Função para registrar informações detalhadas nos logs E na tela
registrar_logs() {
    local log_output="$1"
    echo -e "\n--- [ $(date) ] ---" >> "$log_output"
    echo -e "\n--- LSBLK ---\n" >> "$log_output"
    lsblk >> "$log_output"
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
    echo "Realizando rescan dos discos SCSI..." | tee -a "$LOG_FILE" # Mensagem principal para o terminal e log
    local scsidev_list
    scsidev_list=$(ls /sys/class/scsi_device/ 2>/dev/null)

    if [[ -z "$scsidev_list" ]]; then
        echo "${YELLOW}Aviso: Nenhum dispositivo SCSI encontrado para rescan.${NC}" | tee -a "$LOG_FILE"
        return 0
    fi

    for dev in $scsidev_list; do
        # Mensagem de rescan individual apenas para o log
        echo "  Rescan em /sys/class/scsi_device/$dev/device/rescan..." >> "$LOG_FILE"
        echo "1" > "/sys/class/scsi_device/$dev/device/rescan" 2>/dev/null || \
        echo "${YELLOW}Aviso: Falha ao rescanear $dev. Pode ser necessário um reboot ou rescan manual.${NC}" | tee -a "$LOG_FILE"
    done
    echo "Rescan de discos concluído." | tee -a "$LOG_FILE"
}

# Função principal de redimensionamento LVM
perform_resize() {
    local partition_name_input="$1" # Ex: sdc1 (agora recebemos sem /dev/)
    local partition_path="/dev/${partition_name_input}" # Construímos o caminho completo aqui
    local parent_disk_name # Ex: sdc
    local partition_number # Ex: 1
    local vg_name
    local lv_name
    local lv_mapper_path # Ex: /dev/mapper/vg_teste-lv_teste

    # Extrai o nome do disco pai e o número da partição
    # A regex agora precisa capturar o nome do disco e o número da partição da string "sdXN"
    parent_disk_name=$(echo "$partition_name_input" | grep -io "sd[a-z]\+" | head -n1)
    partition_number=$(echo "$partition_name_input" | grep -o "[0-9]\+$" | head -n1)

    if [[ -z "$parent_disk_name" || -z "$partition_number" ]]; then
        erro "Não foi possível extrair o nome do disco pai ou número da partição de '$partition_name_input'. Formato esperado: sdXN (ex: sda1)."
    fi

    echo "Redimensionando partição: ${partition_name_input} com growpart..." | tee -a "$LOG_FILE"
    growpart "/dev/$parent_disk_name" "$partition_number" >> "$LVM_LOG_FILE" 2>&1
    if [[ $? -ne 0 ]]; then
        erro "Falha ao redimensionar a partição ${partition_name_input} com growpart. Verifique se o disco foi estendido no hypervisor e se a partição é a última."
    fi

    sleep 2
    echo -e "${GREEN}Partição redimensionada com sucesso.${NC}\n" | tee -a "$LOG_FILE"

    echo "Redimensionando Volume Físico (PV) LVM: $partition_path..." | tee -a "$LOG_FILE"
    pvresize "$partition_path" >> "$LVM_LOG_FILE" 2>&1 || erro "Falha ao redimensionar o Volume Físico (PV) $partition_path."

    sleep 2
    echo -e "${GREEN}Volume Físico (PV) redimensionado com sucesso.${NC}\n" | tee -a "$LOG_FILE"

    # Obter VG e LV a partir do PV
    vg_name=$(pvs -o vg_name --noheadings "$partition_path" 2>/dev/null | tr -d ' ')
    if [[ -z "$vg_name" ]]; then
        erro "Não foi possível encontrar o Grupo de Volumes (VG) associado a '$partition_path'."
    fi

    lv_name=$(lvs -o lv_name --noheadings "$vg_name" 2>/dev/null | tr -d ' ')
    if [[ -z "$lv_name" ]]; then
        erro "Nenhum Volume Lógico (LV) encontrado para o Grupo de Volumes '$vg_name'."
    fi

    lv_mapper_path="/dev/mapper/${vg_name}-${lv_name}"

    echo "Estendendo Volume Lógico (LV) '$lv_mapper_path' para usar 100% do espaço livre..." | tee -a "$LOG_FILE"
    lvextend -l +100%free "$lv_mapper_path" >> "$LVM_LOG_FILE" 2>&1
    # lvextend retorna 5 se já não há espaço livre, o que não é um erro fatal se o objetivo foi alcançado
    if [[ $? -ne 0 && $? -ne 5 ]]; then # Verifica se é um erro diferente de "nenhum espaço livre"
        erro "Falha ao estender o Volume Lógico (LV) '$lv_mapper_path'."
    fi

    sleep 2
    echo -e "${GREEN}Volume Lógico (LV) estendido com sucesso.${NC}\n" | tee -a "$LOG_FILE"

    echo "Redimensionando sistema de arquivos em '$lv_mapper_path'..." | tee -a "$LOG_FILE"
    resize2fs "$lv_mapper_path" >> "$LVM_LOG_FILE" 2>&1 || erro "Falha ao redimensionar o sistema de arquivos em '$lv_mapper_path'."

    sucesso # Exibe a mensagem de sucesso
    registrar_logs "$LOG_FILE" # Coleta e exibe os logs no final da operação
}

function space_available () {   
echo -e "\n=============================================================================="
echo -e "\n\n${YELLOW}  ESPAÇO LIVRE EM DISCO $1${NC}\n\n"    
FREE_SPACE=$(lsblk -n -o NAME,MOUNTPOINT "${FULL_PARTITION_PATH}" | grep -v "${PARTITION_NAME_INPUT}" | awk '{print $NF}')
df -hT "${FREE_SPACE}"
echo -e "\n==============================================================================\n\n"
}

# --- Função para encontrar a primeira partição com tamanho diferente do disco ---
function find_inconsistent_partition() {
    local partition_name_output=""
    local current_disk_name=""
    local current_disk_size=""
    local disk_has_critical_partition=0

    lsblk -n -o KNAME,TYPE,SIZE,MOUNTPOINT | while read kname type size mountpoint; do

        if [[ "$type" == "disk" ]]; then
            current_disk_name="$kname"
            current_disk_size="$size"
            disk_has_critical_partition=0 # Reinicia a flag para cada novo disco
        elif [[ "$type" == "part" ]]; then

            # 1. Verifica se o disco já tem uma partição crítica
            if [[ "$disk_has_critical_partition" -eq 1 ]]; then
                continue # Pula para a próxima partição, pois o disco já é "proibido"
            fi

            # 2. Se a partição atual for crítica, marca o disco como "proibido"
            if [[ "$mountpoint" == "/boot" || "$mountpoint" == "/" || "$mountpoint" == "[SWAP]" ]]; then
                disk_has_critical_partition=1
                continue
            fi
            
            # 3. Realiza a lógica de busca se nenhuma partição crítica for encontrada
            local partition_number=$(echo "$kname" | grep -o "[0-9]\+$")
            if [[ "$kname" =~ ^"$current_disk_name"[0-9]+$ ]]; then
                
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

# Verifica se o script está sendo executado como root
if [[ "$EUID" -ne 0 ]]; then
    erro "Este script precisa ser executado como root. Use 'sudo ./resize_disk.sh'."
fi

# Verifica pacotes necessários
check_package "growpart"

echo -e "\n${YELLOW}Opção selecionada: Redimensionar um disco LVM${NC}\n" | tee "$LOG_FILE"

# Realiza o rescan de discos em background. A saída detalhada vai para o log.
echo -e "\n${YELLOW}Realizando rescan dos discos. Por favor, aguarde...${NC}\n" | tee -a "$LOG_FILE"
rescan_disks &
wait # Espera o rescan de discos terminar antes de continuar
echo " "

PARTITION_NAME_INPUT="$(find_inconsistent_partition)"

# Validação da entrada da partição
if [[ -z "$PARTITION_NAME_INPUT" ]]; then
    erro "Nenhum disco elegível tem espaço livre para ser configurado. Encerrando."
fi

# Constrói o caminho completo da partição para validação
FULL_PARTITION_PATH="/dev/${PARTITION_NAME_INPUT}"

# --- Nova lógica de validação ---
# Verifica se a partição existe como um dispositivo de bloco E se é um PV LVM
if ! lsblk -n "$FULL_PARTITION_PATH" &>/dev/null; then
    erro "O dispositivo '$FULL_PARTITION_PATH' (correspondente a '$PARTITION_NAME_INPUT') não existe. Verifique 'lsblk'."
fi

# Apenas para LVM: verificar se é um PV válido.
# Se o PV não for válido, não podemos redimensionar.
if ! pvs -o pv_name --noheadings "$FULL_PARTITION_PATH" &>/dev/null; then
    erro "A partição '$PARTITION_NAME_INPUT' não parece ser um Volume Físico (PV) LVM válido. Por favor, selecione uma partição LVM."
fi

# Chama a função principal de redimensionamento
space_available "ANTES"
perform_resize "$PARTITION_NAME_INPUT"
space_available "DEPOIS"