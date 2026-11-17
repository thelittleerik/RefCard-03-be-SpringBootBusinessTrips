# --- Stage 1: Build ---
FROM eclipse-temurin:21-jdk AS build
WORKDIR /app

# Wrapper und pom.xml zuerst: der Dependency-Layer wird nur bei Änderungen an pom.xml neu gebaut.
COPY .mvn/ .mvn/
COPY mvnw pom.xml ./
RUN ./mvnw -B dependency:go-offline

COPY src ./src
RUN ./mvnw -B clean package -DskipTests

# --- Stage 2: Runtime ---
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

# Nicht als root laufen: der Prozess braucht keine Schreibrechte ausser auf das Upload-Verzeichnis.
RUN addgroup -S app && adduser -S app -G app && mkdir -p /app/uploads && chown app:app /app/uploads
USER app

COPY --from=build /app/target/*.jar app.jar

# Von der Pipeline gesetzt (Git-Tag bzw. Commit) und unter /actuator/info sichtbar.
ARG APP_VERSION=dev
ARG APP_COMMIT=unknown
ENV APP_VERSION=$APP_VERSION \
    APP_COMMIT=$APP_COMMIT \
    APP_STORAGE_LOCATION=/app/uploads \
    JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75"

EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=5s --start-period=60s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/actuator/health || exit 1
ENTRYPOINT ["java", "-jar", "app.jar"]
