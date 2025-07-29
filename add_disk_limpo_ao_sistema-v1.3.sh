#!/usr/bin/env bash
# add_disk_limpo_ao_sistema.sh - Adicionar um disco ao sistema
#
# Autor:        José Enilson Mota Silva
# Manutenção:   José Enilson Mota Silva
#
# ------------------------------------------------------------------------ #
# Este programa adiciona um novo disco ao sistema, criando um PV, VG, LV,
# formatando com EXT4, criando um ponto de montagem e configurando o fstab.
# Prioriza discos sem partições e, em seguida, discos particionados sem LVM.
#
# Requisitos:
#   - util-linux (para fdisk, lsblk, partprobe)
#   - lvm2 (para pvcreate, vgcreate, lvcreate, pvs, vgs, lvs)
#   - e2fsprogs (para mkfs.ext4)
#
# Exemplo de execução:
#   #   ./add_disk_limpo_ao_sistema.sh AUDITORIA
#
#   IMPORTANTE: Informar um argumento ( noem do volume) na execução do script
#              No exemplo acima, AUDITORIA está sendo passado como argumento. 
#              Os volumes serão criados com esse nome. 
# ------------------------------------------------------------------------ #

# --- Configurações Iniciais e Variáveis Globais ---
export LANG=C        # Garante a saída em inglês para parsing consistente de comandos

# Cores para mensagens - Serão usadas apenas para mensagens que vão para a tela
readonly C_GREEN='\033[1;32m'
readonly C_RED='\033[0;31m'
readonly C_YELLOW='\033[1;33m'
readonly C_BLUE='\033[1;34m'
readonly C_RESET='\033[0m'

# Diretório para os arquivos de logs
mkdir -p /var/log/add_disk

# Variáveis do script
readonly LOG_DIR="/var/log/add_disk"
readonly LVM_LOG_FILE="${LOG_DIR}/lvm$(date +%Y%m%d_%H%M).log"

# Adiciona segundos para logs únicos, garantindo que cada execução crie um novo arquivo
readonly DISK_LOG_FILE="${LOG_DIR}/disk_$(date +%Y%m%d_%H%M).log"
readonly PARTITION_NUMBER=1 # Usar 1 para a primeira partição primária

# Recebe um (1) argumento pela linha de comando
USER_INPUT="$1"

# --- Funções de Validação e Mensagens ---

function error_exit() {
    local message="$1"
    # Erros sempre vão para a tela e para os logs
    echo -e "${C_RED}\nERRO: $message${C_RESET}" | tee -a "$DISK_LOG_FILE" "$LVM_LOG_FILE" >&2
    echo -e "${C_RED}Consulte os arquivos de logs: ${LVM_LOG_FILE} e/ou ${DISK_LOG_FILE}${C_RESET}\n" | tee -a "$DISK_LOG_FILE" "$LVM_LOG_FILE" >&2
    exit 1
}

function success_message() {
    local TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S") # Timestamp para o log

    # Adiciona um cabeçalho para a seção de sucesso no log (sem cores para o arquivo)
    echo -e "\n==========================================================================" >> "$DISK_LOG_FILE"
    echo -e "=== RESUMO PÓS-SUCESSO - ${TIMESTAMP} ===" >> "$DISK_LOG_FILE"
    echo -e "==========================================================================\n" >> "$DISK_LOG_FILE"

    # Saída do df -hT
    echo -e "${C_YELLOW}--- DF -hT (Uso de Espaço em Disco) ---${C_RESET}\n" | tee -a "$DISK_LOG_FILE"
    df -hT | tee -a "$DISK_LOG_FILE"
    echo -e "\n--------------------------------------------------------------------------\n" | tee -a "$DISK_LOG_FILE" # Delimitador para tela e log

    # Saída do cat /etc/fstab
    echo -e "${C_YELLOW}--- FSTAB (Entradas de Montagem Persistente) ---${C_RESET}\n" | tee -a "$DISK_LOG_FILE"
    # Adiciona marcadores no log para novas entradas, útil para verificar se tudo foi gravado
    (
        echo "## INÍCIO DAS ENTRADAS ATUAIS DE FSTAB ##"
        cat /etc/fstab
        echo "## FIM DAS ENTRADAS ATUAIS DE FSTAB ##"
    ) | tee -a "$DISK_LOG_FILE" # Redireciona tudo para tela e log
    echo -e "\n--------------------------------------------------------------------------\n" | tee -a "$DISK_LOG_FILE"

    # Saída do lsblk
    echo -e "${C_YELLOW}--- LSBLK (Estrutura de Blocos) ---${C_RESET}\n" | tee -a "$DISK_LOG_FILE"
    lsblk | tee -a "$DISK_LOG_FILE"
    echo -e "\n--------------------------------------------------------------------------\n" | tee -a "$DISK_LOG_FILE"

    # Final do resumo no log
    echo -e "\n==========================================================================" >> "$DISK_LOG_FILE"
    echo -e "=== FIM DO RESUMO PÓS-SUCESSO - ${TIMESTAMP} ===" >> "$DISK_LOG_FILE"
    echo -e "==========================================================================\n" >> "$DISK_LOG_FILE"
}

function record_logs() {
    mkdir -p "$LOG_DIR" # Garante que o diretório de log exista

    local TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S") # Formato YYYY-MM-DD HH:MM:SS

    echo -e "\n==========================================================================" >> "$DISK_LOG_FILE"
    echo -e "=== INÍCIO DA COLETA DE LOGS ANTES DAS ALTERAÇÕES PARA TROUBLESHOOTING - ${TIMESTAMP} ===" >> "$DISK_LOG_FILE"
    echo -e "==========================================================================\n" >> "$DISK_LOG_FILE"

    # lsblk: Agora sem cores para o log, mostrando todos os dispositivos de bloco
    echo -e "\n--- LSBLK (Estrutura de Blocos) ---\n" >> "$DISK_LOG_FILE"
    lsblk -a >> "$DISK_LOG_FILE" 2>&1
    echo -e "\n--------------------------------------------------------------------------\n" >> "$DISK_LOG_FILE"

    # DF -hT: Uso de Espaço em Disco
    echo -e "\n--- DF -hT (Uso de Espaço em Disco) ---\n" >> "$DISK_LOG_FILE"
    df -hT >> "$DISK_LOG_FILE" 2>&1
    echo -e "\n--------------------------------------------------------------------------\n" >> "$DISK_LOG_FILE"

    # cat /etc/fstab: Entradas de Montagem Persistente
    echo -e "\n--- CAT /ETC/FSTAB (Entradas de Montagem Persistente) ---\n" >> "$DISK_LOG_FILE"
    # Adiciona um marcador visual para facilitar a identificação das entradas criadas pelo script
    echo "## INÍCIO DAS ENTRADAS DE FSTAB (GERADAS/MODIFICADAS PELO SCRIPT) ##" >> "$DISK_LOG_FILE"
    cat /etc/fstab >> "$DISK_LOG_FILE" 2>&1
    echo "## FIM DAS ENTRADAS DE FSTAB (GERADAS/MODIFICADAS PELO SCRIPT) ##" >> "$DISK_LOG_FILE"
    echo -e "\n--------------------------------------------------------------------------\n" >> "$DISK_LOG_FILE"

    # PVS: Volumes Físicos LVM
    echo -e "\n--- PVS (Volumes Físicos LVM) ---\n" >> "$DISK_LOG_FILE"
    # Redireciona stderr de 'pvs' para /dev/null (na tela) E para o LVM_LOG_FILE, stdout para DISK_LOG_FILE
    # O '|| echo ...' serve para registrar no DISK_LOG_FILE se o comando falhar ou não encontrar nada.
    pvs -o pv_name,vg_name,pv_fmt,pv_attr,pv_size,free,dev_size --units h >> "$DISK_LOG_FILE" 2>>"$LVM_LOG_FILE" || echo "Nenhum PV encontrado ou erro ao executar pvs." >> "$DISK_LOG_FILE"
    echo -e "\n--------------------------------------------------------------------------\n" >> "$DISK_LOG_FILE"

    # VGS: Grupos de Volumes LVM
    echo -e "\n--- VGS (Grupos de Volumes LVM) ---\n" >> "$DISK_LOG_FILE"
    vgs -o vg_name,pv_count,lv_count,vg_size,free,vg_attr --units h >> "$DISK_LOG_FILE" 2>>"$LVM_LOG_FILE" || echo "Nenhum VG encontrado ou erro ao executar vgs." >> "$DISK_LOG_FILE"
    echo -e "\n--------------------------------------------------------------------------\n" >> "$DISK_LOG_FILE"

    # LVS: Volumes Lógicos LVM
    echo -e "\n--- LVS (Volumes Lógicos LVM) ---\n" >> "$DISK_LOG_FILE"
    lvs -o lv_name,vg_name,lv_size,lv_attr >> "$DISK_LOG_FILE" 2>>"$LVM_LOG_FILE" || echo "Nenhum LV encontrado ou erro ao executar lvs." >> "$DISK_LOG_FILE"
    echo -e "\n--------------------------------------------------------------------------\n" >> "$DISK_LOG_FILE"

    # blkid: Identificadores de Dispositivos de Bloco
    echo -e "\n--- BLKID (Identificadores de Dispositivos de Bloco) ---\n" >> "$DISK_LOG_FILE"
    blkid >> "$DISK_LOG_FILE" 2>&1
    echo -e "\n--------------------------------------------------------------------------\n" >> "$DISK_LOG_FILE"

    # mount: Pontos de Montagem Atuais
    echo -e "\n--- MOUNT (Pontos de Montagem Atuais) ---\n" >> "$DISK_LOG_FILE"
    mount >> "$DISK_LOG_FILE" 2>&1
    echo -e "\n==========================================================================" >> "$DISK_LOG_FILE"
    echo -e "=== FIM DA COLETA DE LOGS ANTES DAS ALTERAÇÕES PARA TROUBLESHOOTING - ${TIMESTAMP} ===" >> "$DISK_LOG_FILE"
    echo -e "==========================================================================\n" >> "$DISK_LOG_FILE"
}

# --- Funções de Hardware e LVM ---

function scan_new_disks() {
    # Mensagens para o usuário na tela, detalhes para o log
    echo -e "${C_BLUE}Escaneando novos discos SCSI...${C_RESET}"
    echo "DEBUG: Escaneando novos discos SCSI..." >> "$DISK_LOG_FILE"
    local scsi_hosts
    scsi_hosts=$(ls /sys/class/scsi_host/)
    for host in $scsi_hosts; do
        echo "DEBUG: Tentando escanear host: $host" >> "$DISK_LOG_FILE"
        # Redireciona a saída de erro de 'echo' para o log
        echo "- - -" > "/sys/class/scsi_host/$host/scan" 2>>"$DISK_LOG_FILE" || echo "WARNING: Falha ao escanear host: $host" >> "$DISK_LOG_FILE"
    done
    echo -e "${C_BLUE}Escaneamento concluído.${C_RESET}"
    echo "DEBUG: Escaneamento concluído." >> "$DISK_LOG_FILE"
    sleep 1 # Pequena pausa para garantir que o kernel processe
}

# Obtém a lista de discos completamente limpos (sem partições)
function get_clean_disks() {
    echo "DEBUG: Executando get_clean_disks()" >> "$DISK_LOG_FILE"
    # lsblk -dn -o KNAME,TYPE lista apenas o nome do kernel e o tipo, sem cabeçalho e sem sub-árvores
    local all_disks=$(lsblk -dn -o KNAME,TYPE | awk '$2=="disk"{print $1}' | tr '\n' ' ')
    echo "DEBUG: Todos os discos detectados: $all_disks" >> "$DISK_LOG_FILE"
    local clean_disks_list=""
    for disk in $all_disks; do
        echo "DEBUG: Verificando se o disco $disk é limpo..." >> "$DISK_LOG_FILE"
        # Um disco é limpo se não tem nenhuma partição (ou seja, lsblk -lnp /dev/$disk não retorna nada para "part")
        if ! lsblk -lnp "/dev/$disk" | grep -q "part"; then
            clean_disks_list+="$disk "
            echo "DEBUG: Disco $disk é limpo." >> "$DISK_LOG_FILE"
        else
            echo "DEBUG: Disco $disk possui partições." >> "$DISK_LOG_FILE"
        fi
    done
    echo "DEBUG: Discos limpos encontrados: $clean_disks_list" >> "$DISK_LOG_FILE"
    echo "$clean_disks_list" # Retorna apenas a lista de discos limpos via stdout
}

# Obtém a lista de discos particionados, mas sem PV/VG (candidatos a LVM)
function get_lvm_candidate_disks() {
    echo "DEBUG: Executando get_lvm_candidate_disks()" >> "$DISK_LOG_FILE"
    local all_disks=$(lsblk -dn -o KNAME,TYPE | awk '$2=="disk"{print $1}' | tr '\n' ' ')
    local lvm_candidates_list=""
    for disk in $all_disks; do
        echo "DEBUG: Verificando se o disco $disk é um candidato LVM..." >> "$DISK_LOG_FILE"
        # É um candidato LVM se tem partições, mas nenhuma delas é LVM ou criptografada,
        # E o disco inteiro ou suas partições ainda não são um PV.
        if lsblk -lnp "/dev/$disk" | grep -q "part" && \
            ! lsblk -lnp "/dev/$disk" | grep -qE "lvm|crypt" && \
            ! pvs --noheadings -o pv_name | grep -qE "^[[:space:]]*/dev/$disk([0-9]+)?[[:space:]]*$"; then
            lvm_candidates_list+="$disk "
            echo "DEBUG: Disco $disk é um candidato LVM válido." >> "$DISK_LOG_FILE"
        else
            echo "DEBUG: Disco $disk não é um candidato LVM válido." >> "$DISK_LOG_FILE"
        fi
    done
    echo "DEBUG: Candidatos LVM encontrados: $lvm_candidates_list" >> "$DISK_LOG_FILE"
    echo "$lvm_candidates_list" # Retorna apenas a lista de candidatos via stdout
}

function partition_instructions() {
    local disk_path="/dev/$1"
    
    echo "DEBUG: Executando partition_instructions para $disk_path" >> "$DISK_LOG_FILE"

    echo -e "\nATENÇÃO: PARTICIONANDO O DISCO AUTOMATICAMENTE: ${disk_path}" > "$DISK_LOG_FILE"
    echo -e "\n${C_YELLOW}ATENÇÃO: PARTICIONANDO O DISCO AUTOMATICAMENTE: ${disk_path}${C_RESET}" 
    #echo -e "${C_YELLOW}Todas as informações em ${disk_path} serão perdidas.${C_RESET}" | tee -a "$DISK_LOG_FILE"
    echo -e "${C_YELLOW}Todas as informações em ${disk_path} serão perdidas.${C_RESET}"
    #echo -e "${C_YELLOW}Será criada uma única partição primária, tipo 'Linux LVM (8e)', ocupando todo o disco.${C_RESET}" | tee -a "$DISK_LOG_FILE"
    echo -e "${C_YELLOW}Será criada uma única partição primária, tipo 'Linux LVM (8e)', ocupando todo o disco.${C_RESET}" 

    echo "DEBUG: Limpando assinaturas existentes em $disk_path" >> "$DISK_LOG_FILE"
    # Redireciona stdout e stderr para /dev/null, e erros para o log
    wipefs -a "$disk_path" >/dev/null 2>>"$DISK_LOG_FILE" || echo "WARNING: wipefs falhou ou teve saída de erro em $disk_path." >> "$DISK_LOG_FILE"

    echo "DEBUG: Executando fdisk automatizado em $disk_path" >> "$DISK_LOG_FILE"
    # Redireciona a saída de fdisk para /dev/null para NÃO POLUIR stdout/stderr,
    # e registra o que fdisk faz no log (stderr) e em DISK_LOG_FILE.
    (
        echo o      # Criar nova tabela de partição dos
        echo n      # Nova partição
        echo p      # Primária
        echo 1      # Número da partição
        echo        # Aceitar setor inicial padrão
        echo        # Aceitar setor final padrão
        echo t      # Alterar tipo da partição
        echo 8e     # Definir como LVM
        echo w      # Gravar alterações
    ) | fdisk "$disk_path" >/dev/null 2>&1

    local fdisk_status="${PIPESTATUS[0]}"
    echo "DEBUG: fdisk status: $fdisk_status" >> "$DISK_LOG_FILE"

    if [ "$fdisk_status" -ne 0 ]; then
        error_exit "Falha ao particionar o disco $disk_path automaticamente com fdisk. Verifique os logs para detalhes."
    fi

    echo "DEBUG: Executando partprobe em $disk_path" >> "$DISK_LOG_FILE"
    # Redireciona saída para /dev/null e erros para o log
    partprobe "$disk_path" >/dev/null 2>>"$DISK_LOG_FILE" || echo "WARNING: partprobe falhou ou teve saída de erro." >> "$DISK_LOG_FILE"
    
    echo "DEBUG: Aguardando 5 segundos para o kernel reconhecer a nova partição." >> "$DISK_LOG_FILE"
    sleep 5 # Dá um tempo para o kernel reconhecer a nova partição

    echo -e "DEBUG: lsblk após fdisk e partprobe:\n" >> "$DISK_LOG_FILE"
    lsblk "$disk_path" >> "$DISK_LOG_FILE" 2>&1 # Loga o estado do disco após particionamento
    
    # Esta função NÃO DEVE ECHOAR nada para stdout para não poluir o retorno de select_disk.
    # Apenas suas mensagens informativas e de debug.
}

# Modificada para selecionar o primeiro disco limpo automaticamente
function select_disk() {
    echo "DEBUG: Executando select_disk() para encontrar o primeiro disco limpo." >> "$DISK_LOG_FILE"
    local first_clean_disk=""

    # Captura a saída de get_clean_disks (que só retorna o nome do disco via stdout)
    # e redireciona DEBUG/ERROS para o log.
    local clean_disks=$(get_clean_disks 2>> "$DISK_LOG_FILE")

    echo "DEBUG: Discos limpos encontrados: '$clean_disks'" >> "$DISK_LOG_FILE"

    if [ -z "$clean_disks" ]; then
        error_exit "NÃO HÁ DISCOS COMPLETAMENTE LIMPOS disponíveis para configuração automática. O script requer um disco limpo."
    fi

    # Pega o primeiro disco da lista de discos limpos
    first_clean_disk=$(echo "$clean_disks" | awk '{print $1}')
    
    # As mensagens informativas agora são enviadas para stderr (>&2)
    echo -e "${C_BLUE}PRIMEIRO DISCO LIMPO DISPONÍVEL SELECIONADO AUTOMATICAMENTE: /dev/${first_clean_disk}${C_RESET}\n" | tee -a "$DISK_LOG_FILE" >&2
    echo -e "${C_YELLOW}AGUARDE!!! INFORME OS DADOS SOMENTE QUANDO SOLICITADO...................${C_RESET}\n" >&2   
    lsblk "/dev/${first_clean_disk}" | tee -a "$DISK_LOG_FILE" >&2 # Exibe e loga informações do disco selecionado, também para stderr

    # Chama partition_instructions, direcionando seu stdout para /dev/null (descarte)
    # e seu stderr (que inclui as mensagens do 'tee') para o DISK_LOG_FILE.
    partition_instructions "$first_clean_disk" >/dev/null 2>> "$DISK_LOG_FILE"
    
    echo "$first_clean_disk" # Este é o ÚNICO valor que deve ser impresso em stdout para ser capturado
}

function add_disk_to_lvm() {
    local disk_name="$1"
    # Constrói o caminho completo da partição (ex: /dev/sdg1)
    local partition_path="/dev/${disk_name}${PARTITION_NUMBER}" 

    echo -e "\n${C_BLUE}Configurando LVM para ${partition_path}...${C_RESET}" | tee -a "$LVM_LOG_FILE" # Mensagem para tela e log

    echo "DEBUG: Verificando se $partition_path existe." >> "$LVM_LOG_FILE"
    if [ ! -b "$partition_path" ]; then
        error_exit "Partição ${partition_path} não encontrada. Verifique se o disco foi particionado corretamente como 'Linux LVM (8e)'."
    fi

    # Cria Physical Volume (PV)
    echo -e "${C_BLUE}Criando Physical Volume em ${partition_path}...${C_RESET}" | tee -a "$LVM_LOG_FILE" # Mensagem para tela e log
    # Adicionado o '-y' para aceitar automaticamente a limpeza de assinaturas existentes
    pvcreate -y "$partition_path" >> "$LVM_LOG_FILE" 2>&1 # Saída apenas para log
    local pvcreate_status="${PIPESTATUS[0]}"
    echo "DEBUG: pvcreate status: $pvcreate_status" >> "$LVM_LOG_FILE"
    if [ "$pvcreate_status" -ne 0 ]; then
        error_exit "Falha ao criar Physical Volume em ${partition_path}. Pode ser que já exista um PV ou a partição não seja do tipo '8e'."
    fi

    # Input do nome do Volume Group
     echo " " 
     if [ -z "$USER_INPUT" ]; then # Validar a entrada original do usuário
        error_exit "Nome do Volume Group não pode ser vazio."
    fi   

    VG_INPUT=$(echo "$USER_INPUT" | tr '[:lower:]' '[:upper:]')
    # Adiciona o prefixo 'vg_'
    VG_NAME="vg_${VG_INPUT}"
    echo "DEBUG: Nome do VG informado: $VG_NAME" >> "$LVM_LOG_FILE"
    #if [ -z "$VG_INPUT" ]; then # Validar a entrada original do usuário
    #    error_exit "Nome do Volume Group não pode ser vazio."
    #fi

    # Cria Volume Group (VG)
    echo -e "${C_BLUE}Criando Volume Group ${VG_NAME}...${C_RESET}" | tee -a "$LVM_LOG_FILE" # Mensagem para tela e log
    # Adicionado o '-y' para aceitar automaticamente a limpeza de assinaturas existentes
    vgcreate -y "$VG_NAME" "$partition_path" >> "$LVM_LOG_FILE" 2>&1 # Saída apenas para log
    local vgcreate_status="${PIPESTATUS[0]}"
    echo "DEBUG: vgcreate status: $vgcreate_status" >> "$LVM_LOG_FILE"
    if [ "$vgcreate_status" -ne 0 ]; then
        error_exit "Falha ao criar Volume Group ${VG_NAME}. Pode ser que já exista um VG com este nome."
    fi

    # Input do nome do Logical Volume
    echo " " 
    LV_NAME="lv_${VG_INPUT}"
    echo "DEBUG: Nome do LV informado: $LV_NAME" >> "$LVM_LOG_FILE"

    # Cria Logical Volume (LV) usando todo o espaço livre do VG
    echo -e "${C_BLUE}Criando Logical Volume ${LV_NAME} em ${VG_NAME}...${C_RESET}" | tee -a "$LVM_LOG_FILE" # Mensagem para tela e log
    # Adicionado o '-y' para aceitar automaticamente a limpeza de assinaturas existentes
    lvcreate -l 100%FREE -n "$LV_NAME" "$VG_NAME" -y >> "$LVM_LOG_FILE" 2>&1 # Saída apenas para log
    local lvcreate_status="${PIPESTATUS[0]}"
    echo "DEBUG: lvcreate status: $lvcreate_status" >> "$LVM_LOG_FILE"
    if [ "$lvcreate_status" -ne 0 ]; then
        error_exit "Falha ao criar Logical Volume ${LV_NAME}. Pode ser que já exista um LV com este nome ou espaço insuficiente."
    fi

    local lv_path="/dev/${VG_NAME}/${LV_NAME}"
    echo "DEBUG: Caminho do LV: $lv_path" >> "$LVM_LOG_FILE"

    # Formata o Logical Volume com ext4
    echo -e "${C_BLUE}Formando ${lv_path} com ext4...${C_RESET}" | tee -a "$LVM_LOG_FILE" # Mensagem para tela e log
    mkfs.ext4 "$lv_path" >> "$LVM_LOG_FILE" 2>&1 # Saída apenas para log
    local mkfs_status="${PIPESTATUS[0]}"
    echo "DEBUG: mkfs.ext4 status: $mkfs_status" >> "$LVM_LOG_FILE"
    if [ "$mkfs_status" -ne 0 ]; then
        error_exit "Falha ao formatar ${lv_path}."
    fi

    # Input do ponto de montagem
    echo " " 
    PONTO_MONTAGEM=$(echo "$VG_INPUT" | tr '[:upper:]' '[:lower:]')
    MOUNT_POINT=$(normaliza_ponto_montagem "${PONTO_MONTAGEM}")
    
    echo "DEBUG: Ponto de montagem informado: $MOUNT_POINT" >> "$LVM_LOG_FILE"
    if [ -z "$MOUNT_POINT" ]; then
        error_exit "Ponto de montagem não pode ser vazio."
    fi
    # A validação '[[ "$MOUNT_POINT" != /* ]]' já está sendo feita dentro de normaliza_ponto_montagem,
    # então a checagem explícita aqui pode ser removida se a normaliza_ponto_montagem for a única fonte.
    # Se normaliza_ponto_montagem garante o '/', esta checagem pode ser simplificada ou removida.
    # Por segurança, mantemos aqui por enquanto, caso a função de normalização mude.
    if [[ "$MOUNT_POINT" != /* ]]; then
        error_exit "Ponto de montagem inválido. Deve começar com '/'. Ex: /dados."
    fi

    # Cria o ponto de montagem e monta o LV
    echo -e "${C_BLUE}Criando ponto de montagem ${MOUNT_POINT} e montando o LV...${C_RESET}" | tee -a "$LVM_LOG_FILE" # Mensagem para tela e log
    mkdir -p "$MOUNT_POINT" >> "$LVM_LOG_FILE" 2>&1 # Saída apenas para log
    mount "$lv_path" "$MOUNT_POINT" >> "$LVM_LOG_FILE" 2>&1 # Saída apenas para log
    local mount_status="${PIPESTATUS[0]}"
    echo "DEBUG: mount status: $mount_status" >> "$LVM_LOG_FILE"
    if [ "$mount_status" -ne 0 ]; then
        error_exit "Falha ao montar ${lv_path} em ${MOUNT_POINT}."
    fi

    # Adiciona ao fstab para montagem persistente
    echo -e "${C_BLUE}Adicionando entrada para ${lv_path} no /etc/fstab...${C_RESET}" | tee -a "$LVM_LOG_FILE" # Mensagem para tela e log
    
    # # Usando diretamente o caminho do LV para maior robustez
    # echo "$lv_path $MOUNT_POINT ext4 defaults 1 2" >> /etc/fstab
    local persisttab=$(echo "$lv_path" | sed -E 's#/dev/(.*)/(.*)#/dev/mapper/\1-\2#g')
    echo "$persisttab $MOUNT_POINT ext4 defaults 1 2" >> /etc/fstab
    
    local fstab_status="$?"
    echo "DEBUG: fstab write status: $fstab_status" >> "$LVM_LOG_FILE"
    if [ "$fstab_status" -ne 0 ]; then
        error_exit "Falha ao adicionar entrada ao /etc/fstab. Por favor, adicione manualmente."
    fi

    echo -e "\n${C_GREEN}Disco configurado e montado com sucesso!${C_RESET}\n" | tee -a "$LVM_LOG_FILE" # Mensagem para tela e log
}

# Retorna: O ponto de montagem padronizado na saída padrão (stdout).
normaliza_ponto_montagem() {
    local entrada_usuario="$1" # 'local' para manter a variável no escopo da função

    # Verifica se a string JÁ COMEÇA com uma barra
    if [[ ! "${entrada_usuario}" =~ ^/ ]]; then
        # Se não começar com barra, adicionamos uma.
        echo "/${entrada_usuario}" # A função AGORA apenas imprime o VALOR
    else
        # Se já começar com barra, usamos como está.
        echo "${entrada_usuario}" # A função AGORA apenas imprime o VALOR
    fi
}

# --- Execução Principal ---
main() {
    echo "DEBUG: Verificando privilégios de root." >> "$DISK_LOG_FILE"
    if [ "$(id -u)" -ne 0 ]; then
        error_exit "Este script deve ser executado como root. Use 'sudo ./add_disk.sh'."
    fi

    echo "DEBUG: Criando diretório de logs: $LOG_DIR" >> "$DISK_LOG_FILE"
    mkdir -p "$LOG_DIR"

    echo -e "\n${C_BLUE}Opção selecionada: Adicionar um disco ao sistema (Modo Automático - Primeiro Disco Limpo)${C_RESET}\n" # Mensagem para tela

    echo "DEBUG: Chamando scan_new_disks em background." >> "$DISK_LOG_FILE"
    scan_new_disks &
    scan_pid=$!
    echo "DEBUG: PID do scan_new_disks: $scan_pid" >> "$DISK_LOG_FILE"
    wait "$scan_pid" # Espera a conclusão do scan
    echo "DEBUG: scan_new_disks concluído." >> "$DISK_LOG_FILE"

    echo "DEBUG: Registrando logs iniciais." >> "$DISK_LOG_FILE"
    record_logs

    echo "DEBUG: Chamando select_disk para identificação automática." >> "$DISK_LOG_FILE"
    # Chama a função select_disk, que agora seleciona o primeiro disco limpo e o particiona.
    # Captura apenas o nome do disco selecionado em SELECTED_DISK.
    SELECTED_DISK=$(select_disk)
    echo "DEBUG: Disco selecionado e particionado por select_disk: $SELECTED_DISK" >> "$DISK_LOG_FILE"

    # Verifica se o disco selecionado não está vazio antes de continuar
    if [ -z "$SELECTED_DISK" ]; then
        error_exit "Nenhum disco foi selecionado automaticamente. O script será encerrado."
    fi

    echo "DEBUG: Chamando add_disk_to_lvm com o disco: $SELECTED_DISK" >> "$DISK_LOG_FILE"
    add_disk_to_lvm "$SELECTED_DISK"

    echo "DEBUG: Exibindo mensagem de sucesso." >> "$DISK_LOG_FILE"
    success_message

    echo "DEBUG: Script finalizado com sucesso." >> "$DISK_LOG_FILE"
    exit 0
}

# Inicia a execução do script
main