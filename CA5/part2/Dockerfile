FROM eclipse-temurin:17-jre-alpine
WORKDIR /app

COPY bookstore/build/libs/bookstore-*.jar app.jar

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
