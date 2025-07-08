#!/bin/env bash

#----------------------------------------------------------------------------#
# OpenSSL create Certificate Chain [Root & Intermediate CA]
# LINK: https://www.golinuxcloud.com/openssl-create-certificate-chain-linux/
#----------------------------------------------------------------------------#

# Configuração de ambiente
export LANG=C
export LC_ALL=C

#==========================================================
#==========================================================

# Step 1: Create OpenSSL Root CA directory structure
#----------------------------------------------------------
mkdir -p ~/myCA/rootCA/{certs,crl,newcerts,private,csr}
mkdir -p ~/myCA/intermediateCA/{certs,crl,newcerts,private,csr}
echo 1000 > ~/myCA/rootCA/serial
echo 1000 > ~/myCA/intermediateCA/serial
echo 0100 > ~/myCA/rootCA/crlnumber
echo 0100 > ~/myCA/intermediateCA/crlnumber
touch ~/myCA/rootCA/index.txt
touch ~/myCA/intermediateCA/index.txt
#=========================================================

# Step 2: Configure openssl.cnf for Root and Intermediate CA Certificate
# ---------------------------------------------------------

touch /root/myCA/openssl_root.cnf
cat << EOF >> /root/myCA/openssl_root.cnf
[ ca ]                                                   # The default CA section
default_ca = CA_default                                  # The default CA name

[ CA_default ]                                           # Default settings for the CA
certs             = /root/myCA/rootCA/certs                           # Certificates directory
crl_dir           = /root/myCA/rootCA/crl                             # CRL directory
new_certs_dir     = /root/myCA/rootCA/newcerts                        # New certificates directory
database          = /root/myCA/rootCA/index.txt                       # Certificate index file
serial            = /root/myCA/rootCA/serial                          # Serial number file
RANDFILE          = /root/myCA/rootCA/private/.rand                   # Random number file
private_key       = /root/myCA/rootCA/private/RootCA.key      # Root CA private key
certificate       = /root/myCA/rootCA/certs/RootCA.crt        # Root CA certificate
crl               = /root/myCA/rootCA/crl/ca.crl.pem                  # Root CA CRL
crlnumber         = /root/myCA/rootCA/crlnumber                       # Root CA CRL number
crl_extensions    = crl_ext                              # CRL extensions
default_crl_days  = 30                                   # Default CRL validity days
default_md        = sha256                               # Default message digest
preserve          = no                                   # Preserve existing extensions
email_in_dn       = no                                   # Exclude email from the DN
name_opt          = ca_default                           # Formatting options for names
cert_opt          = ca_default                           # Certificate output options
policy            = policy_strict                        # Certificate policy
unique_subject    = no                                   # Allow multiple certs with the same DN

[ policy_strict ]                                        # Policy for stricter validation
countryName             = match                          # Must match the issuer's country
stateOrProvinceName     = match                          # Must match the issuer's state
organizationName        = match                          # Must match the issuer's organization
organizationalUnitName  = optional                       # Organizational unit is optional
commonName              = supplied                       # Must provide a common name
emailAddress            = optional                       # Email address is optional

[ req ]                                                  # Request settings
default_bits        = 2048                               # Default key size
distinguished_name  = req_distinguished_name             # Default DN template
string_mask         = utf8only                           # UTF-8 encoding
default_md          = sha256                             # Default message digest
prompt              = no                                 # Non-interactive mode

[ req_distinguished_name ]                               # Template for the DN in the CSR
countryName                     = Country Name (2 letter code)
stateOrProvinceName             = State or Province Name (full name)
localityName                    = Locality Name (city)
0.organizationName              = Organization Name (company)
organizationalUnitName          = Organizational Unit Name (section)
commonName                      = Common Name (your domain)
emailAddress                    = Email Address

[ v3_ca ]                                           # Root CA certificate extensions
subjectKeyIdentifier = hash                         # Subject key identifier
authorityKeyIdentifier = keyid:always,issuer        # Authority key identifier
basicConstraints = critical, CA:true                # Basic constraints for a CA
keyUsage = critical, keyCertSign, cRLSign           # Key usage for a CA

[ crl_ext ]                                         # CRL extensions
authorityKeyIdentifier = keyid:always,issuer        # Authority key identifier

[ v3_intermediate_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
# --------------------------------------------------------
EOF


touch /root/myCA/openssl_intermediate.cnf
cat << EOF >> /root/myCA/openssl_intermediate.cnf
[ ca ]                                                   # The default CA section
default_ca = CA_default                                  # The default CA name

[ CA_default ]                                           # Default settings for the intermediate CA
certs             = /root/myCA/intermediateCA/certs                           # Certificates directory
crl_dir           = /root/myCA/intermediateCA/crl                             # CRL directory
new_certs_dir     = /root/myCA/intermediateCA/newcerts                        # New certificates directory
database          = /root/myCA/intermediateCA/index.txt                       # Certificate index file
serial            = /root/myCA/intermediateCA/serial                          # Serial number file
RANDFILE          = /root/myCA/intermediateCA/private/.rand                   # Random number file
private_key       = /root/myCA/intermediateCA/private/RootSubCA.key       # Intermediate CA private key
certificate       = /root/myCA/intermediateCA/certs/RootSubCA.crt         # Intermediate CA certificate
crl               = /root/myCA/intermediateCA/crl/intermediate.crl.pem        # Intermediate CA CRL
crlnumber         = /root/myCA/intermediateCA/crlnumber                       # Intermediate CA CRL number
crl_extensions    = crl_ext                              # CRL extensions
default_crl_days  = 30                                   # Default CRL validity days
default_md        = sha256                               # Default message digest
preserve          = no                                   # Preserve existing extensions
email_in_dn       = no                                   # Exclude email from the DN
name_opt          = ca_default                           # Formatting options for names
cert_opt          = ca_default                           # Certificate output options
policy            = policy_loose                         # Certificate policy

[ policy_loose ]                                         # Policy for less strict validation
countryName             = optional                       # Country is optional
stateOrProvinceName     = optional                       # State or province is optional
localityName            = optional                       # Locality is optional
organizationName        = optional                       # Organization is optional
organizationalUnitName  = optional                       # Organizational unit is optional
commonName              = supplied                       # Must provide a common name
emailAddress            = optional                       # Email address is optional

[ req ]                                                  # Request settings
default_bits        = 2048                               # Default key size
distinguished_name  = req_distinguished_name             # Default DN template
string_mask         = utf8only                           # UTF-8 encoding
default_md          = sha256                             # Default message digest
x509_extensions     = v3_intermediate_ca                 # Extensions for intermediate CA certificate

[ req_distinguished_name ]                               # Template for the DN in the CSR
countryName                     = Country Name (2 letter code)
stateOrProvinceName             = State or Province Name
localityName                    = Locality Name
0.organizationName              = Organization Name
organizationalUnitName          = Organizational Unit Name
commonName                      = Common Name
emailAddress                    = Email Address

[ v3_intermediate_ca ]                                      # Intermediate CA certificate extensions
subjectKeyIdentifier = hash                                 # Subject key identifier
authorityKeyIdentifier = keyid:always,issuer                # Authority key identifier
basicConstraints = critical, CA:true, pathlen:0             # Basic constraints for a CA
keyUsage = critical, digitalSignature, cRLSign, keyCertSign # Key usage for a CA

[ crl_ext ]                                                 # CRL extensions
authorityKeyIdentifier=keyid:always                         # Authority key identifier

[ server_cert ]                                             # Server certificate extensions
basicConstraints = CA:FALSE                                 # Not a CA certificate
nsCertType = server                                         # Server certificate type
keyUsage = critical, digitalSignature, keyEncipherment      # Key usage for a server cert
extendedKeyUsage = serverAuth                               # Extended key usage for server authentication purposes (e.g., TLS/SSL servers).
authorityKeyIdentifier = keyid,issuer                       # Authority key identifier linking the certificate to the issuer's public key.
EOF

#==========================================================

# Step 3: Generate the root CA key pair and certificate
#----------------------------------------------------------

# Create an RSA key pair for the root CA without a password:

openssl genrsa -out /root/myCA/rootCA/private/RootCA.key 4096
chmod 400 /root/myCA/rootCA/private/RootCA.key
#----------------------------------------------------------
# Create the root CA certificate:

read -p "Informe o nome da Organização (empresa) para a RootCA: " org
read -p "Informe o nome do Unidade Organizacional para a RootCA (se tiver mais de um nome, pôr entre aspas duplas) : " dep

openssl req -config /root/myCA/openssl_root.cnf -key /root/myCA/rootCA/private/RootCA.key -new -x509 -days 7300 -sha256 -extensions v3_ca -out /root/myCA/rootCA/certs/RootCA.crt -subj "/C=BR/ST=Sergipe/L=Aracaju/O="${org}"/OU=\"${dep}\"/CN=RootCA"

chmod 444 /root/myCA/rootCA/certs/RootCA.crt

#========================================================

# Step 4: Generate the intermediate CA key pair and certificate
#----------------------------------------------------------
# Create an RSA key pair for the intermediate CA without a password and secure the file by removing permissions to groups and others:

openssl genrsa -out /root/myCA/intermediateCA/private/RootSubCA.key 4096
chmod 400 /root/myCA/intermediateCA/private/RootSubCA.key
#----------------------------------------------------------
# Create the intermediate CA certificate signing request (CSR):

read -p "Informe o nome da Organização (empresa) para a RootSubCA: " org
read -p "Informe o nome do Unidade Organizacional para a RootSubCA (se tiver mais de um nome, pôr entre asps duplas) : " dep

openssl req -config /root/myCA/openssl_intermediate.cnf -key /root/myCA/intermediateCA/private/RootSubCA.key -new -sha256 -out /root/myCA/intermediateCA/certs/RootSubCA.csr -subj "/C=BR/ST=Sergipe/L=Aracaju/O="${org}"/OU=\"${dep}\"/CN=RootSubCA"

#----------------------------------------------------------
# Sign the intermediate CSR with the root CA key:

openssl ca -config /root/myCA/openssl_root.cnf -extensions v3_intermediate_ca -days 3650 -notext -md sha256 -in /root/myCA/intermediateCA/certs/RootSubCA.csr -out /root/myCA/intermediateCA/certs/RootSubCA.crt
#----------------------------------------------------------
# Assign 444 permission to the CRT to make it readable by everyone:

chmod 444 /root/myCA/intermediateCA/certs/RootSubCA.crt

#==========================================================

# Step 5: Generate OpenSSL Create Certificate Chain (Certificate Bundle)
#----------------------------------------------------------
# I have combined my Root and Intermediate CA certificates to openssl create certificate chain in Linux:

cat /root/myCA/intermediateCA/certs/RootSubCA.crt /root/myCA/rootCA/certs/RootCA.crt > /root/myCA/intermediateCA/certs/RootCA-RootSubCA-chain.crt
#----------------------------------------------------------
# After openssl create certificate chain, to verify certificate chain use below command:

openssl verify -CAfile /root/myCA/intermediateCA/certs/RootCA-RootSubCA-chain.crt /root/myCA/intermediateCA/certs/RootSubCA.crt
