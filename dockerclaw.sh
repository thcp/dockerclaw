#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

INI_FILE="openclaw.ini"

# Parse a section from the ini file. Outputs key=value lines.
ini_section() {
  local section="$1"
  awk -F ' = ' -v sec="[$section]" '
    $0 == sec { found=1; next }
    /^\[/     { found=0 }
    found && /=/ { gsub(/^[ \t]+|[ \t]+$/, "", $1); gsub(/^[ \t]+|[ \t]+$/, "", $2); print $1 "=" $2 }
  ' "$INI_FILE"
}

do_onboard() {
  local args=()
  while IFS='=' read -r key value; do
    if [[ "$value" == "true" ]]; then
      args+=("--${key}")
    elif [[ "$value" != "false" ]]; then
      args+=("--${key}" "$value")
    fi
  done < <(ini_section onboard)

  echo "Onboarding with: ${args[*]}"
  docker compose run --rm --no-deps --entrypoint node openclaw-gateway \
    dist/index.js onboard "${args[@]}"
}

# Generate JSON patch from ini, deep-merge into config in a single container run
do_configure() {
  local config_dir="${OPENCLAW_CONFIG_DIR:-./.openclaw}"
  local config_file="${config_dir}/openclaw.json"
  local patch
  patch=$(python3 scripts/ini2json.py "$INI_FILE")

  echo "Applying configuration..."
  python3 -c "
import json, sys

def deep_merge(base, patch):
    for k, v in patch.items():
        if k in base and isinstance(base[k], dict) and isinstance(v, dict):
            deep_merge(base[k], v)
        else:
            base[k] = v
    return base

config = json.load(open('$config_file'))
patch = json.loads('''$patch''')
json.dump(deep_merge(config, patch), open('$config_file', 'w'), indent=2)
print('Configuration applied.')
"
}

# Install skills (needs running gateway for ClawHub access)
do_install_skills() {
  while IFS='=' read -r key value; do
    [[ "$key" == "install" ]] && {
      echo "Installing skill: $value"
      docker compose run --rm openclaw-cli skills install "$value"
    }
  done < <(ini_section skills)
}

case "${1:-}" in
  setup)
    do_onboard
    echo ""
    echo "Setting file permissions..."
    chmod 700 "${OPENCLAW_CONFIG_DIR:-./.openclaw}"
    chmod 600 "${OPENCLAW_CONFIG_DIR:-./.openclaw}/openclaw.json" 2>/dev/null || true
    echo ""
    echo "Configuring..."
    do_configure
    echo ""
    echo "Starting gateway..."
    docker compose up -d openclaw-gateway
    echo "Waiting for healthy gateway..."
    sleep 25
    do_install_skills
    echo ""
    docker compose run --rm openclaw-cli dashboard --no-open
    echo ""
    echo "Open the dashboard URL above in your browser."
    echo "Waiting for device pairing request (60s timeout)..."
    for i in $(seq 1 12); do
      pending=$(docker compose run -T --rm openclaw-cli devices list --json 2>/dev/null \
        | python3 -c "import sys,json; data=json.load(sys.stdin); reqs=data.get('pending',[]); print(reqs[0]['requestId'] if reqs else '')" 2>/dev/null)
      if [[ -n "$pending" ]]; then
        docker compose run --rm openclaw-cli devices approve "$pending"
        echo "Device paired. Refresh your browser."
        break
      fi
      sleep 5
    done
    [[ -z "$pending" ]] && echo "No pairing request received. Run './dockerclaw.sh dashboard' to pair later."
    echo ""
    echo "Setup complete."
    ;;
  prune)
    docker compose down -v --remove-orphans
    rm -rf .openclaw
    echo "Pruned: containers, volumes, and config removed."
    ;;
  start)      docker compose up -d openclaw-gateway ;;
  stop)       docker compose down ;;
  restart)    docker compose down && docker compose up -d openclaw-gateway ;;
  logs)       docker compose logs -f openclaw-gateway ;;
  status)     docker compose ps ;;
  config)     shift; docker compose run --rm openclaw-cli config "$@" ;;
  skills)     shift; docker compose run --rm openclaw-cli skills "$@" ;;
  get-token)
    python3 -c "import json; print(json.load(open('${OPENCLAW_CONFIG_DIR:-./.openclaw}/openclaw.json'))['gateway']['auth']['token'])"
    ;;
  dashboard)
    docker compose run --rm openclaw-cli dashboard --no-open
    echo ""
    echo "Open the URL above in your browser, then press Enter to approve pairing."
    read -r
    pending=$(docker compose run -T --rm openclaw-cli devices list --json 2>/dev/null \
      | python3 -c "import sys,json; data=json.load(sys.stdin); [print(r['requestId']) for r in data.get('pending',[])]" 2>/dev/null)
    if [[ -z "$pending" ]]; then
      echo "No pending requests — you may already be paired."
    else
      for req in $pending; do
        echo "Approving $req..."
        docker compose run --rm openclaw-cli devices approve "$req"
      done
      echo "Device paired. Refresh your browser."
    fi
    ;;
  cli)        shift; docker compose run --rm openclaw-cli "$@" ;;
  *)
    echo "Usage: $0 <command>" >&2
    echo ""
    echo "  setup      — onboard + configure + start (reads from openclaw.ini)"
    echo "  prune      — remove all containers, volumes, and config"
    echo "  start      — start the gateway"
    echo "  stop       — stop all containers"
    echo "  restart    — restart the gateway"
    echo "  logs       — tail gateway logs"
    echo "  status     — show container status"
    echo "  get-token  — print the gateway auth token"
    echo "  config     — manage configuration (pass args to openclaw-cli)"
    echo "  skills     — manage skills (pass args to openclaw-cli)"
    echo "  dashboard  — print dashboard URL and approve device pairing"
    echo "  cli        — run any openclaw-cli command"
    exit 1
    ;;
esac
