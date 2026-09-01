#!/bin/bash
# ==============================================================================
# Módulo 19: Limpeza Final, Otimização de Pacotes e Resumo
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="LIMPEZA_FINAL"

if check_flag "$FLAG_NAME"; then
    log_msg "INFO" "⏭️  Limpeza final já realizada anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "19. LIMPEZA FINAL E OTIMIZAÇÃO"

log_msg "INFO" "Removendo pacotes residuais e limpando cache..."
sudo apt autoremove -y --purge
sudo apt clean

if command -v flatpak >/dev/null 2>&1; then
    log_msg "INFO" "Removendo runtimes Flatpak não utilizados..."
    flatpak uninstall --unused -y 2>/dev/null || true
fi

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Limpeza concluída com sucesso."
