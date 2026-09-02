#!/bin/bash
# ==============================================================================
# Módulo 12: Suporte e Configuração Nativa da Mesa Digitalizadora Wacom (Kernel Driver)
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="WACOM_TABLET"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Mesa Wacom (Driver Nativo do Kernel) já configurada anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "12. CONFIGURAÇÃO DA MESA WACOM INTUOS PRO (DRIVER NATIVO)"

# 1. Remoção de bloqueios/blacklists do OpenTabletDriver e restauração do módulo 'wacom'
log_msg "INFO" "Removendo bloqueios de kernel do OpenTabletDriver..."
sudo rm -f /etc/modprobe.d/*opentabletdriver*.conf /usr/lib/modprobe.d/*opentabletdriver*.conf /lib/modprobe.d/*opentabletdriver*.conf 2>/dev/null || true
if dpkg -l | grep -q opentabletdriver; then
    sudo apt purge -y opentabletdriver 2>/dev/null || true
fi

# 2. Instalação das bibliotecas e utilitários nativos da Wacom (libwacom)
log_msg "INFO" "Instalando utilitários e drivers nativos da Wacom (libwacom)..."
sudo apt update
sudo apt install -y libwacom-bin libwacom-common libwacom9 xserver-xorg-input-wacom

# 3. Carregamento e persistência do módulo de kernel oficial 'wacom'
log_msg "INFO" "Carregando módulo oficial de kernel 'wacom' e configurando persistência..."
sudo modprobe -i wacom 2>/dev/null || sudo modprobe wacom 2>/dev/null || true
echo "wacom" | sudo tee /etc/modules-load.d/wacom.conf > /dev/null

# 4. Regras Udev e permissões de acesso para hardware Wacom (USB e Bluetooth)
log_msg "INFO" "Configurando regras Udev e permissões de entrada..."
cat << 'EOF' | sudo tee /etc/udev/rules.d/99-wacom.rules > /dev/null
# Wacom Intuos Pro (USB e Bluetooth)
KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput", MODE="0660", GROUP="input"
SUBSYSTEM=="input", ATTRS{idVendor}=="056a", MODE="0664", GROUP="input"
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="056a", MODE="0664", GROUP="input"
EOF

sudo udevadm control --reload-rules 2>/dev/null || true
sudo udevadm trigger 2>/dev/null || true
sudo usermod -aG input "$REAL_USER" 2>/dev/null || true

# 5. Detecção e Confiança (Trust) no Bluetooth BlueZ
log_msg "INFO" "Verificando mesa Wacom no Bluetooth..."
WACOM_MAC=$(bluetoothctl devices 2>/dev/null | grep -iE 'Intuos|Wacom' | head -n 1 | awk '{print $2}' || true)
if [ -z "$WACOM_MAC" ]; then
    WACOM_MAC="E0:9F:2A:20:BC:DD"
fi

if [ -n "$WACOM_MAC" ]; then
    log_msg "INFO" "Configurando mesa Wacom ($WACOM_MAC) como confiável no BlueZ..."
    bluetoothctl trust "$WACOM_MAC" 2>/dev/null || true
fi

# 6. Configurações de Modo Canhoto (Left-Handed / 180° de Rotação)
log_msg "INFO" "Aplicando preferências de Modo Canhoto (180° de rotação) e proporção 1:1..."
set_user_gsetting "org.gnome.desktop.peripherals.tablet" "keep-aspect" "true"
set_user_gsetting "org.gnome.desktop.peripherals.tablet" "left-handed" "true"

# Aplica para os identificadores de hardware USB (056a:0392) e Bluetooth (056a:0393)
for vid_pid in "056a:0392" "056a:0393"; do
    if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
        sudo -u "$REAL_USER" dconf write "/org/gnome/desktop/peripherals/tablets/$vid_pid/left-handed" true 2>/dev/null || true
        sudo -u "$REAL_USER" dconf write "/org/gnome/desktop/peripherals/tablets/$vid_pid/keep-aspect" true 2>/dev/null || true
        sudo -u "$REAL_USER" dconf write "/org/gnome/desktop/peripherals/touchscreens/$vid_pid/left-handed" true 2>/dev/null || true
    else
        dconf write "/org/gnome/desktop/peripherals/tablets/$vid_pid/left-handed" true 2>/dev/null || true
        dconf write "/org/gnome/desktop/peripherals/tablets/$vid_pid/keep-aspect" true 2>/dev/null || true
        dconf write "/org/gnome/desktop/peripherals/touchscreens/$vid_pid/left-handed" true 2>/dev/null || true
    fi
done

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Driver nativo de kernel da Wacom e Modo Canhoto configurados com sucesso."
