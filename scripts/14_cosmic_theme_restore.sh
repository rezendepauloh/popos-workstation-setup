#!/bin/bash
# ==============================================================================
# Módulo 14: Restauração de Temas Visuais do COSMIC, GTK, Qt e Exceções de Janelas
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="COSMIC_THEME_RESTORE"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Temas visuais e regras do COSMIC já restaurados anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "14. RESTAURAÇÃO DE TEMAS, PONTES VISUAIS E REGRAS DE JANELAS"

# ------------------------------------------------------------------------------
# 1. Regras de Exceção do Auto-Tiling (Janelas Flutuantes Automáticas)
# ------------------------------------------------------------------------------
log_msg "INFO" "Configurando regras customizadas de janelas flutuantes (Tiling Exceptions)..."

mkdir -p "$REAL_HOME/.config/cosmic/com.system76.CosmicSettings.WindowRules/v1"

cat << 'EOF' > "$REAL_HOME/.config/cosmic/com.system76.CosmicSettings.WindowRules/v1/tiling_exception_custom"
[
	// Gerenciador de Arquivos
	(appid: "com.system76.CosmicFiles", titles: [".*"]),
	(appid: "com.system76.CosmicFilesDialog", titles: [".*"]),

	// Acesso Remoto
	(appid: "org.remmina.Remmina", titles: [".*"]),

	// Utilitários do Sistema e Hardware
	(appid: "org.gnome.Calculator", titles: [".*"]),
	(appid: "com.github.hluk.copyq", titles: [".*"]),
	(appid: "menu.kando.Kando", titles: [".*"]),
	(appid: "org.openrgb.OpenRGB", titles: [".*"]),
	(appid: "piper", titles: [".*"]),
	(appid: "jstest-gtk", titles: [".*"]),
	(appid: "io.github.antimicrox.antimicrox", titles: [".*"]),
	(appid: "com.ranfdev.Celeste", titles: [".*"]),
	(appid: "rclone-browser", titles: [".*"]),

	// Visualizadores e Ferramentas Rápidas
	(appid: "org.gnome.Loupe", titles: [".*"]),
	(appid: "org.gnome.eog", titles: [".*"]),
	(appid: "org.gnome.Evince", titles: [".*"]),
	(appid: "nm-connection-editor", titles: [".*"]),
]
EOF

# ------------------------------------------------------------------------------
# 2. Restauração de Temas a partir do Google Drive
# ------------------------------------------------------------------------------
COSMIC_BACKUP_DIR="$REAL_HOME/GoogleDrive_Pessoal/Organização/Backup_COSMIC"

if [ -d "$COSMIC_BACKUP_DIR" ]; then
    log_msg "INFO" "Restaurando temas e pontes visuais (GTK 3/4, Qt5/6, COSMIC)..."
    
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
    log_msg "SUCCESS" "Temas restaurados do Google Drive com sucesso."
else
    log_msg "WARN" "Diretório '$COSMIC_BACKUP_DIR' não encontrado ou Google Drive não montado. Pulando restauração de temas da nuvem."
fi

chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/cosmic" "$REAL_HOME/.config/gtk-3.0" "$REAL_HOME/.config/gtk-4.0" "$REAL_HOME/.config/qt5ct" "$REAL_HOME/.config/qt6ct" 2>/dev/null || true

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Etapa de temas visuais e regras de janelas do COSMIC concluída com sucesso."
