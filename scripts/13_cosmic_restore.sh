#!/bin/bash
# ==============================================================================
# Módulo 12: Restauração do Ambiente COSMIC, Temas, Dock e Biblioteca de Apps
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="COSMIC_RESTORE"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Ambiente COSMIC já restaurado e configurado anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "12. RESTAURAÇÃO E CUSTOMIZAÇÃO DO COSMIC DESKTOP"

COSMIC_BACKUP_DIR="$REAL_HOME/GoogleDrive_Pessoal/Organização/Backup_COSMIC"

if [ -d "$COSMIC_BACKUP_DIR" ]; then
    log_msg "INFO" "Restaurando configurações e pontes visuais do Google Drive..."
    if [ -d "$COSMIC_BACKUP_DIR/cosmic" ]; then cp -r "$COSMIC_BACKUP_DIR/cosmic" "$REAL_HOME/.config/"; fi
    for dir in "gtk-3.0" "gtk-4.0" "qt5ct" "qt6ct"; do
        if [ -d "$COSMIC_BACKUP_DIR/$dir" ]; then cp -r "$COSMIC_BACKUP_DIR/$dir" "$REAL_HOME/.config/"; fi
    done
fi

# 1. Desativa o modo auto-tiling e garante o NumLock ligado no COSMIC
mkdir -p "$REAL_HOME/.config/cosmic/com.system76.CosmicComp/v1"
echo "false" > "$REAL_HOME/.config/cosmic/com.system76.CosmicComp/v1/autotile"
echo "true" > "$REAL_HOME/.config/cosmic/com.system76.CosmicComp/v1/numlock_state"

# 2. Garante os Grupos / Pastas da Biblioteca de Aplicativos do COSMIC
mkdir -p "$REAL_HOME/.config/cosmic/com.system76.CosmicAppLibrary/v1"
mkdir -p "$REAL_HOME/.config/cosmic/com.system76.CosmicAppList/v1"

cat << 'EOF' > "$REAL_HOME/.config/cosmic/com.system76.CosmicAppLibrary/v1/groups"
[
    (
        name: "Jogos",
        icon: "input-gaming-symbolic",
        filter: Categories(
            categories: [
                "Game",
            ],
            include: [
                "steam",
                "com.heroicgameslauncher.hgl",
            ],
            exclude: [],
        ),
    ),
    (
        name: "Desenvolvimento",
        icon: "applications-engineering-symbolic",
        filter: Categories(
            categories: [
                "Development",
            ],
            include: [
                "antigravity-ide",
                "code",
            ],
            exclude: [],
        ),
    ),
    (
        name: "Escritório",
        icon: "applications-office-symbolic",
        filter: Categories(
            categories: [
                "Office",
            ],
            include: [
                "org.onlyoffice.desktopeditors",
                "com.dropbox.Client",
            ],
            exclude: [],
        ),
    ),
    (
        name: "Mídia",
        icon: "applications-multimedia-symbolic",
        filter: Categories(
            categories: [
                "AudioVideo",
                "Graphics",
            ],
            include: [
                "org.jellyfin.JellyfinDesktop",
                "org.gimp.GIMP",
            ],
            exclude: [],
        ),
    ),
    (
        name: "cosmic-utilities",
        icon: "folder-symbolic",
        filter: Categories(
            categories: [
                "Utility",
            ],
            include: [
                "nm-connection-editor",
                "com.github.hluk.copyq",
                "menu.kando.Kando",
            ],
            exclude: [
                "com.system76.CosmicEdit",
                "com.system76.CosmicFiles",
            ],
        ),
    ),
    (
        name: "cosmic-system",
        icon: "folder-symbolic",
        filter: Categories(
            categories: [
                "System",
            ],
            include: [
                "gnome-language-selector",
                "im-config",
                "org.freedesktop.IBus.Setup",
                "system76-driver",
            ],
            exclude: [
                "com.system76.CosmicStore",
                "com.system76.CosmicTerm",
            ],
        ),
    ),
]
EOF

cat << 'EOF' > "$REAL_HOME/.config/cosmic/com.system76.CosmicAppList/v1/favorites"
[
    "firefox",
    "com.system76.CosmicFiles",
    "antigravity-ide",
    "code",
    "com.system76.CosmicTerm",
    "com.system76.CosmicStore",
    "com.system76.CosmicSettings",
]
EOF

# 3. Garante o Miniaplicativo de Controle de Mídia no canto inferior esquerdo da Dock
mkdir -p "$REAL_HOME/.config/cosmic/com.system76.CosmicPanel.Dock/v1"
cat << 'EOF' > "$REAL_HOME/.config/cosmic/com.system76.CosmicPanel.Dock/v1/plugins_wings"
Some(([
    "com.github.MusicPlayer",
], [
    "com.system76.CosmicAppletTiling",
    "com.system76.CosmicAppletTime",
    "com.system76.CosmicAppletNotifications",
    "com.system76.CosmicAppletPower",
]))
EOF

chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/cosmic"

# Sincroniza de volta no Google Drive se montado
if [ -d "$COSMIC_BACKUP_DIR/cosmic" ]; then
    mkdir -p "$COSMIC_BACKUP_DIR/cosmic/com.system76.CosmicAppLibrary/v1"
    mkdir -p "$COSMIC_BACKUP_DIR/cosmic/com.system76.CosmicAppList/v1"
    mkdir -p "$COSMIC_BACKUP_DIR/cosmic/com.system76.CosmicPanel.Dock/v1"
    mkdir -p "$COSMIC_BACKUP_DIR/cosmic/com.system76.CosmicComp/v1"
    
    cp "$REAL_HOME/.config/cosmic/com.system76.CosmicAppLibrary/v1/groups" "$COSMIC_BACKUP_DIR/cosmic/com.system76.CosmicAppLibrary/v1/groups" 2>/dev/null || true
    cp "$REAL_HOME/.config/cosmic/com.system76.CosmicAppList/v1/favorites" "$COSMIC_BACKUP_DIR/cosmic/com.system76.CosmicAppList/v1/favorites" 2>/dev/null || true
    cp "$REAL_HOME/.config/cosmic/com.system76.CosmicPanel.Dock/v1/plugins_wings" "$COSMIC_BACKUP_DIR/cosmic/com.system76.CosmicPanel.Dock/v1/plugins_wings" 2>/dev/null || true
    cp "$REAL_HOME/.config/cosmic/com.system76.CosmicComp/v1/numlock_state" "$COSMIC_BACKUP_DIR/cosmic/com.system76.CosmicComp/v1/numlock_state" 2>/dev/null || true
    cp "$REAL_HOME/.config/cosmic/com.system76.CosmicComp/v1/autotile" "$COSMIC_BACKUP_DIR/cosmic/com.system76.CosmicComp/v1/autotile" 2>/dev/null || true
fi

# Recarrega o applet de painel e biblioteca de aplicativos
pkill -f "cosmic-app-library" 2>/dev/null || true
pkill -f "cosmic-panel" 2>/dev/null || true

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Configurações do COSMIC Desktop restauradas e sincronizadas com sucesso."
