#!/bin/bash

# Define o novo tamanho do swap (exemplo: 4G)
NEW_SWAP_SIZE="4G"

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