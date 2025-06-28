#!/usr/bin/env bash
#
# add_disk_to_vg.sh - Adicionar um disco a um grupo de volume
#
# Autor:       José Enilson Mota Silva
# Manutenção:  José Enilson Mota Silva
#
# ------------------------------------------------------------------------ #
# Este programa irá adicionar um disco a um grupo de volume LVM existente.
#
# Exemplo de execução (executar como root):
#        # ./add_disk_to_vg.sh
#
#-----------------PACKAGE REQUIRED ----------------------------------------#
# - bc.x86_64
# ------------------------------------------------------------------------ #

# ------------------------------- VARIAVEIS ------------------------------ #
LANG=C
DISKSFORMAT=$(lsblk | grep -o "sd[a-z]" | uniq -d)
DISKS=$(lsblk | grep -w "sd." | cut -d" " -f 1)
DISKAVAILABLE=$(echo "$DISKSFORMAT $DISKS" | tr ' ' '\n' | sort | uniq -u)
BAR_SIZE=40
BAR_CHAR_DONE="#"
BAR_CHAR_TODO="-"
BAR_PERCENTAGE_SCALE=2
PART_NUM=1

#-------------------------------- FUNCTIONS --------------------------------#

function scanNewDisk() {
    scsi=$(ls /sys/class/scsi_host/) && for dev in $scsi; do $(echo "- - -" >/sys/class/scsi_host/$dev/scan); done
}

function sucesso() {
    echo -e "\n\n  \033[1;32m       ***** CONFIGURACAO EXECUTADA COM SUCESSO *****\033[0m \n\n"
    echo -e "---------------------------- \n\033[1;33m  << DF -HT >> \033[0m\n"
    df -hT
    echo -e "\n\n----------------------------- \n\033[1;33m << FSTAB >>\033[0m"
    cat /etc/fstab
    echo -e "\n\n----------------------------- \n\033[1;33m << LSBLK >> \033[0m"
    lsblk    
    echo -e "\n\n"
}

function erro () {
     echo -e "\n\n\033[0;31m    ERRO AO APLICAR AS CONFIGURACOES!!!\033[0m"
     echo -e "\033[0;31m    CONSULTE OS ARQUIVOS DE LOGS: lvm.log e/ou disk<data>.log\033[0m\n\n"
     exit 1
}

function show_progress {
    current="$1"
    total="$2"

    # calculate the progress in percentage
    percent=$(bc <<<"scale=$BAR_PERCENTAGE_SCALE; 100 * $current / $total")
    # The number of done and todo characters
    done=$(bc <<<"scale=0; $BAR_SIZE * $percent / 100")
    todo=$(bc <<<"scale=0; $BAR_SIZE - $done")

    # build the done and todo sub-bars
    done_sub_bar=$(printf "%${done}s" | tr " " "${BAR_CHAR_DONE}")
    todo_sub_bar=$(printf "%${todo}s" | tr " " "${BAR_CHAR_TODO}")

    # output the bar
    echo -ne "\rProgress : [${done_sub_bar}${todo_sub_bar}] ${percent}%"

    if [ $total -eq $current ]; then
      echo -e "\nDONE"
    fi
}

function call_show_progress_bar() {
    bcPacote=$(whereis bc) && bcPacoteByte=$(echo "$bcPacote" | wc -c)
    if [ "$bcPacoteByte" -lt 10 ]; then
      echo "      DISCOS SENDO ESCANEADOS. AGUARDE ...."
      sleep 5
    else
      echo -e "\n        DISCOS SENDO ESCANEADOS. AGUARDE ...\n"
      tasks_in_total=40
      for current_task in $(seq $tasks_in_total); do
        sleep 0.2 
        show_progress $current_task $tasks_in_total
      done
    fi
}

function discosDisponiveis() {
        if [ -z "$DISKAVAILABLE" ]; then
            echo -e "\n\033[0;31m    NÃO HÁ DISCOS PARA SEREM PARTICIONADOS\033[0m\n"
            echo "Caso o disco já esteja particionado, tecle ENTER e \"AGUARDE...\" ou CTRL + C para encerrar."
            read -p " "
            lsblk
            echo " " 
            read -p "INFORME O DISCO [ sdx ]: " disk
        else
            echo -e "\n  \033[1;34m DISCOS DISPONIVEIS PARA PARTICIONAMENTOS: \n\033[0m"
            lsblk | egrep -w "$(echo "$DISKSFORMAT $DISKS" | tr ' ' '\n' | sort | uniq -u)"
            echo " "
            read -p "INFORME O DISCO [ sdx ]: " disk
            discoExist=$(lsblk | grep -o sd[a-z] | grep -i "$disk") # verifica se o disco exite
            test -z "$discoExist" && erro && exit 1
            discoList=$(echo "$DISKAVAILABLE" | grep -i $disk) # Verifica se o disco informado está disponível
            test -z "$discoList" && erro && exit 1
            instrucoesFSDISK # function
            #pvcreate -y /dev/$disk$PART_NUM -ff >> lvm.log
            if [ "$?" -eq 5 ]; then
                erro
            fi
        fi 
}

instrucoesFSDISK() {

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
    ) | fdisk /dev/"$disk" >/dev/null 2>&1

#    fdisk /dev/$disk
}

function logs() {
    echo -e " [ $(date) ]\n\n"
    echo -e "              << LSBLK >>"
    echo -e "\n$(lsblk)"
    echo -e "\n-----------------------------------------------\n"
    echo -e "              << DF -HT >>"
    echo -e "\n$(df -hT)\n"
    echo -e "\n-----------------------------------------------\n"
    echo -e "              << FSTAB >>"
    echo -e "\n$(cat /etc/fstab)\n"
    echo -e "\n***********************************************"
    echo -e "|=============================================|"
    echo -e "***********************************************"
}

# ------------------------------- EXECUCAO ------------------------------- #
echo -e "\nOpção selecionada: Adicionar um disco a um grupo de volume\n"

logs >>disk$(date +%Y%m%d).log # function
# Função que escaneia os discos
scanNewDisk & 
# Função que chama a barra de progresso
call_show_progress_bar

# Função que lista os discos disponíveis para serem particionados
discosDisponiveis      
echo " "

# A variável 'disk' vem da função 'discosDisponiveis'
# Esta linha abaixo parece redundante, pois o pvcreate é feito em discosDisponiveis
# pvcreate /dev/$disk$PART_NUM >>lvm.log

echo -e "\n$(lvs)\n"
read -p "INFORME O NOME DO VOLUME GROUP [ vg_NOME ]: " vg
read -p "INFORME O NOME DO LOGICAL VOLUME [ lv_NOME ]: " lv
vgextend $vg /dev/$disk$PART_NUM >>lvm.log
test "$?" -ne 0 && erro
lvextend -l +100%free /dev/mapper/$vg-$lv >>lvm.log
resize2fs /dev/mapper/$vg-$lv >>lvm.log
sucesso
logs >>disk$(date +%Y%m%d).log # functio

