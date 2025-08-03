#!/bin/bash

DISK=$1

if [ -z "${DISK}" ]; then
echo -e "\n Executar da seguinte forma: ./resize_disk_com_argumento.sh Nome-Do-Disco\n"
exit 0
fi

scsidev=`ls /sys/class/scsi_device/` && for dev in $scsidev; do echo "1" > /sys/class/scsi_device/$dev/device/rescan; done

echo -e "\n  ANTES DE REDIMENSIONAR O VOLUME\n"
lsblk /dev/"${DISK}"

echo -e "\n\n ========= INICIO DA CONFIGURACAO LVM .....\n"

growpart /dev/"${DISK}" 1

pvresize /dev/"${DISK}1"

lvextend -l +100%free /dev/mapper/"$(lsblk -ln /dev/"${DISK}1" | awk '{print $1}' | tail -n +2)"

resize2fs /dev/mapper/"$(lsblk -ln /dev/"${DISK}1" | awk '{print $1}' | tail -n +2)"

echo -e " ========= FIM DA CONFIGURACAO LVM .....\n"

echo -e "\n\n  APOS REDIMENSIONAR O VOLUME\n"
lsblk /dev/"${DISK}"
