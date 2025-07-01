#!/usr/bin/env bash
#
# remove_disk.sh - Remover um disco que tenha volumes LVM associados
#
# Autor:        José Enilson Mota Silva
# Manutenção:   José Enilson Mota Silva
#
# ------------------------------------------------------------------------ #
# Este programa remove um disco que tenha volumes LVM associados.
#
# Exemplo de execução (executar como root):
#       # sudo ./remove_disk.sh
#
# ------------------------------------------------------------------------ #

# Configuração de ambiente
export LANG=C
export LC_ALL=C

# --- Cores para saída no terminal ---
GREEN='\033[1;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Variáveis Globais ---
PART_NUM=1
LOG_FILE="/var/log/remove_disk/disk_remove_$(date +%Y%m%d_%H%M%S).log" # Log individual por execução
LVM_LOG_FILE="/var/log/remove_disk/lvm_operations.log" # Log específico para operações LVM
mkdir -p /var/log/remove_disk/
# --- Funções ---

# Função para exibir mensagens de erro e sair
erro() {
    local message="${1:-"Erro desconhecido"}"
    echo -e "\n${RED}ERRO: $message${NC}" | tee -a "$LOG_FILE"
    echo -e "${RED}CONSULTE OS ARQUIVOS DE LOGS: $LVM_LOG_FILE e/ou $LOG_FILE${NC}\n" | tee -a "$LOG_FILE"
    exit 1
}

# Função para registrar informações detalhadas nos logs E na tela
registrar_logs() {
    echo -e "\n--- [ $(date) ] ---\n" | tee -a "$1"
    echo -e "--- LSBLK ---\n" | tee -a "$1"
    lsblk | tee -a "$1"
    echo -e "\n--- DF -HT ---\n" | tee -a "$1"
    df -hT | tee -a "$1"
    echo -e "\n--- FSTAB ---\n" | tee -a "$1"
    cat /etc/fstab | tee -a "$1"
    echo -e "\n-------------------------------------------------\n" | tee -a "$1"
}

# Função principal para remover o disco
remover_disco() {
    local disk="$1"
    local vg="$2"
    local lv="$3"
    local mount_point="$4"

    echo -e "\n--- Iniciando remoção para o disco: /dev/$disk ---" | tee -a "$LOG_FILE"

    # Desmontar o ponto de montagem, se existir
    if [[ -n "$mount_point" ]]; then
        echo "Desmontando $mount_point..." | tee -a "$LOG_FILE"
        umount "$mount_point" >> "$LVM_LOG_FILE" 2>&1
        if [[ $? -ne 0 ]]; then
            erro "Não foi possível desmontar $mount_point. Verifique se há processos usando o ponto de montagem."
        fi
    fi

    # Caminho completo do volume lógico no formato /dev/mapper/VG_NAME-LV_NAME
    local lv_mapper_path="/dev/mapper/${vg}-${lv}"

    # Desativar e remover LVs, VGs e PVs
    echo "Desativando e removendo volumes lógicos: $lv_mapper_path..." | tee -a "$LOG_FILE"
    lvchange -an "$lv_mapper_path" >> "$LVM_LOG_FILE" 2>&1 || erro "Falha ao desativar LV $lv_mapper_path."
    lvremove -y "$lv_mapper_path" >> "$LVM_LOG_FILE" 2>&1 || erro "Falha ao remover LV $lv_mapper_path."

    echo "Desativando e removendo grupo de volumes: $vg..." | tee -a "$LOG_FILE"
    vgchange -an "$vg" >> "$LVM_LOG_FILE" 2>&1 || erro "Falha ao desativar VG $vg."
    vgremove -y "$vg" >> "$LVM_LOG_FILE" 2>&1 || erro "Falha ao remover VG $vg."

    echo "Removendo volume físico: /dev/${disk}${PART_NUM}..." | tee -a "$LOG_FILE"
    pvremove -y "/dev/${disk}${PART_NUM}" >> "$LVM_LOG_FILE" 2>&1 || erro "Falha ao remover PV /dev/${disk}${PART_NUM}."

    # Remover o disco do sistema
    echo "Removendo o disco físico /dev/$disk do sistema..." | tee -a "$LOG_FILE"
    echo 1 > "/sys/block/$disk/device/delete" 2>> "$LOG_FILE" || erro "Falha ao remover o disco físico /dev/$disk. Pode ser necessário reiniciar o sistema."

    # Remover entrada do fstab usando o caminho /dev/mapper/VG_NAME-LV_NAME
    echo "Removendo entrada de ${lv_mapper_path} do /etc/fstab..." | tee -a "$LOG_FILE"
    local path_fstab=$(echo "/dev/${vg}/${lv}")
    sed -i.bak "\|^$path_fstab|d" /etc/fstab >> "$LOG_FILE" 2>&1
    if [[ $? -ne 0 ]]; then
        echo "${YELLOW}Aviso: Não foi possível remover a entrada de ${lv_mapper_path} do /etc/fstab automaticamente. Verifique manualmente.${NC}" | tee -a "$LOG_FILE"
    else
        echo "Entrada removida de /etc/fstab. Backup em /etc/fstab.bak." | tee -a "$LOG_FILE"
    fi

    registrar_logs "$LOG_FILE" # Coleta e exibe os logs no final da operação
}

# --- Execução Principal ---

# Verifica se o script está sendo executado como root
if [[ "$EUID" -ne 0 ]]; then
    erro "Este script precisa ser executado como root. Use 'sudo ./remove_disk.sh'."
fi

echo -e "\n${YELLOW}Opção selecionada: Remover um disco que tenha volumes LVM associados${NC}\n" | tee "$LOG_FILE"
echo -e "\n${YELLOW}ATENÇÃO!!! -> AÇÃO IRREVERSÍVEL${NC}"

echo -e "\nDiscos disponíveis no sistema:"
lsblk | tee -a "$LOG_FILE" # Adicionado tee para registrar no log também
echo " "
read -rp "INFORME O DISCO QUE SERÁ REMOVIDO [Exemplo: sda, sdb, etc.]? " DISK_INPUT

# Validação do disco informado
if [[ -z "$DISK_INPUT" ]]; then
    erro "Nenhum disco foi informado. Encerrando."
fi

# --- Condição de segurança para discos essenciais ---
if [[ "$DISK_INPUT" == "sda" || "$DISK_INPUT" == "sdb" || "$DISK_INPUT" == "sdc" ]]; then
    erro "A remoção dos discos '$DISK_INPUT' (sda, sdb, sdc) não é permitida por este script para evitar perda de dados críticos. Se realmente precisa remover um desses discos, faça-o manualmente com extrema cautela."
fi
# --- Fim da condição de segurança ---

# Verifica se o disco existe e é um disco completo (não uma partição)
DISK_PATH="/dev/$DISK_INPUT"
if ! lsblk -n -d "$DISK_PATH" &>/dev/null; then
    erro "O disco '$DISK_INPUT' não existe ou não é um disco completo. Verifique 'lsblk'."
fi

# Obter informações LVM
VG_NAME=$(pvs -o vg_name --noheadings "$DISK_PATH$PART_NUM" 2>/dev/null | tr -d ' ')
if [[ -z "$VG_NAME" ]]; then
    erro "O disco '$DISK_INPUT' (partição ${DISK_PATH}${PART_NUM}) não parece ser parte de um Volume Físico (PV) LVM ou não possui um Grupo de Volumes associado."
fi

LV_NAME=$(lvs -o lv_name --noheadings "$VG_NAME" 2>/dev/null | tr -d ' ')
if [[ -z "$LV_NAME" ]]; then
    erro "Nenhum Volume Lógico (LV) encontrado para o Grupo de Volumes '$VG_NAME'."
fi

# Verificar se o grupo de volumes tem mais de um disco
pvs -o vg_name --noheadings | sort | uniq -d | grep -i $VG_NAME > /dev/null
if [ "$?" -eq 0 ]; then
    echo "\n${YELLOW}O disco não pôde ser removido por meio deste script, visto que pertence a um grupo de volume que possui mais de um disco associado. Remova o disco manualmente para evitar a perda de dados.${NC}"
    exit 0
fi

# Obter ponto de montagem (se houver)
MOUNT_POINT=$(findmnt -n -o TARGET --source "/dev/mapper/$VG_NAME-$LV_NAME" 2>/dev/null)

# Exibe o resumo da operação (sem pedir confirmação)
echo -e "\n${YELLOW}Resumo da Operação:${NC}" | tee -a "$LOG_FILE"
echo "  Disco a ser removido: /dev/$DISK_INPUT" | tee -a "$LOG_FILE"
echo "  Partição LVM: /dev/${DISK_INPUT}${PART_NUM}" | tee -a "$LOG_FILE"
echo "  Grupo de Volumes (VG): $VG_NAME" | tee -a "$LOG_FILE"
echo "  Volume Lógico (LV): $LV_NAME (Caminho /dev/mapper/$VG_NAME-$LV_NAME)" | tee -a "$LOG_FILE"

echo -e "\nApós conferir os dados acima, se estiverem corretos, pressione a tecla ENTER para dar continuidade ou CTRL + C para encerrar.\n"

if [[ -n "$MOUNT_POINT" ]]; then
    echo "  Ponto de Montagem (se houver): $MOUNT_POINT" | tee -a "$LOG_FILE"
else
    echo "  Ponto de Montagem: Nenhum encontrado (ou não montado no momento)." | tee -a "$LOG_FILE"
fi
echo -e "\n${YELLOW}PROSSEGUINDO COM A REMOÇÃO AUTOMÁTICA...${NC}" | tee -a "$LOG_FILE"

# Chama a função de remoção
remover_disco "$DISK_INPUT" "$VG_NAME" "$LV_NAME" "$MOUNT_POINT"
