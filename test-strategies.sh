#!/bin/bash

# Скрипт для автоматического тестирования стратегий обхода DPI

set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Тестовые URL
TEST_URLS=(
    "https://www.youtube.com"
    "https://www.google.com"
    "https://twitter.com"
)

# Стратегии для тестирования
declare -A STRATEGIES
STRATEGIES["split2"]="--dpi-desync=split2 --dpi-desync-split-pos=2"
STRATEGIES["disorder"]="--dpi-desync=disorder --dpi-desync-split-pos=2"
STRATEGIES["fake"]="--dpi-desync=fake --dpi-desync-ttl=5"
STRATEGIES["split2+disorder"]="--dpi-desync=split2,disorder --dpi-desync-split-pos=2"
STRATEGIES["fake+split2"]="--dpi-desync=fake,split2 --dpi-desync-ttl=4 --dpi-desync-split-pos=2"
STRATEGIES["aggressive"]="--dpi-desync=fake,split2 --dpi-desync-ttl=4 --dpi-desync-fooling=badsum --dpi-desync-split-pos=2 --dpi-desync-autottl=2"
STRATEGIES["split2+hostcase"]="--dpi-desync=split2 --dpi-desync-split-pos=2 --hostcase"
STRATEGIES["split2+autottl"]="--dpi-desync=split2 --dpi-desync-split-pos=2 --dpi-desync-autottl=2"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

test_url() {
    local url=$1
    local timeout=10
    
    if curl -x socks5://localhost:1181 -s -o /dev/null -w "%{http_code}" --max-time $timeout "$url" | grep -q "200\|301\|302"; then
        return 0
    else
        return 1
    fi
}

test_strategy() {
    local strategy_name=$1
    local strategy_args=$2
    
    log_info "Тестирование стратегии: ${YELLOW}$strategy_name${NC}"
    log_info "Параметры: $strategy_args"
    
    # Остановка контейнера
    docker-compose down > /dev/null 2>&1
    
    # Установка стратегии через переменную окружения
    export NFQWS_ARGS="$strategy_args"
    
    # Запуск контейнера
    log_info "Запуск контейнера..."
    docker-compose up -d > /dev/null 2>&1
    
    # Ожидание запуска
    sleep 5
    
    # Проверка, что контейнер запущен
    if ! docker ps | grep -q zapret_socks; then
        log_error "Контейнер не запустился"
        return 1
    fi
    
    # Тестирование URL
    local success_count=0
    local total_count=${#TEST_URLS[@]}
    
    for url in "${TEST_URLS[@]}"; do
        echo -n "  Тест $url ... "
        if test_url "$url"; then
            echo -e "${GREEN}OK${NC}"
            ((success_count++))
        else
            echo -e "${RED}FAIL${NC}"
        fi
    done
    
    # Результат
    echo ""
    if [ $success_count -eq $total_count ]; then
        log_success "Стратегия '$strategy_name': ${GREEN}$success_count/$total_count${NC} тестов пройдено"
        return 0
    elif [ $success_count -gt 0 ]; then
        log_warn "Стратегия '$strategy_name': ${YELLOW}$success_count/$total_count${NC} тестов пройдено"
        return 0
    else
        log_error "Стратегия '$strategy_name': ${RED}$success_count/$total_count${NC} тестов пройдено"
        return 1
    fi
}

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Zapret Strategy Tester${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_summary() {
    local working_strategies=("$@")
    
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Результаты тестирования${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ ${#working_strategies[@]} -eq 0 ]; then
        log_error "Ни одна стратегия не работает"
    else
        log_success "Работающие стратегии:"
        for strategy in "${working_strategies[@]}"; do
            echo -e "  ${GREEN}•${NC} $strategy"
        done
    fi
    
    echo ""
}

main() {
    print_header
    
    # Проверка зависимостей
    log_info "Проверка зависимостей..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker не установлен"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        log_error "docker-compose не установлен"
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        log_error "curl не установлен"
        exit 1
    fi
    
    log_success "Все зависимости установлены"
    echo ""
    
    # Массив для хранения работающих стратегий
    working_strategies=()
    
    # Тестирование каждой стратегии
    for strategy_name in "${!STRATEGIES[@]}"; do
        strategy_args="${STRATEGIES[$strategy_name]}"
        
        if test_strategy "$strategy_name" "$strategy_args"; then
            working_strategies+=("$strategy_name")
        fi
        
        echo ""
        echo -e "${BLUE}───────────────────────────────────────────────────────────${NC}"
        echo ""
    done
    
    # Остановка контейнера
    log_info "Остановка контейнера..."
    docker-compose down > /dev/null 2>&1
    
    # Вывод итогов
    print_summary "${working_strategies[@]}"
    
    # Рекомендация
    if [ ${#working_strategies[@]} -gt 0 ]; then
        echo -e "${GREEN}Рекомендация:${NC} Используйте одну из работающих стратегий в docker-compose.yml"
        echo ""
        echo "Пример:"
        echo -e "${YELLOW}environment:${NC}"
        echo -e "${YELLOW}  - NFQWS_ARGS=${STRATEGIES[${working_strategies[0]}]}${NC}"
        echo ""
    fi
}

# Обработка Ctrl+C
trap 'echo ""; log_warn "Тестирование прервано"; docker-compose down > /dev/null 2>&1; exit 1' INT

main