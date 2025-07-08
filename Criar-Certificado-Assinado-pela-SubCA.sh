#!/bin/bash


echo -e "\nGenerate and sign server certificate using Intermediate CA ...\n"

read -p "Informe o nome comum do certificado: " certiName

echo -e "\n Criando a chave do certificado ... "
openssl genpkey -algorithm RSA -out /root/myCA/intermediateCA/private/${certiName}.key.pem
chmod 400 /root/myCA/intermediateCA/private/${certiName}.key.pem

openssl req -config /root/myCA/openssl_intermediate.cnf -key /root/myCA/intermediateCA/private/${certiName}.key.pem -new -sha256 -out /root/myCA/intermediateCA/csr/${certiName}.csr.pem -subj "/C=BR/ST=Sergipe/L=Aracaju/O=LAB-HOME/OU=IT Department/CN=$certiName"

echo -e "\n\n\e[32mASSINANDO CERTIFICADO DE NOME $certiName\e[0m\n"
echo -e "\e[1;33mATENCAO! - Sempre que solicitado digite y e tecle ENTER\e[0m\n"
openssl ca -config /root/myCA/openssl_intermediate.cnf -extensions server_cert -days 375 -notext -md sha256 -in /root/myCA/intermediateCA/csr/${certiName}.csr.pem -out /root/myCA/intermediateCA/certs/${certiName}.cert.pem

#------------------------------------------#

mkdir -p /root/certificados/$certiName

cp /root/myCA/intermediateCA/certs/RootCA-RootSubCA-chain.crt /root/certificados/$certiName/
cp /root/myCA/intermediateCA/certs/$certiName* /root/certificados/$certiName/$certiName.crt
cp /root/myCA/intermediateCA/private/$certiName* /root/certificados/$certiName/$certiName.key

#-----------------------------------------#
echo -e "\n\n\e[1;33mATENCAO! - Informe uma senha forte para ser gerado tambem um arquivo *.pfx\e[0m\n"
openssl pkcs12 -export -out /root/certificados/$certiName/$certiName.pfx -inkey /root/certificados/$certiName/$certiName.key \
-in /root/certificados/$certiName/$certiName.crt \
-certfile /root/certificados/$certiName/RootCA-RootSubCA-chain.crt

echo -e "\n\n\e[1;32m    ARQUIVOS GERADOS COM SUCESSO!!!\e[0m\n"
echo -e "\n\e[32m    Caminho dos arquivos -> cd /root/certificados/$certiName/\e[0m\n"

