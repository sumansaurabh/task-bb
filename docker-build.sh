#!/bin/bash

# Script to build and run the Docker container locally
# Usage: ./docker-build.sh

set -e

IMAGE_NAME="backend-app"
CONTAINER_NAME="backend-container"
PORT=9999

echo "🐳 Building Docker image..."
docker build -t $IMAGE_NAME ./backend

echo "🧹 Cleaning up any existing container..."
docker stop $CONTAINER_NAME 2>/dev/null || true
docker rm $CONTAINER_NAME 2>/dev/null || true

echo "🚀 Running Docker container..."
docker run -d \
  --name $CONTAINER_NAME \
  -p $PORT:3000 \
  $IMAGE_NAME

echo "✅ Container is running!"
echo "🌐 Application is available at: http://localhost:$PORT"
echo "🩺 Health check: http://localhost:$PORT/api/health"
echo ""
echo "📋 Container logs:"
docker logs -f $CONTAINER_NAME &

echo ""
echo "To stop the container, run: docker stop $CONTAINER_NAME"
echo "To remove the container, run: docker rm $CONTAINER_NAME"
