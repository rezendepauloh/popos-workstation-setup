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

log_msg "HEADER" "17. JOGOS, CONTROLES E PERFORMANCE MÁXIMA"

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
CONTROLLER_INDEX=1
for mac in $(bluetoothctl devices 2>/dev/null | grep -iE 'dualsense|wireless controller' | awk '{print $2}'); do
    dev_path="/org/bluez/hci0/dev_$(echo "$mac" | tr ':' '_')"
    busctl set-property org.bluez "$dev_path" org.bluez.Device1 Alias s "DualSense 0$CONTROLLER_INDEX" 2>/dev/null || true
    bluetoothctl trust "$mac" 2>/dev/null || true
    log_msg "SUCCESS" "Controle DualSense $mac configurado como 'DualSense 0$CONTROLLER_INDEX' e confiável."
    CONTROLLER_INDEX=$((CONTROLLER_INDEX + 1))
done

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Jogos, permissões de armazenamento, controles e perfil de performance configurados."
