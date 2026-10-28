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
    jq '.menus[0].shortcut = "Control+Shift+F10" | .menus[0].centered = false | .menus[0].useFixedPosition = false' "$KANDO_BACKUP_DIR/menu-settings-backup.json" > "$KANDO_CONFIG_DIR/menus.json"
    
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

    # Higieniza atalhos legados do Windows para comandos nativos do Linux (Pop!_OS / Flatpak)
    python3 -c "
import json
path = '$KANDO_CONFIG_DIR/menus.json'
try:
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    replacements = {
        'Chrome': 'google-chrome-stable',
        'Firefox': 'flatpak run org.mozilla.firefox',
        'MSEdge': 'brave-browser',
        'Google.Antigravity': 'antigravity',
        'Visual Studio Code': 'code',
        'Microsoft.VisualStudioCode': 'code',
        'Calculadora': 'flatpak run org.gnome.Calculator',
        'Microsoft.WindowsCalculator': 'flatpak run org.gnome.Calculator',
        'Navegador de Arquivos': 'cosmic-files',
        'explorer': 'cosmic-files',
        'Terminal': 'cosmic-term',
        'pwsh': 'cosmic-term',
        'CopyQ': 'copyq toggle',
        'WhatsApp': 'flatpak run com.rtosta.zapzap',
        'web.whatsapp': 'flatpak run com.rtosta.zapzap',
        'Kooha': 'flatpak run io.github.seadve.Kooha',
    }

    def update_actions(node):
        name = node.get('name', '')
        if node.get('type') == 'command' and 'data' in node:
            cmd = node['data'].get('command', '')
            for k, target in replacements.items():
                if k.lower() in name.lower() or k.lower() in cmd.lower():
                    node['data']['command'] = target
                    break
        actions = node.get('selectWorkflow', {}).get('actions', [])
        for a in actions:
            if a.get('type') == 'execute-command':
                cmd = a.get('command', '')
                for k, target in replacements.items():
                    if k.lower() in name.lower() or k.lower() in cmd.lower():
                        a['command'] = target
                        break
        for c in node.get('children', []):
            update_actions(c)

    for m in data.get('menus', []):
        update_actions(m.get('root', {}))

    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
except Exception:
    pass
" 2>/dev/null || true

    # Registra o atalho global nativo no compositor COSMIC (cosmic-comp)
    log_msg "INFO" "Registrando atalho global Ctrl+Shift+F10 no compositor COSMIC..."
    COSMIC_SHORTCUTS_DIR="$REAL_HOME/.config/cosmic/com.system76.CosmicSettings.Shortcuts/v1"
    mkdir -p "$COSMIC_SHORTCUTS_DIR"
    python3 -c "
import os
path = '$COSMIC_SHORTCUTS_DIR/custom'
content = ''
if os.path.exists(path):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

if 'kando --menu' not in content:
    entry = '''    (
        modifiers: [
            Ctrl,
            Shift,
        ],
        key: \"F10\",
    ): Spawn(\"/usr/local/bin/kando --menu \\\\\"Menu Paulo\\\\\"\"),\n'''
    if content.strip().endswith('}'):
        idx = content.rfind('}')
        new_content = content[:idx] + entry + '}\n'
    else:
        new_content = '{\n' + entry + '}\n'
    with open(path, 'w', encoding='utf-8') as f:
        f.write(new_content)
" 2>/dev/null || true

    chown -R "$REAL_USER:$REAL_USER" "$KANDO_CONFIG_DIR"
    chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/cosmic" 2>/dev/null || true
    set_flag "$FLAG_NAME"
    log_msg "SUCCESS" "Configurações do Kando restauradas com sucesso (atalhos adaptados para Linux e atalho global COSMIC configurado)."
else
    log_msg "WARN" "⚠️ Arquivos de backup do Kando não encontrados em '$KANDO_BACKUP_DIR'."
fi
