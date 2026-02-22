#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FLY_TOML="$REPO_ROOT/fly.toml"

readonly REQUIRED_SECRETS=(
  "GOOGLE_CLIENT_ID"
  "GOOGLE_CLIENT_SECRET"
  "GOOGLE_PROJECT_ID"
  "WEB_DEFAULT_PROVIDER"
  "WEB_CORS_ORIGINS"
)

readonly RECOMMENDED_SECRETS=(
  "OPENAI_API_KEY"
  "OPENAI_REASONING_EFFORT"
)

AUTO_CREATE=1
RUN_LOCAL_CHECKS=1
RUN_DEPLOY=1
RUN_HEALTH_CHECK=1
ALLOW_MISSING_REQUIRED_SECRETS=0
VOLUME_SIZE_GB=1
HEALTH_RETRIES=20
HEALTH_RETRY_SECONDS=3

APP_NAME=""
REGION=""
VOLUME_NAME=""
HEALTH_URL=""
FLY_BIN="${FLY_BIN:-}"
ORG_SLUG="${FLY_ORG:-}"

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
  scripts/fly-deploy-check.sh [options]

Description:
  One-click preflight + deploy + post-deploy health check for Fly.io.

Options:
  --app <name>                 Override Fly app name (default: fly.toml app)
  --region <region>            Override region (default: fly.toml primary_region)
  --volume-name <name>         Override volume name (default: fly.toml mounts.source)
  --volume-size <gb>           Volume size in GB when auto-creating (default: 1)
  --health-url <url>           Override health URL (default: https://<app>.fly.dev/health)
  --health-retries <n>         Health check retry count (default: 20)
  --health-delay <seconds>     Delay between health retries (default: 3)
  --fly-bin <cmd>              Fly CLI command override (fly or flyctl)
  --org <slug>                 Organization slug for app creation (optional)
  --skip-local-checks          Skip Next.js build and Python compile checks
  --skip-deploy                Skip fly deploy (run preflight only)
  --skip-health-check          Skip post-deploy /health check
  --no-auto-create             Do not auto-create missing app/volume
  --allow-missing-secrets      Continue even if required Fly secrets are missing
  -h, --help                   Show help

Examples:
  scripts/fly-deploy-check.sh
  scripts/fly-deploy-check.sh --app my-app --region nrt
  scripts/fly-deploy-check.sh --skip-deploy
EOF
}

toml_string() {
  local key="$1"
  local file="$2"

  awk -v target="$key" '
    $0 ~ "^[[:space:]]*" target "[[:space:]]*=" {
      if (match($0, /"[^"]+"/)) {
        print substr($0, RSTART + 1, RLENGTH - 2)
        exit
      }
    }
  ' "$file"
}

contains_line() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_error "Command not found: $cmd"
    exit 1
  fi
}

resolve_fly_command() {
  if [[ -n "$FLY_BIN" ]]; then
    require_command "$FLY_BIN"
    log_info "Using Fly CLI command: $FLY_BIN"
    return
  fi

  if command -v fly >/dev/null 2>&1; then
    FLY_BIN="fly"
    log_info "Using Fly CLI command: $FLY_BIN"
    return
  fi

  if command -v flyctl >/dev/null 2>&1; then
    FLY_BIN="flyctl"
    log_info "Using Fly CLI command: $FLY_BIN"
    return
  fi

  log_error "Fly CLI not found. Install flyctl (or ensure 'fly' is available)."
  exit 1
}

fly_cmd() {
  "$FLY_BIN" "$@"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --app)
        APP_NAME="$2"
        shift 2
        ;;
      --region)
        REGION="$2"
        shift 2
        ;;
      --volume-name)
        VOLUME_NAME="$2"
        shift 2
        ;;
      --volume-size)
        VOLUME_SIZE_GB="$2"
        shift 2
        ;;
      --health-url)
        HEALTH_URL="$2"
        shift 2
        ;;
      --health-retries)
        HEALTH_RETRIES="$2"
        shift 2
        ;;
      --health-delay)
        HEALTH_RETRY_SECONDS="$2"
        shift 2
        ;;
      --fly-bin)
        FLY_BIN="$2"
        shift 2
        ;;
      --org)
        ORG_SLUG="$2"
        shift 2
        ;;
      --skip-local-checks)
        RUN_LOCAL_CHECKS=0
        shift
        ;;
      --skip-deploy)
        RUN_DEPLOY=0
        shift
        ;;
      --skip-health-check)
        RUN_HEALTH_CHECK=0
        shift
        ;;
      --no-auto-create)
        AUTO_CREATE=0
        shift
        ;;
      --allow-missing-secrets)
        ALLOW_MISSING_REQUIRED_SECRETS=1
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

init_defaults_from_toml() {
  if [[ ! -f "$FLY_TOML" ]]; then
    log_error "fly.toml not found: $FLY_TOML"
    exit 1
  fi

  if [[ -z "$APP_NAME" ]]; then
    APP_NAME="$(toml_string "app" "$FLY_TOML")"
  fi
  if [[ -z "$REGION" ]]; then
    REGION="$(toml_string "primary_region" "$FLY_TOML")"
  fi
  if [[ -z "$VOLUME_NAME" ]]; then
    VOLUME_NAME="$(toml_string "source" "$FLY_TOML")"
  fi

  if [[ -z "$APP_NAME" ]]; then
    log_error "Could not resolve app name from fly.toml. Use --app."
    exit 1
  fi
  if [[ -z "$REGION" ]]; then
    REGION="nrt"
    log_warn "primary_region not found in fly.toml. Using default: $REGION"
  fi
  if [[ -z "$VOLUME_NAME" ]]; then
    VOLUME_NAME="clock_data"
    log_warn "mounts.source not found in fly.toml. Using default: $VOLUME_NAME"
  fi

  if [[ -z "$HEALTH_URL" ]]; then
    HEALTH_URL="https://${APP_NAME}.fly.dev/health"
  fi
}

check_fly_auth() {
  log_info "Checking flyctl authentication"
  if ! fly_cmd auth whoami >/dev/null 2>&1; then
    log_error "Not logged in to Fly.io. Run: ${FLY_BIN} auth login"
    exit 1
  fi
}

run_local_checks() {
  if [[ "$RUN_LOCAL_CHECKS" -eq 0 ]]; then
    log_info "Skipping local build checks"
    return
  fi

  require_command uv
  require_command npx

  log_info "Running frontend production build: web/frontend"
  (
    cd "$REPO_ROOT/web/frontend"
    npx next build
  )

  log_info "Running Python compile check: src + web/backend/app"
  (
    cd "$REPO_ROOT"
    uv run python -m compileall -q src web/backend/app
  )
}

ensure_app() {
  log_info "Checking Fly app: $APP_NAME"

  if fly_cmd apps list | awk 'NR > 1 && $1 != "" {print $1}' | grep -Fxq "$APP_NAME"; then
    log_info "Fly app exists"
    return
  fi

  if [[ "$AUTO_CREATE" -eq 0 ]]; then
    log_error "Fly app does not exist: $APP_NAME"
    log_error "Create it first: ${FLY_BIN} apps create $APP_NAME"
    exit 1
  fi

  log_warn "Fly app not found. Creating: $APP_NAME"

  local create_output
  local -a create_args=(apps create "$APP_NAME")
  if [[ -n "$ORG_SLUG" ]]; then
    create_args+=(--org "$ORG_SLUG")
    log_info "Using organization slug: $ORG_SLUG"
  fi

  if ! create_output="$(fly_cmd "${create_args[@]}" 2>&1)"; then
    printf '%s\n' "$create_output" >&2
    if printf '%s' "$create_output" | grep -Eqi 'payment information|add a credit card|buy credit|billing'; then
      log_error "Fly app creation blocked by billing requirements."
      log_error "1) Add payment method or credits in Fly dashboard"
      log_error "2) Or use a billed org: --org <slug>"
      log_error "3) Or create app manually then rerun with --no-auto-create"
    fi
    exit 1
  fi

  printf '%s\n' "$create_output"
}

ensure_volume() {
  log_info "Checking Fly volume '$VOLUME_NAME' in region '$REGION'"

  if fly_cmd volumes list --app "$APP_NAME" | awk 'NR > 1 && $3 != "" && $5 != "" {print $3 ":" $5}' | grep -Fxq "${VOLUME_NAME}:${REGION}"; then
    log_info "Volume exists"
    return
  fi

  if [[ "$AUTO_CREATE" -eq 0 ]]; then
    log_error "Volume not found: $VOLUME_NAME"
    log_error "Create it first: ${FLY_BIN} volumes create $VOLUME_NAME --app $APP_NAME --region $REGION --size $VOLUME_SIZE_GB"
    exit 1
  fi

  log_warn "Volume not found. Creating: $VOLUME_NAME"
  fly_cmd volumes create "$VOLUME_NAME" --app "$APP_NAME" --region "$REGION" --size "$VOLUME_SIZE_GB"
}

check_secrets() {
  log_info "Checking Fly secrets"

  local secrets_output
  if ! secrets_output="$(fly_cmd secrets list --app "$APP_NAME")"; then
    log_error "Failed to fetch Fly secrets list"
    exit 1
  fi

  mapfile -t secret_names < <(printf '%s\n' "$secrets_output" | awk 'NR > 1 {if ($1 == "*" && $2 != "") print $2; else if ($1 != "") print $1}')

  local missing_required=()
  local missing_recommended=()
  local key

  for key in "${REQUIRED_SECRETS[@]}"; do
    if ! contains_line "$key" "${secret_names[@]}"; then
      missing_required+=("$key")
    fi
  done

  for key in "${RECOMMENDED_SECRETS[@]}"; do
    if ! contains_line "$key" "${secret_names[@]}"; then
      missing_recommended+=("$key")
    fi
  done

  if [[ "${#missing_recommended[@]}" -gt 0 ]]; then
    log_warn "Missing recommended secrets: ${missing_recommended[*]}"
  fi

  if [[ "${#missing_required[@]}" -eq 0 ]]; then
    log_info "Required secrets are present"
    return
  fi

  if [[ "$ALLOW_MISSING_REQUIRED_SECRETS" -eq 1 ]]; then
    log_warn "Missing required secrets (continuing due to --allow-missing-secrets): ${missing_required[*]}"
    return
  fi

  log_error "Missing required secrets: ${missing_required[*]}"
  log_error "Set them with: ${FLY_BIN} secrets set KEY=value --app $APP_NAME"
  exit 1
}

validate_fly_config() {
  if fly_cmd config validate --help >/dev/null 2>&1; then
    log_info "Validating fly.toml"
    fly_cmd config validate --config "$FLY_TOML"
  else
    log_warn "fly config validate is not available in this flyctl version"
  fi
}

deploy_if_enabled() {
  if [[ "$RUN_DEPLOY" -eq 0 ]]; then
    log_info "Skipping deploy"
    return
  fi

  log_info "Deploying app to Fly.io"
  (
    cd "$REPO_ROOT"
    fly_cmd deploy --app "$APP_NAME"
  )
}

post_checks() {
  log_info "Checking Fly app status"
  fly_cmd status --app "$APP_NAME"

  if [[ "$RUN_HEALTH_CHECK" -eq 0 ]]; then
    log_info "Skipping health check"
    return
  fi

  require_command curl

  log_info "Checking health endpoint: $HEALTH_URL (retries=$HEALTH_RETRIES, delay=${HEALTH_RETRY_SECONDS}s)"

  local attempt=1
  local body
  while [[ "$attempt" -le "$HEALTH_RETRIES" ]]; do
    if body="$(curl -fsS --max-time 20 "$HEALTH_URL" 2>&1)"; then
      if printf '%s' "$body" | grep -Eq '"status"[[:space:]]*:[[:space:]]*"ok"'; then
        log_info "Health check passed on attempt $attempt/$HEALTH_RETRIES: $body"
        return
      fi
      log_warn "Health check attempt $attempt/$HEALTH_RETRIES returned unexpected body: $body"
    else
      log_warn "Health check attempt $attempt/$HEALTH_RETRIES failed: $body"
    fi

    if [[ "$attempt" -lt "$HEALTH_RETRIES" ]]; then
      sleep "$HEALTH_RETRY_SECONDS"
    fi
    attempt=$((attempt + 1))
  done

  log_error "Health endpoint did not become ready in time: $HEALTH_URL"
  exit 1
}

main() {
  parse_args "$@"
  init_defaults_from_toml

  resolve_fly_command
  require_command awk
  require_command grep

  log_info "Starting Fly.io deployment check"
  log_info "App=$APP_NAME Region=$REGION Volume=$VOLUME_NAME"
  if [[ -n "$ORG_SLUG" ]]; then
    log_info "Org=$ORG_SLUG"
  fi

  check_fly_auth
  run_local_checks
  validate_fly_config
  ensure_app
  ensure_volume
  check_secrets
  deploy_if_enabled
  post_checks

  log_info "Done. Fly deployment check workflow completed successfully."
  log_info "Useful commands:"
  log_info "  ${FLY_BIN} logs --app $APP_NAME"
  log_info "  ${FLY_BIN} releases --app $APP_NAME"
  log_info "  ${FLY_BIN} machine list --app $APP_NAME"
}

main "$@"
