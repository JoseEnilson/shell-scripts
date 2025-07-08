#!/bin/bash

read -p "Digite a operação desejada (c para criptografar, d para descriptografar): " operacao

read -p "Digite a frase: " frase

read -p  "Digite a senha: " senha

if [ "$operacao" == "c" ]; then
    resultado=$(echo -n "$frase" | openssl enc -aes-256-cbc -a -salt -pbkdf2 -iter 100000 -pass pass:"$senha")
    echo "🔐 Frase criptografada:"
    echo "$resultado"
elif [ "$operacao" == "d" ]; then
    resultado=$(echo "$frase" | openssl enc -aes-256-cbc -a -d -salt -pbkdf2 -iter 100000 -pass pass:"$senha")
    echo "🔓 Frase descriptografada:"
    echo "$resultado"
else
    echo "❌ Operação inválida. Use 'c' para criptografar ou 'd' para descriptografar."
fi
