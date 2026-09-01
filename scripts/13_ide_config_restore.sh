#!/bin/bash
# ==============================================================================
# Módulo 13: Restauração de Configurações das IDEs (VS Code & Antigravity IDE)
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="IDE_CONFIG_RESTORE"

if check_flag "$FLAG_NAME"; then
    log_msg "INFO" "⏭️  Configurações das IDEs já restauradas anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "13. RESTAURAÇÃO DE CONFIGURAÇÕES DAS IDES"

IDE_BACKUP_DIR="$REAL_HOME/GoogleDrive_Pessoal/Organização/VSCode_Antigravity"
VSCODE_USER_DIR="$REAL_HOME/.config/Code/User"
ANTIGRAVITY_USER_DIR="$REAL_HOME/.config/Antigravity IDE/User"

mkdir -p "$VSCODE_USER_DIR"
mkdir -p "$ANTIGRAVITY_USER_DIR"

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

    chown -R "$REAL_USER:$REAL_USER" "$VSCODE_USER_DIR"
    chown -R "$REAL_USER:$REAL_USER" "$ANTIGRAVITY_USER_DIR"
    
    set_flag "$FLAG_NAME"
    log_msg "SUCCESS" "Configurações sincronizadas para VS Code e Antigravity IDE."
else
    log_msg "WARN" "⚠️ Pasta de backup das IDEs não encontrada em '$IDE_BACKUP_DIR'."
fi
