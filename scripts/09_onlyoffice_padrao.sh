#!/bin/bash
# ==============================================================================
# Módulo 08: Associação do OnlyOffice como Leitor Padrão de Documentos
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="ONLYOFFICE_DEFAULT"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  OnlyOffice já definido como padrão anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "8. DEFININDO ONLYOFFICE COMO APLICATIVO PADRÃO"

# Associa arquivos .docx, .xlsx e .pptx ao OnlyOffice
if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    sudo -u "$REAL_USER" xdg-mime default org.onlyoffice.desktopeditors.desktop application/vnd.openxmlformats-officedocument.wordprocessingml.document 2>/dev/null || true
    sudo -u "$REAL_USER" xdg-mime default org.onlyoffice.desktopeditors.desktop application/vnd.openxmlformats-officedocument.spreadsheetml.sheet 2>/dev/null || true
    sudo -u "$REAL_USER" xdg-mime default org.onlyoffice.desktopeditors.desktop application/vnd.openxmlformats-officedocument.presentationml.presentation 2>/dev/null || true
else
    xdg-mime default org.onlyoffice.desktopeditors.desktop application/vnd.openxmlformats-officedocument.wordprocessingml.document 2>/dev/null || true
    xdg-mime default org.onlyoffice.desktopeditors.desktop application/vnd.openxmlformats-officedocument.spreadsheetml.sheet 2>/dev/null || true
    xdg-mime default org.onlyoffice.desktopeditors.desktop application/vnd.openxmlformats-officedocument.presentationml.presentation 2>/dev/null || true
fi

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "OnlyOffice configurado como manipulador padrão de documentos office."
