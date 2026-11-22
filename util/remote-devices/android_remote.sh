#!/bin/bash
# ==============================================================================
# Utilitário: Controle & Limpeza Remota Android via ADB Wi-Fi / Tailscale + scrcpy
# ==============================================================================
# Uso:
#   ./android_remote.sh [--mode lan|tailscale] [--connect|--status|--clean-cache|--scrcpy|--disconnect]
# ==============================================================================

set -eo pipefail

C_RESET='\033[0m'
C_CYAN='\033[1;36m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[1;31m'
C_BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"

if [ -f "$ENV_FILE" ] && [ ! -L "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

if ! command -v adb >/dev/null 2>&1; then
    echo -e "${C_RED}[ERRO] 'adb' não instalado. Rode 'sudo apt install -y adb'.${C_RESET}" >&2
    exit 1
fi

MODE="lan"
ACTION="--status"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            MODE="${2:-lan}"
            shift 2
            ;;
        --connect|--status|--clean-cache|--scrcpy|--disconnect)
            ACTION="$1"
            shift
            ;;
        --help|-h)
            echo "Uso: $0 [--mode lan|tailscale] [--connect|--status|--clean-cache|--scrcpy|--disconnect]"
            exit 0
            ;;
        *)
            echo -e "${C_RED}[ERRO] Argumento desconhecido: $1${C_RESET}" >&2
            exit 1
            ;;
    esac
done

HOST="${REMOTE_ANDROID_LAN_HOST:-}"
if [ "$MODE" = "tailscale" ] && [ -n "${REMOTE_ANDROID_TS_HOST:-}" ]; then
    HOST="$REMOTE_ANDROID_TS_HOST"
fi
PORT="${REMOTE_ANDROID_PORT:-5555}"

if [[ -z "$HOST" ]] || [[ ! "$HOST" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo -e "${C_RED}[ERRO] REMOTE_ANDROID_LAN_HOST / REMOTE_ANDROID_TS_HOST ausente ou inválido no .env.${C_RESET}" >&2
    exit 1
fi
if [[ ! "$PORT" =~ ^[0-9]+$ ]]; then
    echo -e "${C_RED}[ERRO] REMOTE_ANDROID_PORT inválido no .env.${C_RESET}" >&2
    exit 1
fi

TARGET="${HOST}:${PORT}"

ensure_connected() {
    if ! adb devices | grep -q "^${TARGET}[[:space:]]\+device$"; then
        echo -e "${C_CYAN}[INFO] Conectando ao Android em ${TARGET}...${C_RESET}"
        adb connect "$TARGET"
    fi
    if ! adb devices | grep -q "^${TARGET}[[:space:]]\+device$"; then
        echo -e "${C_YELLOW}[!] Não foi possível conectar a ${TARGET}.${C_RESET}"
        echo -e "    Dica: No celular, ative 'Depuração sem fio' em Opções do Desenvolvedor (ou conecte USB uma vez e rode 'adb tcpip ${PORT}')."
        exit 1
    fi
}

case "$ACTION" in
    --connect)
        adb connect "$TARGET"
        adb -s "$TARGET" shell "echo 'Modelo:' \$(getprop ro.product.model) '| Android:' \$(getprop ro.build.version.release)"
        ;;
    --disconnect)
        adb disconnect "$TARGET"
        ;;
    --status)
        ensure_connected
        echo -e "${C_CYAN}${C_BOLD}=== STATUS DO ANDROID (${TARGET}) ===${C_RESET}"
        echo -e "Aparelho : $(adb -s "$TARGET" shell getprop ro.product.manufacturer | tr -d '\r') $(adb -s "$TARGET" shell getprop ro.product.model | tr -d '\r')"
        echo -e "Android  : $(adb -s "$TARGET" shell getprop ro.build.version.release | tr -d '\r')"
        echo -e "\n${C_BOLD}Bateria:${C_RESET}"
        adb -s "$TARGET" shell dumpsys battery | grep -E "level:|temperature:|status:" || true
        echo -e "\n${C_BOLD}Armazenamento (/data & /sdcard):${C_RESET}"
        adb -s "$TARGET" shell df -h /data /sdcard 2>/dev/null || true
        ;;
    --clean-cache)
        ensure_connected
        echo -e "${C_CYAN}${C_BOLD}=== LIMPEZA DE CACHE DE APPS ANDROID (${TARGET}) ===${C_RESET}"
        echo -e "${C_YELLOW}Espaço antes:${C_RESET}"
        adb -s "$TARGET" shell df -h /data | tail -n 1
        echo -e "${C_CYAN}[INFO] Executando trim-caches nativo do Android (sem root)...${C_RESET}"
        adb -s "$TARGET" shell pm trim-caches 999999999999G || adb -s "$TARGET" shell pm trim-caches 999999999999
        echo -e "${C_GREEN}[✔] Limpeza concluída! Espaço depois:${C_RESET}"
        adb -s "$TARGET" shell df -h /data | tail -n 1
        ;;
    --scrcpy)
        ensure_connected
        if ! command -v scrcpy >/dev/null 2>&1; then
            echo -e "${C_YELLOW}[!] 'scrcpy' não encontrado. Instale com: sudo apt update && sudo apt install -y scrcpy${C_RESET}" >&2
            exit 1
        fi
        echo -e "${C_CYAN}[INFO] Abrindo espelhamento interativo scrcpy para ${TARGET}...${C_RESET}"
        exec scrcpy -s "$TARGET" --stay-awake
        ;;
esac
