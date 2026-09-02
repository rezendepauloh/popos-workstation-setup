#!/bin/bash
# ==============================================================================
# Módulo 12: Suporte e Configuração da Mesa Wacom (Driver Nativo do Kernel + Modo Canhoto 180°)
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="WACOM_TABLET"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Mesa Wacom (Driver Nativo do Kernel + Modo Canhoto) já configurada anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "12. CONFIGURAÇÃO DA MESA WACOM INTUOS PRO (DRIVER NATIVO DO KERNEL)"

# Variáveis do ambiente (.env)
WACOM_USB_ID="${USB_ID_WACOM_PTH460_USB:-}"
WACOM_BT_ID="${USB_ID_WACOM_PTH460_BT:-}"
WACOM_MAC="${MAC_WACOM_INTUOS:-}"

# 1. Remoção e Limpeza Completa do OpenTabletDriver
log_msg "INFO" "Removendo OpenTabletDriver e limpando bloqueios de modprobe..."
killall -9 OpenTabletDriver.UX.Gtk OpenTabletDriver.Daemon otd-daemon 2>/dev/null || true

if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user stop opentabletdriver.service 2>/dev/null || true
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user disable opentabletdriver.service 2>/dev/null || true
fi

if dpkg -l | grep -q opentabletdriver; then
    sudo apt purge -y opentabletdriver 2>/dev/null || true
fi

sudo rm -f /etc/modprobe.d/*opentabletdriver*.conf /usr/lib/modprobe.d/*opentabletdriver*.conf /lib/modprobe.d/*opentabletdriver*.conf 2>/dev/null || true
rm -rf "$REAL_HOME/.config/OpenTabletDriver" "$REAL_HOME/.local/share/OpenTabletDriver" "$REAL_HOME/.local/share/applications/OpenTabletDriver.desktop" 2>/dev/null || true

# 2. Instalação de Utilitários Oficiais da Wacom e Mapeador de Entrada Nativo
log_msg "INFO" "Instalando utilitários oficiais Wacom (libwacom) e input-remapper..."
sudo apt update
sudo apt install -y libwacom-bin libwacom-common libwacom9 xserver-xorg-input-wacom input-remapper

# 3. Carregamento e Persistência do Módulo Oficial de Kernel 'wacom'
log_msg "INFO" "Carregando módulo de kernel oficial 'wacom' (USB e Bluetooth)..."
sudo modprobe -i wacom 2>/dev/null || sudo modprobe wacom 2>/dev/null || true
echo "wacom" | sudo tee /etc/modules-load.d/wacom.conf > /dev/null

# 4. Regras Udev: Calibração de Hardware 180° (Modo Canhoto) para Caneta, Toque e Mesa
log_msg "INFO" "Configurando regras Udev com Matriz de Calibração 180° (Modo Canhoto)..."
WACOM_VENDOR="056a"
if [ -n "$WACOM_USB_ID" ]; then
    WACOM_VENDOR="${WACOM_USB_ID%%:*}"
fi

cat << EOF | sudo tee /etc/udev/rules.d/99-wacom.rules > /dev/null
# Permissões Udev para Wacom Intuos Pro (USB e Bluetooth)
KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput", MODE="0660", GROUP="input"
SUBSYSTEM=="input", ATTRS{idVendor}=="$WACOM_VENDOR", TAG+="uaccess", MODE="0664", GROUP="input"
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="$WACOM_VENDOR", TAG+="uaccess", MODE="0664", GROUP="input"

# Matriz de Calibração 180° (Modo Canhoto) a nível de Kernel/libinput para Caneta, Toque (Finger) e Mesa (Pad)
ACTION=="add|change", KERNEL=="event*", SUBSYSTEM=="input", ATTRS{name}=="Wacom Intuos Pro S*", ENV{LIBINPUT_CALIBRATION_MATRIX}="-1 0 1 0 -1 1", TAG+="uaccess"
ACTION=="add|change", KERNEL=="event*", SUBSYSTEM=="input", ATTRS{idVendor}=="$WACOM_VENDOR", ENV{LIBINPUT_CALIBRATION_MATRIX}="-1 0 1 0 -1 1", TAG+="uaccess"
ACTION=="add|change", SUBSYSTEM=="input", ATTRS{idVendor}=="$WACOM_VENDOR", ENV{LIBINPUT_CALIBRATION_MATRIX}="-1 0 1 0 -1 1", TAG+="uaccess"
EOF

# 5. Configuração no hwdb do libinput para garantia de rotação de 180°
cat << 'EOF' | sudo tee /etc/udev/hwdb.d/70-wacom-lefthanded.hwdb > /dev/null
# Wacom Intuos Pro S USB & Bluetooth - 180° Left Handed Matrix
evdev:name:Wacom Intuos Pro S*:*
 LIBINPUT_CALIBRATION_MATRIX=-1 0 1 0 -1 1
EOF

sudo systemd-hwdb update 2>/dev/null || true
sudo udevadm control --reload-rules 2>/dev/null || true
sudo udevadm trigger 2>/dev/null || true
sudo usermod -aG input "$REAL_USER" 2>/dev/null || true

# 6. Configurações de Desktop GNOME/COSMIC (Modo Canhoto e Proporção 1:1)
log_msg "INFO" "Aplicando chaves de Modo Canhoto no desktop..."
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

# 7. Mapeamento de Botões Físicos da Mesa via input-remapper
log_msg "INFO" "Configurando atalhos dos botões físicos (ExpressKeys) e Zoom no input-remapper..."
sudo systemctl enable --now input-remapper.service 2>/dev/null || true

REMAPPER_CONFIG_DIR="$REAL_HOME/.config/input-remapper-2/presets/Wacom Intuos Pro S Pad"
mkdir -p "$REMAPPER_CONFIG_DIR"

cat << 'EOF' > "$REMAPPER_CONFIG_DIR/pad_shortcuts.json"
[
    {
        "input_combination": [
            [1, 256, 1]
        ],
        "target_combination": [
            [1, 29, 1],
            [1, 44, 1],
            [1, 44, 0],
            [1, 29, 0]
        ]
    },
    {
        "input_combination": [
            [1, 257, 1]
        ],
        "target_combination": [
            [1, 29, 1],
            [1, 42, 1],
            [1, 44, 1],
            [1, 44, 0],
            [1, 42, 0],
            [1, 29, 0]
        ]
    },
    {
        "input_combination": [
            [1, 258, 1]
        ],
        "target_combination": [
            [1, 57, 1],
            [1, 57, 0]
        ]
    },
    {
        "input_combination": [
            [1, 259, 1]
        ],
        "target_combination": [
            [1, 29, 1],
            [1, 31, 1],
            [1, 31, 0],
            [1, 29, 0]
        ]
    },
    {
        "input_combination": [
            [1, 260, 1]
        ],
        "target_combination": [
            [1, 29, 1],
            [1, 46, 1],
            [1, 46, 0],
            [1, 29, 0]
        ]
    },
    {
        "input_combination": [
            [1, 261, 1]
        ],
        "target_combination": [
            [1, 29, 1],
            [1, 47, 1],
            [1, 47, 0],
            [1, 29, 0]
        ]
    }
]
EOF

chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/input-remapper-2" 2>/dev/null || true

# 8. Detecção e Confiança (Trust) no Bluetooth BlueZ
if [ -n "$WACOM_MAC" ]; then
    log_msg "INFO" "Garantindo dispositivo Wacom ($WACOM_MAC) como confiável no Bluetooth BlueZ..."
    bluetoothctl trust "$WACOM_MAC" 2>/dev/null || true
fi

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Driver nativo do Kernel Linux (wacom.ko) configurado com Touch, Caneta e Modo Canhoto 180° com sucesso."
