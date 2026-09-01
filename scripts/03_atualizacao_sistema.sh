#!/bin/bash
# ==============================================================================
# Módulo 03: Atualização Geral do Sistema e Repositórios
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="UPDATE_SISTEMA"

if check_flag "$FLAG_NAME"; then
    log_msg "INFO" "⏭️  Atualização de sistema já realizada anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "3. ATUALIZAÇÃO DO SISTEMA"

log_msg "INFO" "Atualizando listas de repositórios e pacotes APT..."
sudo apt update
sudo apt full-upgrade -y

# Atualiza partição de recuperação Pop!_OS e firmwares do sistema (se disponíveis)
log_msg "INFO" "Verificando partição de recuperação Pop!_OS e firmwares..."
sudo pop-upgrade recovery upgrade from-release 2>/dev/null || true
fwupdmgr refresh --force 2>/dev/null || true

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Sistema e repositórios atualizados com sucesso."
