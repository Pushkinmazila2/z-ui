#!/bin/bash

# Настройка логирования
LOG_LEVEL=${LOG_LEVEL:-debug}

# Цвета для логов
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Файлы для отслеживания клиентов
CLIENT_MAP="/tmp/zapret2_client_map"
LAST_CLIENT_IP="/tmp/zapret2_last_client"
touch "$CLIENT_MAP" "$LAST_CLIENT_IP"

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

log_info() { echo -e "${GREEN}[$(timestamp)] [INFO]${NC} $1"; }
log_debug() { [ "$LOG_LEVEL" = "debug" ] && echo -e "${CYAN}[$(timestamp)] [DEBUG]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[$(timestamp)] [WARN]${NC} $1"; }
log_error() { echo -e "${RED}[$(timestamp)] [ERROR]${NC} $1" >&2; }

# Обработка логов nfqws2
process_nfqws_log() {
    local line="$1"
    # Логируем срабатывание стратегий
    if echo "$line" | grep -qE "(desync|fake|split|disorder|wssize|seqovl)"; then
        echo -e "${MAGENTA}[$(timestamp)] [DPI-ACTIVE]${NC} ${YELLOW}$line${NC}"
    # Логируем хосты
    elif echo "$line" | grep -qE "(hostname|SNI|Host:)"; then
        local host=$(echo "$line" | sed -nE 's/.*(hostname|SNI|Host:)[: ]*([^ ]+).*/\2/p' | head -1)
        echo -e "${BLUE}[$(timestamp)] [TARGET]${NC} Запрос к: ${GREEN}$host${NC}"
    # Логируем ошибки
    elif echo "$line" | grep -qiE "(error|fail|drop)"; then
        log_error "NFQWS: $line"
    fi
}

# Обработка логов Dante (SOCKS5)
process_dante_log() {
    local line="$1"
    if echo "$line" | grep -q "accept.*connection from"; then
        local ip=$(echo "$line" | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
        log_info "New SOCKS5 connection from $ip"
    fi
}

log_info "Starting zapret2 SOCKS5 proxy container"

# Переменные по умолчанию
SOCKS5_PORT=${SOCKS5_PORT:-1080}
NFQUEUE_NUM=${NFQUEUE_NUM:-200}
ZAPRET_CONFIG=${ZAPRET_CONFIG:-/opt/zapret2/config}

# Загрузка конфига
if [ -f "$ZAPRET_CONFIG" ]; then
    log_info "Loading config from $ZAPRET_CONFIG"
    . "$ZAPRET_CONFIG"
else
    log_warn "Config file not found, using defaults"
fi

# Создание пользователя для прокси (Dante)
id -u proxyuser &>/dev/null || adduser -D -H -s /bin/false proxyuser

# Настройка iptables (ВАЖНО для обхода DPI)
log_info "Setting up iptables rules"
iptables -t mangle -F
iptables -F
# 1. Исключаем трафик nfqws2 (от root), чтобы не зациклиться
iptables -t mangle -A OUTPUT -m owner --uid-owner root -j RETURN
# 2. Весь трафик от Dante (proxyuser) отправляем в DPI
iptables -t mangle -A OUTPUT -m owner --uid-owner proxyuser -p tcp -j NFQUEUE --queue-num $NFQUEUE_NUM --queue-bypass
iptables -t mangle -A OUTPUT -m owner --uid-owner proxyuser -p udp -j NFQUEUE --queue-num $NFQUEUE_NUM --queue-bypass
# 3. Разрешаем DNS напрямую
iptables -t mangle -A OUTPUT -p udp --dport 53 -j RETURN

# Конфигурация Dante
cat > /etc/sockd.conf <<EOF
logoutput: stderr
internal: 0.0.0.0 port = $SOCKS5_PORT
external: eth0
clientmethod: none
socksmethod: none
user.privileged: root
user.unprivileged: proxyuser
client pass { from: 0.0.0.0/0 to: 0.0.0.0/0; log: error; }
socks pass { from: 0.0.0.0/0 to: 0.0.0.0/0; log: error; }
EOF

# Сборка опций nfqws2
NFQWS_BASE="--qnum=$NFQUEUE_NUM --lua-init=@/opt/zapret2/lua/zapret-lib.lua --lua-init=@/opt/zapret2/lua/zapret-antidpi.lua"

if [ "$NFQWS2_ENABLE" = "1" ]; then
    log_info "Using custom strategy: $NFQWS2_OPT"
    FINAL_NFQWS_OPTS="$NFQWS_BASE $NFQWS2_OPT"
else
    log_info "Using default strategy"
    FINAL_NFQWS_OPTS="$NFQWS_BASE --filter-tcp=80,443 --filter-l7=http,tls --lua-desync=multidisorder:pos=midsld"
fi

# Запуск процессов
log_info "Launching services..."

# 1. NFQWS2
( /usr/local/bin/nfqws2 -v $FINAL_NFQWS_OPTS 2>&1 | while read -r line; do process_nfqws_log "$line"; done ) &
NFQWS_PID=$!

# 2. Dante
( sockd -f /etc/sockd.conf -D 2>&1 | while read -r line; do process_dante_log "$line"; done ) &
SOCKS_PID=$!

log_info "✓ zapret2 is ready! Listening on $SOCKS5_PORT"

# Мониторинг (не дает контейнеру упасть)
while true; do
    if ! kill -0 $NFQWS_PID 2>/dev/null; then
        log_error "NFQWS process died! Restarting..."
        ( /usr/local/bin/nfqws2 -v $FINAL_NFQWS_OPTS 2>&1 | while read -r line; do process_nfqws_log "$line"; done ) &
        NFQWS_PID=$!
    fi
    if ! kill -0 $SOCKS_PID 2>/dev/null; then
        log_error "SOCKS5 process died! Restarting..."
        ( sockd -f /etc/sockd.conf -D 2>&1 | while read -r line; do process_dante_log "$line"; done ) &
        SOCKS_PID=$!
    fi
    sleep 10
done
