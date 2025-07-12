#!/bin/bash
#teste
echo "Escolha o tipo de entrada:"
echo "1 - Frase"
echo "2 - Arquivo"
read -p "Opção: " tipo

read -p "Digite a operação (c para criptografar / d para descriptografar): " operacao

if [ "$tipo" == "1" ]; then
    read -p "Digite a frase: " frase
elif [ "$tipo" == "2" ]; then
    read -p "Informe o caminho do arquivo (.txt): " arquivo
    if [ ! -f "$arquivo" ]; then
        echo "❌ Arquivo não encontrado!"
        exit 1
    fi
else
    echo "❌ Tipo inválido."
    exit 1
fi

read -s -p "Digite a senha: " senha
echo ""

if [ "$operacao" == "c" ]; then
    if [ "$tipo" == "1" ]; then
        resultado=$(echo -n "$frase" | openssl enc -aes-256-cbc -a -salt -pbkdf2 -iter 100000 -pass pass:"$senha")
        echo "🔐 Frase criptografada:"
        echo "$resultado"
    else
        out="${arquivo}.enc"
        openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 -in "$arquivo" -out "$out" -pass pass:"$senha"
        echo "🔐 Arquivo criptografado: $out"
    fi
elif [ "$operacao" == "d" ]; then
    if [ "$tipo" == "1" ]; then
        resultado=$(echo "$frase" | openssl enc -aes-256-cbc -a -d -salt -pbkdf2 -iter 100000 -pass pass:"$senha")
        echo "🔓 Frase descriptografada:"
        echo "$resultado"
    else
        out="recuperado_$(basename "$arquivo" .enc).txt"
        openssl enc -aes-256-cbc -d -salt -pbkdf2 -iter 100000 -in "$arquivo" -out "$out" -pass pass:"$senha"
        echo "🔓 Arquivo descriptografado: $out"
    fi
else
    echo "❌ Operação inválida."
    exit 1
fi
