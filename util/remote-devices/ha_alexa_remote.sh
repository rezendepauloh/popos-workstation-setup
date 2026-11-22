#!/bin/bash
# ==============================================================================
# Utilitário: Integração Home Assistant / Alexa (TTS & Rotinas via API REST)
# ==============================================================================
# Uso:
#   ./ha_alexa_remote.sh --check
#   ./ha_alexa_remote.sh --notify "Mensagem falada na Alexa"
# ==============================================================================

set -eo pipefail

C_RESET='\033[0m'
C_CYAN='\033[1;36m'
C_GREEN='\033[1;32m'
C_RED='\033[1;31m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"

if [ -f "$ENV_FILE" ] && [ ! -L "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

HA_URL="${HA_URL:-}"
HA_TOKEN="${HA_TOKEN:-}"
NOTIFY_SVC="${HA_ALEXA_NOTIFY_SERVICE:-notify.alexa_media}"

if [ -z "$HA_URL" ] || [ -z "$HA_TOKEN" ]; then
    echo -e "${C_RED}[ERRO] HA_URL e HA_TOKEN devem estar preenchidos no .env (Fail-Closed).${C_RESET}" >&2
    exit 1
fi

if [ "${1:-}" = "--notify" ]; then
    MSG="${2:-}"
    if [ -z "$MSG" ]; then
        echo -e "${C_RED}[ERRO] Informe a mensagem após --notify.${C_RESET}" >&2
        exit 1
    fi
    SVC_PATH="${NOTIFY_SVC/.//}"
    PAYLOAD=$(python3 -c 'import json, sys; print(json.dumps({"message": sys.argv[1]}))' "$MSG")
    curl -fsS -X POST "${HA_URL%/}/api/services/${SVC_PATH}" \
        -H "Authorization: Bearer ${HA_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" >/dev/null
    echo -e "${C_GREEN}[OK] Notificação enviada para ${NOTIFY_SVC}.${C_RESET}"
else
    echo -e "${C_CYAN}[INFO] Verificando API do Home Assistant em ${HA_URL}...${C_RESET}"
    curl -fsS "${HA_URL%/}/api/" -H "Authorization: Bearer ${HA_TOKEN}"
    echo ""
fi
