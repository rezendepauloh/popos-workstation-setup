#!/bin/bash
# ==============================================================================
# Módulo 13: Restauração de Configurações das IDEs (VS Code & Antigravity IDE)
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="IDE_CONFIG_RESTORE"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Configurações das IDEs já restauradas anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "16. RESTAURAÇÃO DE CONFIGURAÇÕES DE IDES (VS CODE & ANTIGRAVITY)"

IDE_BACKUP_DIR="$REAL_HOME/GoogleDrive_Pessoal/Organização/VSCode_Antigravity"
VSCODE_USER_DIR="$REAL_HOME/.config/Code/User"
ANTIGRAVITY_USER_DIR="$REAL_HOME/.config/Antigravity IDE/User"

mkdir -p "$VSCODE_USER_DIR"
mkdir -p "$ANTIGRAVITY_USER_DIR"

# Limpeza preventiva de locks residuais e caches de falhas (evita que as IDEs recusem abrir após um crash)
log_msg "INFO" "Limpando locks residuais e caches de falhas (code.lock, GPUCache, Crashpad)..."
rm -f "$REAL_HOME/.config/Antigravity IDE/code.lock" "$REAL_HOME/.config/Code/code.lock" 2>/dev/null || true
rm -rf "$REAL_HOME/.config/Antigravity IDE/GPUCache" \
       "$REAL_HOME/.config/Antigravity IDE/DawnGraphiteCache" \
       "$REAL_HOME/.config/Antigravity IDE/DawnWebGPUCache" \
       "$REAL_HOME/.config/Code/GPUCache" 2>/dev/null || true
rm -f "$REAL_HOME/.config/Antigravity IDE/Crashpad/pending"/* "$REAL_HOME/.config/Code/Crashpad/pending"/* 2>/dev/null || true

# Garante que as flags de inicialização usem Wayland nativo no COSMIC
mkdir -p "$REAL_HOME/.config"
for conf in "$REAL_HOME/.config/antigravity-flags.conf" "$REAL_HOME/.config/antigravity-ide-flags.conf" "$REAL_HOME/.config/code-flags.conf"; do
    cat << 'EOF' > "$conf"
--ozone-platform=wayland
EOF
done
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/"*-flags.conf 2>/dev/null || true

if [ -d "$IDE_BACKUP_DIR" ]; then
    log_msg "INFO" "Restaurando settings.json, keybindings e snippets a partir do Google Drive..."
    
    # 1. VS Code
    if [ -f "$IDE_BACKUP_DIR/settings.json" ]; then
        cp "$IDE_BACKUP_DIR/settings.json" "$VSCODE_USER_DIR/settings.json"
    fi
    if [ -f "$IDE_BACKUP_DIR/keybindings.json" ]; then
        cp "$IDE_BACKUP_DIR/keybindings.json" "$VSCODE_USER_DIR/keybindings.json"
    fi
    if [ -d "$IDE_BACKUP_DIR/snippets" ]; then
        cp -r "$IDE_BACKUP_DIR/snippets" "$VSCODE_USER_DIR/"
    fi

    # 2. Antigravity IDE
    if [ -f "$IDE_BACKUP_DIR/settings.json" ]; then
        cp "$IDE_BACKUP_DIR/settings.json" "$ANTIGRAVITY_USER_DIR/settings.json"
    fi
    if [ -f "$IDE_BACKUP_DIR/keybindings.json" ]; then
        cp "$IDE_BACKUP_DIR/keybindings.json" "$ANTIGRAVITY_USER_DIR/keybindings.json"
    fi
    if [ -d "$IDE_BACKUP_DIR/snippets" ]; then
        cp -r "$IDE_BACKUP_DIR/snippets" "$ANTIGRAVITY_USER_DIR/"
    fi

    # 3. Garante que 'keyboard.dispatch: keyCode' está configurado para Cedilha nativo em Wayland
    python3 -c "
import os
for p in [
    '$VSCODE_USER_DIR/settings.json',
    '$ANTIGRAVITY_USER_DIR/settings.json'
]:
    if os.path.exists(p):
        with open(p, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        if not any('keyboard.dispatch' in l for l in lines):
            for i, line in enumerate(lines):
                if '{' in line:
                    lines.insert(i + 1, '  \"keyboard.dispatch\": \"keyCode\",\n')
                    break
            with open(p, 'w', encoding='utf-8') as f:
                f.writelines(lines)
" 2>/dev/null || true

    # 4. Garante lançador local do Antigravity IDE compatível com Wayland
    if [ -f /usr/local/bin/antigravity ]; then
        mkdir -p "$REAL_HOME/.local/share/applications"
        cat << 'EOF' > "$REAL_HOME/.local/share/applications/antigravity.desktop"
[Desktop Entry]
Name=Antigravity
Comment=Google Antigravity IDE (Advanced Agentic Coding)
GenericName=Text Editor
Exec=/usr/local/bin/antigravity %F
Icon=antigravity
Type=Application
StartupNotify=false
StartupWMClass=antigravity-ide
Categories=Development;IDE;TextEditor;
MimeType=text/plain;inode/directory;application/x-code-workspace;
Keywords=vscode;development;ide;antigravity;agy;
EOF
        chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.local/share/applications/antigravity.desktop" 2>/dev/null || true
        update-desktop-database "$REAL_HOME/.local/share/applications" 2>/dev/null || true
    fi

    chown -R "$REAL_USER:$REAL_USER" "$VSCODE_USER_DIR"
    chown -R "$REAL_USER:$REAL_USER" "$ANTIGRAVITY_USER_DIR"
    
    set_flag "$FLAG_NAME"
    log_msg "SUCCESS" "Configurações sincronizadas para VS Code e Antigravity IDE (com proteção contra crashes)."
else
    log_msg "WARN" "⚠️ Pasta de backup das IDEs não encontrada em '$IDE_BACKUP_DIR'."
fi
