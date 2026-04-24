# Стратегии обхода DPI для разных провайдеров

Этот документ содержит примеры рабочих стратегий для различных провайдеров и ситуаций.

## Общие рекомендации

1. Начните с простых стратегий и постепенно усложняйте
2. Тестируйте каждую стратегию на заблокированных сайтах
3. Комбинируйте разные методы для лучшего результата
4. Следите за производительностью - сложные стратегии могут замедлить соединение

## Базовые стратегии

### 1. Split2 (Разделение пакета)

**Описание**: Разделяет TCP-пакет на две части в указанной позиции.

```yaml
NFQWS_ARGS: --dpi-desync=split2 --dpi-desync-split-pos=2
```

**Когда использовать**: Первая стратегия для тестирования, работает с простыми DPI.

### 2. Disorder (Изменение порядка)

**Описание**: Отправляет пакеты в неправильном порядке.

```yaml
NFQWS_ARGS: --dpi-desync=disorder --dpi-desync-split-pos=2
```

**Когда использовать**: Когда split2 не работает.

### 3. Fake (Фейковые пакеты)

**Описание**: Отправляет фейковые пакеты с низким TTL, которые не доходят до сервера.

```yaml
NFQWS_ARGS: --dpi-desync=fake --dpi-desync-ttl=5
```

**Когда использовать**: Для обхода активных DPI, которые блокируют пакеты.

## Продвинутые стратегии

### 4. Split2 + Disorder

```yaml
NFQWS_ARGS: --dpi-desync=split2,disorder --dpi-desync-split-pos=2
```

### 5. Fake + Split2

```yaml
NFQWS_ARGS: --dpi-desync=fake,split2 --dpi-desync-ttl=4 --dpi-desync-split-pos=2
```

### 6. Агрессивная стратегия

```yaml
NFQWS_ARGS: --dpi-desync=fake,split2 --dpi-desync-ttl=4 --dpi-desync-fooling=badsum --dpi-desync-split-pos=2 --dpi-desync-autottl=2
```

## Стратегии для HTTPS

### 7. Split2 + HostCase

```yaml
NFQWS_ARGS: --dpi-desync=split2 --dpi-desync-split-pos=2 --hostcase
```

### 8. Split2 + HostNoSpace

```yaml
NFQWS_ARGS: --dpi-desync=split2 --dpi-desync-split-pos=2 --hostnospace
```

### 9. Комбинированная для HTTPS

```yaml
NFQWS_ARGS: --dpi-desync=fake,split2 --dpi-desync-ttl=5 --dpi-desync-split-pos=2 --hostcase --hostnospace
```

## Стратегии для конкретных провайдеров

### Ростелеком

```yaml
NFQWS_ARGS: --dpi-desync=split2 --dpi-desync-split-pos=2 --dpi-desync-autottl=2
```

### МТС

```yaml
NFQWS_ARGS: --dpi-desync=fake,split2 --dpi-desync-ttl=4 --dpi-desync-split-pos=2
```

### Билайн

```yaml
NFQWS_ARGS: --dpi-desync=disorder --dpi-desync-split-pos=2 --dpi-desync-autottl=2
```

### Мегафон

```yaml
NFQWS_ARGS: --dpi-desync=split2,disorder --dpi-desync-split-pos=2 --hostcase
```

### МГТС

```yaml
NFQWS_ARGS: --dpi-desync=fake --dpi-desync-ttl=5 --dpi-desync-fooling=badsum
```

## Специальные случаи

### Для YouTube

```yaml
NFQWS_ARGS: --dpi-desync=split2 --dpi-desync-split-pos=2 --dpi-desync-autottl=2
```

### Для Discord

```yaml
NFQWS_ARGS: --dpi-desync=fake,split2 --dpi-desync-ttl=4 --dpi-desync-split-pos=2
```

### Для Telegram

```yaml
NFQWS_ARGS: --dpi-desync=disorder --dpi-desync-split-pos=2
```

### Для VPN протоколов

```yaml
NFQWS_ARGS: --dpi-desync=fake --dpi-desync-ttl=3 --dpi-desync-any-protocol=1
```

## Параметры TTL

### Auto TTL (рекомендуется)

```yaml
NFQWS_ARGS: --dpi-desync=split2 --dpi-desync-split-pos=2 --dpi-desync-autottl=2
```

**Описание**: Автоматически определяет оптимальный TTL.

### Фиксированный TTL

```yaml
NFQWS_ARGS: --dpi-desync=fake --dpi-desync-ttl=5
```

**Значения TTL**:
- `3-4`: Для близких DPI (1-2 хопа)
- `5-7`: Для средних расстояний (3-5 хопов)
- `8-10`: Для дальних DPI (6+ хопов)

## Методы обмана (Fooling)

### BadSum (неверная контрольная сумма)

```yaml
NFQWS_ARGS: --dpi-desync=fake --dpi-desync-ttl=5 --dpi-desync-fooling=badsum
```

### MD5Sig (неверная MD5 подпись)

```yaml
NFQWS_ARGS: --dpi-desync=fake --dpi-desync-ttl=5 --dpi-desync-fooling=md5sig
```

### BadSeq (неверный sequence number)

```yaml
NFQWS_ARGS: --dpi-desync=fake --dpi-desync-ttl=5 --dpi-desync-fooling=badseq
```

## Тестирование стратегий

### Скрипт для автоматического тестирования

```bash
#!/bin/bash

# Список стратегий для тестирования
strategies=(
    "--dpi-desync=split2 --dpi-desync-split-pos=2"
    "--dpi-desync=disorder --dpi-desync-split-pos=2"
    "--dpi-desync=fake --dpi-desync-ttl=5"
    "--dpi-desync=fake,split2 --dpi-desync-ttl=4 --dpi-desync-split-pos=2"
    "--dpi-desync=split2 --dpi-desync-split-pos=2 --hostcase"
)

# Тестовый URL
test_url="https://www.youtube.com"

for strategy in "${strategies[@]}"; do
    echo "Тестирование: $strategy"
    
    # Остановка контейнера
    docker-compose down
    
    # Установка стратегии
    export NFQWS_ARGS="$strategy"
    
    # Запуск контейнера
    docker-compose up -d
    sleep 5
    
    # Тест
    if curl -x socks5://localhost:1181 -s -o /dev/null -w "%{http_code}" "$test_url" | grep -q "200"; then
        echo "✓ Работает!"
    else
        echo "✗ Не работает"
    fi
    
    echo "---"
done
```

## Оптимизация производительности

### Минимальная модификация (быстро)

```yaml
NFQWS_ARGS: --dpi-desync=split2 --dpi-desync-split-pos=2
```

### Средняя модификация (баланс)

```yaml
NFQWS_ARGS: --dpi-desync=split2,disorder --dpi-desync-split-pos=2 --dpi-desync-autottl=2
```

### Максимальная модификация (медленно, но эффективно)

```yaml
NFQWS_ARGS: --dpi-desync=fake,split2,disorder --dpi-desync-ttl=4 --dpi-desync-fooling=badsum --dpi-desync-split-pos=2 --dpi-desync-autottl=2 --hostcase --hostnospace
```

## Отладка

### Включение подробного логирования

Добавьте в `docker-compose.yml`:

```yaml
environment:
  - NFQWS_ARGS=--debug=1 --dpi-desync=split2 --dpi-desync-split-pos=2
```

### Проверка работы стратегии

```bash
# Просмотр логов nfqws
docker-compose logs -f zapret | grep nfqws

# Проверка правил iptables
docker exec zapret_socks iptables -t mangle -L OUTPUT -n -v

# Тест конкретного сайта
curl -v -x socks5://localhost:1181 https://example.com
```

## Рекомендации

1. **Начните с простого**: Сначала попробуйте `split2`
2. **Добавляйте постепенно**: Если не работает, добавьте `disorder` или `fake`
3. **Используйте autottl**: Это упрощает настройку TTL
4. **Тестируйте на разных сайтах**: Разные сайты могут требовать разных стратегий
5. **Следите за производительностью**: Сложные стратегии замедляют соединение
6. **Обновляйте стратегии**: DPI постоянно обновляются, стратегии могут перестать работать

## Полезные ссылки

- [Документация zapret](https://github.com/bol-van/zapret)
- [Обсуждение стратегий на форумах](https://github.com/bol-van/zapret/issues)
- [Wiki по обходу блокировок](https://github.com/bol-van/zapret/wiki)