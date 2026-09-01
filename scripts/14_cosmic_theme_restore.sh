#!/bin/bash
# ==============================================================================
# Módulo 14: Restauração de Temas Visuais do COSMIC, GTK e Qt do Google Drive
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="COSMIC_THEME_RESTORE"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Temas visuais do COSMIC já restaurados anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "14. RESTAURAÇÃO DE TEMAS E PONTES VISUAIS (GOOGLE DRIVE)"

COSMIC_BACKUP_DIR="$REAL_HOME/GoogleDrive_Pessoal/Organização/Backup_COSMIC"

if [ -d "$COSMIC_BACKUP_DIR" ]; then
    log_msg "INFO" "Restaurando temas e pontes visuais (GTK 3/4, Qt5/6, COSMIC)..."
    
    # Restauração com rsync para copiar apenas arquivos novos/alterados
    if command -v rsync >/dev/null 2>&1; then
        if [ -d "$COSMIC_BACKUP_DIR/cosmic" ]; then
            rsync -au --info=progress2 "$COSMIC_BACKUP_DIR/cosmic/" "$REAL_HOME/.config/cosmic/" 2>/dev/null || cp -rn "$COSMIC_BACKUP_DIR/cosmic"/* "$REAL_HOME/.config/cosmic/" 2>/dev/null || true
        fi
        for dir in "gtk-3.0" "gtk-4.0" "qt5ct" "qt6ct"; do
            if [ -d "$COSMIC_BACKUP_DIR/$dir" ]; then
                mkdir -p "$REAL_HOME/.config/$dir"
                rsync -au "$COSMIC_BACKUP_DIR/$dir/" "$REAL_HOME/.config/$dir/" 2>/dev/null || cp -rn "$COSMIC_BACKUP_DIR/$dir"/* "$REAL_HOME/.config/$dir/" 2>/dev/null || true
            fi
        done
    else
        if [ -d "$COSMIC_BACKUP_DIR/cosmic" ]; then cp -rn "$COSMIC_BACKUP_DIR/cosmic" "$REAL_HOME/.config/" 2>/dev/null || true; fi
        for dir in "gtk-3.0" "gtk-4.0" "qt5ct" "qt6ct"; do
            if [ -d "$COSMIC_BACKUP_DIR/$dir" ]; then cp -rn "$COSMIC_BACKUP_DIR/$dir" "$REAL_HOME/.config/" 2>/dev/null || true; fi
        done
    fi
    
    chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/cosmic" "$REAL_HOME/.config/gtk-3.0" "$REAL_HOME/.config/gtk-4.0" "$REAL_HOME/.config/qt5ct" "$REAL_HOME/.config/qt6ct" 2>/dev/null || true
    log_msg "SUCCESS" "Temas restaurados do Google Drive com sucesso."
else
    log_msg "WARN" "Diretório '$COSMIC_BACKUP_DIR' não encontrado ou Google Drive não montado. Pulando restauração de temas da nuvem."
fi

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Etapa de temas visuais do COSMIC concluída com sucesso."
