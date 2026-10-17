#!/usr/bin/env bash
set -e

echo "=== [PROXY] A configurar chave SSH ==="
cat /tmp/id_rsa.pub >> /home/vagrant/.ssh/authorized_keys
chmod 600 /home/vagrant/.ssh/authorized_keys
chown vagrant:vagrant /home/vagrant/.ssh/authorized_keys

echo "=== [PROXY] Instalar Nginx ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nginx

echo "=== [PROXY] Configurar Reverse Proxy para a VM APP ==="
cat << 'EOF' > /etc/nginx/sites-available/default
server {
    listen 80;
    server_name localhost;

    location / {
        proxy_pass http://192.168.56.11:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

nginx -t
systemctl restart nginx