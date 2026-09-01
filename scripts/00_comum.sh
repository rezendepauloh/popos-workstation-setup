#!/bin/bash
# ==============================================================================
# Módulo 00: Biblioteca Comum de Funções, Variáveis e Idempotência
# Utilizado por todos os scripts do Setup Pop!_OS
# ==============================================================================

# Definições de Cores
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[0;34m'
C_MAGENTA='\033[0;35m'
C_CYAN='\033[0;36m'
C_WHITE='\033[1;37m'
C_BOLD='\033[1m'

# Diretórios e Usuário Real
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPTS_DIR="$BASE_DIR/scripts"
PROGRESS_LOG="$BASE_DIR/.setup_progress.log"

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
REAL_UID=$(id -u "$REAL_USER" 2>/dev/null || echo 1000)

# Função de Log Formatado
log_msg() {
    local TYPE="$1"
    local MSG="$2"
    local TIMESTAMP
    TIMESTAMP="$(date +'%Y-%m-%d %H:%M:%S')"
    case "$TYPE" in
        "INFO")    echo -e "${C_CYAN}[INFO]${C_RESET} ${TIMESTAMP} - ${MSG}" ;;
        "SUCCESS") echo -e "${C_GREEN}[SUCCESS]${C_RESET} ${TIMESTAMP} - ${MSG}" ;;
        "WARN")    echo -e "${C_YELLOW}[WARN]${C_RESET} ${TIMESTAMP} - ${MSG}" ;;
        "ERROR")   echo -e "${C_RED}[ERROR]${C_RESET} ${TIMESTAMP} - ${MSG}" ;;
        "HEADER")  echo -e "\n${C_MAGENTA}${C_BOLD}=== ${MSG} ===${C_RESET}\n" ;;
        *)         echo -e "[LOG] ${TIMESTAMP} - ${MSG}" ;;
    esac
}

# Sistema de Checkpoint / Idempotência
check_flag() {
    local FLAG="$1"
    if [ -f "$PROGRESS_LOG" ] && grep -Fxq "$FLAG" "$PROGRESS_LOG"; then
        return 0 # Concluído anteriormente
    else
        return 1 # Pendente
    fi
}

set_flag() {
    local FLAG="$1"
    touch "$PROGRESS_LOG"
    if ! grep -Fxq "$FLAG" "$PROGRESS_LOG"; then
        echo "$FLAG" >> "$PROGRESS_LOG"
    fi
    log_msg "SUCCESS" "Etapa concluída e registrada: $FLAG"
}

clear_flag() {
    local FLAG="$1"
    if [ -f "$PROGRESS_LOG" ]; then
        sed -i "/^$FLAG$/d" "$PROGRESS_LOG"
    fi
}

# Helper para aplicar GSettings no contexto da sessão gráfica do usuário real
set_user_gsetting() {
    local SCHEMA="$1"
    local KEY="$2"
    local VALUE="$3"

    if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
        sudo -u "$REAL_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" gsettings set "$SCHEMA" "$KEY" "$VALUE" 2>/dev/null || true
    else
        gsettings set "$SCHEMA" "$KEY" "$VALUE" 2>/dev/null || true
    fi
}

# Verificação de montagem FUSE do Google Drive
verificar_gdrive_montado() {
    local GDRIVE_PATH="$REAL_HOME/GoogleDrive_Pessoal"
    if [ -d "$GDRIVE_PATH" ] && [ -n "$(ls -A "$GDRIVE_PATH" 2>/dev/null)" ]; then
        return 0
    else
        return 1
    fi
}
