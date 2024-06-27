#!/bin/bash

# Definir a versão específica do GLPI
VERSION="10.0.15"

# Configurar o fuso horário
if [[ -z "$TIMEZONE" ]]; then
    echo "O TIMEZONE não está definido"
else
    PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
    echo "date.timezone = \"$TIMEZONE\"" > /etc/php/$PHP_VERSION/apache2/conf.d/timezone.ini
    echo "date.timezone = \"$TIMEZONE\"" > /etc/php/$PHP_VERSION/cli/conf.d/timezone.ini
    rm /etc/localtime && ln -s /usr/share/zoneinfo/$TIMEZONE /etc/localtime
fi

# Configurar o tamanho máximo de upload
if [[ -z "$UPLOAD_MAX_FILESIZE" ]]; then
    php /opt/default_upload_max_filesize.php
else
    PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
    sed -i "s/2M/$UPLOAD_MAX_FILESIZE/" /etc/php/$PHP_VERSION/apache2/php.ini
    sed -i "s/2M/$UPLOAD_MAX_FILESIZE/" /etc/php/$PHP_VERSION/cli/php.ini
    sed -i "s/2M/$UPLOAD_MAX_FILESIZE/" /usr/lib/php/$PHP_VERSION/php.ini-development
    sed -i "s/2M/$UPLOAD_MAX_FILESIZE/" /usr/lib/php/$PHP_VERSION/php.ini-production
    sed -i "s/2M/$UPLOAD_MAX_FILESIZE/" /usr/lib/php/$PHP_VERSION/php.ini-production.cli
    php /opt/change_upload_max_filesize.php
fi

# Configurar o tamanho máximo de POST
if [[ -z "$POST_MAX_FILESIZE" ]]; then
    echo "O POST_MAX_FILESIZE não está definido"
else
    PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
    sed -i "s/post_max_size = 8M/post_max_size = $POST_MAX_FILESIZE/" /etc/php/$PHP_VERSION/apache2/php.ini
    sed -i "s/post_max_size = 8M/post_max_size = $POST_MAX_FILESIZE/" /etc/php/$PHP_VERSION/cli/php.ini
    sed -i "s/post_max_size = 8M/post_max_size = $POST_MAX_FILESIZE/" /usr/lib/php/$PHP_VERSION/php.ini-development
    sed -i "s/post_max_size = 8M/post_max_size = $POST_MAX_FILESIZE/" /usr/lib/php/$PHP_VERSION/php.ini-production
    sed -i "s/post_max_size = 8M/post_max_size = $POST_MAX_FILESIZE/" /usr/lib/php/$PHP_VERSION/php.ini-production.cli
fi

# Configurar a segurança das sessões
PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
echo "session.cookie_httponly = on" >> /etc/php/$PHP_VERSION/apache2/php.ini
echo "session.cookie_httponly = on" >> /etc/php/$PHP_VERSION/cli/php.ini

# Definir o link de download do GLPI para a versão específica
LINK_GLPI="https://github.com/glpi-project/glpi/releases/download/$VERSION/glpi-$VERSION.tgz"
if [[ -z "$LINK_GLPI" ]]; then
    echo "Erro ao obter o link de download do GLPI."
    exit 1
fi

# Ajustando TLS LDAP
if ! grep -q "TLS_REQCERT" /etc/ldap/ldap.conf; then
    echo -e "TLS_REQCERT\tnever" >> /etc/ldap/ldap.conf
fi

# Extraindo o instalador do GLPI
if [ -z "$(ls -A /var/www/html/public)" ]; then
    wget -q $LINK_GLPI --output-document=/tmp/glpi.tar.gz
    tar -zxf /tmp/glpi.tar.gz -C /tmp
    mkdir -p /var/www/html/public
    mv /tmp/glpi/* /var/www/html/public/
    mv /tmp/glpi/.* /var/www/html/public/ || true
    rm -rf /tmp/glpi*
    chown -R www-data:www-data /var/www/html/public/
else
    echo "O GLPI já se encontra instalado"
fi

# Configurar diretórios de dados do GLPI
mkdir -p /var/glpi/files
mkdir -p /var/glpi/config
chown -R www-data:www-data /var/glpi/files /var/glpi/config

# Criar links simbólicos para os diretórios de dados
ln -s /var/glpi/files /var/www/html/public/files
ln -s /var/glpi/config /var/www/html/public/config

# Adicionando regra no crontab para forçar o script PHP a rodar
echo '*/2 * * * * www-data /usr/bin/php /var/www/html/public/front/cron.php 2>&- 1>&-' >> /etc/cron.d/glpi

# Subindo o crontrab
service cron start

# Subindo o Apache
/usr/sbin/apache2ctl -D FOREGROUND
