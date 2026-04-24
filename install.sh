#!/bin/bash

# Скрипт автоматической установки Zapret SOCKS Proxy

set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

print_header() {
    clear
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Zapret SOCKS Proxy - Установка${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

check_root() {
    if [ "$EUID" -eq 0 ]; then
        log_warn "Скрипт запущен от root. Рекомендуется запускать от обычного пользователя."
        read -p "Продолжить? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

check_dependencies() {
    log_info "Проверка зависимостей..."
    
    local missing_deps=()
    
    # Проверка Docker
    if ! command -v docker &> /dev/null; then
        missing_deps+=("docker")
    fi
    
    # Проверка docker-compose
    if ! command -v docker-compose &> /dev/null; then
        missing_deps+=("docker-compose")
    fi
    
    # Проверка curl
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Отсутствуют зависимости: ${missing_deps[*]}"
        echo ""
        log_info "Установка зависимостей..."
        
        # Определение ОС
        if [ -f /etc/debian_version ]; then
            log_info "Обнаружена Debian/Ubuntu"
            sudo apt-get update
            
            for dep in "${missing_deps[@]}"; do
                case $dep in
                    docker)
                        log_info "Установка Docker..."
                        curl -fsSL https://get.docker.com -o get-docker.sh
                        sudo sh get-docker.sh
                        sudo usermod -aG docker $USER
                        rm get-docker.sh
                        ;;
                    docker-compose)
                        log_info "Установка docker-compose..."
                        sudo apt-get install -y docker-compose
                        ;;
                    curl)
                        log_info "Установка curl..."
                        sudo apt-get install -y curl
                        ;;
                esac
            done
            
            log_success "Зависимости установлены"
            log_warn "Необходимо перелогиниться для применения изменений группы docker"
            log_info "Выполните: newgrp docker"
            
        elif [ -f /etc/redhat-release ]; then
            log_info "Обнаружена RedHat/CentOS/Fedora"
            
            for dep in "${missing_deps[@]}"; do
                case $dep in
                    docker)
                        log_info "Установка Docker..."
                        curl -fsSL https://get.docker.com -o get-docker.sh
                        sudo sh get-docker.sh
                        sudo usermod -aG docker $USER
                        sudo systemctl start docker
                        sudo systemctl enable docker
                        rm get-docker.sh
                        ;;
                    docker-compose)
                        log_info "Установка docker-compose..."
                        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
                        sudo chmod +x /usr/local/bin/docker-compose
                        ;;
                    curl)
                        log_info "Установка curl..."
                        sudo yum install -y curl
                        ;;
                esac
            done
            
            log_success "Зависимости установлены"
            
        else
            log_error "Неизвестная ОС. Установите зависимости вручную:"
            echo "  - Docker: https://docs.docker.com/engine/install/"
            echo "  - docker-compose: https://docs.docker.com/compose/install/"
            echo "  - curl"
            exit 1
        fi
    else
        log_success "Все зависимости установлены"
    fi
    
    echo ""
}

check_port() {
    local port=$1
    
    if netstat -tlnp 2>/dev/null | grep -q ":$port " || ss -tlnp 2>/dev/null | grep -q ":$port "; then
        log_warn "Порт $port уже используется"
        return 1
    fi
    
    return 0
}

configure_installation() {
    log_info "Конфигурация установки..."
    echo ""
    
    # Порт SOCKS
    read -p "Порт SOCKS-прокси [1181]: " SOCKS_PORT
    SOCKS_PORT=${SOCKS_PORT:-1181}
    
    if ! check_port $SOCKS_PORT; then
        log_error "Порт $SOCKS_PORT занят. Выберите другой порт."
        exit 1
    fi
    
    # Стратегия
    echo ""
    log_info "Выберите стратегию обхода DPI:"
    echo "  1) split2 (базовая, рекомендуется)"
    echo "  2) disorder"
    echo "  3) fake"
    echo "  4) fake+split2 (комбинированная)"
    echo "  5) aggressive (агрессивная)"
    echo "  6) custom (ввести вручную)"
    echo ""
    read -p "Выбор [1]: " STRATEGY_CHOICE
    STRATEGY_CHOICE=${STRATEGY_CHOICE:-1}
    
    case $STRATEGY_CHOICE in
        1)
            NFQWS_ARGS="--dpi-desync=split2 --dpi-desync-split-pos=2"
            ;;
        2)
            NFQWS_ARGS="--dpi-desync=disorder --dpi-desync-split-pos=2"
            ;;
        3)
            NFQWS_ARGS="--dpi-desync=fake --dpi-desync-ttl=5"
            ;;
        4)
            NFQWS_ARGS="--dpi-desync=fake,split2 --dpi-desync-ttl=4 --dpi-desync-split-pos=2"
            ;;
        5)
            NFQWS_ARGS="--dpi-desync=fake,split2 --dpi-desync-ttl=4 --dpi-desync-fooling=badsum --dpi-desync-split-pos=2 --dpi-desync-autottl=2"
            ;;
        6)
            read -p "Введите параметры nfqws: " NFQWS_ARGS
            ;;
        *)
            log_error "Неверный выбор"
            exit 1
            ;;
    esac
    
    echo ""
    log_info "Конфигурация:"
    echo "  Порт: $SOCKS_PORT"
    echo "  Стратегия: $NFQWS_ARGS"
    echo ""
}

update_docker_compose() {
    log_info "Обновление docker-compose.yml..."
    
    # Создание резервной копии
    if [ -f docker-compose.yml ]; then
        cp docker-compose.yml docker-compose.yml.backup
        log_info "Создана резервная копия: docker-compose.yml.backup"
    fi
    
    # Обновление портов и переменных окружения
    sed -i "s/- SOCKS_PORT=.*/- SOCKS_PORT=$SOCKS_PORT/" docker-compose.yml
    sed -i "s/- NFQWS_ARGS=.*/- NFQWS_ARGS=$NFQWS_ARGS/" docker-compose.yml
    sed -i "s/\"1181:1181\"/\"$SOCKS_PORT:$SOCKS_PORT\"/" docker-compose.yml
    
    log_success "docker-compose.yml обновлен"
}

build_and_start() {
    log_info "Сборка Docker образа..."
    docker-compose build
    
    log_info "Запуск контейнера..."
    docker-compose up -d
    
    log_info "Ожидание запуска сервисов..."
    sleep 5
    
    # Проверка статуса
    if docker ps | grep -q zapret_socks; then
        log_success "Контейнер запущен успешно"
    else
        log_error "Не удалось запустить контейнер"
        log_info "Проверьте логи: docker-compose logs"
        exit 1
    fi
}

test_proxy() {
    log_info "Тестирование SOCKS-прокси..."
    
    if curl -x socks5://localhost:$SOCKS_PORT -s -o /dev/null -w "%{http_code}" --max-time 10 https://ifconfig.me | grep -q "200"; then
        log_success "SOCKS-прокси работает!"
        
        echo ""
        log_info "Ваш IP через прокси:"
        curl -x socks5://localhost:$SOCKS_PORT -s https://ifconfig.me
        echo ""
    else
        log_warn "Не удалось протестировать прокси"
        log_info "Попробуйте вручную: curl -x socks5://localhost:$SOCKS_PORT https://ifconfig.me"
    fi
}

print_summary() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Установка завершена!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${BLUE}SOCKS-прокси доступен:${NC}"
    echo -e "  Адрес: ${YELLOW}localhost${NC} (или IP вашего сервера)"
    echo -e "  Порт: ${YELLOW}$SOCKS_PORT${NC}"
    echo -e "  Тип: ${YELLOW}SOCKS5${NC}"
    echo ""
    echo -e "${BLUE}Полезные команды:${NC}"
    echo -e "  Логи:        ${YELLOW}docker-compose logs -f${NC}"
    echo -e "  Остановка:   ${YELLOW}docker-compose down${NC}"
    echo -e "  Перезапуск:  ${YELLOW}docker-compose restart${NC}"
    echo -e "  Статус:      ${YELLOW}docker-compose ps${NC}"
    echo ""
    echo -e "${BLUE}Тестирование:${NC}"
    echo -e "  ${YELLOW}curl -x socks5://localhost:$SOCKS_PORT https://ifconfig.me${NC}"
    echo ""
    echo -e "${BLUE}Документация:${NC}"
    echo -e "  Быстрый старт: ${YELLOW}QUICKSTART.md${NC}"
    echo -e "  Полная:        ${YELLOW}README.md${NC}"
    echo -e "  Стратегии:     ${YELLOW}examples/strategies.md${NC}"
    echo ""
}

main() {
    print_header
    
    check_root
    check_dependencies
    configure_installation
    update_docker_compose
    build_and_start
    test_proxy
    print_summary
}

# Обработка Ctrl+C
trap 'echo ""; log_warn "Установка прервана"; exit 1' INT

main