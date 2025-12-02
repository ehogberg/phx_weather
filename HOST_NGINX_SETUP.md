# Host Nginx Setup Guide

This guide shows how to configure your existing host nginx to proxy to the PhxWeather Docker containers.

## Quick Setup

### For Single Instance (docker-compose.yml)

1. **Ensure your container is exposing port 4000**:
   ```bash
   docker-compose up -d
   ```

2. **Create nginx config**:
   ```bash
   sudo nano /etc/nginx/sites-available/phx-weather
   ```

3. **Paste this configuration**:
   ```nginx
   upstream phx_weather {
       server localhost:4000;
   }

   server {
       listen 80;
       server_name your-domain.com;  # CHANGE THIS

       location / {
           proxy_pass http://phx_weather;
           proxy_http_version 1.1;

           # Required for WebSocket support (LiveView)
           proxy_set_header Upgrade $http_upgrade;
           proxy_set_header Connection "upgrade";

           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
           proxy_set_header X-Forwarded-Proto $scheme;

           proxy_read_timeout 86400;
       }
   }
   ```

4. **Enable and test**:
   ```bash
   sudo ln -s /etc/nginx/sites-available/phx-weather /etc/nginx/sites-enabled/
   sudo nginx -t
   sudo systemctl reload nginx
   ```

### For Clustered Setup (docker-compose.clustered.yml)

1. **Start the cluster** (exposes ports 4001, 4002, 4003):
   ```bash
   docker-compose -f docker-compose.clustered.yml up -d
   ```

2. **Copy the provided config**:
   ```bash
   sudo cp nginx-host.conf /etc/nginx/sites-available/phx-weather
   sudo nano /etc/nginx/sites-available/phx-weather  # Edit to change your-domain.com
   ```

3. **Enable and test**:
   ```bash
   sudo ln -s /etc/nginx/sites-available/phx-weather /etc/nginx/sites-enabled/
   sudo nginx -t
   sudo systemctl reload nginx
   ```

## Adding SSL with Certbot

Once your basic config is working:

```bash
# Install certbot if needed
sudo apt install certbot python3-certbot-nginx

# Get SSL certificate (replace your-domain.com)
sudo certbot --nginx -d your-domain.com

# Certbot automatically:
# - Obtains the certificate from Let's Encrypt
# - Modifies your nginx config to use SSL
# - Sets up HTTPS redirect from HTTP
# - Configures auto-renewal
```

## Verification

```bash
# Check containers are running and ports are exposed
docker-compose ps

# Test direct connection to containers
curl http://localhost:4000  # Single instance
curl http://localhost:4001  # Clustered instance 1
curl http://localhost:4002  # Clustered instance 2
curl http://localhost:4003  # Clustered instance 3

# Test nginx proxy
curl http://your-domain.com

# Check nginx status
sudo systemctl status nginx

# View nginx logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

## Troubleshooting

### Port already in use

If port 4000 is already in use on the host, modify `.env`:
```bash
# For single instance
PORT=4010
```

Then update your nginx upstream to use the new port.

### Connection refused

```bash
# Verify containers are running
docker-compose ps

# Check container logs
docker-compose logs phx_weather

# Ensure firewall allows connections
sudo ufw status
sudo ufw allow 4000/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

### WebSocket not working

Ensure these headers are present in your nginx config:
```nginx
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_http_version 1.1;
```

### Load balancing not working

```bash
# Check all containers are healthy
docker-compose -f docker-compose.clustered.yml ps

# Test each backend directly
curl http://localhost:4001
curl http://localhost:4002
curl http://localhost:4003

# Check nginx upstream status in logs
sudo tail -f /var/log/nginx/error.log
```

## Key Differences from Docker nginx

| Aspect | Docker nginx (removed) | Host nginx (new) |
|--------|----------------------|------------------|
| Configuration | `nginx.conf` in repo | `/etc/nginx/sites-available/` |
| SSL/TLS | Manual config | Certbot auto-config |
| Port exposure | Internal only | Host ports 4001-4003 |
| Logging | Docker logs | `/var/log/nginx/` |
| Management | `docker-compose` | `systemctl` |

## Important .env Settings

Make sure your `.env` includes:

```bash
# Your actual domain
PHX_HOST=your-domain.com

# For clustered setup, this ensures WebSocket connections work
PHX_CHECK_ORIGIN=//your-domain.com

# If using custom port
PORT=4000
```

## Multiple Domains/Subdomains

If you want to run multiple sites on the same server:

```nginx
# weather.example.com
server {
    listen 80;
    server_name weather.example.com;

    location / {
        proxy_pass http://phx_weather_cluster;
        # ... proxy settings
    }
}

# app.example.com (different application)
server {
    listen 80;
    server_name app.example.com;

    location / {
        proxy_pass http://localhost:5000;
        # ... proxy settings
    }
}
```

## Reload vs Restart

```bash
# Reload (no downtime, preferred for config changes)
sudo systemctl reload nginx

# Restart (brief downtime)
sudo systemctl restart nginx

# Test config before reloading
sudo nginx -t
```
