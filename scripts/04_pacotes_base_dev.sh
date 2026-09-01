#!/bin/bash
# ==============================================================================
# Módulo 04: Instalação de Pacotes Base e Ferramentas de Desenvolvimento
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="PACOTES_BASE"

if check_flag "$FLAG_NAME"; then
    log_msg "INFO" "⏭️  Pacotes base e ferramentas dev já instalados. Pulando..."
    exit 0
fi

log_msg "HEADER" "4. PACOTES BASE E FERRAMENTAS DEV"

log_msg "INFO" "Instalando utilitários essenciais via APT..."
sudo apt install -y \
    curl wget git build-essential \
    software-properties-common apt-transport-https ca-certificates gnupg lsb-release \
    htop btop neofetch p7zip-full unrar \
    vlc piper ratbagd jq tree rclone \
    zsh cargo rustc just pkg-config libssl-dev libdbus-1-dev libglib2.0-dev libasound2-dev \
    libxkbcommon-dev libwayland-dev libfontconfig1-dev libfreetype-dev libpipewire-0.3-dev libspa-0.2-dev

# Instalação do NVM (Node Version Manager)
log_msg "INFO" "Instalando Node Version Manager (NVM)..."
if [ ! -d "$REAL_HOME/.nvm" ]; then
    sudo -u "$REAL_USER" bash -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"
fi

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Pacotes base e ferramentas de desenvolvimento instalados com sucesso."
