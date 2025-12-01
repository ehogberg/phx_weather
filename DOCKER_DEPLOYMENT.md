# Docker Deployment Guide

This guide explains how to deploy PhxWeather as a Docker container on a server running dockerd, replacing the previous Kubernetes (GKE) deployment.

## Prerequisites

- A server with Docker and Docker Compose installed
- Domain name pointed to your server (optional but recommended)
- OpenWeather API key from https://home.openweathermap.org

## Deployment Options

PhxWeather can be deployed in two ways:

1. **Single Instance** - Simple deployment with one container
2. **Clustered** - Multiple instances behind nginx for high availability and load balancing

## Option 1: Single Instance Deployment

This is the simplest deployment option, suitable for most use cases.

### Setup Steps

1. **Clone the repository** on your server:
   ```bash
   git clone <repository-url>
   cd phx_weather
   ```

2. **Create environment file**:
   ```bash
   cp .env.example .env
   ```

3. **Edit `.env` file** with your values:
   ```bash
   # Generate secret key base
   docker run --rm phx_weather:latest /app/bin/phx_weather eval "IO.puts(:crypto.strong_rand_bytes(64) |> Base.encode64())"
   # Or use this command if image not built yet:
   # openssl rand -base64 64

   # Edit .env
   nano .env
   ```

   Set these values:
   - `OPENWEATHER_API_KEY` - Your API key from OpenWeather
   - `SECRET_KEY_BASE` - Generated secret (64 bytes, base64 encoded)
   - `PHX_HOST` - Your domain name (e.g., weather.example.com)
   - `PORT` - Port to expose (default: 4000)

4. **Build and start the container**:
   ```bash
   docker-compose up -d
   ```

5. **Verify deployment**:
   ```bash
   docker-compose ps
   docker-compose logs -f
   ```

   Visit `http://your-server:4000` to confirm it's running.

### Updating the Application

```bash
git pull
docker-compose build
docker-compose up -d
```

### Stopping the Application

```bash
docker-compose down
```

## Option 2: Clustered Deployment with Load Balancing

This option runs 3 instances of the application behind an nginx load balancer, providing high availability and better performance for multiple concurrent users.

### Setup Steps

1. **Clone the repository** on your server:
   ```bash
   git clone <repository-url>
   cd phx_weather
   ```

2. **Create environment file**:
   ```bash
   cp .env.example .env
   nano .env
   ```

   Set these values:
   - `OPENWEATHER_API_KEY` - Your API key
   - `SECRET_KEY_BASE` - Generated secret (use method from Option 1)
   - `PHX_HOST` - Your domain name
   - `PORT` - External port for nginx (default: 80)
   - `ERLANG_COOKIE` - A secret string for cluster communication (e.g., `openssl rand -base64 32`)

3. **Configure clustering** (if needed):

   The clustered setup requires configuring Elixir release for distribution. Add to `rel/env.sh.eex`:
   ```bash
   export RELEASE_DISTRIBUTION="${RELEASE_DISTRIBUTION:-none}"
   export RELEASE_NODE="${RELEASE_NODE:-phx_weather@127.0.0.1}"
   ```

4. **Build and start the cluster**:
   ```bash
   docker-compose -f docker-compose.clustered.yml up -d
   ```

5. **Verify deployment**:
   ```bash
   docker-compose -f docker-compose.clustered.yml ps
   docker-compose -f docker-compose.clustered.yml logs -f
   ```

   Visit `http://your-server` to confirm nginx is load balancing.

### Scaling

To change the number of instances, edit `docker-compose.clustered.yml` and add/remove service definitions, then update the nginx upstream configuration in `nginx.conf`.

### Updating the Clustered Application

```bash
git pull
docker-compose -f docker-compose.clustered.yml build
docker-compose -f docker-compose.clustered.yml up -d
```

## Production Recommendations

### 1. Use a Reverse Proxy with SSL

For production, put nginx or Caddy in front of your application with SSL/TLS:

**Option A: Update nginx.conf for SSL**
```nginx
server {
    listen 443 ssl http2;
    server_name your-domain.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    # ... rest of config
}
```

**Option B: Use Caddy** (easiest - automatic HTTPS)
Create `Caddyfile`:
```
your-domain.com {
    reverse_proxy phx_weather_1:4000 phx_weather_2:4000 phx_weather_3:4000 {
        lb_policy least_conn
        health_uri /
        health_interval 30s
    }
}
```

### 2. Set Up Log Aggregation

Configure Docker logging driver in docker-compose.yml:
```yaml
services:
  phx_weather:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

Or use a centralized logging solution like Loki or ELK.

### 3. Set Up Monitoring

Add Prometheus + Grafana monitoring:
- Use Phoenix telemetry metrics
- Monitor container health
- Track response times and error rates

### 4. Configure Backups

While PhxWeather is stateless, backup your configuration:
```bash
# Backup script
tar -czf phx-weather-backup-$(date +%Y%m%d).tar.gz .env docker-compose.yml
```

### 5. Set Up Automatic Updates

Use Watchtower for automatic image updates:
```yaml
watchtower:
  image: containrrr/watchtower
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock
  command: --interval 300 phx_weather
```

## CI/CD with GitHub Actions

### Option 1: Docker Hub Deployment

Update `.github/workflows/docker-deploy.yml`:

```yaml
name: Build and Push to Docker Hub

on:
  push:
    branches: [ main ]

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKER_USERNAME }}
          password: ${{ secrets.DOCKER_PASSWORD }}

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: |
            ${{ secrets.DOCKER_USERNAME }}/phx_weather:latest
            ${{ secrets.DOCKER_USERNAME }}/phx_weather:${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  deploy:
    needs: build-and-push
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to server
        uses: appleboy/ssh-action@master
        with:
          host: ${{ secrets.SERVER_HOST }}
          username: ${{ secrets.SERVER_USER }}
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          script: |
            cd /path/to/phx_weather
            docker-compose pull
            docker-compose up -d
```

### Option 2: Self-Hosted Registry

Set up a private Docker registry on your server and push images there.

## Troubleshooting

### Container won't start
```bash
# Check logs
docker-compose logs phx_weather

# Common issues:
# - Missing OPENWEATHER_API_KEY
# - Missing SECRET_KEY_BASE
# - Port already in use
```

### Can't connect to application
```bash
# Check if container is running
docker-compose ps

# Check if port is accessible
curl http://localhost:4000

# Check firewall
sudo ufw status
sudo ufw allow 4000/tcp
```

### Clustering issues
```bash
# Check if nodes can see each other
docker-compose -f docker-compose.clustered.yml exec phx_weather_1 /app/bin/phx_weather remote

# Verify ERLANG_COOKIE is the same across all nodes
docker-compose -f docker-compose.clustered.yml exec phx_weather_1 env | grep ERLANG_COOKIE
```

### Health check failing
```bash
# Check health status
docker inspect phx_weather | grep -A 10 Health

# Test health endpoint manually
docker exec phx_weather curl -f http://localhost:4000
```

## Environment Variables Reference

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OPENWEATHER_API_KEY` | Yes | - | API key from OpenWeather |
| `SECRET_KEY_BASE` | Yes | - | Phoenix secret (64 bytes base64) |
| `PHX_HOST` | No | `localhost` | Domain name for the application |
| `PORT` | No | `4000` | HTTP port |
| `PHX_CHECK_ORIGIN` | No | `//${PHX_HOST}` | Comma-separated allowed origins |
| `ERLANG_COOKIE` | Cluster only | - | Erlang distribution cookie |
| `RELEASE_DISTRIBUTION` | Cluster only | `none` | Set to `name` for clustering |
| `RELEASE_NODE` | Cluster only | - | Node name for clustering |
| `DNS_CLUSTER_QUERY` | Cluster only | - | Comma-separated node names |

## Migration from Kubernetes

If you're migrating from the previous GKE deployment:

1. **Extract secrets from Kubernetes**:
   ```bash
   kubectl get secret phx-weather-config -o jsonpath='{.data.openweather-service-api-key}' | base64 -d
   kubectl get secret phx-weather-config -o jsonpath='{.data.phoenix-secret-key-base}' | base64 -d
   ```

2. **Update DNS** to point to your new server instead of GKE load balancer

3. **Test deployment** on new server before switching DNS

4. **Decommission GKE resources** after successful migration:
   ```bash
   kubectl delete deployment phx-weather-application
   kubectl delete service phx-weather-service
   ```

## Support

For issues or questions, refer to the main README.md or open an issue in the repository.
