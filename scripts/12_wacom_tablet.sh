#!/bin/bash
# ==============================================================================
# Módulo 12: Suporte, Drivers e Configuração da Mesa Wacom (OpenTabletDriver Wayland)
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="WACOM_TABLET"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Mesa Wacom (OpenTabletDriver Wayland) já configurada anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "12. CONFIGURAÇÃO DA MESA WACOM INTUOS PRO (OPENTABLETDRIVER WAYLAND)"

# 1. Instalação das bibliotecas e utilitários (.NET Runtime 8 e OpenTabletDriver)
log_msg "INFO" "Instalando dependências (.NET Runtime 8, libwacom) e OpenTabletDriver GUI..."
sudo apt update
sudo apt install -y libwacom-bin libwacom-common libwacom9 dotnet-runtime-8.0

if ! dpkg -l | grep -q opentabletdriver; then
    OTD_URL="https://github.com/OpenTabletDriver/OpenTabletDriver/releases/download/v0.6.7/opentabletdriver_0.6.7-1_x64.deb"
    wget -qO /tmp/opentabletdriver.deb "$OTD_URL"
    sudo apt install -y /tmp/opentabletdriver.deb
    rm -f /tmp/opentabletdriver.deb
fi

# 2. Configuração de permissões Udev para Wayland / uinput
log_msg "INFO" "Configurando regras Udev para emulação de caneta via /dev/uinput..."
cat << 'EOF' | sudo tee /etc/udev/rules.d/99-opentabletdriver.rules > /dev/null
KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput", MODE="0660", GROUP="input"
SUBSYSTEM=="input", ATTRS{idVendor}=="056a", MODE="0664", GROUP="input"
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="056a", MODE="0664", GROUP="input"
EOF

sudo udevadm control --reload-rules 2>/dev/null || true
sudo udevadm trigger 2>/dev/null || true
sudo usermod -aG input "$REAL_USER" 2>/dev/null || true

# 3. Configuração Declarativa do OpenTabletDriver para Wayland (LinuxVirtualTablet & 180° Canhoto)
log_msg "INFO" "Configurando modo de saída 'LinuxVirtualTablet' (Wayland) e Modo Canhoto (180°)..."
OTD_CONFIG_DIR="$REAL_HOME/.config/OpenTabletDriver"
mkdir -p "$OTD_CONFIG_DIR"

cat << 'EOF' > "$OTD_CONFIG_DIR/settings.json"
{
  "Revision": "0.6.7",
  "Profiles": [
    {
      "Tablet": "Wacom PTH-460",
      "OutputMode": {
        "Path": "OpenTabletDriver.Desktop.Output.LinuxVirtualTablet",
        "Settings": [],
        "Enable": true
      },
      "Filters": [],
      "AbsoluteModeSettings": {
        "Display": {
          "Width": 3440.0,
          "Height": 1440.0,
          "X": 1720.0,
          "Y": 720.0,
          "Rotation": 0.0
        },
        "Tablet": {
          "Width": 159.6,
          "Height": 99.75,
          "X": 79.8,
          "Y": 49.875,
          "Rotation": 180.0
        },
        "EnableClipping": true,
        "EnableAreaLimiting": false,
        "LockAspectRatio": true
      },
      "RelativeModeSettings": {
        "XSensitivity": 10.0,
        "YSensitivity": 10.0,
        "RelativeRotation": 180.0,
        "RelativeResetDelay": "00:00:00.1000000"
      },
      "Bindings": {
        "TipActivationThreshold": 1.0,
        "TipButton": {
          "Path": "OpenTabletDriver.Desktop.Binding.AdaptiveBinding",
          "Settings": [
            {
              "Property": "Binding",
              "Value": "Tip"
            }
          ],
          "Enable": true
        },
        "EraserActivationThreshold": 1.0,
        "EraserButton": {
          "Path": "OpenTabletDriver.Desktop.Binding.AdaptiveBinding",
          "Settings": [
            {
              "Property": "Binding",
              "Value": "Eraser"
            }
          ],
          "Enable": true
        },
        "PenButtons": [
          {
            "Path": "OpenTabletDriver.Desktop.Binding.AdaptiveBinding",
            "Settings": [
              {
                "Property": "Binding",
                "Value": "Button 1"
              }
            ],
            "Enable": true
          },
          {
            "Path": "OpenTabletDriver.Desktop.Binding.AdaptiveBinding",
            "Settings": [
              {
                "Property": "Binding",
                "Value": "Button 2"
              }
            ],
            "Enable": true
          }
        ],
        "AuxButtons": [
          null,
          null,
          null,
          null,
          null,
          null
        ],
        "MouseButtons": [],
        "MouseScrollUp": null,
        "MouseScrollDown": null,
        "WheelBindings": [
          {
            "WheelButtons": [
              null
            ],
            "ClockwiseRotation": null,
            "ClockwiseActivationThreshold": 5.0,
            "CounterClockwiseRotation": null,
            "CounterClockwiseActivationThreshold": 5.0,
            "StepSize": 5.0
          }
        ],
        "DisablePressure": false,
        "DisableTilt": false,
        "EnableDragBindings": false
      }
    }
  ],
  "LockUsableAreaDisplay": true,
  "LockUsableAreaTablet": true,
  "Tools": []
}
EOF

chown -R "$REAL_USER:$REAL_USER" "$OTD_CONFIG_DIR"

# 4. Ativação e Inicialização do Serviço de Segundo Plano do OpenTabletDriver
log_msg "INFO" "Ativando serviço opentabletdriver.service no ambiente do usuário..."
if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user daemon-reload 2>/dev/null || true
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user enable opentabletdriver.service 2>/dev/null || true
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user restart opentabletdriver.service 2>/dev/null || true
else
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable opentabletdriver.service 2>/dev/null || true
    systemctl --user restart opentabletdriver.service 2>/dev/null || true
fi

# 5. Detecção e Confiança (Trust) no Bluetooth BlueZ
WACOM_MAC="${MAC_WACOM_INTUOS:-"E0:9F:2A:20:BC:DD"}"
log_msg "INFO" "Garantindo dispositivo Wacom ($WACOM_MAC) como confiável no Bluetooth BlueZ..."
bluetoothctl trust "$WACOM_MAC" 2>/dev/null || true

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "OpenTabletDriver (Wayland VirtualTablet), Modo Canhoto 180° e GUI configurados com sucesso."
