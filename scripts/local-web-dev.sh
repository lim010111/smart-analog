#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BACKEND_HOST="127.0.0.1"
BACKEND_PORT=8000
FRONTEND_HOST="127.0.0.1"
FRONTEND_PORT=3000
INSTALL_DEPS=1
WAIT_BACKEND=1
OPEN_BROWSER=0
DRY_RUN=0
KILL_EXISTING_FRONTEND=0

UV_BIN="${UV_BIN:-uv}"
NPM_BIN="${NPM_BIN:-npm}"

BACKEND_PID=""
FRONTEND_PID=""
CLEANUP_DONE=0
REUSE_FRONTEND=0

log_info() {
  printf '[INFO] %s\n' "$*"
}

log_warn() {
  printf '[WARN] %s\n' "$*"
}

log_error() {
  printf '[ERROR] %s\n' "$*" >&2
}

usage() {
  cat <<'EOF'
Usage:
  scripts/local-web-dev.sh [options]

Description:
  Run FastAPI backend + Next.js frontend together for localhost testing.
  If the frontend port is already in use, the script automatically picks the next free port.

Options:
  --backend-port <n>      Backend port (default: 8000)
  --frontend-port <n>     Frontend port (default: 3000)
  --kill-existing-frontend
                          Kill existing frontend dev process in this repo before start
  --skip-install          Skip dependency installation
  --no-wait-backend       Skip waiting for backend /health before frontend start
  --open                  Try opening browser automatically
  --dry-run               Print commands without running them
  -h, --help              Show help

Examples:
  scripts/local-web-dev.sh
  scripts/local-web-dev.sh --skip-install
  scripts/local-web-dev.sh --kill-existing-frontend
  scripts/local-web-dev.sh --backend-port 18000 --frontend-port 13000 --open
EOF
}

is_port_in_use() {
  local host="$1"
  local port="$2"

  python3 - "$host" "$port" <<'PY'
import socket
import sys

host = sys.argv[1]
port = int(sys.argv[2])

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    try:
        sock.bind((host, port))
    except OSError:
        sys.exit(0)

sys.exit(1)
PY
}

find_available_port() {
  local host="$1"
  local start_port="$2"
  local max_checks=100
  local port="$start_port"

  for ((i = 0; i < max_checks; i += 1)); do
    if ! is_port_in_use "$host" "$port"; then
      printf '%s' "$port"
      return 0
    fi
    port=$((port + 1))
  done

  return 1
}

is_frontend_dev_running() {
  local marker="$REPO_ROOT/web/frontend"
  ps -eo command \
    | grep -F "$marker" \
    | grep -E "next dev|npm .*run dev" \
    | grep -v grep >/dev/null 2>&1
}

frontend_dev_pids() {
  local marker="$REPO_ROOT/web/frontend"
  ps -eo pid=,command= \
    | awk -v marker="$marker" '
      index($0, marker) && ($0 ~ /next dev/ || $0 ~ /npm .*run dev/) {
        print $1
      }
    '
}

kill_existing_frontend_dev() {
  local pids
  pids="$(frontend_dev_pids)"
  if [[ -z "$pids" ]]; then
    log_info "No existing frontend dev process found for this repo."
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "[DRY-RUN] Would kill existing frontend process(es): $(echo "$pids" | tr '\n' ' ')"
    return 0
  fi

  log_warn "Killing existing frontend process(es): $(echo "$pids" | tr '\n' ' ')"
  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    kill "$pid" >/dev/null 2>&1 || true
  done <<< "$pids"

  for ((i = 0; i < 25; i += 1)); do
    if [[ -z "$(frontend_dev_pids)" ]]; then
      log_info "Existing frontend process(es) stopped."
      return 0
    fi
    sleep 0.2
  done

  local remaining
  remaining="$(frontend_dev_pids)"
  if [[ -n "$remaining" ]]; then
    log_warn "Force killing stubborn frontend process(es): $(echo "$remaining" | tr '\n' ' ')"
    while IFS= read -r pid; do
      [[ -z "$pid" ]] && continue
      kill -9 "$pid" >/dev/null 2>&1 || true
    done <<< "$remaining"
  fi
}

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_error "Command not found: $cmd"
    exit 1
  fi
}

is_valid_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  ((port >= 1 && port <= 65535)) || return 1
  return 0
}

run_cmd() {
  local desc="$1"
  shift
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "[DRY-RUN] $desc: $*"
    return
  fi
  log_info "$desc"
  "$@"
}

cleanup() {
  if [[ "$CLEANUP_DONE" -eq 1 ]]; then
    return
  fi
  CLEANUP_DONE=1

  if [[ -n "$FRONTEND_PID" ]] && kill -0 "$FRONTEND_PID" >/dev/null 2>&1; then
    log_info "Stopping frontend (PID: $FRONTEND_PID)"
    kill "$FRONTEND_PID" >/dev/null 2>&1 || true
  fi

  if [[ -n "$BACKEND_PID" ]] && kill -0 "$BACKEND_PID" >/dev/null 2>&1; then
    log_info "Stopping backend (PID: $BACKEND_PID)"
    kill "$BACKEND_PID" >/dev/null 2>&1 || true
  fi

  wait >/dev/null 2>&1 || true
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --backend-port)
        BACKEND_PORT="$2"
        shift 2
        ;;
      --frontend-port)
        FRONTEND_PORT="$2"
        shift 2
        ;;
      --kill-existing-frontend)
        KILL_EXISTING_FRONTEND=1
        shift
        ;;
      --skip-install)
        INSTALL_DEPS=0
        shift
        ;;
      --no-wait-backend)
        WAIT_BACKEND=0
        shift
        ;;
      --open)
        OPEN_BROWSER=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done
}

wait_for_backend() {
  local health_url="$1"
  local retries=40
  local delay=0.5

  for ((i = 1; i <= retries; i += 1)); do
    if curl -fsS "$health_url" >/dev/null 2>&1; then
      log_info "Backend is healthy: $health_url"
      return 0
    fi
    sleep "$delay"
  done

  log_error "Backend health check failed: $health_url"
  return 1
}

open_browser() {
  local url="$1"
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 || true
    return
  fi
  if command -v open >/dev/null 2>&1; then
    open "$url" >/dev/null 2>&1 || true
    return
  fi
  log_warn "No browser opener found. Open this URL manually: $url"
}

main() {
  parse_args "$@"

  if ! is_valid_port "$BACKEND_PORT"; then
    log_error "Invalid backend port: $BACKEND_PORT"
    exit 1
  fi

  if ! is_valid_port "$FRONTEND_PORT"; then
    log_error "Invalid frontend port: $FRONTEND_PORT"
    exit 1
  fi

  require_command "$UV_BIN"
  require_command "$NPM_BIN"
  require_command python3
  require_command curl

  local frontend_lock_file="$REPO_ROOT/web/frontend/.next/dev/lock"

  if [[ "$KILL_EXISTING_FRONTEND" -eq 1 ]]; then
    kill_existing_frontend_dev
    REUSE_FRONTEND=0
    if [[ -f "$frontend_lock_file" ]]; then
      if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "[DRY-RUN] Would remove frontend lock file: $frontend_lock_file"
      else
        log_warn "Removing frontend lock file: $frontend_lock_file"
        rm -f "$frontend_lock_file"
      fi
    fi
  fi

  if is_port_in_use "$BACKEND_HOST" "$BACKEND_PORT"; then
    log_error "Backend port ${BACKEND_HOST}:${BACKEND_PORT} is already in use. Use --backend-port to choose another port."
    exit 1
  fi

  if is_port_in_use "$FRONTEND_HOST" "$FRONTEND_PORT"; then
    local fallback_frontend_port
    fallback_frontend_port="$(find_available_port "$FRONTEND_HOST" "$((FRONTEND_PORT + 1))")" || {
      log_error "Frontend port ${FRONTEND_HOST}:${FRONTEND_PORT} is in use and no fallback port was found."
      exit 1
    }
    log_warn "Frontend port ${FRONTEND_HOST}:${FRONTEND_PORT} is in use. Switching to ${fallback_frontend_port}."
    FRONTEND_PORT="$fallback_frontend_port"
  fi

  local backend_url="http://${BACKEND_HOST}:${BACKEND_PORT}"
  local frontend_url="http://${FRONTEND_HOST}:${FRONTEND_PORT}"
  local frontend_origin="http://${FRONTEND_HOST}:${FRONTEND_PORT}"
  local cors_origins="${frontend_origin},http://localhost:${FRONTEND_PORT},http://127.0.0.1:${FRONTEND_PORT}"

  if [[ "$KILL_EXISTING_FRONTEND" -eq 0 ]] && [[ -f "$frontend_lock_file" ]]; then
    if is_frontend_dev_running; then
      REUSE_FRONTEND=1
      log_warn "Detected existing frontend dev process for this repo. Reusing it and skipping frontend start."
    else
      if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "[DRY-RUN] Would remove stale frontend lock file: $frontend_lock_file"
      else
        log_warn "Removing stale frontend lock file: $frontend_lock_file"
        rm -f "$frontend_lock_file"
      fi
    fi
  fi

  log_info "Repository root: $REPO_ROOT"
  log_info "Backend URL: $backend_url"
  log_info "Frontend URL: $frontend_url"
  log_info "Backend CORS origins: $cors_origins"

  if [[ "$INSTALL_DEPS" -eq 1 ]]; then
    run_cmd "Installing backend dependencies" "$UV_BIN" pip install -r "$REPO_ROOT/web/backend/requirements.txt"
    run_cmd "Installing frontend dependencies" "$NPM_BIN" --prefix "$REPO_ROOT/web/frontend" install
  else
    log_info "Skipping dependency installation"
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    run_cmd "Starting backend" env WEB_CORS_ORIGINS="$cors_origins" "$UV_BIN" run uvicorn web.backend.app.main:app --reload --host 0.0.0.0 --port "$BACKEND_PORT"
    if [[ "$REUSE_FRONTEND" -eq 1 ]]; then
      log_info "[DRY-RUN] Reusing existing frontend process; skipping frontend start"
    else
      run_cmd "Starting frontend" env NEXT_PUBLIC_BACKEND_URL="$backend_url" "$NPM_BIN" --prefix "$REPO_ROOT/web/frontend" run dev -- --hostname "$FRONTEND_HOST" --port "$FRONTEND_PORT"
    fi
    exit 0
  fi

  trap cleanup EXIT INT TERM

  log_info "Starting backend server"
  (
    cd "$REPO_ROOT"
    WEB_CORS_ORIGINS="$cors_origins" \
      "$UV_BIN" run uvicorn web.backend.app.main:app --reload --host 0.0.0.0 --port "$BACKEND_PORT"
  ) &
  BACKEND_PID="$!"

  if [[ "$WAIT_BACKEND" -eq 1 ]]; then
    wait_for_backend "$backend_url/health"
  fi

  if [[ "$REUSE_FRONTEND" -eq 1 ]]; then
    FRONTEND_PID=""
    log_info "Using existing frontend dev server (not managed by this script)"
  else
    log_info "Starting frontend server"
    (
      cd "$REPO_ROOT"
      NEXT_PUBLIC_BACKEND_URL="$backend_url" \
        "$NPM_BIN" --prefix "$REPO_ROOT/web/frontend" run dev -- --hostname "$FRONTEND_HOST" --port "$FRONTEND_PORT"
    ) &
    FRONTEND_PID="$!"
  fi

  if [[ "$OPEN_BROWSER" -eq 1 ]]; then
    open_browser "$frontend_url"
  else
    log_info "Open browser: $frontend_url"
  fi

  local exit_code=0
  if [[ -n "$FRONTEND_PID" ]]; then
    wait -n "$BACKEND_PID" "$FRONTEND_PID"
    exit_code=$?
  else
    wait "$BACKEND_PID"
    exit_code=$?
  fi
  if [[ "$exit_code" -ne 0 ]]; then
    log_warn "One of the processes exited with code $exit_code"
  fi
  exit "$exit_code"
}

main "$@"
