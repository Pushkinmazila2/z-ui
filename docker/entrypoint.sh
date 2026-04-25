#!/bin/bash



set -e

LOG_LEVEL=${LOG_LEVEL:-info}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
NC='\033[0m'

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

log_info()  { echo -e "${GREEN}[$(timestamp)] [INFO]${NC} $1"; }
log_debug() { [ "$LOG_LEVEL" = "debug" ] && echo -e "${CYAN}[$(timestamp)] [DEBUG]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[$(timestamp)] [WARN]${NC} $1"; }
log_error() { echo -e "${RED}[$(timestamp)] [ERROR]${NC} $1" >&2; }

process_nfqws_log() {
local line="$1"

```
if echo "$line" | grep -qE "(desync|fake|split|disorder|wssize|seqovl)"; then
    echo -e "${MAGENTA}[$(timestamp)] [DPI-ACTIVE]${NC} ${YELLOW}$line${NC}"

elif echo "$line" | grep -qE "(hostname|SNI|Host:)"; then
    local host=$(echo "$line" | sed -nE 's/.*(hostname|SNI|Host:)[: ]*([^ ]+).*/\2/p' | head -1)
    echo -e "${BLUE}[$(timestamp)] [TARGET]${NC} ${GREEN}$host${NC}"

elif echo "$line" | grep -qiE "(error|fail|drop)"; then
    log_error "NFQWS: $line"
fi
```

}

process_dante_log() {
local line="$1"

```
if echo "$line" | grep -q "accept.*connection from"; then
    local ip=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    log_info "SOCKS5 connection from $ip"
fi
```

}

log_info "Starting zapret2 (OUTPUT mode)"

SOCKS5_PORT=${SOCKS5_PORT:-1080}
NFQUEUE_NUM=${NFQUEUE_NUM:-200}
ZAPRET_CONFIG=${ZAPRET_CONFIG:-/opt/zapret2/config}

if [ -f "$ZAPRET_CONFIG" ]; then
log_info "Loading config from $ZAPRET_CONFIG"
. "$ZAPRET_CONFIG"
else
log_warn "Config not found, using defaults"
fi

debug_dump() {
log_warn "==== DEBUG MODE ENABLED ===="

```
echo "---- USER ----"
id

echo "---- CAPABILITIES ----"
capsh --print 2>/dev/null || echo "capsh not available"

echo "---- NETWORK ----"
ip a || true
ip route || true

echo "---- IPTABLES ----"
iptables -t mangle -L -v || true

echo "---- NFQUEUE ----"
if [ -f /proc/net/netfilter/nfnetlink_queue ]; then
    cat /proc/net/netfilter/nfnetlink_queue
else
    echo "NFQUEUE proc file not found"
fi

echo "---- MODULES ----"
lsmod | grep nfnetlink_queue || echo "nfnetlink_queue not loaded"

echo "---- BINARIES ----"
ls -lah /usr/local/bin/

echo "---- LDD nfqws2 ----"
ldd /usr/local/bin/nfqws2 || true

echo "---- LDD sockd ----"
ldd /usr/sbin/sockd || true

echo "---- LUA FILES ----"
ls -lah /opt/zapret2/lua/ || true

echo "---- CONFIG ----"
ls -lah /opt/zapret2/ || true

echo "---- NFQWS TEST RUN ----"
/usr/local/bin/nfqws2 -v $FINAL_NFQWS_OPTS 2>&1 || true

echo "---- SOCKD TEST RUN ----"
sockd -f /etc/sockd.conf -D 2>&1 || true

log_warn "==== DEBUG END ===="
```

}

# --- USER ---

id -u proxyuser &>/dev/null || adduser -D -H -s /bin/false proxyuser

# --- CLEAN IPTABLES ---

log_info "Resetting iptables"
iptables -t mangle -F OUTPUT || true

# --- RULES ---

log_info "Applying OUTPUT rules"

# 1. bypass loopback

iptables -t mangle -A OUTPUT -d 127.0.0.0/8 -j RETURN

# 2. bypass local networks

iptables -t mangle -A OUTPUT -d 10.0.0.0/8 -j RETURN
iptables -t mangle -A OUTPUT -d 172.16.0.0/12 -j RETURN
iptables -t mangle -A OUTPUT -d 192.168.0.0/16 -j RETURN

# 3. bypass DNS (optional)

iptables -t mangle -A OUTPUT -p udp --dport 53 -j RETURN

# 4. prevent loop (nfqws2 runs as root)

iptables -t mangle -A OUTPUT -m owner --uid-owner root -j RETURN

# 5. MAIN RULE (ONLY proxyuser traffic)

iptables -t mangle -A OUTPUT \
    -m owner --uid-owner proxyuser \
    -p tcp \
    -j NFQUEUE --queue-num $NFQUEUE_NUM --queue-bypass

# --- DEBUG (optional) ---

if [ "$LOG_LEVEL" = "debug" ]; then
log_debug "iptables rules:"
iptables -t mangle -L OUTPUT -v
fi

# --- DANTE CONFIG ---

cat > /etc/sockd.conf <<EOF
logoutput: stderr
internal: 0.0.0.0 port = $SOCKS5_PORT
external: eth0
clientmethod: none
socksmethod: none
user.privileged: root
user.unprivileged: proxyuser
client pass { from: 0.0.0.0/0 to: 0.0.0.0/0; }
socks pass { from: 0.0.0.0/0 to: 0.0.0.0/0; }
EOF

# --- NFQWS OPTIONS ---

NFQWS_BASE="--qnum=$NFQUEUE_NUM 
--lua-init=@/opt/zapret2/lua/zapret-lib.lua 
--lua-init=@/opt/zapret2/lua/zapret-antidpi.lua"

if [ "$NFQWS2_ENABLE" = "1" ]; then
log_info "Using custom strategy"
FINAL_NFQWS_OPTS="$NFQWS_BASE $NFQWS2_OPT"
else
log_info "Using default strategy"
FINAL_NFQWS_OPTS="$NFQWS_BASE 
--filter-tcp=80,443 
--filter-l7=http,tls 
--lua-desync=multidisorder:pos=midsld"
fi

# --- START SERVICES ---

log_info "Starting nfqws2"
( /usr/local/bin/nfqws2 -v $FINAL_NFQWS_OPTS 2>&1 | while read -r l; do process_nfqws_log "$l"; done ) &
NFQWS_PID=$!

log_info "Starting SOCKS5 (Dante)"
( sockd -f /etc/sockd.conf -D 2>&1 | while read -r l; do process_dante_log "$l"; done ) &
SOCKS_PID=$!

log_info "✓ Ready on port $SOCKS5_PORT"

# --- WATCHDOG ---

while true; do
if ! kill -0 $NFQWS_PID 2>/dev/null; then
log_error "nfqws2 died, restarting"
( /usr/local/bin/nfqws2 -v $FINAL_NFQWS_OPTS 2>&1 | while read -r l; do process_nfqws_log "$l"; done ) &
NFQWS_PID=$!
fi

```
if ! kill -0 $SOCKS_PID 2>/dev/null; then
    log_error "sockd died, restarting"
    ( sockd -f /etc/sockd.conf -D 2>&1 | while read -r l; do process_dante_log "$l"; done ) &
    SOCKS_PID=$!
fi

sleep 5
```

done
