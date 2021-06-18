FROM php:8-fpm-alpine as base-bedrock

RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
ADD https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar wp-cli.phar

RUN set -ex; \
  apk add --no-cache --virtual .build-deps \
    freetype-dev \
    libzip-dev \
    libjpeg-turbo-dev \
    libpng-dev \
  ; \
  docker-php-ext-configure gd --with-freetype --with-jpeg; \
  docker-php-ext-install -j$(nproc) gd mysqli opcache zip; \
  \
  runDeps="$( \
    scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
      | tr ',' '\n' \
      | sort -u \
      | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
  )"; \
  apk add --virtual .wordpress-phpexts-rundeps $runDeps; \
  apk del .build-deps; \
  { \
    echo 'opcache.memory_consumption=128'; \
    echo 'opcache.interned_strings_buffer=8'; \
    echo 'opcache.max_accelerated_files=4000'; \
    echo 'opcache.revalidate_freq=2'; \
    echo 'opcache.fast_shutdown=1'; \
    echo 'opcache.enable_cli=1'; \
  } > /usr/local/etc/php/conf.d/opcache-recommended.ini; \
  { \
    echo 'error_reporting = 4339'; \
    echo 'display_errors = Off'; \
    echo 'display_startup_errors = Off'; \
    echo 'log_errors = On'; \
    echo 'error_log = /dev/stderr'; \
    echo 'log_errors_max_len = 1024'; \
    echo 'ignore_repeated_errors = On'; \
    echo 'ignore_repeated_source = Off'; \
    echo 'html_errors = Off'; \
  } > /usr/local/etc/php/conf.d/error-logging.ini; \
  export EXPECTED_CHECKSUM="$(php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')"; \
  export ACTUAL_CHECKSUM="$(php -r 'echo hash_file("sha384", "composer-setup.php");')"; \
  [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ] || php composer-setup.php; \
  chmod 755 wp-cli.phar && mv wp-cli.phar /usr/local/bin/wp; \
  rm composer-setup.php; \
  mv composer.phar /usr/local/bin/composer;

FROM base-bedrock as bedrock

RUN set -ex; \
  mkdir /www; \
  cd /www && composer create-project roots/bedrock webroot && cd webroot && composer require roots/wp-password-bcrypt && rm composer.lock && rm -rf vendor; \
  chown -R www-data:www-data /www

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint

USER www-data

ENTRYPOINT [ "docker-entrypoint" ]

WORKDIR /www/webroot

CMD [ "php-fpm" ]
