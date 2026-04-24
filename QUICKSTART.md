# Быстрый старт Zapret SOCKS Proxy

## За 3 минуты

### 1. Клонирование и запуск

```bash
# Клонируйте репозиторий (или скопируйте файлы)
git clone <your-repo-url>
cd zapret-docker

# Запустите контейнер
docker-compose up -d

# Проверьте логи
docker-compose logs -f
```

### 2. Тестирование

```bash
# Проверка работы прокси
curl -x socks5://localhost:1181 https://ifconfig.me

# Проверка доступа к YouTube
curl -x socks5://localhost:1181 https://www.youtube.com
```

### 3. Использование

Настройте ваше приложение на использование SOCKS5-прокси:
- **Адрес**: `localhost` (или IP вашего сервера)
- **Порт**: `1181`
- **Тип**: SOCKS5

## Команды управления

```bash
# Запуск
docker-compose up -d

# Остановка
docker-compose down

# Перезапуск
docker-compose restart

# Логи
docker-compose logs -f

# Статус
docker-compose ps
```

## Использование Makefile (опционально)

```bash
# Показать все команды
make -f Makefile.docker help

# Запуск
make -f Makefile.docker up

# Тест
make -f Makefile.docker test

# Логи
make -f Makefile.docker logs
```

## Смена стратегии обхода DPI

Отредактируйте `docker-compose.yml`:

```yaml
environment:
  # Измените эту строку
  - NFQWS_ARGS=--dpi-desync=split2 --dpi-desync-split-pos=2
```

Популярные стратегии:

```yaml
# Базовая (по умолчанию)
- NFQWS_ARGS=--dpi-desync=split2 --dpi-desync-split-pos=2

# Для сложных DPI
- NFQWS_ARGS=--dpi-desync=fake,split2 --dpi-desync-ttl=4 --dpi-desync-split-pos=2

# Агрессивная
- NFQWS_ARGS=--dpi-desync=fake,split2 --dpi-desync-ttl=4 --dpi-desync-fooling=badsum --dpi-desync-split-pos=2 --dpi-desync-autottl=2
```

После изменения:

```bash
docker-compose down
docker-compose up -d
```

## Автоматическое тестирование стратегий

```bash
# Сделайте скрипт исполняемым
chmod +x test-strategies.sh

# Запустите тестирование
./test-strategies.sh
```

Скрипт автоматически протестирует все популярные стратегии и покажет, какие работают.

## Интеграция с sing-box

1. Создайте `sing-box-config.json` (пример в `examples/sing-box-config.json`)
2. Раскомментируйте секцию `sing-box` в `docker-compose.yml`
3. Запустите:

```bash
docker-compose up -d
```

Теперь sing-box доступен на порту 1080 и использует zapret для обхода блокировок.

## Устранение проблем

### Контейнер не запускается

```bash
# Проверьте логи
docker-compose logs

# Проверьте, что порт свободен
netstat -tlnp | grep 1181
```

### Прокси не работает

```bash
# Проверьте процессы
docker exec zapret_socks ps aux | grep -E 'tpws|nfqws'

# Проверьте iptables
docker exec zapret_socks iptables -t mangle -L OUTPUT -n -v

# Попробуйте другую стратегию
```

### Медленная скорость

1. Используйте более простую стратегию (только `split2`)
2. Уменьшите количество модификаций
3. Проверьте нагрузку: `docker stats zapret_socks`

## Дополнительная информация

- Полная документация: `README.md`
- Примеры стратегий: `examples/strategies.md`
- Продвинутая конфигурация: `examples/docker-compose.advanced.yml`

## Поддержка

Для вопросов по zapret: https://github.com/bol-van/zapret