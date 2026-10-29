# syntax=docker/dockerfile:1

# ---------- build stage ----------
FROM eclipse-temurin:17-jdk AS build
WORKDIR /src
COPY bookstore/ ./
RUN sed -i 's/\r$//' gradlew \
 && chmod +x gradlew \
 && ./gradlew bootJar --no-daemon

# ---------- runtime stage ----------
FROM eclipse-temurin:17-jre
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --system spring \
 && useradd --system --gid spring spring
WORKDIR /app
COPY --from=build --chown=spring:spring /src/build/libs/bookstore-1.0.0.jar app.jar
USER spring
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
