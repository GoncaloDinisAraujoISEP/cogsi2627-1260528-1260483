#!/usr/bin/env bash
# Installs dependencies, clones the repo, builds both apps and installs the systemd units.
# Idempotent: every step checks the current state before changing it.
set -euo pipefail

REPO_DIR=/home/vagrant/repo
BOOKSTORE_DIR="$REPO_DIR/CA1/part2"
CHAT_PATH="$REPO_DIR/$CHAT_DIR"
JAVA17=/usr/lib/jvm/java-17-openjdk-amd64

# ---------- 1. Dependencies ----------
need_install=()
for pkg in git openjdk-17-jdk-headless openjdk-21-jdk-headless; do
  dpkg -s "$pkg" >/dev/null 2>&1 || need_install+=("$pkg")
done
if [ ${#need_install[@]} -gt 0 ]; then
  echo ">> Installing: ${need_install[*]}"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -q
  apt-get install -y -q "${need_install[@]}"
else
  echo ">> Dependencies already installed"
fi
# Gradle is not installed system-wide: each project uses its own wrapper (./gradlew).

# ---------- 2. Clone / update ----------
if [ "$CLONE_REPO" = "true" ]; then
  git_auth=()
  if [ -n "$GITHUB_TOKEN" ]; then
    # Token is sent as a header only, so it is never written to .git/config
    basic=$(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 -w0)
    git_auth=(-c "http.extraHeader=Authorization: Basic $basic")
  fi
  if [ -d "$REPO_DIR/.git" ]; then
    echo ">> Updating repository"
    sudo -u vagrant git "${git_auth[@]}" -C "$REPO_DIR" pull --ff-only origin "$REPO_BRANCH"
  else
    echo ">> Cloning repository"
    sudo -u vagrant git "${git_auth[@]}" clone -b "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
  fi
else
  echo ">> CLONE_REPO=false, skipping clone"
fi

# ---------- 3. Build ----------
if [ "$BUILD_APPS" = "true" ]; then
  echo ">> Building Bookstore"
  sudo -u vagrant bash -c "cd '$BOOKSTORE_DIR' && chmod +x gradlew && JAVA_HOME=$JAVA17 ./gradlew --no-daemon bootJar"
  echo ">> Building chat app"
  sudo -u vagrant bash -c "cd '$CHAT_PATH' && chmod +x gradlew && JAVA_HOME=$JAVA17 ./gradlew --no-daemon installDist"
else
  echo ">> BUILD_APPS=false, skipping build"
fi

# ---------- 4. Bookstore configuration (file-based H2 in the synced folder) ----------
mkdir -p /opt/bookstore
cat > /opt/bookstore/application.properties << PROPS
spring.datasource.url=jdbc:h2:file:/h2-data/bookstore
spring.jpa.hibernate.ddl-auto=update
spring.h2.console.settings.web-allow-others=true
service.version=1.0.0
service.build-timestamp=vagrant
PROPS

# ---------- 5. systemd units (started by start-apps.sh) ----------
cat > /etc/systemd/system/bookstore.service << UNIT
[Unit]
Description=Bookstore Spring Boot app
After=network.target

[Service]
User=vagrant
Environment=JAVA_HOME=$JAVA17
ExecStart=$JAVA17/bin/java -jar $BOOKSTORE_DIR/build/libs/bookstore-1.0.0.jar --spring.config.additional-location=file:/opt/bookstore/application.properties
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT

cat > /etc/systemd/system/chat-server.service << UNIT
[Unit]
Description=Chat server (CA1 part 1)
After=network.target

[Service]
User=vagrant
ExecStart=/usr/lib/jvm/java-21-openjdk-amd64/bin/java -cp "$CHAT_PATH/app/build/install/app/lib/*" org.example.ChatServerApp 59001
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
echo ">> Provisioning finished"