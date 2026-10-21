#!/bin/bash
set -e
echo "==> Running SaltStack Alternative Configuration Management <=="

declare -A NODES=( ["192.168.56.10"]="proxy" ["192.168.56.11"]="db" ["192.168.56.12"]="app" )

for IP in "${!NODES[@]}"; do
  ROLE=${NODES[$IP]}
  echo "--> Setting up Salt repository and minion on $ROLE ($IP)..."
  
  # Instalar dependências, importar chave e repositório do Salt Project
  sshpass -p "vagrant" ssh -o StrictHostKeyChecking=no vagrant@$IP "sudo mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://packages.broadcom.com/artifactory/api/security/keypair/SaltProjectKey/public | sudo gpg --dearmor --yes -o /etc/apt/keyrings/salt-archive-keyring.gpg && \
    echo 'deb [signed-by=/etc/apt/keyrings/salt-archive-keyring.gpg] https://packages.broadcom.com/artifactory/saltproject-deb/ stable main' | sudo tee /etc/apt/sources.list.d/salt.list && \
    sudo apt-get update -qq && \
    sudo apt-get install -y -qq salt-minion"

  echo "--> Copying Salt states for $ROLE..."
  sshpass -p "vagrant" ssh -o StrictHostKeyChecking=no vagrant@$IP "sudo mkdir -p /srv/salt"
  sshpass -p "vagrant" scp -o StrictHostKeyChecking=no -r ansible-alternative/salt/common vagrant@$IP:/tmp/
  sshpass -p "vagrant" scp -o StrictHostKeyChecking=no -r ansible-alternative/salt/$ROLE vagrant@$IP:/tmp/

  echo "--> Applying Salt states locally on $ROLE..."
  sshpass -p "vagrant" ssh -o StrictHostKeyChecking=no vagrant@$IP "sudo rm -rf /srv/salt/common /srv/salt/$ROLE && sudo mv /tmp/common /tmp/$ROLE /srv/salt/ && sudo salt-call --local state.apply common && sudo salt-call --local state.apply $ROLE"
done

echo "==> Validating application via Reverse Proxy <=="
curl -i http://192.168.56.10/books
