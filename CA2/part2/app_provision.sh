#!/usr/bin/env bash
set -e

echo "=== [APP] A configurar chave SSH ==="
cat /tmp/id_rsa.pub >> /home/vagrant/.ssh/authorized_keys
chmod 600 /home/vagrant/.ssh/authorized_keys
chown vagrant:vagrant /home/vagrant/.ssh/authorized_keys

echo "=== [APP] Instalar dependencias ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y openjdk-17-jdk netcat-openbsd

echo "=== [APP] Health Check: Aguardar pelo servidor H2 (192.168.56.10:9092) ==="
until nc -z -v -w5 192.168.56.10 9092; do
  echo "A aguardar pela base de dados H2..."
  sleep 3
done
echo "Ligacao estabelecida com sucesso ao H2!"

echo "=== [APP] Configurar servico Systemd para a aplicacao ==="
cat << 'EOF' > /etc/systemd/system/bookstore.service
[Unit]
Description=Bookstore Application
After=network.target

[Service]
Type=simple
User=vagrant
WorkingDirectory=/vagrant_ca1
ExecStart=/bin/bash /vagrant_ca1/gradlew bootRun
Restart=always

[Install]
WantedBy=multi-user.target
EOF

chmod +x /vagrant_ca1/gradlew || true
systemctl daemon-reload
systemctl enable --now bookstore