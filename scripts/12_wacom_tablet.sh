#!/bin/bash
# ==============================================================================
# Módulo 12: Suporte Nativo à Mesa Wacom Intuos Pro S (Kernel wacom.ko + COSMIC Epoch)
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="WACOM_TABLET"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Mesa Wacom (Driver Nativo COSMIC / Wayland) já configurada. Pulando..."
    exit 0
fi

log_msg "HEADER" "12. CONFIGURAÇÃO DA MESA WACOM (DRIVER NATIVO KERNEL + COSMIC WAYLAND)"

# Variáveis do ambiente (.env)
WACOM_USB_ID="${USB_ID_WACOM_PTH460_USB:-056a:0392}"
WACOM_BT_ID="${USB_ID_WACOM_PTH460_BT:-056a:0393}"
WACOM_MAC="${MAC_WACOM_INTUOS:-E0:9F:2A:20:BC:DD}"

# 1. Limpeza de daemons legados e desativação do OpenTabletDriver
log_msg "INFO" "Desativando daemons legados de terceiros (OpenTabletDriver)..."
killall -9 otd-daemon OpenTabletDriver.Daemon 2>/dev/null || true

# Desativa serviços systemd user do OpenTabletDriver
if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user stop opentabletdriver.service 2>/dev/null || true
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user disable opentabletdriver.service 2>/dev/null || true
else
    systemctl --user stop opentabletdriver.service 2>/dev/null || true
    systemctl --user disable opentabletdriver.service 2>/dev/null || true
fi

# Remove autostart do OpenTabletDriver
rm -f "$REAL_HOME/.config/autostart/otd-daemon.desktop" "$REAL_HOME/.config/autostart/otd-daemon.desktop.bak" 2>/dev/null || true

# 2. Desbloqueio e ativação do módulo nativo do kernel (wacom.ko)
log_msg "INFO" "Assegurando que o módulo wacom.ko do kernel esteja desbloqueado e ativo..."
# Anula o bloqueio criado pelo OpenTabletDriver em /usr/lib/modprobe.d/99-opentabletdriver.conf
sudo ln -sf /dev/null /etc/modprobe.d/99-opentabletdriver.conf

# Carrega o driver oficial do kernel
sudo modprobe wacom 2>/dev/null || true

# 3. Pacotes nativos de suporte e calibração
log_msg "INFO" "Instalando utilitários nativos de suporte à Wacom (libwacom)..."
sudo apt update
sudo apt install -y libwacom-bin libwacom-common libwacom9

# 4. Limpeza de regras antigas conflitantes de calibração
log_msg "INFO" "Removendo matrizes de calibração conflitantes em udev/hwdb..."
sudo rm -f /etc/udev/rules.d/99-wacom-lefthanded.rules \
           /etc/udev/rules.d/99-wacom-hybrid.rules \
           /etc/udev/rules.d/99-wacom.rules \
           /etc/udev/hwdb.d/70-wacom-lefthanded.hwdb 2>/dev/null || true

sudo systemd-hwdb update 2>/dev/null || true

# 5. Regras Udev Oficiais para Wacom (USB e Bluetooth) com permissão uaccess
log_msg "INFO" "Configurando regras Udev para permissão de usuário no Wayland..."
cat << 'EOF' | sudo tee /etc/udev/rules.d/99-wacom-native.rules > /dev/null
# Wacom Intuos Pro S (PTH-460) - Suporte Nativo Wayland/COSMIC (USB e Bluetooth)
SUBSYSTEM=="input", ATTRS{idVendor}=="056a", TAG+="uaccess", MODE="0664", GROUP="input"
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="056a", TAG+="uaccess", MODE="0664", GROUP="input"
KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput", MODE="0660", GROUP="input"
EOF

sudo usermod -aG input "$REAL_USER" 2>/dev/null || true
sudo udevadm control --reload-rules 2>/dev/null || true
sudo udevadm trigger 2>/dev/null || true

# 6. Configuração no Compositor COSMIC (cosmic-comp)
log_msg "INFO" "Gravando mapeamento e orientação nativa no COSMIC Compositor..."
COSMIC_INPUT_DIR="$REAL_HOME/.config/cosmic/com.system76.CosmicComp/v1"
mkdir -p "$COSMIC_INPUT_DIR"

# Detecta a tela principal conectada (prioriza DP-1, ou a primeira do cosmic-randr)
PRIMARY_DISPLAY=$(cosmic-randr list 2>/dev/null | grep -E "^[A-Za-z0-9-]+ \(enabled\)" | awk '{print $1}' | head -n 1)
[ -z "$PRIMARY_DISPLAY" ] && PRIMARY_DISPLAY="DP-1"

cat << EOF > "$COSMIC_INPUT_DIR/input_devices"
{
    "Wacom Intuos Pro S Pen": (
        state: Enabled,
        map_to_output: Some("${PRIMARY_DISPLAY}"),
    ),
    "Wacom Intuos Pro S Finger": (
        state: Enabled,
        map_to_output: Some("${PRIMARY_DISPLAY}"),
        left_handed: Some(true),
        rotation_angle: Some(180),
    ),
}
EOF

chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/cosmic"

# 7. Instalação e Ativação do Daemon de ExpressKeys & Touch Ring
log_msg "INFO" "Instalando daemon nativo de ExpressKeys e Touch Ring (UInput)..."
mkdir -p "$REAL_HOME/.local/bin" "$REAL_HOME/.config/systemd/user"

cp -f "$SCRIPT_DIR/daemons/wacom-expresskeys-daemon.py" "$REAL_HOME/.local/bin/wacom-expresskeys-daemon.py"
chmod +x "$REAL_HOME/.local/bin/wacom-expresskeys-daemon.py"
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.local/bin/wacom-expresskeys-daemon.py"

cp -f "$BASE_DIR/config/systemd/user/wacom-expresskeys.service" "$REAL_HOME/.config/systemd/user/wacom-expresskeys.service"
chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/systemd/user"

if [ -n "$REAL_UID" ]; then
    if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
        sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user daemon-reload 2>/dev/null || true
        sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user enable --now wacom-expresskeys.service 2>/dev/null || true
    else
        systemctl --user daemon-reload 2>/dev/null || true
        systemctl --user enable --now wacom-expresskeys.service 2>/dev/null || true
    fi
fi

# 8. Confiança e emparelhamento no BlueZ
if [ -n "$WACOM_MAC" ]; then
    log_msg "INFO" "Configurando confiança para Wacom Bluetooth ($WACOM_MAC)..."
    bluetoothctl trust "$WACOM_MAC" 2>/dev/null || true
fi

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Mesa Wacom configurada com sucesso no modo 100% nativo (Caneta calibrada + Toque Canhoto 180° + ExpressKeys & Touch Ring UInput + Mapeamento ${PRIMARY_DISPLAY})."

