
#!/usr/bin/env bash
set -Eeuo pipefail

DOMAIN="$1"
PROYEK="$HOME/snapotter"

sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl --proto '=https' --tlsv1.2 -fsSL \
  https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo docker run --rm hello-world

install -d -m 700 "$PROYEK"
cd "$PROYEK"
curl --proto '=https' --tlsv1.2 -fsSLo docker-compose.yml \
  https://raw.githubusercontent.com/snapotter-hq/SnapOtter/v2.2.0/docker/docker-compose.yml

cat > compose.minimum.yml <<'YAML'
services:
  SnapOtter:
    image: snapotter/snapotter:2.2.0
    ports: !override
      - "127.0.0.1:1349:1349"
    environment:
      CONCURRENT_JOBS: "1"
      MAX_WORKER_THREADS: "2"
      MAX_BATCH_SIZE: "5"
      MAX_UPLOAD_SIZE_MB: "100"
      MAX_MEGAPIXELS: "50"
      MAX_VIDEO_DURATION_S: "300"
      PROCESSING_TIMEOUT_S: "600"
      SNAPOTTER_TELEMETRY: "0"
    mem_limit: 1152m
    memswap_limit: 1536m
    cpus: "1.5"
    shm_size: "128m"
  postgres:
    mem_limit: 384m
    memswap_limit: 512m
    cpus: "0.5"
  redis:
    mem_limit: 128m
    memswap_limit: 256m
    cpus: "0.5"
    command: >-
      redis-server
      --maxmemory-policy noeviction
      --maxmemory 64mb
      --appendonly yes
      --requirepass ${REDIS_PASSWORD:-snapotter}
YAML

sudo docker compose -f docker-compose.yml -f compose.minimum.yml config --quiet
sudo docker compose -f docker-compose.yml -f compose.minimum.yml pull
sudo docker compose -f docker-compose.yml -f compose.minimum.yml up -d --no-build

sudo apt-get install -y caddy
sudo tee /etc/caddy/Caddyfile >/dev/null <<EOF
{
    servers {
        protocols h1 h2
    }
}

$DOMAIN {
    reverse_proxy 127.0.0.1:1349 {
        flush_interval -1
        transport http {
            read_timeout 300s
            write_timeout 300s
        }
    }
}
EOF

sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl enable --now caddy
sudo systemctl reload caddy

curl --retry 30 --retry-delay 3 --retry-all-errors --max-time 10 -fsS \
  http://127.0.0.1:1349/api/v1/health
curl --retry 30 --retry-delay 5 --retry-all-errors --max-time 10 -fsS \
  "https://$DOMAIN/api/v1/health"
sudo docker compose -f docker-compose.yml -f compose.minimum.yml ps
