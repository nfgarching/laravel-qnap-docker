# Bookworm (glibc 2.36) läuft auf dem QNAP-Kernel 5.10.60. Nicht "php:8.4-fpm" ohne
# Suffix verwenden: das ist Trixie (glibc 2.41, nutzt fchmodat2 → "Bad address").
FROM php:8.4-fpm-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        curl \
        unzip \
        libpng-dev \
        libzip-dev \
        libonig-dev \
        libxml2-dev \
        libicu-dev \
        libsqlite3-dev \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        ocrmypdf \
        tesseract-ocr \
        tesseract-ocr-deu \
    && rm -rf /var/lib/apt/lists/* \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install \
        pdo_mysql \
        pdo_sqlite \
        mbstring \
        exif \
        pcntl \
        bcmath \
        intl \
        gd \
        zip \
        ftp

# jbig2-Encoder für ocrmypdf: in Debian Bookworm nicht paketiert (erst ab Trixie),
# daher aus der Quelle bauen. Liefert /usr/local/bin/jbig2.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        build-essential \
        autoconf \
        automake \
        libtool \
        zlib1g-dev \
        libleptonica-dev \
    && git clone --depth 1 --branch 0.29 https://github.com/agl/jbig2enc /tmp/jbig2enc \
    && cd /tmp/jbig2enc \
    && ./autogen.sh \
    && ./configure \
    && make \
    && make install \
    && cd / \
    && rm -rf /tmp/jbig2enc \
    && rm -rf /var/lib/apt/lists/*

# Imagick (für spatie/pdf-to-image). Nicht als Core-Extension gebündelt,
# daher via PECL bauen. Build-Tools (build-essential, autoconf) stammen aus dem
# jbig2-Block oben und sind hier noch vorhanden.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libmagickwand-dev \
    && pecl install imagick \
    && docker-php-ext-enable imagick \
    && rm -rf /var/lib/apt/lists/*

# Debians ImageMagick-Policy blockt den PDF-Coder standardmäßig (Ghostscript-
# RCE-Härtung), wodurch spatie/pdf-to-image (Imagick) an jedem PDF scheitert.
# Für unseren Anwendungsfall (interne, bereits gescannte/erzeugte PDFs) lockern
# wir das gezielt statt den Coder komplett auszuschalten.
RUN sed -i '/pattern="PDF"/s/rights="none"/rights="read|write"/' /etc/ImageMagick-6/policy.xml

# IMAP (z. B. für webklex/php-imap). Seit PHP 8.4 kein
# Core-Modul mehr, daher via PECL. Ohne diese Extension bleibt der
# Fallback-Decoder der Bibliothek wirkungslos und MIME-kodierte Header
# (z.B. "=?UTF-8?Q?J=C3=BCrgen_M=C3=BCller?=") werden nicht aufgelöst.
# Die zwei Konfig-Prompts (Kerberos-/SSL-Support) beantworten wir mit den
# Default-Antworten ("yes").
RUN apt-get update && apt-get install -y --no-install-recommends \
        libc-client2007e-dev \
        libkrb5-dev \
    && printf '\n\n' | pecl install imap \
    && docker-php-ext-enable imap \
    && rm -rf /var/lib/apt/lists/*

# phpredis für Cache, Sessions und Queue über den Service "redis" (REDIS_CLIENT=phpredis).
# Die Konfig-Prompts (igbinary, lzf, zstd, msgpack, lz4) mit den Vorgaben ("no") beantworten.
RUN printf '\n\n\n\n\n' | pecl install redis \
    && docker-php-ext-enable redis

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# PHP-FPM als Host-User laufen lassen, damit Writes in den Bind-Mount
# (storage/, bootstrap/cache/, SQLite-DB) mit den Datei-Eigentümern übereinstimmen.
ARG WWWUSER=1000
ARG WWWGROUP=100
RUN usermod -u ${WWWUSER} www-data \
    && usermod -g ${WWWGROUP} www-data

WORKDIR /var/www/html
