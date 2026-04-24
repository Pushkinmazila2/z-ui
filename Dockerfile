# Multi-stage build для минимизации размера образа
FROM debian:bookworm-slim AS builder

# Установка зависимостей для сборки
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    libnetfilter-queue-dev \
    libnfnetlink-dev \
    libmnl-dev \
    libcap-ng-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Клонирование репозитория zapret
WORKDIR /build
RUN git clone --depth 1 https://github.com/bol-van/zapret.git .

# Сборка бинарников
RUN make

# Финальный образ
FROM debian:bookworm-slim

# Установка runtime зависимостей
RUN apt-get update && apt-get install -y \
    iptables \
    libnetfilter-queue1 \
    libnfnetlink0 \
    libmnl0 \
    libcap-ng0 \
    zlib1g \
    && rm -rf /var/lib/apt/lists/*

# Копирование скомпилированных бинарников
COPY --from=builder /build/binaries/my/nfqws /usr/local/bin/
COPY --from=builder /build/binaries/my/tpws /usr/local/bin/
COPY --from=builder /build/binaries/my/mdig /usr/local/bin/

# Создание директории для конфигурации
RUN mkdir -p /opt/zapret

# Копирование entrypoint скрипта
COPY entrypoint.sh /opt/zapret/
RUN chmod +x /opt/zapret/entrypoint.sh

# Открытие порта SOCKS-прокси
EXPOSE 1181

# Запуск entrypoint
ENTRYPOINT ["/opt/zapret/entrypoint.sh"]