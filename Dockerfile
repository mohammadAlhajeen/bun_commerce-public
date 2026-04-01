# ---------- Build stage ----------
ARG APP_JAR=platform-0.4.0.jar

FROM eclipse-temurin:25-alpine-3.23 AS build
WORKDIR /app

# Copy Maven wrapper and metadata first
COPY mvnw ./
COPY .mvn .mvn
COPY pom.xml ./

RUN chmod +x mvnw \
    && ./mvnw -ntp -B dependency:go-offline

# Copy application sources
COPY src src

# Build the jar
RUN ./mvnw -ntp -B clean package -DskipTests

# ---------- Runtime stage ----------
FROM eclipse-temurin:25-jre
WORKDIR /app

# Install runtime deps
RUN apt-get update && \
  apt-get install -y curl python3 python3-pip python3-venv && \
  python3 -m pip install --break-system-packages osmnx psycopg2-binary python-dotenv && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

ARG APP_JAR
COPY --from=build /app/target/${APP_JAR} /app/platform.jar

# =========================
# Copy Flyway migrations
# =========================
COPY src/main/resources/db/migration /app/db/migration


# Copy Python scripts
COPY geo-tools /app/geo-tools

# Upload & logs dirs
ENV UPLOAD_DIR=/app/uploads
RUN mkdir -p /app/logs "$UPLOAD_DIR"

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD curl --fail http://localhost:8080/actuator/health || exit 1

# =========================
# Run generator then app
# =========================
ENTRYPOINT ["/bin/sh", "-c", "/app/generate-admin.sh && java -jar /app/platform.jar"]
