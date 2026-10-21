#!/bin/bash
# SaltStack (masterless) alternative to site.yml.
# Run from the CA3 folder:  bash ansible-alternative/apply.sh
set -e

SALT_DIR=ansible-alternative/salt
APP_JAR=roles/app/files/app.jar
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

remote() { sshpass -p vagrant ssh $SSH_OPTS "vagrant@$1" "$2"; }
upload() { local ip=$1; shift; sshpass -p vagrant scp $SSH_OPTS -r "$@" "vagrant@$ip:/tmp/salt-states/"; }

[ -f "$APP_JAR" ] || { echo "Missing $APP_JAR (build it from CA1/part2 first)"; exit 1; }

echo "==> SaltStack alternative configuration management <=="

# Same order as site.yml: db, then app, then proxy
for NODE in "192.168.56.11 db" "192.168.56.12 app" "192.168.56.10 proxy"; do
  read -r IP ROLE <<< "$NODE"

  echo "--> [$ROLE] Installing salt-minion (only if missing)"
  remote "$IP" "command -v salt-call >/dev/null || ( \
    sudo mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://packages.broadcom.com/artifactory/api/security/keypair/SaltProjectKey/public | sudo gpg --dearmor --yes -o /etc/apt/keyrings/salt-archive-keyring.gpg && \
    echo 'deb [signed-by=/etc/apt/keyrings/salt-archive-keyring.gpg] https://packages.broadcom.com/artifactory/saltproject-deb/ stable main' | sudo tee /etc/apt/sources.list.d/salt.list >/dev/null && \
    sudo apt-get update -qq && sudo apt-get install -y -qq salt-minion )"
  # Masterless: the minion daemon (which would look for a master) is not needed
  remote "$IP" "sudo systemctl disable --now salt-minion >/dev/null 2>&1 || true"

  echo "--> [$ROLE] Copying states"
  remote "$IP" "rm -rf /tmp/salt-states && mkdir -p /tmp/salt-states"
  FILES="$SALT_DIR/top.sls $SALT_DIR/secrets.jinja $SALT_DIR/common $SALT_DIR/$ROLE"
  if [ "$ROLE" != "proxy" ]; then FILES="$FILES $SALT_DIR/security"; fi
  upload "$IP" $FILES
  if [ "$ROLE" = "app" ]; then
    sshpass -p vagrant scp $SSH_OPTS "$APP_JAR" "vagrant@$IP:/tmp/salt-states/app/app.jar"
  fi
  remote "$IP" "sudo rm -rf /srv/salt && sudo mv /tmp/salt-states /srv/salt"

  echo "--> [$ROLE] Applying states"
  remote "$IP" "sudo salt-call --local --state-output=terse state.apply common && \
                sudo salt-call --local --state-output=terse state.apply $ROLE"
done

echo "==> End-to-end check through the reverse proxy <=="
curl -fsS http://192.168.56.10/books && echo
