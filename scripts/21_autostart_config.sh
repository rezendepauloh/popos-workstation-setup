#!/bin/bash
# ==============================================================================
# Módulo 18: Configuração de Autostart no Boot (CopyQ, Kando, Espanso, NumLock)
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="AUTOSTART_CONFIG"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Entradas de Autostart já configuradas anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "21. CONFIGURAÇÃO DE INICIALIZAÇÃO AUTOMÁTICA (AUTOSTART)"

AUTOSTART_DIR="$REAL_HOME/.config/autostart"
mkdir -p "$AUTOSTART_DIR"

# 1. CopyQ (Nativo)
cat << 'EOF' > "$AUTOSTART_DIR/copyq.desktop"
[Desktop Entry]
Type=Application
Name=CopyQ
GenericName=Clipboard Manager
Comment=Gerenciador de Área de Transferência
Exec=/usr/bin/copyq
Icon=copyq
Terminal=false
Categories=Utility;
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=2
EOF
rm -f "$AUTOSTART_DIR/com.github.hluk.copyq.desktop" 2>/dev/null || true

# 2. Kando
cat << 'EOF' > "$AUTOSTART_DIR/menu.kando.Kando.desktop"
[Desktop Entry]
Type=Application
Name=Kando
Comment=The Cross-Platform Pie Menu.
Exec=env XDG_SESSION_TYPE=x11 GDK_BACKEND=x11 /usr/lib/kando/kando
Icon=kando
Terminal=false
Categories=Utility;
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=2
EOF

# 3. Sincronização do LED do NumLock no Hardware
cat << 'EOF' > "$AUTOSTART_DIR/numlock-led.desktop"
[Desktop Entry]
Type=Application
Name=NumLock LED Sync
Exec=/bin/bash -c 'for led in /sys/class/leds/*::numlock/brightness; do echo 1 > "$led" 2>/dev/null || true; done'
Terminal=false
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=1
EOF

# Remove entradas duplicadas, legadas ou obsoletas (Espanso roda via systemd user service)
rm -f "$AUTOSTART_DIR/numlock.desktop" "$AUTOSTART_DIR/espanso.desktop" 2>/dev/null || true

chown -R "$REAL_USER:$REAL_USER" "$AUTOSTART_DIR"

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Entradas de autostart otimizadas para CopyQ, Kando, NumLock LED e OpenTabletDriver."
