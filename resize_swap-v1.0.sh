#!/bin/bash

scsidev=`ls /sys/class/scsi_device/` && for dev in $scsidev; do echo "1" > /sys/class/scsi_device/$dev/device/rescan; done
scsi=`ls /sys/class/scsi_host/` && for dev in $scsi; do `echo "- - -" > /sys/class/scsi_host/$dev/scan`; done

# Rodar esses comandos
growpart /dev/sda 2
pvresize /dev/sda2

# Define o novo tamanho do swap (exemplo: 4G)
NEW_SWAP_SIZE="1G"

# Define o Logical Volume do swap
SWAP_DEVICE="/dev/mapper/ol_192-swap"

# Desabilita o swap
echo "Desabilitando o swap..."
sudo swapoff $SWAP_DEVICE

# Redimensiona o Logical Volume do swap
echo "Redimensionando o swap para $NEW_SWAP_SIZE..."
sudo lvresize -L $NEW_SWAP_SIZE $SWAP_DEVICE

# Cria a nova área de swap no Logical Volume
echo "Criando nova área de swap..."
sudo mkswap $SWAP_DEVICE

# Habilita o swap novamente
echo "Habilitando o swap..."
sudo swapon $SWAP_DEVICE

# Verifica o status
echo "Swap redimensionado com sucesso. Verificando o status..."
swapon --show
