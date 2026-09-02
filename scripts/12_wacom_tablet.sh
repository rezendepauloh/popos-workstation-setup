#!/bin/bash
# ==============================================================================
# Módulo 12: Suporte e Configuração da Mesa Wacom (Driver Nativo do Kernel + Modo Canhoto 180°)
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="WACOM_TABLET"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Mesa Wacom (Driver Nativo do Kernel) já configurada anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "12. CONFIGURAÇÃO DA MESA WACOM INTUOS PRO (DRIVER NATIVO DO KERNEL)"

# Variáveis do ambiente (.env)
WACOM_USB_ID="${USB_ID_WACOM_PTH460_USB:-}"
WACOM_BT_ID="${USB_ID_WACOM_PTH460_BT:-}"
WACOM_MAC="${MAC_WACOM_INTUOS:-}"

# 1. Desativação de serviços conflitantes e remoção de blacklists
log_msg "INFO" "Desativando daemons conflitantes e garantindo módulo nativo 'wacom'..."
killall -9 OpenTabletDriver.UX.Gtk 2>/dev/null || true
if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user stop opentabletdriver.service 2>/dev/null || true
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user disable opentabletdriver.service 2>/dev/null || true
else
    systemctl --user stop opentabletdriver.service 2>/dev/null || true
    systemctl --user disable opentabletdriver.service 2>/dev/null || true
fi

# Remove bloqueios de kernel criados por pacotes de terceiros
sudo rm -f /etc/modprobe.d/*opentabletdriver*.conf /usr/lib/modprobe.d/*opentabletdriver*.conf /lib/modprobe.d/*opentabletdriver*.conf 2>/dev/null || true

# 2. Instalação de bibliotecas essenciais e utilitários libwacom
log_msg "INFO" "Instalando utilitários oficiais da Wacom (libwacom, xserver-xorg-input-wacom)..."
sudo apt update
sudo apt install -y libwacom-bin libwacom-common libwacom9 xserver-xorg-input-wacom

# 3. Carregamento e Persistência do Módulo Oficial de Kernel 'wacom'
log_msg "INFO" "Carregando módulo 'wacom' do kernel Linux..."
sudo modprobe -i wacom 2>/dev/null || sudo modprobe wacom 2>/dev/null || true
echo "wacom" | sudo tee /etc/modules-load.d/wacom.conf > /dev/null

# 4. Regras Udev de Calibração de Hardware para Modo Canhoto 180° (USB & Bluetooth)
log_msg "INFO" "Aplicando matriz de rotação 180° (Modo Canhoto) para Caneta, Toque e Mesa..."
WACOM_VENDOR="056a"
if [ -n "$WACOM_USB_ID" ]; then
    WACOM_VENDOR="${WACOM_USB_ID%%:*}"
fi

cat << EOF | sudo tee /etc/udev/rules.d/99-wacom-lefthanded.rules > /dev/null
# Matriz de Calibração 180° (Modo Canhoto) a nível de Hardware/libinput para Wacom Intuos Pro
ACTION=="add|change", KERNEL=="event*", SUBSYSTEM=="input", ATTRS{idVendor}=="$WACOM_VENDOR", ENV{LIBINPUT_CALIBRATION_MATRIX}="-1 0 1 0 -1 1", TAG+="uaccess"
ACTION=="add|change", KERNEL=="event*", SUBSYSTEM=="input", ATTRS{name}=="Wacom Intuos Pro S*", ENV{LIBINPUT_CALIBRATION_MATRIX}="-1 0 1 0 -1 1", TAG+="uaccess"
ACTION=="add|change", SUBSYSTEM=="input", ATTRS{idVendor}=="$WACOM_VENDOR", ENV{LIBINPUT_CALIBRATION_MATRIX}="-1 0 1 0 -1 1", TAG+="uaccess"
ACTION=="add|change", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="$WACOM_VENDOR", TAG+="uaccess", MODE="0664", GROUP="input"
EOF

sudo udevadm control --reload-rules 2>/dev/null || true
sudo udevadm trigger 2>/dev/null || true
sudo usermod -aG input "$REAL_USER" 2>/dev/null || true

# 5. Configurações de Desktop Dconf / GSettings (Modo Canhoto e Proporção 1:1)
log_msg "INFO" "Aplicando preferências de Modo Canhoto no ambiente de desktop..."
set_user_gsetting "org.gnome.desktop.peripherals.tablet" "keep-aspect" "true"
set_user_gsetting "org.gnome.desktop.peripherals.tablet" "left-handed" "true"

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

# 6. Detecção e Confiança (Trust) no Bluetooth BlueZ
if [ -n "$WACOM_MAC" ]; then
    log_msg "INFO" "Garantindo dispositivo Wacom ($WACOM_MAC) como confiável no Bluetooth BlueZ..."
    bluetoothctl trust "$WACOM_MAC" 2>/dev/null || true
fi

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Driver oficial do kernel Linux (Wacom Intuos Pro) configurado com Modo Canhoto 180° e Touch nativo."
