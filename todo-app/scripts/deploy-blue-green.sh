#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Blue-Green Zero-Downtime Deployment & Automated Rollback Script
# ==============================================================================

ECR_REGISTRY="${ECR_REGISTRY:-}"
ECR_REPOSITORY="${ECR_REPOSITORY:-todo-app}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
HEALTHCHECK_MAX_RETRIES="${HEALTHCHECK_MAX_RETRIES:-15}"
HEALTHCHECK_INTERVAL_SECS="${HEALTHCHECK_INTERVAL_SECS:-2}"

if [ -z "$ECR_REGISTRY" ]; then
  FULL_IMAGE="${ECR_REPOSITORY}:${IMAGE_TAG}"
else
  FULL_IMAGE="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"
fi

NETWORK_NAME="todo-network"
PROXY_CONTAINER="todo-proxy"
CONF_DIR="${HOME}/.todo-app/proxy-conf"
mkdir -p "$CONF_DIR"

echo "=================================================="
echo " Starting Blue-Green Deployment"
echo " Image: $FULL_IMAGE"
echo "=================================================="

# 1. Ensure Docker bridge network exists
if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  echo "Creating network $NETWORK_NAME..."
  docker network create "$NETWORK_NAME"
fi

# 2. Determine active slot and idle target slot
BLUE_RUNNING=$(docker ps --filter "name=^todo-app-blue$" --filter "status=running" -q)
GREEN_RUNNING=$(docker ps --filter "name=^todo-app-green$" --filter "status=running" -q)

if [ -n "$BLUE_RUNNING" ] && [ -z "$GREEN_RUNNING" ]; then
  ACTIVE_SLOT="blue"
  TARGET_SLOT="green"
elif [ -n "$GREEN_RUNNING" ] && [ -z "$BLUE_RUNNING" ]; then
  ACTIVE_SLOT="green"
  TARGET_SLOT="blue"
elif [ -n "$BLUE_RUNNING" ] && [ -n "$GREEN_RUNNING" ]; then
  # If both are running, default target to green and active to blue
  ACTIVE_SLOT="blue"
  TARGET_SLOT="green"
else
  # Cold start / initial deployment
  ACTIVE_SLOT=""
  TARGET_SLOT="blue"
fi

echo "Active Slot: ${ACTIVE_SLOT:-<none>} | Target Slot: $TARGET_SLOT"

# 3. Helper function to generate Nginx proxy configuration
generate_proxy_conf() {
  local target="$1"
  cat <<EOF > "$CONF_DIR/default.conf"
upstream app_upstream {
    server todo-app-${target}:8080;
}

server {
    listen 80;
    listen [::]:80;
    server_name _;

    location / {
        proxy_pass http://app_upstream;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
    }
}
EOF
}

# 4. Pull target image
echo "Pulling image $FULL_IMAGE..."
docker pull "$FULL_IMAGE"

# 5. Remove any stale container in the target slot and start new container
echo "Starting new container todo-app-$TARGET_SLOT..."
docker stop "todo-app-$TARGET_SLOT" >/dev/null 2>&1 || true
docker rm "todo-app-$TARGET_SLOT" >/dev/null 2>&1 || true

docker run -d \
  --name "todo-app-$TARGET_SLOT" \
  --network "$NETWORK_NAME" \
  --restart unless-stopped \
  "$FULL_IMAGE"

# 6. Health check polling on target slot
echo "Performing health checks on todo-app-$TARGET_SLOT (/health)..."
HEALTHY=false
for i in $(seq 1 "$HEALTHCHECK_MAX_RETRIES"); do
  if docker exec "todo-app-$TARGET_SLOT" wget --no-verbose --tries=1 --spider http://127.0.0.1:8080/health >/dev/null 2>&1; then
    echo "Health check passed (Attempt $i/$HEALTHCHECK_MAX_RETRIES)!"
    HEALTHY=true
    break
  fi
  echo "Waiting for health check to pass... ($i/$HEALTHCHECK_MAX_RETRIES)"
  sleep "$HEALTHCHECK_INTERVAL_SECS"
done

# 7. Traffic Switch or Rollback
if [ "$HEALTHY" = true ]; then
  echo "Target slot is healthy! Updating proxy configuration..."
  generate_proxy_conf "$TARGET_SLOT"

  # Ensure proxy container is running with mounted config
  PROXY_RUNNING=$(docker ps --filter "name=^${PROXY_CONTAINER}$" --filter "status=running" -q)
  if [ -z "$PROXY_RUNNING" ]; then
    echo "Starting $PROXY_CONTAINER on port 80..."
    docker stop "$PROXY_CONTAINER" >/dev/null 2>&1 || true
    docker rm "$PROXY_CONTAINER" >/dev/null 2>&1 || true
    docker run -d \
      --name "$PROXY_CONTAINER" \
      --network "$NETWORK_NAME" \
      -p 80:80 \
      -v "$CONF_DIR:/etc/nginx/conf.d:ro" \
      --restart unless-stopped \
      nginx:alpine-slim
  else
    echo "Reloading $PROXY_CONTAINER configuration for zero-downtime switch..."
    docker exec "$PROXY_CONTAINER" nginx -s reload
  fi

  # Stop previous active container after traffic switch
  if [ -n "$ACTIVE_SLOT" ] && [ "$ACTIVE_SLOT" != "$TARGET_SLOT" ]; then
    echo "Decommissioning old active container todo-app-$ACTIVE_SLOT..."
    docker stop "todo-app-$ACTIVE_SLOT" >/dev/null 2>&1 || true
    docker rm "todo-app-$ACTIVE_SLOT" >/dev/null 2>&1 || true
  fi

  echo "=================================================="
  echo " Deployment SUCCESSFUL! Active slot: $TARGET_SLOT"
  echo "=================================================="
  exit 0
else
  echo "=================================================="
  echo " HEALTH CHECK FAILED on todo-app-$TARGET_SLOT!"
  echo " Initiating AUTOMATIC ROLLBACK..."
  echo "=================================================="

  # Stop and remove unhealthy container
  docker stop "todo-app-$TARGET_SLOT" >/dev/null 2>&1 || true
  docker rm "todo-app-$TARGET_SLOT" >/dev/null 2>&1 || true

  if [ -n "$ACTIVE_SLOT" ]; then
    echo "Rollback complete: Old slot 'todo-app-$ACTIVE_SLOT' remains active with zero downtime."
  else
    echo "Rollback complete: No previous active slot existed."
  fi

  exit 1
fi
