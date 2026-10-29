#!/bin/sh
set -e

: "${H2_USER:?H2_USER is required}"
: "${H2_PASSWORD:?H2_PASSWORD is required}"

DB_FILE="$H2_DATA_DIR/$H2_DB_NAME.mv.db"

if [ ! -f "$DB_FILE" ]; then
  echo "Creating database $H2_DB_NAME in $H2_DATA_DIR"
  java -cp /opt/h2/h2.jar org.h2.tools.Shell \
    -url "jdbc:h2:$H2_DATA_DIR/$H2_DB_NAME" \
    -user "$H2_USER" -password "$H2_PASSWORD" \
    -sql "SELECT 1" > /dev/null
fi

echo "Starting H2 TCP server on port $H2_TCP_PORT"
exec java -cp /opt/h2/h2.jar org.h2.tools.Server \
  -tcp -tcpAllowOthers -tcpPort "$H2_TCP_PORT" \
  -baseDir "$H2_DATA_DIR"
