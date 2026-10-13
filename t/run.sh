#!/bin/bash
# Runtime tests for dynamic_resolve.
# usage: t/run.sh /path/to/nginx
#
# "localhost" resolves to 127.0.0.1 at startup (the stale address, backend A),
# while the test DNS server controls what it resolves to at run time.

NGINX=${1:?usage: $0 /path/to/nginx}
DIR=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d)
FAILED=0

# "localhost" may also resolve to ::1 at startup, serve A there when possible
LISTEN6=
if ip -6 addr show dev lo 2>/dev/null | grep -q '::1'; then
    LISTEN6="listen [::1]:8081;"
fi

mkdir -p $T/logs

for x in A B C D; do
    mkdir -p $T/www/$x
    echo $x > $T/www/$x/index.html
done

cat > $T/nginx.conf <<EOF
worker_processes 1;
error_log $T/error.log debug;
pid $T/nginx.pid;
events { worker_connections 64; }
http {
    access_log $T/access.log;
    resolver 127.0.0.1:5353 valid=1s ipv6=off;
    resolver_timeout 1s;

    upstream stale    { dynamic_resolve fallback=stale fail_timeout=2s; server localhost:8081; }
    upstream shutdown { dynamic_resolve fallback=shutdown fail_timeout=2s; server localhost:8081; }
    upstream next     { dynamic_resolve fallback=next fail_timeout=2s; server localhost:8081; server 127.0.0.4:8081; }
    upstream hashed   { hash \$arg_k; dynamic_resolve fallback=stale; server localhost:8081; }
    upstream ka       { dynamic_resolve fallback=stale; server localhost:8081; keepalive 4; }
    upstream iponly   { dynamic_resolve; server 127.0.0.4:8081; }

    server {
        listen 127.0.0.1:8080;
        location /stale/    { proxy_pass http://stale/; }
        location /shutdown/ { proxy_pass http://shutdown/; }
        location /next/     { proxy_pass http://next/; }
        location /hashed/   { proxy_pass http://hashed/; }
        location /ka/       { proxy_pass http://ka/; proxy_http_version 1.1; proxy_set_header Connection ""; }
        location /iponly/   { proxy_pass http://iponly/; }
    }
    server { listen 127.0.0.1:8081; $LISTEN6 root $T/www/A; }
    server { listen 127.0.0.2:8081; root $T/www/B; }
    server { listen 127.0.0.3:8081; root $T/www/C; }
    server { listen 127.0.0.4:8081; root $T/www/D; }
}
EOF

dns() { echo "$1" > $T/dns.json; }

# prints the backend name on 200, the status code otherwise
get() {
    local out code
    out=$(curl -s -m 5 -w '\n%{http_code}' http://127.0.0.1:8080/$1/)
    code=${out##*$'\n'}
    if [ "$code" = 200 ]; then
        echo "${out%%$'\n'*}"
    else
        echo "$code"
    fi
}

check() {
    local name=$1 expected=$2 got=$3
    if [ "$got" = "$expected" ]; then
        echo "ok   $name"
    else
        echo "FAIL $name: expected '$expected', got '$got'"
        FAILED=1
    fi
}

cleanup() {
    [ -f $T/nginx.pid ] && kill $(cat $T/nginx.pid) 2>/dev/null
    [ -n "$DNSPID" ] && kill $DNSPID 2>/dev/null
}
trap cleanup EXIT

dns '{"localhost": ["127.0.0.2"]}'
python3 -I $DIR/dns.py $T/dns.json &
DNSPID=$!
sleep 0.5

$NGINX -p $T -c $T/nginx.conf || exit 1
sleep 0.5

check "resolve at run time"           B   "$(get stale)"
dns '{"localhost": ["127.0.0.3"]}'; sleep 2.5
check "DNS change picked up"          C   "$(get stale)"
check "hash balancer"                 C   "$(get hashed)"
check "keepalive"                     C   "$(get ka)"
check "keepalive, cached connection"  C   "$(get ka)"
check "IP-only upstream"              D   "$(get iponly)"
check "round robin 1"                 C   "$(get next)"
check "round robin 2"                 D   "$(get next)"

dns '{"drop": true}'; sleep 2.5
check "timeout, fallback=stale"       A   "$(get stale)"
check "fail_timeout, fallback=stale"  A   "$(get stale)"
check "timeout, fallback=shutdown"    502 "$(get shutdown)"
check "fail_timeout, shutdown"        502 "$(get shutdown)"
check "timeout, fallback=next"        D   "$(get next)"

dns '{"nxdomain": true}'; sleep 2.5
check "NXDOMAIN, fallback=stale"      A   "$(get stale)"

dns '{"localhost": ["127.0.0.2"], "delay": 2}'; sleep 2.5
curl -s -m 0.5 -o /dev/null http://127.0.0.1:8080/stale/
sleep 2.5
dns '{"localhost": ["127.0.0.2"]}'; sleep 2.5
check "after client abort mid-resolve" B  "$(get stale)"

res=$(for i in $(seq 1 50); do curl -s -m 5 http://127.0.0.1:8080/stale/ & done; wait)
check "50 concurrent requests"        50  "$(echo "$res" | grep -c '^B$')"

check "client abort logged as 499"    1   "$(grep -c '" 499 ' $T/access.log)"
check "no worker crashes"             0   "$(grep -c 'exited on signal' $T/error.log)"
check "no alerts"                     0   "$(grep -c '\[alert\]\|\[crit\]' $T/error.log)"

if [ $FAILED != 0 ]; then
    echo "--- error.log (errors only)"
    grep '\[error\]\|\[alert\]\|\[crit\]' $T/error.log | tail -50
fi

exit $FAILED
