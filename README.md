# Zapret SOCKS Proxy Docker Container

Docker-контейнер на базе [zapret](https://github.com/bol-van/zapret), работающий как SOCKS-прокси с обходом DPI через nfqws.

## Архитектура

```
Клиент (sing-box/другой) → SOCKS Proxy (tpws:1181) → iptables NFQUEUE → nfqws (модификация пакетов) → Интернет
```

### Как это работает:

1. **tpws** принимает SOCKS-соединения на порту 1181
2. **tpws** создает новые TCP-пакеты для отправки в интернет (работает от имени пользователя `tpws`)
3. **iptables** перехватывает исходящий трафик от пользователя `tpws` и направляет в NFQUEUE
4. **nfqws** обрабатывает пакеты из очереди, модифицирует их (split, disorder, fake и т.д.)
5. Модифицированные пакеты уходят в интернет через сетевой интерфейс контейнера

## Быстрый старт

### 1. Сборка и запуск

```bash
docker-compose up -d
```

### 2. Проверка работы

```bash
# Просмотр логов
docker-compose logs -f zapret

# Проверка статуса
docker-compose ps

# Тест SOCKS-прокси
curl -x socks5://localhost:1181 https://ifconfig.me
```

### 3. Остановка

```bash
docker-compose down
```

## Конфигурация

### Переменные окружения

Все параметры настраиваются через переменные окружения в `docker-compose.yml`:

#### Основные параметры

- **SOCKS_PORT** (по умолчанию: `1181`) - порт SOCKS-прокси
- **NFQUEUE_NUM** (по умолчанию: `200`) - номер очереди NFQUEUE

#### Параметры nfqws (стратегии обхода DPI)

**NFQWS_ARGS** - параметры для nfqws. Примеры:

```yaml
# Базовая стратегия - разделение на 2 части
NFQWS_ARGS: --dpi-desync=split2 --dpi-desync-split-pos=2

# Разделение + изменение порядка
NFQWS_ARGS: --dpi-desync=split2,disorder --dpi-desync-split-pos=2

# Отправка фейковых пакетов
NFQWS_ARGS: --dpi-desync=fake --dpi-desync-ttl=5

# Комбинированная стратегия
NFQWS_ARGS: --dpi-desync=split2 --dpi-desync-split-pos=2 --dpi-desync-ttl=5 --dpi-desync-autottl=2

# Для HTTPS с изменением регистра Host
NFQWS_ARGS: --dpi-desync=split2 --dpi-desync-split-pos=2 --hostcase

# Агрессивная стратегия
NFQWS_ARGS: --dpi-desync=fake,split2 --dpi-desync-ttl=4 --dpi-desync-fooling=badsum --dpi-desync-split-pos=2
```

#### Популярные стратегии обхода

| Стратегия | Описание | Пример |
|-----------|----------|--------|
| `split2` | Разделение пакета на 2 части | `--dpi-desync=split2 --dpi-desync-split-pos=2` |
| `disorder` | Изменение порядка пакетов | `--dpi-desync=disorder` |
| `fake` | Отправка фейковых пакетов | `--dpi-desync=fake --dpi-desync-ttl=5` |
| `split2,disorder` | Комбинация разделения и беспорядка | `--dpi-desync=split2,disorder` |
| `--hostcase` | Изменение регистра Host: заголовка | `--hostcase` |
| `--hostnospace` | Удаление пробела после Host: | `--hostnospace` |
| `--dpi-desync-ttl` | Установка TTL для десинхронизации | `--dpi-desync-ttl=5` |
| `--dpi-desync-autottl` | Автоматический TTL | `--dpi-desync-autottl=2` |

#### Параметры tpws

**TPWS_ARGS** - параметры для tpws:

```yaml
# Базовый SOCKS-прокси
TPWS_ARGS: --socks --port=1181

# SOCKS с изменением регистра Host
TPWS_ARGS: --socks --port=1181 --hostcase

# SOCKS с дополнительными опциями
TPWS_ARGS: --socks --port=1181 --hostcase --split-pos=2
```

#### Дополнительные правила iptables

**IPTABLES_EXTRA** - дополнительные команды iptables:

```yaml
# Блокировка определенного IP
IPTABLES_EXTRA: iptables -A OUTPUT -d 8.8.8.8 -j DROP

# Несколько правил (разделяются точкой с запятой)
IPTABLES_EXTRA: iptables -A OUTPUT -d 8.8.8.8 -j DROP; iptables -A OUTPUT -d 1.1.1.1 -j DROP
```

## Интеграция с sing-box

### Пример конфигурации sing-box

Создайте файл `sing-box-config.json`:

```json
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "::",
      "listen_port": 1080
    }
  ],
  "outbounds": [
    {
      "type": "socks",
      "tag": "zapret-proxy",
      "server": "zapret",
      "server_port": 1181,
      "version": "5"
    },
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "rules": [
      {
        "outbound": "zapret-proxy"
      }
    ]
  }
}
```

Раскомментируйте секцию `sing-box` в `docker-compose.yml` и запустите:

```bash
docker-compose up -d
```

Теперь sing-box будет принимать соединения на порту 1080 и направлять их через zapret SOCKS-прокси.

## Примеры использования

### Тестирование разных стратегий

```bash
# Стратегия 1: split2
docker-compose down
export NFQWS_ARGS="--dpi-desync=split2 --dpi-desync-split-pos=2"
docker-compose up -d
curl -x socks5://localhost:1181 https://example.com

# Стратегия 2: fake
docker-compose down
export NFQWS_ARGS="--dpi-desync=fake --dpi-desync-ttl=5"
docker-compose up -d
curl -x socks5://localhost:1181 https://example.com

# Стратегия 3: комбинированная
docker-compose down
export NFQWS_ARGS="--dpi-desync=fake,split2 --dpi-desync-ttl=4 --dpi-desync-split-pos=2"
docker-compose up -d
curl -x socks5://localhost:1181 https://example.com
```

### Использование с curl

```bash
curl -x socks5://localhost:1181 https://ifconfig.me
curl -x socks5://localhost:1181 https://www.google.com
```

### Использование с браузером

Настройте SOCKS5-прокси в браузере:
- **Адрес**: `localhost` или IP вашего сервера
- **Порт**: `1181`
- **Тип**: SOCKS5

### Использование с другими приложениями

Любое приложение, поддерживающее SOCKS5-прокси, может использовать zapret:

```bash
# Telegram Desktop
telegram-desktop -proxy socks5://localhost:1181

# Git
git config --global http.proxy socks5://localhost:1181

# SSH
ssh -o ProxyCommand="nc -X 5 -x localhost:1181 %h %p" user@host
```

## Отладка

### Просмотр логов

```bash
# Все логи
docker-compose logs -f

# Только zapret
docker-compose logs -f zapret

# Последние 100 строк
docker-compose logs --tail=100 zapret
```

### Проверка правил iptables

```bash
docker exec zapret_socks iptables -t mangle -L OUTPUT -n -v
```

### Проверка процессов

```bash
docker exec zapret_socks ps aux | grep -E 'tpws|nfqws'
```

### Интерактивная оболочка

```bash
docker exec -it zapret_socks /bin/bash
```

## Устранение неполадок

### Контейнер не запускается

1. Проверьте, что Docker запущен в привилегированном режиме или с необходимыми capabilities
2. Убедитесь, что порт 1181 не занят другим приложением
3. Проверьте логи: `docker-compose logs zapret`

### SOCKS-прокси не работает

1. Проверьте, что tpws запущен: `docker exec zapret_socks pgrep tpws`
2. Проверьте, что порт открыт: `netstat -tlnp | grep 1181`
3. Попробуйте другую стратегию обхода DPI

### Медленная скорость

1. Попробуйте более простую стратегию (например, только `split2`)
2. Уменьшите количество модификаций пакетов
3. Проверьте нагрузку на CPU: `docker stats zapret_socks`

## Безопасность

- Контейнер работает в привилегированном режиме для доступа к iptables
- tpws запускается от отдельного пользователя для изоляции
- Рекомендуется использовать firewall для ограничения доступа к SOCKS-порту
- Не используйте этот прокси как публичный сервис без дополнительной аутентификации

## Производительность

- Контейнер оптимизирован для минимального использования ресурсов
- Multi-stage build уменьшает размер образа
- Используется Debian Slim для минимального footprint

## Лицензия

Этот проект использует [zapret](https://github.com/bol-van/zapret), который распространяется под собственной лицензией.

## Поддержка

Для вопросов по zapret обращайтесь к [оригинальному репозиторию](https://github.com/bol-van/zapret).

## Благодарности

- [bol-van](https://github.com/bol-van) за создание zapret
- Сообществу за тестирование и обратную связь