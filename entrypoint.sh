#!/bin/bash
set -e

# Цвета для логов
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Переменные окружения с значениями по умолчанию
SOCKS_PORT="${SOCKS_PORT:-1181}"
NFQUEUE_NUM="${NFQUEUE_NUM:-200}"

# Параметры nfqws (стратегии обхода DPI)
NFQWS_ARGS="${NFQWS_ARGS:---dpi-desync=split2 --dpi-desync-split-pos=2}"

# Параметры tpws
TPWS_ARGS="${TPWS_ARGS:---socks --port=$SOCKS_PORT}"

# Дополнительные параметры iptables
IPTABLES_EXTRA="${IPTABLES_EXTRA:-}"

log_info "Запуск Zapret SOCKS Proxy Container"
log_info "SOCKS порт: $SOCKS_PORT"
log_info "NFQUEUE номер: $NFQUEUE_NUM"
log_info "nfqws параметры: $NFQWS_ARGS"
log_info "tpws параметры: $TPWS_ARGS"

# Функция очистки при завершении
cleanup() {
    log_info "Остановка сервисов..."
    
    # Остановка процессов
    if [ ! -z "$NFQWS_PID" ]; then
        kill $NFQWS_PID 2>/dev/null || true
    fi
    if [ ! -z "$TPWS_PID" ]; then
        kill $TPWS_PID 2>/dev/null || true
    fi
    
    # Очистка правил iptables
    log_info "Очистка правил iptables..."
    iptables -t mangle -D OUTPUT -p tcp -m owner --uid-owner tpws -j NFQUEUE --queue-num $NFQUEUE_NUM 2>/dev/null || true
    iptables -t mangle -D OUTPUT -p udp -m owner --uid-owner tpws -j NFQUEUE --queue-num $NFQUEUE_NUM 2>/dev/null || true
    
    log_info "Контейнер остановлен"
    exit 0
}

trap cleanup SIGTERM SIGINT SIGQUIT

# Создание пользователя tpws для изоляции трафика
if ! id -u tpws > /dev/null 2>&1; then
    log_info "Создание пользователя tpws..."
    useradd -r -s /bin/false tpws
fi

# Настройка iptables для перенаправления трафика в NFQUEUE
log_info "Настройка правил iptables..."

# Очистка существующих правил (на всякий случай)
iptables -t mangle -D OUTPUT -p tcp -m owner --uid-owner tpws -j NFQUEUE --queue-num $NFQUEUE_NUM 2>/dev/null || true
iptables -t mangle -D OUTPUT -p udp -m owner --uid-owner tpws -j NFQUEUE --queue-num $NFQUEUE_NUM 2>/dev/null || true

# Перенаправление исходящего TCP трафика от tpws в NFQUEUE
iptables -t mangle -A OUTPUT -p tcp -m owner --uid-owner tpws -j NFQUEUE --queue-num $NFQUEUE_NUM

# Опционально: перенаправление UDP трафика (если нужно)
if echo "$NFQWS_ARGS" | grep -q "udp"; then
    log_info "Включено перенаправление UDP трафика"
    iptables -t mangle -A OUTPUT -p udp -m owner --uid-owner tpws -j NFQUEUE --queue-num $NFQUEUE_NUM
fi

# Применение дополнительных правил iptables
if [ ! -z "$IPTABLES_EXTRA" ]; then
    log_info "Применение дополнительных правил iptables..."
    eval "$IPTABLES_EXTRA"
fi

# Вывод текущих правил iptables
log_info "Текущие правила iptables (mangle OUTPUT):"
iptables -t mangle -L OUTPUT -n -v

# Запуск nfqws для обработки пакетов из NFQUEUE
log_info "Запуск nfqws..."
nfqws --qnum=$NFQUEUE_NUM $NFQWS_ARGS &
NFQWS_PID=$!

# Проверка запуска nfqws
sleep 1
if ! kill -0 $NFQWS_PID 2>/dev/null; then
    log_error "Не удалось запустить nfqws"
    exit 1
fi
log_info "nfqws запущен (PID: $NFQWS_PID)"

# Запуск tpws в режиме SOCKS-прокси от имени пользователя tpws
log_info "Запуск tpws SOCKS-прокси..."
su -s /bin/sh tpws -c "tpws $TPWS_ARGS" &
TPWS_PID=$!

# Проверка запуска tpws
sleep 1
if ! kill -0 $TPWS_PID 2>/dev/null; then
    log_error "Не удалось запустить tpws"
    cleanup
    exit 1
fi
log_info "tpws запущен (PID: $TPWS_PID)"

log_info "Zapret SOCKS Proxy готов к работе на порту $SOCKS_PORT"
log_info "Для остановки нажмите Ctrl+C"

# Ожидание завершения процессов
wait $NFQWS_PID $TPWS_PID