#!/usr/bin/env bash
set -e

echo "1. A iniciar Jenkins e VM de produção..."
docker start jenkins-ca5 2>/dev/null || true
vagrant.exe up || true

echo "2. A configurar encaminhamento NAT no VirtualBox (portas 2225 e 8085)..."
VM_ID=$(cat .vagrant/machines/prod/virtualbox/id)
VBoxManage.exe controlvm "$VM_ID" natpf1 "ca5_ssh,tcp,0.0.0.0,2225,,22" 2>/dev/null || true
VBoxManage.exe controlvm "$VM_ID" natpf1 "ca5_app,tcp,0.0.0.0,8085,,8080" 2>/dev/null || true

echo "3. A garantir interface de rede interna eth1 (192.168.56.30) na VM..."
ssh.exe -o StrictHostKeyChecking=no -p 2225 vagrant@127.0.0.1 \
  "sudo ip link set eth1 up && sudo ip addr replace 192.168.56.30/24 dev eth1"

echo "4. A autorizar chave pública do Jenkins na VM..."
JENKINS_PUB=$(docker exec jenkins-ca5 ssh-keygen -y -f /var/jenkins_home/.ssh/ca5_prod_key)
ssh.exe -o StrictHostKeyChecking=no -p 2225 vagrant@127.0.0.1 \
  "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$JENKINS_PUB' >> ~/.ssh/authorized_keys && sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

echo "5. A ligar ponte interna no contentor Jenkins (192.168.56.30:22 -> host.docker.internal:2225)..."
docker exec -u 0 jenkins-ca5 bash -c "
  ip addr add 192.168.56.30/32 dev lo 2>/dev/null || true
  which socat >/dev/null 2>&1 || (apt-get update -qq && apt-get install -y -qq socat >/dev/null)
  pkill socat 2>/dev/null || true
  nohup socat TCP-LISTEN:22,bind=192.168.56.30,fork,reuseaddr TCP:host.docker.internal:2225 >/tmp/socat.log 2>&1 &
"

echo "Ambiente pronto! Jenkins em http://localhost:8080 | App em http://localhost:8085/books"
