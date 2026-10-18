#!/usr/bin/env bash
set -e

echo "=== [1/4] A lançar nós do cluster (db, app, proxy) ==="
lxc launch ubuntu:24.04 db --config=user.user-data="$(cat db.yaml)" -c limits.cpu=1 -c limits.memory=1024MB || true
lxc launch ubuntu:24.04 app --config=user.user-data="$(cat app.yaml)" -c limits.cpu=2 -c limits.memory=2048MB || true
lxc launch ubuntu:24.04 proxy --config=user.user-data="$(cat proxy.yaml)" -c limits.cpu=1 -c limits.memory=512MB || true

echo "=== [2/4] A aguardar finalização do provisionamento Cloud-Init ==="
lxc exec db -- cloud-init status --wait
lxc exec app -- cloud-init status --wait
lxc exec proxy -- cloud-init status --wait

echo "=== [3/4] A interligar os nós dinamicamente ==="
DB_IP=$(lxc list db -c 4 --format csv | cut -d' ' -f1)
APP_IP=$(lxc list app -c 4 --format csv | cut -d' ' -f1)
PROXY_IP=$(lxc list proxy -c 4 --format csv | cut -d' ' -f1)

echo "IPs detetados: DB=$DB_IP | APP=$APP_IP | PROXY=$PROXY_IP"

# 1. Ajustar firewall no db para permitir o IP do app
lxc exec db -- ufw allow from "$APP_IP" to any port 9092 proto tcp || true

# 2. Atualizar o IP do db na Bookstore e reiniciar a app
lxc exec app -- sed -i "s|10.148.196.[0-9]*:9092|${DB_IP}:9092|g" /etc/systemd/system/bookstore.service || true
lxc exec app -- systemctl daemon-reload
lxc exec app -- systemctl enable --now bookstore
lxc exec app -- systemctl restart bookstore

# 3. Atualizar o IP do app no Proxy Nginx
lxc exec proxy -- sed -i "s|proxy_pass http://[^:]*:8080;|proxy_pass http://${APP_IP}:8080;|" /etc/nginx/sites-available/reverse-proxy
lxc exec proxy -- rm -f /etc/nginx/sites-enabled/default
lxc exec proxy -- ln -sf /etc/nginx/sites-available/reverse-proxy /etc/nginx/sites-enabled/
lxc exec proxy -- nginx -t
lxc exec proxy -- systemctl reload nginx

echo "A aguardar que a Bookstore responda na porta 8080..."
until lxc exec app -- curl -s http://localhost:8080/health | grep -q "UP"; do
    printf '.'
    sleep 3
done
echo " Aplicação operacional!"

echo "=== [4/4] Cluster operacional! ==="
echo "Endpoints disponíveis:"
echo "  -> http://${PROXY_IP}/"
echo "  -> http://${PROXY_IP}/books"
echo "  -> http://${PROXY_IP}/health"
