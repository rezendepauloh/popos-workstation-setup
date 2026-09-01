#!/bin/bash
# ==============================================================================
# Módulo 11: Suporte, Drivers e Conexão Bluetooth da Mesa Digitalizadora Wacom (Intuos Pro)
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="WACOM_TABLET"

if check_flag "$FLAG_NAME"; then
    log_msg "INFO" "⏭️  Mesa Wacom já configurada anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "11. CONFIGURAÇÃO DA MESA DIGITALIZADORA WACOM (INTUOS PRO)"

# 1. Instalação das bibliotecas nativas da Wacom e do OpenTabletDriver (GUI)
log_msg "INFO" "Instalando utilitários Wacom, .NET Runtime e OpenTabletDriver (GUI)..."
sudo apt update
sudo apt install -y libwacom-bin libwacom-common libwacom9 xserver-xorg-input-wacom dotnet-runtime-8.0

OTD_URL="https://github.com/OpenTabletDriver/OpenTabletDriver/releases/download/v0.6.7/opentabletdriver_0.6.7-1_x64.deb"
wget -qO /tmp/opentabletdriver.deb "$OTD_URL"
sudo apt install -y /tmp/opentabletdriver.deb
rm -f /tmp/opentabletdriver.deb

# 2. Carregamento automático do módulo de kernel 'wacom'
log_msg "INFO" "Garantindo módulo de kernel 'wacom' carregado no boot..."
sudo modprobe wacom 2>/dev/null || true
echo "wacom" | sudo tee /etc/modules-load.d/wacom.conf > /dev/null

# 3. Regras Udev e permissões para dispositivos Wacom e OpenTabletDriver
log_msg "INFO" "Configurando regras Udev para permissões de entrada e caneta..."
cat << 'EOF' | sudo tee /etc/udev/rules.d/99-wacom.rules > /dev/null
KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput", MODE="0660", GROUP="input"
SUBSYSTEM=="input", ATTRS{idVendor}=="056a", MODE="0664", GROUP="input"
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="056a", MODE="0664", GROUP="input"
EOF
sudo udevadm control --reload-rules 2>/dev/null || true
sudo udevadm trigger 2>/dev/null || true

# Adiciona o usuário aos grupos de input
sudo usermod -aG input "$REAL_USER" 2>/dev/null || true

# 4. Habilita o serviço em segundo plano do OpenTabletDriver para o usuário
log_msg "INFO" "Ativando serviço do OpenTabletDriver para o usuário..."
if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user daemon-reload 2>/dev/null || true
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user enable opentabletdriver.service 2>/dev/null || true
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user restart opentabletdriver.service 2>/dev/null || true
else
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable opentabletdriver.service 2>/dev/null || true
    systemctl --user restart opentabletdriver.service 2>/dev/null || true
fi

# 5. Detecção e Emparelhamento Bluetooth Automatizado
log_msg "INFO" "Verificando dispositivos Wacom Bluetooth emparelhados..."
WACOM_MAC=$(bluetoothctl devices 2>/dev/null | grep -iE 'Intuos|Wacom' | head -n 1 | awk '{print $2}' || true)

if [ -n "$WACOM_MAC" ]; then
    log_msg "INFO" "Dispositivo Wacom detectado no Bluetooth: $WACOM_MAC"
    log_msg "INFO" "Definindo dispositivo como confiável (trust) para auto-reconexão..."
    bluetoothctl trust "$WACOM_MAC" 2>/dev/null || true
    
    # Tenta conectar se a mesa estiver ligada
    log_msg "INFO" "Tentando estabelecer conexão Bluetooth..."
    if bluetoothctl connect "$WACOM_MAC" 2>/dev/null; then
        log_msg "SUCCESS" "Mesa Wacom conectada com sucesso via Bluetooth ($WACOM_MAC)!"
    else
        log_msg "INFO" "Mesa Wacom registrada como confiável. Quando ligar a mesa ou colocá-la em modo de pareamento, ela conectará automaticamente."
    fi
else
    log_msg "INFO" "Nenhuma mesa Wacom emparelhada anteriormente no Bluetooth."
    log_msg "INFO" "Dica: Para emparelhar sua Intuos Pro via Bluetooth, segure o botão central do Touch Ring por 3 segundos até o LED azul piscar rapidamente."
fi

# 6. Configurações de Modo Canhoto (Left-Handed / Rotação 180°) e Proporção 1:1
log_msg "INFO" "Aplicando modo canhoto (180° de rotação) e trava de proporção 1:1..."
set_user_gsetting "org.gnome.desktop.peripherals.tablet" "keep-aspect" "true"
set_user_gsetting "org.gnome.desktop.peripherals.tablet" "left-handed" "true"

if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    sudo -u "$REAL_USER" dconf write /org/gnome/desktop/peripherals/tablets/056a:0393/left-handed true 2>/dev/null || true
    sudo -u "$REAL_USER" dconf write /org/gnome/desktop/peripherals/tablets/056a:0393/keep-aspect true 2>/dev/null || true
    sudo -u "$REAL_USER" dconf write /org/gnome/desktop/peripherals/touchscreens/056a:0393/left-handed true 2>/dev/null || true
else
    dconf write /org/gnome/desktop/peripherals/tablets/056a:0393/left-handed true 2>/dev/null || true
    dconf write /org/gnome/desktop/peripherals/tablets/056a:0393/keep-aspect true 2>/dev/null || true
    dconf write /org/gnome/desktop/peripherals/touchscreens/056a:0393/left-handed true 2>/dev/null || true
fi

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Suporte, Modo Canhoto e GUI da Wacom configurados com sucesso."
