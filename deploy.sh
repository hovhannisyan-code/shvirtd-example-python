#!/usr/bin/env bash


set -euo pipefail

# --- Config (override via env) ---
REPO_URL="${REPO_URL:-https://github.com/hovhannisyan-code/shvirtd-example-python.git}"
APP_DIR="/opt/shvirtd-example-python"

log()  { echo -e "\033[1;32m[INFO]\033[0m $*"; }
err()  { echo -e "\033[1;31m[ERR ]\033[0m  $*" >&2; }

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    err "Run this script as root (sudo)."; exit 1
  fi
}

install_docker_official() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker already installed."; return
  fi
  log "Installing Docker Engine (official repo + Compose v2 plugin)..."
  apt-get update
  apt-get install -y ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" \
  > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin git
  systemctl enable --now docker
}

clone_or_update_repo() {
  if [ ! -d "$APP_DIR/.git" ]; then
    log "Cloning repo to $APP_DIR"
    git clone "$REPO_URL" "$APP_DIR"
  else
    log "Repo exists, pulling latest changes"
    git -C "$APP_DIR" pull --ff-only || true
  fi
}

ensure_env() {
  cd "$APP_DIR"
  if [ -f .env ]; then
    log ".env exists, not overwriting."
    return
  fi
  log "Creating .env with random secrets (override by exporting env vars before run)."
  MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-$(openssl rand -hex 16)}"
  MYSQL_DB="${MYSQL_DB:-example}"
  MYSQL_USER="${MYSQL_USER:-app}"
  MYSQL_PASSWORD="${MYSQL_PASSWORD:-$(openssl rand -hex 16)}"
  TABLE_NAME="${TABLE_NAME:-requests}"
  cat > .env <<EOF
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
MYSQL_DB=${MYSQL_DB}
MYSQL_USER=${MYSQL_USER}
MYSQL_PASSWORD=${MYSQL_PASSWORD}
TABLE_NAME=${TABLE_NAME}
EOF
  chmod 600 .env
}

compose_up() {
  cd "$APP_DIR"
  log "Starting stack (proxy.yaml included by compose.yaml)..."
  docker compose up -d --build
}

wait_mysql_healthy() {
  cd "$APP_DIR"
  log "Waiting for MySQL to become healthy..."
  for i in {1..30}; do
    cid="$(docker compose ps -q db || true)"
    [ -n "$cid" ] && state="$(docker inspect -f '{{.State.Health.Status}}' "$cid" 2>/dev/null || true)" || state=""
    [ "$state" = "healthy" ] && { log "MySQL is healthy."; return 0; }
    sleep 3
  done
  log "MySQL did not report healthy in time; continuing."
}

main() {
  require_root
  install_docker_official
  clone_or_update_repo
  ensure_env
  compose_up
  wait_mysql_healthy
  log "Done. If this is a cloud VM, ensure port 8090/TCP is open."
  log "Local test:   curl -L http://127.0.0.1:8090"
  log "Internet test: curl -L http://<public-ip>:8090"
}
main "$@"
