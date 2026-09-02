#!/bin/bash
# ==============================================================================
# Módulo 12: Solução Híbrida Wacom (Driver do Kernel para Touch + OpenTabletDriver para Caneta e Botões)
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="WACOM_TABLET"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Mesa Wacom (Solução Híbrida Caneta + Touch 180°) já configurada. Pulando..."
    exit 0
fi

log_msg "HEADER" "12. CONFIGURAÇÃO HÍBRIDA DA MESA WACOM (CANETA + TOUCH 180°)"

# Variáveis do ambiente (.env)
WACOM_USB_ID="${USB_ID_WACOM_PTH460_USB:-}"
WACOM_BT_ID="${USB_ID_WACOM_PTH460_BT:-}"
WACOM_MAC="${MAC_WACOM_INTUOS:-}"

# 1. Remoção de bloqueios de modprobe e carregamento do módulo nativo 'wacom'
log_msg "INFO" "Garantindo driver nativo 'wacom' no kernel Linux para o modo Touch..."
sudo rm -f /etc/modprobe.d/*opentabletdriver*.conf /usr/lib/modprobe.d/*opentabletdriver*.conf /lib/modprobe.d/*opentabletdriver*.conf 2>/dev/null || true
sudo modprobe -i wacom 2>/dev/null || sudo modprobe wacom 2>/dev/null || true
echo "wacom" | sudo tee /etc/modules-load.d/wacom.conf > /dev/null

# 2. Instalação do OpenTabletDriver e utilitários
log_msg "INFO" "Instalando dependências e OpenTabletDriver para controle de caneta e botões..."
sudo apt update
sudo apt install -y libwacom-bin libwacom-common libwacom9 dotnet-runtime-8.0

if ! dpkg -l | grep -q opentabletdriver; then
    OTD_URL="https://github.com/OpenTabletDriver/OpenTabletDriver/releases/download/v0.6.7/opentabletdriver_0.6.7-1_x64.deb"
    wget -qO /tmp/opentabletdriver.deb "$OTD_URL"
    sudo apt install -y /tmp/opentabletdriver.deb
    rm -f /tmp/opentabletdriver.deb
fi

# 3. Regras Udev Híbridas (Touch 180° via Kernel + Permissões para OpenTabletDriver)
log_msg "INFO" "Aplicando regras Udev de permissões e rotação 180° para o Touch nativo..."
cat << 'EOF' | sudo tee /etc/udev/rules.d/99-wacom-hybrid.rules > /dev/null
# Permissões de Uinput e HID para o OpenTabletDriver (USB e Bluetooth)
KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput", MODE="0660", GROUP="input"
KERNEL=="hidraw*", SUBSYSTEM=="hidraw", TAG+="uaccess", MODE="0664", GROUP="input"
SUBSYSTEM=="hidraw", TAG+="uaccess", MODE="0664", GROUP="input"
SUBSYSTEM=="input", TAG+="uaccess", MODE="0664", GROUP="input"

# Matriz de Calibração 180° (Modo Canhoto) para o Touchpad / Toque do Kernel
ATTRS{name}=="*Finger*", ENV{LIBINPUT_CALIBRATION_MATRIX}="-1 0 1 0 -1 1"
ATTRS{name}=="*Touch*", ENV{LIBINPUT_CALIBRATION_MATRIX}="-1 0 1 0 -1 1"
ENV{ID_INPUT_TOUCHPAD}=="1", ATTRS{idVendor}=="056a", ENV{LIBINPUT_CALIBRATION_MATRIX}="-1 0 1 0 -1 1"
ENV{ID_INPUT_TOUCHSCREEN}=="1", ATTRS{idVendor}=="056a", ENV{LIBINPUT_CALIBRATION_MATRIX}="-1 0 1 0 -1 1"
EOF

sudo udevadm control --reload-rules 2>/dev/null || true
sudo udevadm trigger 2>/dev/null || true
sudo usermod -aG input "$REAL_USER" 2>/dev/null || true

# 4. Definição de Hardware para o OpenTabletDriver (USB 914 + Bluetooth 915)
log_msg "INFO" "Configurando suporte a hardware Wacom PTH-460 (USB e Bluetooth)..."
OTD_CONFIG_DIR="$REAL_HOME/.config/OpenTabletDriver"
mkdir -p "$OTD_CONFIG_DIR/Configurations"

cat << 'EOF' > "$OTD_CONFIG_DIR/Configurations/Wacom PTH-460.json"
{
  "Name": "Wacom PTH-460",
  "Specifications": {
    "Digitizer": {
      "Width": 159.6,
      "Height": 99.75,
      "MaxX": 31920,
      "MaxY": 19950
    },
    "Pen": {
      "MaxPressure": 8191,
      "ButtonCount": 2
    },
    "AuxiliaryButtons": {
      "ButtonCount": 6
    },
    "Wheels": [
      {
        "AbsoluteWheelMax": 71,
        "AngleOfZeroReading": 90.0,
        "ButtonCount": 1
      }
    ]
  },
  "DigitizerIdentifiers": [
    {
      "VendorID": 1386,
      "ProductID": 914,
      "InputReportLength": 192,
      "OutputReportLength": 0,
      "ReportParser": "OpenTabletDriver.Configurations.Parsers.Wacom.IntuosV2.IntuosV2ReportParser",
      "FeatureInitReport": [
        "AgI="
      ],
      "InitializationStrings": [
        0
      ]
    },
    {
      "VendorID": 1386,
      "ProductID": 914,
      "InputReportLength": 193,
      "OutputReportLength": 0,
      "ReportParser": "OpenTabletDriver.Configurations.Parsers.Wacom.IntuosV2.WacomDriverIntuosV2ReportParser",
      "InitializationStrings": [
        0
      ]
    },
    {
      "VendorID": 1386,
      "ProductID": 915,
      "InputReportLength": 192,
      "OutputReportLength": 0,
      "ReportParser": "OpenTabletDriver.Configurations.Parsers.Wacom.IntuosV2.IntuosV2ReportParser",
      "InitializationStrings": [
        0
      ]
    },
    {
      "VendorID": 1386,
      "ProductID": 915,
      "InputReportLength": 193,
      "OutputReportLength": 0,
      "ReportParser": "OpenTabletDriver.Configurations.Parsers.Wacom.IntuosV2.WacomDriverIntuosV2ReportParser",
      "InitializationStrings": [
        0
      ]
    },
    {
      "VendorID": 1386,
      "ProductID": 988,
      "InputReportLength": 192,
      "OutputReportLength": 0,
      "ReportParser": "OpenTabletDriver.Configurations.Parsers.Wacom.IntuosV2.IntuosV2ReportParser",
      "InitializationStrings": [
        0
      ]
    }
  ],
  "AuxiliaryDeviceIdentifiers": [
    {
      "VendorID": 1386,
      "ProductID": 914,
      "InputReportLength": 44,
      "ReportParser": "OpenTabletDriver.Configurations.Parsers.Wacom.IntuosV2.IntuosV2ReportParser"
    },
    {
      "VendorID": 1386,
      "ProductID": 915,
      "InputReportLength": 44,
      "ReportParser": "OpenTabletDriver.Configurations.Parsers.Wacom.IntuosV2.IntuosV2ReportParser"
    }
  ]
}
EOF

# 5. Configuração Declarativa do OpenTabletDriver (Modo Absoluto 180° e Mapeamento de Botões)
log_msg "INFO" "Gravando configuração com Modo Canhoto 180°, botões físicos e anel de zoom..."
cat << 'EOF' > "$OTD_CONFIG_DIR/settings.json"
{
  "Revision": "0.6.7",
  "Profiles": [
    {
      "Tablet": "Wacom PTH-460",
      "OutputMode": {
        "Path": "OpenTabletDriver.Desktop.Output.AbsoluteMode",
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
            "Path": "OpenTabletDriver.Desktop.Binding.MouseBinding",
            "Settings": [
              {
                "Property": "Button",
                "Value": "Right"
              }
            ],
            "Enable": true
          },
          {
            "Path": "OpenTabletDriver.Desktop.Binding.MouseBinding",
            "Settings": [
              {
                "Property": "Button",
                "Value": "Middle"
              }
            ],
            "Enable": true
          }
        ],
        "AuxButtons": [
          {
            "Path": "OpenTabletDriver.Desktop.Binding.MultiKeyBinding",
            "Settings": [
              {
                "Property": "Keys",
                "Value": [
                  "KeyboardLeftControl",
                  "KeyboardZ"
                ]
              }
            ],
            "Enable": true
          },
          {
            "Path": "OpenTabletDriver.Desktop.Binding.MultiKeyBinding",
            "Settings": [
              {
                "Property": "Keys",
                "Value": [
                  "KeyboardLeftControl",
                  "KeyboardLeftShift",
                  "KeyboardZ"
                ]
              }
            ],
            "Enable": true
          },
          {
            "Path": "OpenTabletDriver.Desktop.Binding.MultiKeyBinding",
            "Settings": [
              {
                "Property": "Keys",
                "Value": [
                  "KeyboardSpace"
                ]
              }
            ],
            "Enable": true
          },
          {
            "Path": "OpenTabletDriver.Desktop.Binding.MultiKeyBinding",
            "Settings": [
              {
                "Property": "Keys",
                "Value": [
                  "KeyboardLeftControl",
                  "KeyboardS"
                ]
              }
            ],
            "Enable": true
          },
          {
            "Path": "OpenTabletDriver.Desktop.Binding.MultiKeyBinding",
            "Settings": [
              {
                "Property": "Keys",
                "Value": [
                  "KeyboardLeftControl",
                  "KeyboardC"
                ]
              }
            ],
            "Enable": true
          },
          {
            "Path": "OpenTabletDriver.Desktop.Binding.MultiKeyBinding",
            "Settings": [
              {
                "Property": "Keys",
                "Value": [
                  "KeyboardLeftControl",
                  "KeyboardV"
                ]
              }
            ],
            "Enable": true
          }
        ],
        "MouseButtons": [],
        "MouseScrollUp": null,
        "MouseScrollDown": null,
        "WheelBindings": [
          {
            "WheelButtons": [
              null
            ],
            "ClockwiseRotation": {
              "Path": "OpenTabletDriver.Desktop.Binding.MultiKeyBinding",
              "Settings": [
                {
                  "Property": "Keys",
                  "Value": [
                    "KeyboardLeftControl",
                    "KeyboardEqual"
                  ]
                }
              ],
              "Enable": true
            },
            "ClockwiseActivationThreshold": 5.0,
            "CounterClockwiseRotation": {
              "Path": "OpenTabletDriver.Desktop.Binding.MultiKeyBinding",
              "Settings": [
                {
                  "Property": "Keys",
                  "Value": [
                    "KeyboardLeftControl",
                    "KeyboardMinus"
                  ]
                }
              ],
              "Enable": true
            },
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

# 6. Ocultar o inicializador da GUI para evitar resets acidentais para Artist Mode
if [ -f "/usr/share/applications/OpenTabletDriver.desktop" ]; then
    mkdir -p "$REAL_HOME/.local/share/applications"
    sed 's/NoDisplay=false/NoDisplay=true/g' /usr/share/applications/OpenTabletDriver.desktop > "$REAL_HOME/.local/share/applications/OpenTabletDriver.desktop" 2>/dev/null || true
    echo "NoDisplay=true" >> "$REAL_HOME/.local/share/applications/OpenTabletDriver.desktop"
    chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.local/share/applications/OpenTabletDriver.desktop" 2>/dev/null || true
fi

# 7. Ativação e Inicialização do Serviço em Segundo Plano
log_msg "INFO" "Reiniciando serviço opentabletdriver.service em segundo plano..."
killall -9 OpenTabletDriver.UX.Gtk 2>/dev/null || true

if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user daemon-reload 2>/dev/null || true
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user enable opentabletdriver.service 2>/dev/null || true
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user restart opentabletdriver.service 2>/dev/null || true
else
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable opentabletdriver.service 2>/dev/null || true
    systemctl --user restart opentabletdriver.service 2>/dev/null || true
fi

# 8. Garantia do Modo Absoluto via CLI (otd)
if command -v otd >/dev/null 2>&1; then
    LC_ALL=C otd setoutputmode "Wacom PTH-460" OpenTabletDriver.Desktop.Output.AbsoluteMode 2>/dev/null || true
    LC_ALL=C otd settabletarea "Wacom PTH-460" 159.6 99.75 79.8 49.875 180 2>/dev/null || true
    LC_ALL=C otd setlockaspectratio "Wacom PTH-460" true 2>/dev/null || true
    LC_ALL=C otd savedefaultsettings 2>/dev/null || true
fi

# 9. Detecção e Confiança (Trust) no Bluetooth BlueZ
if [ -n "$WACOM_MAC" ]; then
    bluetoothctl trust "$WACOM_MAC" 2>/dev/null || true
fi

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Configuração Híbrida concluída: Kernel wacom.ko (Touch 180°) + OpenTabletDriver (Caneta Absoluta e Botões)."
