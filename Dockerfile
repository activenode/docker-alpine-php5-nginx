FROM nginx:1.13.8-alpine
LABEL maintainer="David Lorenz <info@activenode.de>"

#Configure Nginx:
RUN \
    #to output logging info to Docker-Logs
    ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log


RUN echo '@community http://dl-cdn.alpinelinux.org/alpine/edge/community' >> /etc/apk/repositories
RUN apk update

# Install runit, nginx, php, PEAR, and php-fpm
RUN apk add     \
        ca-certificates             \
        curl                        \
        php5-common                  \
        php5-pdo                     \
        php5-pdo_mysql               \
        php5-curl                    \
        php5-iconv                   \
        php5-ctype                   \
        php5-json                    \
        php5-mcrypt                  \
        php5-openssl                 \
        php5-opcache                 \
        php5-pear                    \
        php5-phar                    \
        php5-mysql                   \
        php5-mysqli                  \
        php5-imagick                 \
        php5-apcu                    \
        php5-fpm                     \
        runit@community          && \
    curl -sS https://getcomposer.org/installer | \
    php -- --install-dir=/usr/local/bin --filename=composer 

RUN rm -rf /var/cache/apk/*



# Configure system:
#   - Add 'php' user and group to run as
# Configure nginx:
#   - Copy config file into place
# Configure php:
#   - Don't fix path info
# Configure php-fpm:
#   - Listen on a unix socket
#   - Fix permissions on socket
#   - No limits on allowed clients
#   - Do not catch worker outputs
#   - No error logging
#   - Do not daemonize
# Configure runit:
#   - Create service directories for everything
RUN echo "** Configuring system" && \
    addgroup -g 1001 php && \
    adduser                 \
        -D                  \
        -u 1001             \
        -G php              \
        -s /bin/sh          \
        php              && \
    echo "** Configuring PHP" && \
    sed -i -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" /etc/php5/php.ini && \
    echo "** Configuring PHP-FPM" && \
    sed -e 's|^listen\s*=.*$|listen = /var/run/php-fpm.sock|g'     \
            -e 's/;listen.mode = 0660/listen.mode = 0666/g' \
            -e '/allowed_clients/d'                             \
            -e 's/user\s*=\s*nobody/user = php/'            \
            -e 's/group\s*=\s*nobody/group = php/'          \
            -e '/catch_workers_output/s/^;//'               \
            -e '/error_log/d'                               \
            -e 's/;daemonize\s*=\s*yes/daemonize = no/g'    \
            -i /etc/php5/php-fpm.conf

# Write service files in place
RUN mkdir -p /etc/sv/php-fpm && \
    echo '#!/bin/sh' > /etc/sv/php-fpm/run && \
    echo 'exec 2>&1' >> /etc/sv/php-fpm/run && \
    echo 'exec /usr/bin/php-fpm --nodaemonize' >> /etc/sv/php-fpm/run && \
    chmod +x /etc/sv/php-fpm/run

RUN echo '** Enabling services' && \
    chmod -R 777 /etc/sv/php-fpm && \
    ln -s /etc/sv/php-fpm /etc/service/php-fpm


RUN mkdir -p /var/www/app/webroot && \
    echo '<?php' > /var/www/app/webroot/index.php && \
    echo 'phpinfo(); ' >> /var/www/app/webroot/index.php

# Copy config files
COPY defaultsettings_custom_pre.conf /etc/nginx/custom_conf/defaultsettings_custom_pre.conf
COPY nginx_default.conf /etc/nginx/conf.d/default.conf

RUN mkdir -p /home && \
    echo '#!/bin/sh' > /home/container-run.sh && \
    echo "echo '*** Container started ***'" >> /home/container-run.sh && \
    echo 'runsvdir -P /etc/service &' >> /home/container-run.sh && \
    echo 'echo "*** Service started ***"' >> /home/container-run.sh && \
    echo 'nginx -g "daemon off;"' >> /home/container-run.sh && chmod +x /home/container-run.sh

EXPOSE 80

CMD /home/container-run.sh