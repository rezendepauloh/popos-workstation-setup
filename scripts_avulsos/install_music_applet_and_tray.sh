#!/bin/bash
# ==============================================================================
# Script: Instalação do Miniaplicativo de Controle de Mídia (Dock) e Bandeja (Painel)
# 1. Compila e instala o cosmic-applet-music-player (MPRIS, capas de álbum e controles)
# 2. Adiciona o reprodutor de mídia no canto inferior esquerdo da Dock do COSMIC
# 3. Libera permissões de bandeja (StatusNotifierWatcher) para o CopyQ (Flatpak)
# ==============================================================================

set -e

echo "🚀 Iniciando configuração do Miniaplicativo de Mídia e Bandeja do COSMIC..."

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# ==============================================================================
# 1. DEPENDÊNCIAS DE COMPILAÇÃO E SISTEMA
# ==============================================================================
echo "📦 1. Instalando ferramentas e bibliotecas de desenvolvimento..."
if [ "$(id -u)" -eq 0 ] || sudo -n true 2>/dev/null; then
    sudo apt update
    sudo apt install -y cargo rustc just pkg-config libssl-dev libdbus-1-dev git libglib2.0-dev libasound2-dev libxkbcommon-dev libwayland-dev libfontconfig1-dev libfreetype6-dev libpipewire-0.3-dev libspa-0.2-dev
fi

# ==============================================================================
# 2. COMPILAÇÃO E INSTALAÇÃO DO COSMIC-APPLET-MUSIC-PLAYER
# ==============================================================================
echo "🎵 2. Baixando e compilando o miniaplicativo de controle de mídia..."
BUILD_DIR="/tmp/cosmic-applet-music-player-build"
if [ ! -d "$BUILD_DIR" ]; then
    git clone --depth 1 https://github.com/Ebbo/cosmic-applet-music-player.git "$BUILD_DIR"
fi
cd "$BUILD_DIR"

if [ ! -f "target/release/cosmic-ext-applet-music-player" ]; then
    echo "  ⚙️ Compilando em modo Release (otimizado)..."
    cargo build --release --manifest-path music-player/Cargo.toml
fi

echo "  📥 Instalando binário e recursos no sistema..."
if [ "$(id -u)" -eq 0 ] || sudo -n true 2>/dev/null; then
    sudo install -Dm755 target/release/cosmic-ext-applet-music-player /usr/bin/cosmic-ext-applet-music-player
    
    # Instalar arquivo .desktop
    if [ -f res/com.github.MusicPlayer.desktop ]; then
        sudo install -Dm644 res/com.github.MusicPlayer.desktop /usr/share/applications/com.github.MusicPlayer.desktop
    fi
    
    # Instalar metainfo
    if [ -f res/com.github.MusicPlayer.metainfo.xml ]; then
        sudo install -Dm644 res/com.github.MusicPlayer.metainfo.xml /usr/share/metainfo/com.github.MusicPlayer.metainfo.xml
    fi
    
    # Instalar ícones se existirem
    if [ -d res/icons ]; then
        sudo cp -r res/icons/* /usr/share/icons/ 2>/dev/null || true
    fi
    
    sudo update-desktop-database /usr/share/applications 2>/dev/null || true
fi
rm -rf "$BUILD_DIR"
echo "  ✅ Miniaplicativo de Mídia instalado com sucesso em /usr/bin/cosmic-ext-applet-music-player."

# ==============================================================================
# 3. CONFIGURAR O MINIAPLICATIVO NA DOCK (LADO INFERIOR ESQUERDO)
# ==============================================================================
echo "⚓ 3. Posicionando o controle de mídia no canto inferior esquerdo da Dock..."

DOCK_CONFIG_DIR="$REAL_HOME/.config/cosmic/com.system76.CosmicPanel.Dock/v1"
mkdir -p "$DOCK_CONFIG_DIR"

cat << 'EOF' > "$DOCK_CONFIG_DIR/plugins_wings"
Some(([
    "com.github.MusicPlayer",
], [
    "com.system76.CosmicAppletTiling",
    "com.system76.CosmicAppletTime",
    "com.system76.CosmicAppletNotifications",
    "com.system76.CosmicAppletPower",
]))
EOF

chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/cosmic/com.system76.CosmicPanel.Dock"

# Sincroniza no Google Drive se montado
if [ -d "$REAL_HOME/GoogleDrive_Pessoal/Organização/Backup_COSMIC/cosmic" ]; then
    mkdir -p "$REAL_HOME/GoogleDrive_Pessoal/Organização/Backup_COSMIC/cosmic/com.system76.CosmicPanel.Dock/v1"
    cp "$DOCK_CONFIG_DIR/plugins_wings" "$REAL_HOME/GoogleDrive_Pessoal/Organização/Backup_COSMIC/cosmic/com.system76.CosmicPanel.Dock/v1/plugins_wings" 2>/dev/null || true
    echo "  ✅ Backup da Dock sincronizado no Google Drive."
fi

# ==============================================================================
# 4. PERMISSÕES DA BANDEJA PARA O COPYQ (FLATPAK)
# ==============================================================================
echo "✂️ 4. Liberando permissões de bandeja do Wayland para o CopyQ..."
if command -v flatpak >/dev/null 2>&1; then
    flatpak override --user --talk-name=org.kde.StatusNotifierWatcher --talk-name=org.freedesktop.StatusNotifierWatcher com.github.hluk.copyq 2>/dev/null || true
    if [ "$(id -u)" -eq 0 ] || sudo -n true 2>/dev/null; then
        sudo flatpak override --talk-name=org.kde.StatusNotifierWatcher --talk-name=org.freedesktop.StatusNotifierWatcher com.github.hluk.copyq 2>/dev/null || true
    fi
    echo "  ✅ Permissões de StatusNotifierWatcher aplicadas ao CopyQ."
fi

# ==============================================================================
# 5. RECARREGAMENTO DOS PAINÉIS DO COSMIC
# ==============================================================================
echo "🔄 5. Recarregando painéis e dock do COSMIC..."
pkill -f "cosmic-panel" 2>/dev/null || true
pkill -f "cosmic-applet" 2>/dev/null || true

echo ""
echo "🎉 Concluído com sucesso! O miniaplicativo de mídia está posicionado na sua Dock e a bandeja está configurada."
