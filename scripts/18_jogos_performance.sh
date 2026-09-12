#!/bin/bash
# ==============================================================================
# Módulo 15: Instalação de Jogos e Otimização de Performance Máxima
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="JOGOS_PERFORMANCE"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Jogos e perfil de performance já configurados anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "18. JOGOS, CONTROLES E PERFORMANCE MÁXIMA"

log_msg "INFO" "Instalando Steam, Gamemode, MangoHud e jstest-gtk (Testador de Controles)..."
sudo apt install -y steam gamemode mangohud jstest-gtk

log_msg "INFO" "Instalando Heroic Games Launcher e AntiMicroX (Mapeador de Controles) via Flatpak..."
flatpak install -y --system flathub com.heroicgameslauncher.hgl io.github.antimicrox.antimicrox

# Permissão para o Heroic acessar o SSD dedicado de jogos
flatpak override --user --filesystem=/mnt/nvme_01 com.heroicgameslauncher.hgl 2>/dev/null || true

# Criação da pasta de jogos no SSD dedicado
log_msg "INFO" "Verificando diretório /mnt/nvme_01/Jogos..."
if [ -d "/mnt/nvme_01" ]; then
    sudo mkdir -p /mnt/nvme_01/Jogos
    sudo chown -R "$REAL_USER:$REAL_USER" /mnt/nvme_01/Jogos
    sudo chmod -R 775 /mnt/nvme_01/Jogos
    log_msg "SUCCESS" "Diretório /mnt/nvme_01/Jogos configurado com permissão 775."
fi

# Configura o perfil de energia para Performance Máxima no Pop!_OS
log_msg "INFO" "Definindo perfil de energia para Performance Máxima..."
if command -v system76-power >/dev/null 2>&1; then
    sudo system76-power profile performance 2>/dev/null || true
elif command -v powerprofilesctl >/dev/null 2>&1; then
    powerprofilesctl set performance 2>/dev/null || true
fi

# Configuração e Nomeação Amigável de Controles Bluetooth (DualSense / Gamepads)
log_msg "INFO" "Configurando nomes amigáveis e reconexão automática para controles DualSense..."
if [ -n "$MAC_DUALSENSE_01" ]; then
    dev_path="/org/bluez/hci0/dev_$(echo "$MAC_DUALSENSE_01" | tr ':' '_')"
    busctl set-property org.bluez "$dev_path" org.bluez.Device1 Alias s "DualSense 01" 2>/dev/null || true
    bluetoothctl trust "$MAC_DUALSENSE_01" 2>/dev/null || true
    log_msg "SUCCESS" "Controle DualSense 01 ($MAC_DUALSENSE_01) configurado e confiável."
fi

if [ -n "$MAC_DUALSENSE_02" ]; then
    dev_path="/org/bluez/hci0/dev_$(echo "$MAC_DUALSENSE_02" | tr ':' '_')"
    busctl set-property org.bluez "$dev_path" org.bluez.Device1 Alias s "DualSense 02" 2>/dev/null || true
    bluetoothctl trust "$MAC_DUALSENSE_02" 2>/dev/null || true
    log_msg "SUCCESS" "Controle DualSense 02 ($MAC_DUALSENSE_02) configurado e confiável."
fi

# Fallback para quaisquer outros controles pareados no sistema
CONTROLLER_INDEX=1
for mac in $(bluetoothctl devices 2>/dev/null | grep -iE 'dualsense|wireless controller' | awk '{print $2}'); do
    if [ "$mac" != "$MAC_DUALSENSE_01" ] && [ "$mac" != "$MAC_DUALSENSE_02" ]; then
        dev_path="/org/bluez/hci0/dev_$(echo "$mac" | tr ':' '_')"
        busctl set-property org.bluez "$dev_path" org.bluez.Device1 Alias s "DualSense 0$CONTROLLER_INDEX" 2>/dev/null || true
        bluetoothctl trust "$mac" 2>/dev/null || true
        log_msg "SUCCESS" "Controle detectado $mac configurado como 'DualSense 0$CONTROLLER_INDEX' e confiável."
        CONTROLLER_INDEX=$((CONTROLLER_INDEX + 1))
    fi
done

# ==============================================================================
# Instalação e Configuração do Sunshine Game Streamer (Self-hosted GameStream)
# ==============================================================================
log_msg "INFO" "Configurando Sunshine Game Streamer..."
if ! command -v sunshine >/dev/null 2>&1; then
    log_msg "INFO" "Buscando release oficial mais recente do Sunshine (.deb para Ubuntu 24.04)..."
    SUNSHINE_DEB_URL=$(curl -sL https://api.github.com/repos/LizardByte/Sunshine/releases/latest | jq -r '.assets[] | select(.name | test("ubuntu24\\.04.*amd64\\.deb$")) | .browser_download_url' | head -n 1)

    if [ -n "$SUNSHINE_DEB_URL" ] && [ "$SUNSHINE_DEB_URL" != "null" ]; then
        log_msg "INFO" "Baixando Sunshine: $SUNSHINE_DEB_URL..."
        wget -qO /tmp/sunshine.deb "$SUNSHINE_DEB_URL"
        sudo apt install -y /tmp/sunshine.deb
        rm -f /tmp/sunshine.deb
        log_msg "SUCCESS" "Sunshine instalado com sucesso via .deb oficial."
    else
        log_msg "WARN" "Não foi possível localizar o .deb dinamicamente via GitHub API. Tentando fallback ou repositório..."
    fi
else
    log_msg "INFO" "Sunshine já está instalado no sistema ($(sunshine --version 2>/dev/null || true))."
fi

# Configuração de Permissões de Captura e Uinput (Gamepad Virtual e Entrada)
log_msg "INFO" "Configurando regras udev e permissões para /dev/uinput (Sunshine)..."
echo 'KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"' | sudo tee /etc/udev/rules.d/60-sunshine.rules > /dev/null
sudo udevadm control --reload-rules 2>/dev/null || true
sudo udevadm trigger 2>/dev/null || true

# Garante que o usuário pertença ao grupo input
sudo usermod -aG input "$REAL_USER" 2>/dev/null || true

# Configura capability no binário caso necessário para KMS/DRM capture
SUNSHINE_BIN=$(which sunshine || true)
if [ -n "$SUNSHINE_BIN" ]; then
    sudo setcap cap_sys_admin+ep "$SUNSHINE_BIN" 2>/dev/null || true
fi

# Habilita o serviço do Sunshine no systemd de usuário
log_msg "INFO" "Habilitando serviço do Sunshine no Systemd de Usuário..."
SUNSHINE_SVC="app-dev.lizardbyte.app.Sunshine.service"
if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    sudo -u "$REAL_USER" systemctl --user daemon-reload 2>/dev/null || true
    sudo -u "$REAL_USER" systemctl --user enable "$SUNSHINE_SVC" 2>/dev/null || true
    sudo -u "$REAL_USER" systemctl --user restart "$SUNSHINE_SVC" 2>/dev/null || true
else
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable "$SUNSHINE_SVC" 2>/dev/null || true
    systemctl --user restart "$SUNSHINE_SVC" 2>/dev/null || true
fi

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Jogos, permissões de armazenamento, controles, Sunshine e perfil de performance configurados."
