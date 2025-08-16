# Docker Setup for Backend

This guide explains how to build, run, and deploy the backend application using Docker.

## Files Created

- `backend/Dockerfile` - Multi-stage Docker configuration
- `backend/.dockerignore` - Files to exclude from Docker build context
- `.github/workflows/docker-build-and-push.yml` - GitHub Actions workflow for CI/CD
- `docker-build.sh` - Local build and run script

## Local Development

### Prerequisites
- Docker installed on your machine
- Node.js (for local development without Docker)

### Building and Running Locally

1. **Using the provided script (Recommended):**
   ```bash
   ./docker-build.sh
   ```

2. **Manual build and run:**
   ```bash
   # Build the image
   docker build -t backend-app ./backend
   
   # Run the container
   docker run -d --name backend-container -p 3000:3000 backend-app
   ```

3. **Access the application:**
   - Main endpoint: http://localhost:3000
   - Health check: http://localhost:3000/api/health
   - Users API: http://localhost:3000/api/users

### Managing the Container

```bash
# View logs
docker logs backend-container

# Stop the container
docker stop backend-container

# Remove the container
docker rm backend-container

# View running containers
docker ps

# Enter the container shell
docker exec -it backend-container sh
```

## GitHub Actions Workflow

The workflow automatically:

1. **Triggers on:**
   - Push to `main` or `develop` branches (when backend files change)
   - Pull requests to `main` branch (when backend files change)

2. **Security Features:**
   - Uses GitHub Container Registry (ghcr.io)
   - Runs Trivy security scanning
   - Uses Docker BuildKit for enhanced security and performance

3. **Optimization:**
   - Multi-stage Docker builds
   - Docker layer caching
   - Only builds when backend files change

## Image Tagging Strategy

The workflow creates multiple tags:
- `latest` (for main branch)
- `main-<sha>` (for main branch with git SHA)
- `develop-<sha>` (for develop branch with git SHA)
- `pr-<number>` (for pull requests)

## Accessing the Container Registry

After the workflow runs, your images will be available at:
```
ghcr.io/sumansaurabh/task-bb/backend:latest
```

To pull and run the published image:
```bash
# Login to GitHub Container Registry
echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin

# Pull the image
docker pull ghcr.io/sumansaurabh/task-bb/backend:latest

# Run the image
docker run -d -p 3000:3000 ghcr.io/sumansaurabh/task-bb/backend:latest
```

## Environment Variables

The application supports these environment variables:
- `PORT` - Server port (default: 3000)

Example with custom port:
```bash
docker run -d -p 8080:8080 -e PORT=8080 backend-app
```

## Docker Image Details

- **Base Image:** node:18-alpine (lightweight Linux distribution)
- **Security:** Runs as non-root user
- **Size:** Optimized with multi-stage build and .dockerignore
- **Port:** Exposes port 3000

## Troubleshooting

1. **Build fails:**
   ```bash
   # Clear Docker cache
   docker system prune -a
   
   # Rebuild without cache
   docker build --no-cache -t backend-app ./backend
   ```

2. **Port already in use:**
   ```bash
   # Use different port
   docker run -d -p 8080:3000 backend-app
   ```

3. **Check application health:**
   ```bash
   curl http://localhost:3000/api/health
   ```
