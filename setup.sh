#!/bin/bash

# Exit on error
set -e

# Function to copy .db.template files if corresponding .db files do not exist
copy_db_templates() {
    find . -name '*.db.template' -exec sh -c 'mkdir -p ./db; target="./db/$(basename "$1" .template)"; [ ! -f "$target" ] && cp "$1" "$target"' _ {} \;
}

# Function to check if running in interactive mode
is_interactive() {
    if [ -t 0 ] && [ -t 1 ]; then
        return 0
    else
        return 1
    fi
}

# Remove existing container if it exists
echo "Removing existing container if present..."
docker container rm -f zbojeijureq 2>/dev/null || true

# Rebuild the Docker image
echo "Building Docker image..."
docker build -t zbojeijureq .

# Copy database templates
echo "Setting up database templates..."
copy_db_templates

# Use $PWD for the current directory to avoid hardcoded paths
container_path="$PWD"
logs_dir="$container_path/logs"
db_dir="$container_path/db"
www_logs_dir="$container_path/www/logs" # for uploads of logs

# Create necessary directories
echo "Creating directories..."
mkdir -p "$logs_dir"
mkdir -p "$db_dir"
mkdir -p "$www_logs_dir"

# Set up docker run flags
DOCKER_FLAGS="-e TZ=Europe/Berlin --net=host --restart unless-stopped --name zbojeijureq"

# Add interactive flags only if in interactive mode
if is_interactive; then
    echo "Running in interactive mode..."
    DOCKER_FLAGS="$DOCKER_FLAGS -it"
else
    echo "Running in detached mode..."
    DOCKER_FLAGS="$DOCKER_FLAGS -d"
fi

# Check if we're on Windows
if [[ "$(uname)" =~ NT ]]; then
    echo "Windows detected"
    export MSYS_NO_PATHCONV=1
    echo "Container path: $container_path"
    docker run $DOCKER_FLAGS \
        -v "$container_path/db":"/ZbojeiJureq/db":Z \
        -v "$container_path/logs":"/ZbojeiJureq/logs":Z \
        -v "$container_path/www/logs":"/log_upload":Z \
        zbojeijureq
else
    echo "Starting container..."
    docker run $DOCKER_FLAGS \
        --mount type=bind,source="$db_dir",target=/ZbojeiJureq/db \
        --mount type=bind,source="$logs_dir",target=/ZbojeiJureq/logs \
        --mount type=bind,source="$www_logs_dir",target=/log_upload \
        zbojeijureq
fi

# Show container status
echo ""
echo "Container status:"
docker ps -a | grep zbojeijureq || echo "Container not found"

# If running in detached mode, show logs
if ! is_interactive; then
    echo ""
    echo "Container logs (last 20 lines):"
    sleep 2  # Give container time to start
    docker logs --tail 20 zbojeijureq 2>/dev/null || echo "Unable to fetch logs"
fi

echo ""
echo "Setup complete! Use 'docker logs -f zbojeijureq' to follow the logs."