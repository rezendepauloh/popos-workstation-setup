#!/bin/bash
# ==============================================================================
# Módulo 16: Permissões de Sistema de Arquivos e Bandeja para Flatpaks
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="FLATPAK_PERMISSIONS"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Permissões e overrides de Flatpak já aplicados. Pulando..."
    exit 0
fi

log_msg "HEADER" "16. PERMISSÕES ADICIONAIS DE FLATPAK (OVERRIDES)"

log_msg "INFO" "Aplicando permissões de discos secundários..."
flatpak override --user --filesystem=/mnt/storage_700 org.onlyoffice.desktopeditors 2>/dev/null || true
flatpak override --user --filesystem=/mnt/storage_930 org.onlyoffice.desktopeditors 2>/dev/null || true
flatpak override --user --filesystem=/mnt org.gimp.GIMP 2>/dev/null || true

log_msg "INFO" "Liberando barramento StatusNotifierWatcher para o CopyQ..."
flatpak override --user --talk-name=org.kde.StatusNotifierWatcher --talk-name=org.freedesktop.StatusNotifierWatcher com.github.hluk.copyq 2>/dev/null || true
if [ "$(id -u)" -eq 0 ] || sudo -n true 2>/dev/null; then
    sudo flatpak override --talk-name=org.kde.StatusNotifierWatcher --talk-name=org.freedesktop.StatusNotifierWatcher com.github.hluk.copyq 2>/dev/null || true
fi

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Overrides de Flatpak aplicados com sucesso."
