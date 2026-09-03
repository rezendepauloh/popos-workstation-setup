#!/bin/bash
# ==============================================================================
# Módulo 23: OpenRGB - Controle de Iluminação ARGB/RGB de Placa-Mãe e Fans
# Suporta ASUS TUF GAMING B760M-PLUS (AURA LED Controller) e periféricos
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="OPENRGB_CONFIG"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  OpenRGB e regras de iluminação já configurados anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "23. CONFIGURAÇÃO DO OPENRGB (ILUMINAÇÃO ARGB / RGB)"

# ------------------------------------------------------------------------------
# 1. Instalação do OpenRGB via Flatpak
# ------------------------------------------------------------------------------
log_msg "INFO" "Instalando OpenRGB via Flatpak (Flathub)..."
flatpak install -y --system flathub org.openrgb.OpenRGB

# ------------------------------------------------------------------------------
# 2. Carregamento dos módulos I2C no Kernel (SMBus / Placa-mãe / RAM)
# ------------------------------------------------------------------------------
log_msg "INFO" "Habilitando módulo do kernel i2c-dev..."
if ! grep -q "^i2c-dev" /etc/modules 2>/dev/null; then
    echo "i2c-dev" | sudo tee -a /etc/modules > /dev/null
fi
sudo modprobe i2c-dev 2>/dev/null || true

# ------------------------------------------------------------------------------
# 3. Geração e Instalação das Regras Udev do OpenRGB (Sem necessidade de root)
# ------------------------------------------------------------------------------
log_msg "INFO" "Instalando regras Udev oficiais para controle direto de hardware..."
sudo mkdir -p /etc/udev/rules.d

RULES_SOURCE=$(find /var/lib/flatpak/app/org.openrgb.OpenRGB/ -name "60-openrgb.rules" 2>/dev/null | head -n 1)

if [ -n "$RULES_SOURCE" ] && [ -s "$RULES_SOURCE" ]; then
    sudo cp "$RULES_SOURCE" /etc/udev/rules.d/60-openrgb.rules
    log_msg "SUCCESS" "Regras Udev oficiais do OpenRGB copiadas para /etc/udev/rules.d/60-openrgb.rules."
else
    cat << 'EOF' | sudo tee /etc/udev/rules.d/60-openrgb.rules > /dev/null
# ASUS Aura LED Controller
SUBSYSTEMS=="usb", ATTRS{idVendor}=="0b05", ATTRS{idProduct}=="19af", TAG+="uaccess", MODE="0666"
SUBSYSTEMS=="usb", ATTRS{idVendor}=="0b05", ATTRS{idProduct}=="18f3", TAG+="uaccess", MODE="0666"
SUBSYSTEMS=="usb", ATTRS{idVendor}=="0b05", ATTRS{idProduct}=="1872", TAG+="uaccess", MODE="0666"
SUBSYSTEM=="i2c-dev", TAG+="uaccess", MODE="0666"
KERNEL=="i2c-[0-9]*", TAG+="uaccess", MODE="0666"
EOF
fi

# Adiciona o usuário ao grupo i2c se o grupo existir
if getent group i2c >/dev/null 2>&1; then
    sudo usermod -aG i2c "$REAL_USER" 2>/dev/null || true
fi

# Recarrega regras udev
sudo udevadm control --reload-rules 2>/dev/null || true
sudo udevadm trigger 2>/dev/null || true

# ------------------------------------------------------------------------------
# 4. Permissões Flatpak para OpenRGB acessar dispositivos USB/HID
# ------------------------------------------------------------------------------
log_msg "INFO" "Configurando overrides de permissão para o OpenRGB..."
flatpak override --system --device=all org.openrgb.OpenRGB 2>/dev/null || true
flatpak override --user --device=all org.openrgb.OpenRGB 2>/dev/null || true

# ------------------------------------------------------------------------------
# 5. Entrada de Inicialização Silenciosa no Autostart (Inicia minimizado)
# ------------------------------------------------------------------------------
log_msg "INFO" "Configurando autostart do OpenRGB minimizado na bandeja..."
AUTOSTART_DIR="$REAL_HOME/.config/autostart"
mkdir -p "$AUTOSTART_DIR"

cat << 'EOF' > "$AUTOSTART_DIR/org.openrgb.OpenRGB.desktop"
[Desktop Entry]
Type=Application
Name=OpenRGB
Comment=Open source RGB lighting control
Exec=flatpak run org.openrgb.OpenRGB --startminimized
Icon=org.openrgb.OpenRGB
Terminal=false
Categories=Utility;
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=3
EOF
chown "$REAL_USER:$REAL_USER" "$AUTOSTART_DIR/org.openrgb.OpenRGB.desktop"

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "OpenRGB instalado, regras udev aplicadas e autostart minimizado configurado com sucesso."
