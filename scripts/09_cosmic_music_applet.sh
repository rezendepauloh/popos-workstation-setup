#!/bin/bash
# ==============================================================================
# Módulo 09: Compilação e Instalação do Miniaplicativo de Música do COSMIC
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="COSMIC_MUSIC_APPLET"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Miniaplicativo de música do COSMIC já instalado. Pulando..."
    exit 0
fi

log_msg "HEADER" "9. MINIAPLICATIVO DE CONTROLE DE MÍDIA (COSMIC)"

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
    log_msg "INFO" "Compilando applet em modo release..."
    cargo build --release --manifest-path music-player/Cargo.toml
fi

log_msg "INFO" "Instalando binário e metadados no sistema..."
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
sudo update-desktop-database /usr/share/applications 2>/dev/null || true

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Miniaplicativo de controle de mídia compilado e instalado com sucesso."
