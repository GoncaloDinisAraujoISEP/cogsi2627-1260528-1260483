# CA4 - Part 2: Bookstore with Docker Compose

The CA2 Part 2 setup (proxy, application and database on separate machines) rebuilt with **Docker Compose** instead of Vagrant. Three containers run the Gradle version of the Bookstore (CA1/part2):

| Service | Image | Role | Port |
|---|---|---|---|
| `proxy` | `pbarbosa08/cogsi-ca4-proxy` | Nginx reverse proxy, the only entry point | host `${PROXY_PORT}` → 80 |
| `web` | `pbarbosa08/cogsi-ca4-web` | Bookstore (Spring Boot) | 8080 (internal) |
| `db` | `pbarbosa08/cogsi-ca4-db` | H2 in TCP server mode | 9092 (internal) |

```
Host ──:8080──▶ proxy ──frontend──▶ web ──backend──▶ db ──▶ volume h2-data
```

## Prerequisites

- Linux with Docker Engine, Buildx and the Compose plugin (here, the Ubuntu VM used since CA1):
  ```bash
  sudo apt install -y docker.io docker-buildx docker-compose-v2
  sudo usermod -aG docker $USER
  ```
- A Docker Hub account, to publish the images.

## Files

```
CA4/part2/
├── docker-compose.yml
├── .env.example          # copy to .env (not committed)
├── db/
│   ├── Dockerfile
│   ├── entrypoint.sh
│   └── .dockerignore
├── web/
│   ├── Dockerfile
│   ├── .dockerignore
│   └── bookstore/        # Gradle Bookstore source (from CA1/part2)
└── proxy/
    ├── Dockerfile
    ├── default.conf.template
    └── .dockerignore
```

## 1. Bookstore source

```bash
cd CA4/part2
rsync -a --exclude build --exclude .gradle ../../CA1/part2/ web/bookstore/
```

Only the source is copied. `build/` and `.gradle/` are generated, and the image builds the application itself.

## 2. `db` image (H2 server)

[`db/Dockerfile`](db/Dockerfile):

```dockerfile
# syntax=docker/dockerfile:1
FROM eclipse-temurin:17-jre
ARG H2_VERSION=2.2.224
RUN groupadd --system h2 \
 && useradd --system --gid h2 --home-dir /opt/h2 h2 \
 && mkdir -p /opt/h2 /opt/h2-data \
 && chown h2:h2 /opt/h2-data
ADD --chmod=644 https://repo1.maven.org/maven2/com/h2database/h2/${H2_VERSION}/h2-${H2_VERSION}.jar /opt/h2/h2.jar
COPY --chmod=755 entrypoint.sh /opt/h2/entrypoint.sh
ENV H2_DATA_DIR=/opt/h2-data H2_DB_NAME=bookstore H2_TCP_PORT=9092
USER h2
EXPOSE 9092
VOLUME /opt/h2-data
ENTRYPOINT ["/opt/h2/entrypoint.sh"]
```

| Choice | Why |
|---|---|
| `eclipse-temurin:17-jre` | H2 only needs to run, so the smaller JRE is enough |
| H2 2.2.224 | same version as the JDBC driver that Spring Boot 3.3.0 puts in the Bookstore, so client and server match |
| user `h2` | the server does not run as root; it owns `/opt/h2-data`, and a new volume inherits that owner |
| `ADD --chmod` | downloads the JAR and sets its permissions in one layer (needs BuildKit, enabled by the `# syntax` line) |

[`db/entrypoint.sh`](db/entrypoint.sh) creates the database on the first start, then starts the server:

```sh
if [ ! -f "$H2_DATA_DIR/$H2_DB_NAME.mv.db" ]; then
  java -cp /opt/h2/h2.jar org.h2.tools.Shell \
    -url "jdbc:h2:$H2_DATA_DIR/$H2_DB_NAME" \
    -user "$H2_USER" -password "$H2_PASSWORD" -sql "SELECT 1" > /dev/null
fi
exec java -cp /opt/h2/h2.jar org.h2.tools.Server \
  -tcp -tcpAllowOthers -tcpPort "$H2_TCP_PORT" -baseDir "$H2_DATA_DIR"
```

- **Local creation:** H2 does not allow creating databases over TCP unless `-ifNotExists` is used, which would let any client create databases. Creating it locally keeps remote creation disabled.
- **Credentials:** the database is created with `H2_USER` / `H2_PASSWORD`, which come from Compose. The script stops with an error if they are missing.
- **`exec`:** Java becomes PID 1 and receives the stop signal from Docker.

## 3. `web` image (Bookstore, multi-stage)

[`web/Dockerfile`](web/Dockerfile):

```dockerfile
# syntax=docker/dockerfile:1
FROM eclipse-temurin:17-jdk AS build
WORKDIR /src
COPY bookstore/ ./
RUN sed -i 's/\r$//' gradlew && chmod +x gradlew && ./gradlew bootJar --no-daemon

FROM eclipse-temurin:17-jre
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --system spring && useradd --system --gid spring spring
WORKDIR /app
COPY --from=build --chown=spring:spring /src/build/libs/bookstore-1.0.0.jar app.jar
USER spring
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

- **Two stages:** the first has the JDK and Gradle to build; the final image has only the JRE and the JAR. Source code, Gradle and build dependencies stay out of it.
- **`sed`:** removes Windows line endings from `gradlew`, in case it was checked out on Windows.
- **`curl`:** only for the health check. The apt cache is removed in the same layer.
- **User `spring`:** the application does not run as root.

## 4. `proxy` image (Nginx)

[`proxy/default.conf.template`](proxy/default.conf.template):

```nginx
server {
    listen ${NGINX_PORT};
    location / {
        proxy_pass http://${WEB_HOST}:${WEB_PORT};
        proxy_set_header Host $host;
        ...
    }
}
```

The official Nginx image runs `envsubst` on `/etc/nginx/templates/*.template` at startup and writes the result to `/etc/nginx/conf.d/`. Only defined environment variables are replaced, so Nginx variables like `$host` are kept. This is what lets Compose configure the listening port and the backend.

[`proxy/Dockerfile`](proxy/Dockerfile) uses `nginx:1.27-alpine` (small, and includes `wget` for the health check) and sets default values for the three variables.

## 5. `.dockerignore`

| Image | Content | Why |
|---|---|---|
| `db` | `*` then `!entrypoint.sh` | the build only needs the script; everything else stays out of the context |
| `proxy` | `*` then `!default.conf.template` | same idea |
| `web` | `bookstore/build`, `bookstore/.gradle`, `bookstore/.idea`, `*.md` | host build output and caches are not needed (the image builds from source), and they would make the context larger and break layer caching |

## 6. Docker Compose

### Environment variables

Every service is configured through variables read from `.env` ([`.env.example`](.env.example)):

```bash
cp .env.example .env     # set DOCKERHUB_USER
```

| Variable | Used by | Purpose |
|---|---|---|
| `DOCKERHUB_USER`, `TAG` | all | image names for Docker Hub |
| `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_PORT` | db, web | database name, credentials, TCP port |
| `WEB_PORT` | web, proxy | Spring Boot port and proxy backend |
| `PROXY_PORT` | proxy | port published on the host |

`.env` holds the password, so it is in `.gitignore`; the repository only has `.env.example`.

How each service uses them:

- **db:** `H2_DB_NAME`, `H2_USER`, `H2_PASSWORD`, `H2_TCP_PORT`, `H2_DATA_DIR`.
- **web:** `SPRING_DATASOURCE_URL=jdbc:h2:tcp://db:${DB_PORT}/${DB_NAME}`, plus username, password, `SERVER_PORT` and `SPRING_JPA_HIBERNATE_DDL_AUTO`. Spring Boot gives environment variables priority over the `application.properties` inside the JAR, so the in-memory H2 is replaced by the `db` container without changing the code.
- **proxy:** `NGINX_PORT`, `WEB_HOST`, `WEB_PORT`, and `${PROXY_PORT}:80` in `ports`.

### Networks

| Network | Services |
|---|---|
| `frontend` | proxy, web |
| `backend` | web, db |

Compose's internal DNS resolves each service by its name (`db`, `web`). The proxy is not on `backend`, so it cannot reach the database. Only the proxy publishes a port on the host.

### Health checks and startup order

| Service | Health check | Who waits for it |
|---|---|---|
| `db` | H2 `Shell` opens a JDBC connection and runs `SELECT 1` | `web` (`depends_on: condition: service_healthy`) |
| `web` | `curl -fs http://localhost:${WEB_PORT}/actuator/health` | `proxy` (`condition: service_healthy`) |
| `proxy` | `wget` on `/actuator/health` through Nginx | - |

Both checks test the application, not just a port:

- **db:** the query proves the database accepts connections with the configured credentials.
- **web:** Spring Boot's health endpoint includes the datasource check, so it is `UP` only if the database answers too.

In the `db` health check, `$${H2_USER}` is escaped with `$$`. Compose leaves it alone and it is resolved inside the container, so the password is not written into the health check definition.

### Volume

```yaml
volumes:
  - h2-data:/opt/h2-data
```

`h2-data` is a named volume managed by Docker, outside the container's filesystem. It survives `docker compose down` and container recreation. Only `docker compose down -v` deletes it.

## 7. Build and run

```bash
cd CA4/part2
docker compose build
docker compose up -d
docker compose ps
```

<img width="923" height="150" alt="image" src="https://github.com/user-attachments/assets/0f4648f5-3e29-410c-9022-3f91ff892e9e" />
<img width="923" height="292" alt="image" src="https://github.com/user-attachments/assets/cc252722-2ccf-48bf-873f-521c6a5ea048" />

Startup order in the logs (database created, then the application starts):

```bash
docker compose logs db web
```

<img width="923" height="570" alt="image" src="https://github.com/user-attachments/assets/3d4bb624-7de3-4a4f-9ffc-7685170a2fbd" />

```bash
curl http://localhost:8080/books
```

<img width="923" height="113" alt="image" src="https://github.com/user-attachments/assets/2d9ee335-02c9-4edf-9077-bb1db4e70dbe" />

## 8. Verification

### Name resolution and connectivity

```bash
docker compose exec web getent hosts db
docker compose exec proxy nslookup web
docker compose exec proxy wget -qO- http://web:8080/books
docker compose exec web bash -c 'echo > /dev/tcp/db/9092 && echo "db:9092 reachable"'
```

<img width="923" height="362" alt="image" src="https://github.com/user-attachments/assets/28054ecf-b7f5-430b-9fe6-b8c8ffcf14b3" />

Isolation: the proxy cannot resolve `db`.

```bash
docker compose exec proxy nslookup db
```

<img width="923" height="185" alt="image" src="https://github.com/user-attachments/assets/80f4b2d6-30a3-4d91-be9a-c518b68dc70b" />

### Health checks

```bash
docker inspect --format '{{.Name}} {{.State.Health.Status}}' ca4-part2-db-1 ca4-part2-web-1
```

<img width="923" height="116" alt="image" src="https://github.com/user-attachments/assets/081663ce-1d94-4ee5-8d77-08ccae353289" />

### Persistence

```bash
curl -X POST http://localhost:8080/books -H "Content-Type: application/json" \
     -d '{"title":"Persisted","author":"Test","price":10}'
docker compose down
docker compose up -d
curl http://localhost:8080/books
```

<img width="923" height="406" alt="image" src="https://github.com/user-attachments/assets/db28e636-a65d-4d27-b49f-7510912a3d74" />

```bash
docker volume inspect ca4-part2_h2-data
```

<img width="923" height="353" alt="image" src="https://github.com/user-attachments/assets/39f2bc20-2b66-485f-80ec-5ed0046b6e2a" />

### Environment variables resolved

```bash
docker compose config
```

<img width="923" height="938" alt="image" src="https://github.com/user-attachments/assets/a59e2050-372a-4890-9295-027c7cb37ece" />

## 9. Publish to Docker Hub

```bash
docker login -u pbarbosa08
docker compose push
```

<img width="923" height="788" alt="image" src="https://github.com/user-attachments/assets/c5b1cfc4-016f-4d41-89d3-31c2217b0c89" />

## 10. Tag

```bash
git tag ca4-part2
git push origin refs/tags/ca4-part2
```

The alternative (Podman) for this part is in [`../alternative/part-2-alternative`](../alternative/part-2-alternative/README.md).
