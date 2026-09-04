#!/bin/bash
# ==============================================================================
# Módulo 10: Miniaplicativos Customizados do COSMIC (Mídia na Dock & Minimon no Painel)
# Instala o cosmic-applet-music-player (Dock) e o Minimon System Monitor (Painel)
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="COSMIC_APPLETS_CUSTOM"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Miniaplicativos customizados do COSMIC já instalados. Pulando..."
    exit 0
fi

log_msg "HEADER" "10. MINIAPLICATIVOS DO COSMIC (CONTROLE DE MÍDIA & MONITOR DO SISTEMA)"

# ------------------------------------------------------------------------------
# 1. Miniaplicativo de Mídia (Dock - Canto Inferior Esquerdo)
# ------------------------------------------------------------------------------
log_msg "INFO" "Verificando miniaplicativo de controle de mídia..."

if ! command -v cosmic-ext-applet-music-player >/dev/null 2>&1; then
    log_msg "INFO" "Garantindo dependências de compilação..."
    sudo apt update
    sudo apt install -y cargo rustc just pkg-config libssl-dev libdbus-1-dev git libglib2.0-dev libasound2-dev libxkbcommon-dev libwayland-dev libfontconfig1-dev libfreetype-dev libpipewire-0.3-dev libspa-0.2-dev

    BUILD_DIR="/tmp/cosmic-applet-music-player-build"
    if [ ! -d "$BUILD_DIR" ]; then
        log_msg "INFO" "Clonando repositório do cosmic-applet-music-player..."
        git clone --depth 1 https://github.com/Ebbo/cosmic-applet-music-player.git "$BUILD_DIR"
    fi
    cd "$BUILD_DIR"

    if [ ! -f "target/release/cosmic-ext-applet-music-player" ]; then
        log_msg "INFO" "Compilando applet de música em modo release..."
        cargo build --release --manifest-path music-player/Cargo.toml
    fi

    log_msg "INFO" "Instalando binário e metadados do applet de música no sistema..."
    sudo install -Dm755 target/release/cosmic-ext-applet-music-player /usr/bin/cosmic-ext-applet-music-player
    if [ -f res/com.github.MusicPlayer.desktop ]; then
        sudo install -Dm644 res/com.github.MusicPlayer.desktop /usr/share/applications/com.github.MusicPlayer.desktop
    fi
    if [ -f res/com.github.MusicPlayer.metainfo.xml ]; then
        sudo install -Dm644 res/com.github.MusicPlayer.metainfo.xml /usr/share/metainfo/com.github.MusicPlayer.metainfo.xml
    fi
    if [ -d res/icons ]; then
        sudo cp -r res/icons/* /usr/share/icons/ 2>/dev/null || true
    fi
    log_msg "SUCCESS" "Miniaplicativo de música instalado com sucesso."
else
    log_msg "INFO" "Miniaplicativo de música já instalado."
fi

# ------------------------------------------------------------------------------
# 2. Miniaplicativo Minimon (Painel Superior Direito - Dropdown de CPU/RAM/Disco/Rede)
# ------------------------------------------------------------------------------
log_msg "INFO" "Verificando miniaplicativo Minimon (Monitor do Sistema)..."

sudo apt install -y lm-sensors sysstat

if ! command -v cosmic-ext-applet-minimon >/dev/null 2>&1 && [ ! -f /usr/share/applications/io.github.cosmic_utils.minimon-applet.desktop ]; then
    TEMP_MINIMON_DEB=$(mktemp /tmp/minimon_XXXXXX.deb)
    MINIMON_URL="https://github.com/cosmic-utils/minimon-applet/releases/download/v1.2.0/cosmic-ext-applet-minimon_1.2.0_amd64.deb"

    log_msg "INFO" "Baixando pacote oficial do Minimon Applet da cosmic-utils..."
    rm -f "$TEMP_MINIMON_DEB"
    curl -fSL --progress-bar "$MINIMON_URL" -o "$TEMP_MINIMON_DEB"

    log_msg "INFO" "Instalando pacote Minimon no sistema..."
    sudo apt install -y "$TEMP_MINIMON_DEB" || sudo apt-get install -f -y
    rm -f "$TEMP_MINIMON_DEB"
    log_msg "SUCCESS" "Minimon System Monitor Applet instalado com sucesso."
else
    log_msg "INFO" "Minimon Applet já instalado."
fi

# ------------------------------------------------------------------------------
# 3. Registro dos Applets no Painel Superior e na Dock do COSMIC
# ------------------------------------------------------------------------------
log_msg "INFO" "Posicionando Minimon no Painel Superior e Mídia na Dock..."

mkdir -p "$REAL_HOME/.config/cosmic/com.system76.CosmicPanel.Panel/v1"
mkdir -p "$REAL_HOME/.config/cosmic/com.system76.CosmicPanel.Dock/v1"

# Painel Superior: Minimon no canto superior direito
cat << 'INNER_EOF' > "$REAL_HOME/.config/cosmic/com.system76.CosmicPanel.Panel/v1/plugins_wings"
Some(([
    "com.system76.CosmicPanelWorkspacesButton",
    "com.system76.CosmicPanelAppButton",
], [
    "io.github.cosmic_utils.minimon-applet",
    "com.system76.CosmicAppletInputSources",
    "com.system76.CosmicAppletStatusArea",
    "com.system76.CosmicAppletA11y",
    "com.system76.CosmicAppletTiling",
    "com.system76.CosmicAppletAudio",
    "com.system76.CosmicAppletBluetooth",
    "com.system76.CosmicAppletNetwork",
    "com.system76.CosmicAppletNotifications",
    "com.system76.CosmicAppletPower",
]))
INNER_EOF

# Dock: Controle de Mídia no canto inferior esquerdo
cat << 'INNER_EOF' > "$REAL_HOME/.config/cosmic/com.system76.CosmicPanel.Dock/v1/plugins_wings"
Some(([
    "com.github.MusicPlayer",
], [
    "com.system76.CosmicAppletTiling",
    "com.system76.CosmicAppletTime",
    "com.system76.CosmicAppletNotifications",
    "com.system76.CosmicAppletPower",
]))
INNER_EOF

chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/cosmic"
sudo update-desktop-database /usr/share/applications 2>/dev/null || true
pkill -f "cosmic-panel" 2>/dev/null || true

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Miniaplicativos customizados do COSMIC configurados e ativos no painel e dock."
