# syntax=docker/dockerfile:1
FROM eclipse-temurin:17-jre

ARG H2_VERSION=2.2.224

RUN groupadd --system h2 \
 && useradd --system --gid h2 --home-dir /opt/h2 h2 \
 && mkdir -p /opt/h2 /opt/h2-data \
 && chown h2:h2 /opt/h2-data

ADD --chmod=644 https://repo1.maven.org/maven2/com/h2database/h2/${H2_VERSION}/h2-${H2_VERSION}.jar /opt/h2/h2.jar
COPY --chmod=755 entrypoint.sh /opt/h2/entrypoint.sh

ENV H2_DATA_DIR=/opt/h2-data \
    H2_DB_NAME=bookstore \
    H2_TCP_PORT=9092

USER h2
EXPOSE 9092
VOLUME /opt/h2-data
ENTRYPOINT ["/opt/h2/entrypoint.sh"]
