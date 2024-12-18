FROM --platform=amd64 php:8.2.0-fpm

ARG NEW_RELIC_LICENSE_KEY=$NEW_RELIC_LICENSE_KEY
ARG LICENSE_KEY=$LICENSE_KEY
ENV NEW_RELIC_AGENT_VERSION=10.15.0.4
ENV NEW_RELIC_LICENSE_KEY=$NEW_RELIC_LICENSE_KEY
ENV NEW_RELIC_APPNAME=socialpost
ENV TZ=UTC
ENV COMPOSER_ALLOW_SUPERUSER=1
RUN apt-get update && apt-get install -y --no-install-recommends \
    redis-tools \
    nginx \
    software-properties-common \
    supervisor \
    zip \
    unzip \
    git \
    cron \
    redis-tools \
    ca-certificates \
    lsb-release \
    zlib1g-dev \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libjpeg62-turbo-dev \
    ffmpeg \
    software-properties-common
WORKDIR /var/www/html
COPY --from=composer/composer:latest-bin /composer /usr/bin/composer
RUN docker-php-ext-configure gd --with-freetype --with-jpeg
RUN pecl install redis
RUN docker-php-ext-enable redis
RUN docker-php-ext-install pcntl \
    mysqli \
    pdo pdo_mysql \
    gd
COPY docker-conf/default.conf /etc/nginx/sites-available/default
COPY docker-conf/php.ini /usr/local/etc/php/conf.d/99-app.ini
COPY docker-conf/supervisord.conf /etc/supervisor/supervisord.conf
COPY docker-conf/start.sh /usr/local/bin/start.sh
COPY docker-conf/wait-for-it.sh /usr/local/bin/wait-for-it.sh
COPY docker-conf/php-fpm.conf /usr/local/etc/php-fpm.conf
RUN mkdir /root/.composer
RUN curl -L https://download.newrelic.com/php_agent/archive/${NEW_RELIC_AGENT_VERSION}/newrelic-php5-${NEW_RELIC_AGENT_VERSION}-linux.tar.gz | tar -C /tmp -zx \
    && export NR_INSTALL_USE_CP_NOT_LN=1 \
    && export NR_INSTALL_SILENT=1 \
    && /tmp/newrelic-php5-${NEW_RELIC_AGENT_VERSION}-linux/newrelic-install install \
    && rm -rf /tmp/newrelic-php5-* /tmp/nrinstall*

RUN sed -i -e "s/REPLACE_WITH_REAL_KEY/${NEW_RELIC_LICENSE_KEY}/" \
    -e "s/newrelic.appname[[:space:]]=[[:space:]].*/newrelic.appname=\"${NEW_RELIC_APPNAME}\"/" \
    -e '$anewrelic.daemon.address="localhost:31339"' \
    $(php -r "echo(PHP_CONFIG_FILE_SCAN_DIR);")/newrelic.ini
RUN sed -i 's/listen = 127.0.0.1:9000/listen = \/usr\/local\/var\/run\/php-fpm.sock/' /usr/local/etc/php-fpm.d/www.conf
RUN sed -i 's/listen = 9000/listen = \/usr\/local\/var\/run\/php-fpm.sock/' /usr/local/etc/php-fpm.d/zz-docker.conf
RUN echo "listen.mode = 0666" >> /usr/local/etc/php-fpm.d/zz-docker.conf
RUN echo '{"http-basic": {"packages.inovector.com": {"username": "username","password": "'$LICENSE_KEY'"}}}' > /root/.composer/auth.json
RUN echo "newrelic.error_collector.capture_events = true" > /usr/local/etc/php/conf.d/post_max_size.ini
RUN echo "newrelic.error_collector.enabled = true" > /usr/local/etc/php/conf.d/post_max_size.ini
RUN echo "newrelic.application_logging.enabled = true" >> /usr/local/etc/php/conf.d/newrelic.ini
RUN echo "newrelic.application_logging.forwarding.enabled = true" >> /usr/local/etc/php/conf.d/newrelic.ini
COPY . .
RUN composer update
RUN touch /var/log/cron.log
RUN chmod 0644 /etc/cron.d/* && \
    usermod -aG crontab www-data && \
    chmod u+s /usr/sbin/cron && \
    echo "* * * * * www-data cd /var/www/html && php artisan schedule:run " >> /etc/crontab
EXPOSE 80
ENTRYPOINT ["start.sh"]
