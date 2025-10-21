FROM eclipse-temurin:17-jre

# Metadata
LABEL maintainer="demo-team"
LABEL version="1.0.0"
LABEL description="Demo Microservice for ArgoCD Testing"

# Create app directory
WORKDIR /app

# Copy the jar file (or create a dummy one for demo)
COPY target/demo-microservice-*.jar app.jar 2>/dev/null || echo 'echo "Demo app running on version $APP_VERSION"' > app

# Expose port
EXPOSE 8080

# Environment variables with defaults
ENV APP_VERSION=v-1-0-0
ENV TARGET_URI=""
ENV SPRING_PROFILES_ACTIVE=default
ENV SERVER_PORT=8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

# Run the application
ENTRYPOINT ["java", "-jar", "app.jar"]