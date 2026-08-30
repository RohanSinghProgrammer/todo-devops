# Stage 1: Build the React application
FROM node:24-alpine AS builder

# Set the working directory
WORKDIR /app

# Copy package files for dependency installation
COPY package.json package-lock.json ./

# Install all dependencies (using ci for reproducible builds)
RUN npm ci

# Copy the rest of the application code
COPY . .

# Build the Vite application for production
RUN npm run build

# Stage 2: Serve the application with NGINX (Unprivileged for Security)
FROM nginxinc/nginx-unprivileged:alpine-slim

USER root
# Upgrade all base packages to patch security vulnerabilities (e.g. OpenSSL/libcrypto3/libssl3)
RUN apk update && apk upgrade --no-cache && rm -rf /var/cache/apk/*
USER 101

# Copy the built assets from the builder stage to NGINX's serve directory
COPY --from=builder /app/dist /usr/share/nginx/html

# Expose the unprivileged port
EXPOSE 8080

# Add a healthcheck to ensure the container is running correctly
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost:8080/ || exit 1

# Start NGINX server
CMD ["nginx", "-g", "daemon off;"]
