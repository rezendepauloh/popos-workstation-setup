#!/bin/bash
# ==============================================================================
# Módulo 04: Instalação de Pacotes Base e Ferramentas de Desenvolvimento
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="PACOTES_BASE"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Pacotes base e ferramentas dev já instalados. Pulando..."
    exit 0
fi

log_msg "HEADER" "4. PACOTES BASE E FERRAMENTAS DEV"

log_msg "INFO" "Instalando utilitários essenciais via APT..."
sudo apt install -y \
    curl wget git build-essential \
    software-properties-common apt-transport-https ca-certificates gnupg lsb-release \
    htop btop neofetch p7zip-full unrar \
    piper ratbagd jq tree rclone \
    nautilus gvfs-backends syncthing \
    kdeconnect adb \
    zsh cargo rustc just pkg-config libssl-dev libdbus-1-dev libglib2.0-dev libasound2-dev \
    libxkbcommon-dev libwayland-dev libfontconfig1-dev libfreetype-dev libpipewire-0.3-dev libspa-0.2-dev

# Garante permissões de udev para dispositivos Android (ADB sem necessidade de root)
sudo usermod -aG plugdev "$REAL_USER" 2>/dev/null || true

# Instalação do scrcpy oficial (GitHub latest) para suporte a Android 15/16/17+
if [ ! -x /usr/local/bin/scrcpy ]; then
    log_msg "INFO" "Instalando scrcpy oficial (GitHub latest) em /opt/scrcpy..."
    SCRCPY_URL=$(curl -fsSL https://api.github.com/repos/Genymobile/scrcpy/releases/latest | jq -r '.assets[] | select(.name | test("scrcpy-linux-x86_64-.*\\.tar\\.gz$")) | .browser_download_url' 2>/dev/null || true)
    if [ -n "$SCRCPY_URL" ] && [ "$SCRCPY_URL" != "null" ]; then
        WORK_TMP_SCRCPY=$(mktemp -d /tmp/popos_scrcpy_XXXXXX)
        if curl -fSL "$SCRCPY_URL" -o "$WORK_TMP_SCRCPY/scrcpy.tar.gz"; then
            sudo rm -rf /opt/scrcpy
            sudo mkdir -p /opt/scrcpy
            sudo tar -xzf "$WORK_TMP_SCRCPY/scrcpy.tar.gz" -C /opt/scrcpy --strip-components=1
            sudo ln -sf /opt/scrcpy/scrcpy /usr/local/bin/scrcpy
            log_msg "SUCCESS" "scrcpy instalado em /usr/local/bin/scrcpy."
        fi
        rm -rf "$WORK_TMP_SCRCPY"
    else
        log_msg "WARN" "Não foi possível obter URL do scrcpy; instalando fallback via APT..."
        sudo apt install -y scrcpy || true
    fi
fi


# Instalação do NVM (Node Version Manager)
log_msg "INFO" "Instalando Node Version Manager (NVM)..."
if [ ! -d "$REAL_HOME/.nvm" ]; then
    sudo -u "$REAL_USER" bash -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"
fi

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Pacotes base e ferramentas de desenvolvimento instalados com sucesso."
