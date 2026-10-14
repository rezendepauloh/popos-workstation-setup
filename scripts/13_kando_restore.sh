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
    
    # Injeta atalho do gravador de tela Kooha no submenu de Utilitários se ainda não existir
    python3 -c "
import json
path = '$KANDO_CONFIG_DIR/menus.json'
try:
    with open(path, 'r') as f:
        data = json.load(f)
    utils = data['menus'][0]['root']['children'][0]['children'][0]
    names = [item.get('name', '') for item in utils.get('children', [])]
    if 'Gravar Tela (Kooha)' not in names:
        utils['children'].append({
            'type': 'command',
            'data': {
                'command': 'flatpak run io.github.seadve.Kooha',
                'detached': True,
                'isolated': False,
                'delayed': False
            },
            'name': 'Gravar Tela (Kooha)',
            'icon': 'video-camera',
            'iconTheme': 'system'
        })
        with open(path, 'w') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
except Exception:
    pass
" 2>/dev/null || true

    chown -R "$REAL_USER:$REAL_USER" "$KANDO_CONFIG_DIR"
    set_flag "$FLAG_NAME"
    log_msg "SUCCESS" "Configurações do Kando restauradas com sucesso."
else
    log_msg "WARN" "⚠️ Arquivos de backup do Kando não encontrados em '$KANDO_BACKUP_DIR'."
fi
