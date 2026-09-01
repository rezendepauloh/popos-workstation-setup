#!/bin/bash
# ==============================================================================
# Módulo 11: Restauração de Configurações e Menus do Kando (Google Drive)
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="KANDO_RESTORE"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Configurações do Kando já restauradas anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "13. RESTAURAÇÃO DO KANDO (PIE MENU)"

if ! verificar_gdrive_montado; then
    log_msg "WARN" "⚠️ Google Drive não está montado em '$REAL_HOME/GoogleDrive_Pessoal'. Pulando restauração por enquanto..."
    exit 0
fi

KANDO_CONFIG_DIR="$REAL_HOME/.config/kando"
KANDO_BACKUP_DIR="$REAL_HOME/GoogleDrive_Pessoal/Organização/Kando/Casa"
mkdir -p "$KANDO_CONFIG_DIR"

if [ -f "$KANDO_BACKUP_DIR/general-settings-backup.json" ] && [ -f "$KANDO_BACKUP_DIR/menu-settings-backup.json" ]; then
    log_msg "INFO" "Restaurando configurações e injetando atalho Control+Shift+F10..."
    cp "$KANDO_BACKUP_DIR/general-settings-backup.json" "$KANDO_CONFIG_DIR/config.json"
    jq '.menus[0].shortcut = "Control+Shift+F10" | .menus[0].centered = true' "$KANDO_BACKUP_DIR/menu-settings-backup.json" > "$KANDO_CONFIG_DIR/menus.json"
    chown -R "$REAL_USER:$REAL_USER" "$KANDO_CONFIG_DIR"
    set_flag "$FLAG_NAME"
    log_msg "SUCCESS" "Configurações do Kando restauradas com sucesso."
else
    log_msg "WARN" "⚠️ Arquivos de backup do Kando não encontrados em '$KANDO_BACKUP_DIR'."
fi
