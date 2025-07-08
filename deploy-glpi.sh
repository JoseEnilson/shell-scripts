#!/bin/env bash

# Sai imediatamente se um comando falhar, se uma variável não for definida ou se um pipe falhar
set -euo pipefail 

# Configuração de ambiente
export LANG=C
export LC_ALL=C

echo -e "\nSCRIPT PARA Oracle Linux Server 9.X\n"

echo "Para prosseguir pressione ENTER, ou digite Ctrl + C para cancelar"
read -p ""

echo "Fazendo backup das configuraÃ§Ãµes do SELINUX"
cp /etc/selinux/config /etc/selinux/config.original
echo "Desativando SELINUX"
setenforce 0
echo "SELINUX=disabled" > /etc/selinux/config
echo "SELINUXTYPE=targeted"  >> /etc/selinux/config

echo "Desabilitando o Firewall"
systemctl stop firewalld.service
systemctl disable firewalld.service

sudo dnf update -y
sudo dnf install wget tar policycoreutils-python-utils vim unzip -y
sudo dnf autoremove && sudo dnf clean all
ls -l /etc/localtime
dnf  -y install https://rpms.remirepo.net/enterprise/remi-release-9.3.rpm;
sudo dnf module list php -y;
sudo dnf module enable php:remi-8.2 -y;
sudo dnf -y install httpd;
sudo systemctl enable --now httpd.service;
sudo dnf install php -y
sudo dnf install php-{mbstring,mysqli,xml,cli,ldap,openssl,xmlrpc,pecl-apcu,zip,curl,gd,json,session,imap,intl,zlib,redis} -y;
url=$(wget -qO- https://github.com/glpi-project/glpi/releases/latest | grep -o 'https://github.com/glpi-project/glpi/releases/download/[^"]*' | head -1)
file_name=$(basename "$url")
wget "$url"
sudo mkdir /var/www/ACME;
tar xvf "$file_name" -C /var/www/ACME;
sudo mv -v /var/www/ACME/glpi/files /var/www/ACME/glpi/config /var/www/ACME/;
sudo sed -i 's/\/config/\/..\/config/g' /var/www/ACME/glpi/inc/based_config.php
sudo sed -i 's/\/files/\/..\/files/g' /var/www/ACME/glpi/inc/based_config.php
sudo chown apache:apache /var/www/ACME/glpi -Rf;
sudo chown apache:apache /var/www/ACME/files -Rf;
sudo chown apache:apache /var/www/ACME/config -Rf;
sudo find /var/www/ACME/ -type d -exec chmod 755 {} \;
sudo find /var/www/ACME/ -type f -exec chmod 644 {} \;
sudo semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/ACME(/.*)?";
sudo restorecon -Rv /var/www/ACME;
sudo setsebool -P httpd_can_sendmail 1;
sudo setsebool -P httpd_can_network_connect 1;
sudo setsebool -P httpd_can_network_connect_db 1;
sudo setsebool -P httpd_mod_auth_ntlm_winbind  1;
sudo setsebool -P allow_httpd_mod_auth_ntlm_winbind 1;
sudo sed -i "s/session.cookie_httponly =/session.cookie_httponly = on/"  /etc/php.ini
sudo sed -i "s/;session.cookie_secure =/session.cookie_secure = on/"  /etc/php.ini

cat << EOF >> /etc/httpd/conf/httpd.conf
RewriteEngine On
RewriteCond %{SERVER_PORT} !^443$
RewriteRule (.*) https://%{HTTP_HOST}\$1 [L]
RequestHeader set X-Forwarded-Proto "https"
EOF

sudo dnf install mod_ssl -y
sudo httpd -M 2>| /dev/null | grep ssl
sudo httpd -M 2>| /dev/null | grep rewrite

cat << EOF > /etc/httpd/conf.d/glpi.conf
<VirtualHost *:443>
    ServerName glpi.ch.vlab

    DocumentRoot /var/www/ACME/glpi/public

    # If you want to place GLPI in a subfolder of your site (e.g. your virtual host is serving multiple applications),
    # you can use an Alias directive. If you do this, the DocumentRoot directive MUST NOT target the GLPI directory itself.
    # Alias "/glpi" "/var/www/glpi/public"


                ErrorLog "logs/glpi_error.log"
                CustomLog "logs/glpi_access.log" combined


                SSLEngine on
                SSLCertificateFile      /etc/httpd/ssl/certs/glpi-selfsigned.crt
                SSLCertificateKeyFile   /etc/httpd/ssl/private/glpi-selfsigned.key

    <Directory /var/www/ACME/glpi/public>
                Options -Indexes
                Options -Includes -ExecCGI
        Require all granted

        RewriteEngine On

        # Ensure authorization headers are passed to PHP.
        # Some Apache configurations may filter them and break usage of API, CalDAV, ...
        RewriteCond %{HTTP:Authorization} ^(.+)$
        RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]

        # Redirect all requests to GLPI router, unless file exists.
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteRule ^(.*)$ index.php [QSA,L]

                <IfModule mod_php.c>
        php_value max_execution_time 600
        php_value always_populate_raw_post_data -1
                </IfModule>

    </Directory>

    <Directory /var/www/ACME/config>
        Options -Indexes
        Options -Includes -ExecCGI
        AllowOverride None
        Require all denied
    </Directory>

    <Directory /var/www/ACME/files>
        Options -Indexes
        Options -Includes -ExecCGI
        AllowOverride None
        Require all denied
    </Directory>
</VirtualHost>
EOF

echo "===================================================="
echo -e "\nCONFIGURACAO DO CERTIFICADO AUTOASSINADO\n"
sudo mkdir -p /etc/httpd/ssl/{private,certs}

echo " "
read -p "Informe o nome do Estado: " estado
read -p "Informe o nome da cidade: " cidade
read -p "Informe o nome da sua Organização: " org
read -p "Informe o nome da Unidade Oraganizacional: " ou
read -p "Informe o nome comum do certificado: " cn
read -p "Informe um Email: " email

(
echo BR
echo $estado
echo $cidade
echo $org
echo $ou
echo $cn
echo $email
) | openssl req -x509 -nodes -days 1095 -newkey rsa:2048 -keyout /etc/httpd/ssl/private/glpi-selfsigned.key -out /etc/httpd/ssl/certs/glpi-selfsigned.crt
echo " "

echo "===================================================="
echo -e "\nCONFIGURACAO DO BANCO DE DADOS MARIADB\n"
sudo dnf -y install mariadb-server;

#habilitando e iniciando o serviço
sudo systemctl enable --now mariadb.service ;

#Criando Usuário e Base de Dados MySQL
echo " "
read -p "Informe um nome para a base de dados (database): " databaseName
mysql -e "create database $databaseName character set utf8";


# Criando usuário
read -p "Informe um nome de usuário: " nome
read -s -p "Informe uma senha para o usuário: " senha
mysql -e "create user '$nome'@'localhost' identified by '$senha'";

# Dando privilégios ao usuário
mysql -e "grant all privileges on $databaseName.* to '$nome'@'localhost' with grant option";

# Habilitando suporte ao timezone no MySQL/Mariadb
mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql mysql;

# Permitindo acesso do usuário ao TimeZone
mysql -e "GRANT SELECT ON mysql.time_zone_name TO '$nome'@'localhost';";

# Forçando aplicação dos privilégios
mysql -e "FLUSH PRIVILEGES;";

systemctl restart mysqld httpd;

openssl x509 -in /etc/httpd/ssl/certs/glpi-selfsigned.crt -text -noout

echo "$(hostname -I) $cn" >> /etc/hosts
sudo sed -i "s|glpi.ch.vlab|$cn|g" /etc/httpd/conf.d/glpi.conf

echo -e "\n====================================================================================================\n"
echo -e "\nAcesse a rede e desabilite o IPV6\n"
echo -e "\n        REINICIE O SERVIDOR!!!!\n"
echo -e "\n====================================================================================================\n"
