#!/bin/bash
# ==============================================================================
# Módulo 15: Configuração e Organização do Menu (App Library) e Dock do COSMIC
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="COSMIC_MENU_DOCK"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Menu e Dock do COSMIC já configurados anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "15. ORGANIZAÇÃO DO MENU (APP LIBRARY) E DOCK DO COSMIC"

log_msg "INFO" "Configurando auto-tiling desligado e estado do teclado no compositor..."
mkdir -p "$REAL_HOME/.config/cosmic/com.system76.CosmicComp/v1"
echo "false" > "$REAL_HOME/.config/cosmic/com.system76.CosmicComp/v1/autotile"
echo "true" > "$REAL_HOME/.config/cosmic/com.system76.CosmicComp/v1/numlock_state"

log_msg "INFO" "Gerando categorias e abas organizadas na Biblioteca de Aplicativos..."
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
                "jstest-gtk",
                "io.github.antimicrox.antimicrox",
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
                "pwsh",
                "com.system76.CosmicTerm",
            ],
            exclude: [],
        ),
    ),
    (
        name: "Comunicação & Internet",
        icon: "chat-symbolic",
        filter: Categories(
            categories: [
                "Network",
                "Chat",
                "InstantMessaging",
                "WebBrowser",
            ],
            include: [
                "google-chrome",
                "brave-browser",
                "org.telegram.desktop",
                "com.rtosta.zapzap",
            ],
            exclude: [],
        ),
    ),
    (
        name: "Escritório & Trabalho Remoto",
        icon: "applications-office-symbolic",
        filter: Categories(
            categories: [
                "Office",
            ],
            include: [
                "vpn-mpms",
                "org.onlyoffice.desktopeditors",
                "masterpdfeditor5",
                "org.kde.okular",
                "forticlient",
                "org.remmina.Remmina",
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
                "vlc",
                "opentabletdriver",
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
                "org.openrgb.OpenRGB",
                "piper",
                "nm-connection-editor",
                "com.github.hluk.copyq",
                "menu.kando.Kando",
                "com.ranfdev.Celeste",
                "rclone-browser",
                "rclone-webui",
                "com.rcloneui.RcloneUI",
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

log_msg "INFO" "Configurando aplicativos favoritos..."
cat << 'EOF' > "$REAL_HOME/.config/cosmic/com.system76.CosmicAppList/v1/favorites"
[
    "google-chrome",
    "brave-browser",
    "com.system76.CosmicFiles",
    "antigravity-ide",
    "code",
    "org.remmina.Remmina",
    "com.system76.CosmicTerm",
    "com.system76.CosmicSettings",
]
EOF

# 3. Garante o Miniaplicativo de Controle de Mídia no canto inferior esquerdo da Dock
log_msg "INFO" "Configurando miniplayer de mídia na Dock..."
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

# Recarrega a biblioteca de aplicativos e o painel
pkill -f "cosmic-app-library" 2>/dev/null || true
pkill -f "cosmic-panel" 2>/dev/null || true

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Menu (App Library), favoritos e Dock configurados com sucesso em menos de 1 segundo."
