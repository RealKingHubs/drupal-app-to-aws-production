# ============================================================
# Drupal 11 Custom Image
# Built from official PHP 8.3-FPM base (Debian Bookworm)
# PHP-FPM serves PHP. Nginx runs as a separate container.
# ============================================================

FROM php:8.3-fpm-bookworm

# ============================================================
# System dependencies
# ============================================================
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    rsync \
    libpng-dev \
    libjpeg-dev \
    libwebp-dev \
    libfreetype6-dev \
    libzip-dev \
    libxml2-dev \
    libicu-dev \
    libonig-dev \
    libpq-dev \
    default-mysql-client \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# PHP extensions required by Drupal 11
# ============================================================
RUN docker-php-ext-configure gd \
    --with-freetype \
    --with-jpeg \
    --with-webp \
  && docker-php-ext-install -j$(nproc) \
    gd \
    pdo \
    pdo_mysql \
    mysqli \
    zip \
    xml \
    mbstring \
    intl \
    opcache \
    bcmath

# ============================================================
# Composer
# ============================================================
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

# ============================================================
# PHP configuration
# ============================================================
COPY php/php.ini /usr/local/etc/php/conf.d/drupal.ini

# ============================================================
# Drupal application
# Run as www-data so file ownership is correct from the start
# COMPOSER_PROCESS_TIMEOUT increased for slow connections
# ============================================================
WORKDIR /var/www/html

RUN chown www-data:www-data /var/www/html

USER www-data

ENV COMPOSER_PROCESS_TIMEOUT=600

RUN composer create-project drupal/recommended-project:^11 . \
    --no-interaction \
    --prefer-dist

RUN composer require drush/drush --no-interaction

# ============================================================
# File permissions
# ============================================================
RUN mkdir -p web/sites/default/files \
    && chmod 775 web/sites/default/files

EXPOSE 9000

CMD ["php-fpm"]
