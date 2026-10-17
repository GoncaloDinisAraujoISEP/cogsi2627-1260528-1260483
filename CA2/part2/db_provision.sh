#!/usr/bin/env bash
set -e

echo "=== [DB] A configurar chave SSH ==="
cat /tmp/id_rsa.pub >> /home/vagrant/.ssh/authorized_keys
chmod 600 /home/vagrant/.ssh/authorized_keys
chown vagrant:vagrant /home/vagrant/.ssh/authorized_keys

echo "=== [DB] Instalar dependencias ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y openjdk-17-jre-headless wget ufw

echo "=== [DB] Descarregar H2 Database ==="
mkdir -p /opt/h2 /opt/h2-data
if [ ! -f /opt/h2/h2.jar ]; then
  wget -q https://repo1.maven.org/maven2/com/h2database/h2/2.2.224/h2-2.2.224.jar -O /opt/h2/h2.jar
fi

echo "=== [DB] Configurar servico Systemd para H2 Server ==="
# Assegurar diretorio e ficheiro inicial da BD H2 com permissoes completas
mkdir -p /opt/h2-data
touch /opt/h2-data/bookstore.mv.db
chmod -R 777 /opt/h2-data
cat << 'EOF' > /etc/systemd/system/h2.service
[Unit]
Description=H2 Database Server
After=network.target

[Service]
Type=simple
User=vagrant
ExecStart=/usr/bin/java -cp /opt/h2/h2.jar org.h2.tools.Server -tcp -tcpAllowOthers -tcpPort 9092 -baseDir /opt/h2-data -ifNotExists
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now h2

echo "=== [DB] Configurar Firewall (UFW) ==="
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow from 192.168.56.11 to any port 9092 proto tcp
ufw --force enable
ufw status verbose