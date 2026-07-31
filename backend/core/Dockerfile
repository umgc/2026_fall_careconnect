# Runtime stage — jar is built locally and passed in via build context
FROM eclipse-temurin:17-jre-jammy
WORKDIR /app

# Install curl for health checks; ffmpeg for KVS attendee fragment → WAV (speaker ID)
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ffmpeg && \
    rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd --system appuser && \
    useradd --system --gid appuser --no-create-home appuser

# Copy the pre-built Spring Boot fat jar
COPY target/careconnect-backend-0.0.1-SNAPSHOT.jar app.jar

# Create uploads directory (in case local file storage is used)
RUN mkdir -p /app/uploads && chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Spring Boot default port
EXPOSE 8080

# Health check using Spring Actuator
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/v1/api/test/health || exit 1

# JVM tuning for containers — respects Fargate memory/CPU limits
ENTRYPOINT ["java", \
    "-XX:+UseContainerSupport", \
    "-XX:MaxRAMPercentage=75.0", \
    "-Djava.security.egd=file:/dev/./urandom", \
    "-jar", "app.jar"]
