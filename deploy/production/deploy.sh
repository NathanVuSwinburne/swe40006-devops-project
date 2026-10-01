#!/usr/bin/env bash
# Deploys the latest code to production. Runs ON the production server as the ubuntu user.
#   - manually:          bash /opt/swe40006/app/deploy/production/deploy.sh
#   - from the pipeline: GitHub Actions -> AWS SSM -> this script (see ssm-deploy.sh)
#
# Steps: pull latest commit -> rebuild + restart containers -> check /health
#        -> if the health check fails, roll back to the previous commit.
#
# Everything is inside main() on purpose: this script lives in the repo it updates,
# so `git reset` can change this file while it is running. Bash reads the whole
# function before running it, so a changed file can't break the current run.
set -euo pipefail

main() {
  local REPO_DIR="${REPO_DIR:-/opt/swe40006/app}"
  local BRANCH="${DEPLOY_BRANCH:-main}"
  local PROD_DIR="$REPO_DIR/deploy/production"
  local COMPOSE=(docker compose -f "$PROD_DIR/docker-compose.prod.yml")
  local HEALTH_URL="http://localhost/health"
  LOG_FILE=/var/log/swe40006/deploy.log

  # First run only: create the .env with a random DB password (never committed)
  if [ ! -f "$PROD_DIR/.env" ]; then
    cat > "$PROD_DIR/.env" <<EOF
POSTGRES_USER=taskmanager
POSTGRES_DB=taskmanager
POSTGRES_PASSWORD=$(openssl rand -hex 16)
EOF
    chmod 600 "$PROD_DIR/.env"
    log "Created $PROD_DIR/.env"
  fi

  cd "$REPO_DIR"
  local PREVIOUS CURRENT
  PREVIOUS=$(git rev-parse HEAD)

  log "===== Deploy started (branch: $BRANCH)"
  git fetch --prune origin
  git checkout -q "$BRANCH" 2>/dev/null || git checkout -q -b "$BRANCH" "origin/$BRANCH"
  git reset -q --hard "origin/$BRANCH"
  CURRENT=$(git rev-parse --short HEAD)
  log "Deploying commit $CURRENT: $(git log -1 --pretty=%s)"

  if ! "${COMPOSE[@]}" up -d --build --remove-orphans 2>&1 | tee -a "$LOG_FILE"; then
    log "docker compose up FAILED (build or start error)"
  fi

  if health_ok "$HEALTH_URL"; then
    docker image prune -f >/dev/null
    log "===== Deploy SUCCESS: commit $CURRENT is live"
    return 0
  fi

  log "Health check FAILED for $CURRENT, rolling back to ${PREVIOUS:0:7}"
  "${COMPOSE[@]}" logs --tail 50 app 2>&1 | tee -a "$LOG_FILE"
  git reset -q --hard "$PREVIOUS"
  "${COMPOSE[@]}" up -d --build --remove-orphans 2>&1 | tee -a "$LOG_FILE"
  if health_ok "$HEALTH_URL"; then
    log "===== Deploy FAILED, rollback to ${PREVIOUS:0:7} succeeded"
  else
    log "===== Deploy FAILED, rollback ALSO failed - needs manual fix"
  fi
  return 1
}

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG_FILE"; }

health_ok() {
  local body
  for i in $(seq 1 20); do
    if body=$(curl -fsS --max-time 3 "$1" 2>/dev/null); then
      log "Health check passed (attempt $i): $body"
      return 0
    fi
    sleep 3
  done
  return 1
}

main "$@"
exit $?
