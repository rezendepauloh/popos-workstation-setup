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

# 1. CopyQ
cat << 'EOF' > "$AUTOSTART_DIR/com.github.hluk.copyq.desktop"
[Desktop Entry]
Type=Application
Name=CopyQ
GenericName=Clipboard Manager
Comment=Gerenciador de Área de Transferência
Exec=/usr/bin/flatpak run --branch=stable --arch=x86_64 --command=copyq com.github.hluk.copyq --hide
Icon=com.github.hluk.copyq
Terminal=false
Categories=Utility;
X-GNOME-Autostart-enabled=true
EOF

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
EOF

# 3. Espanso
cat << 'EOF' > "$AUTOSTART_DIR/espanso.desktop"
[Desktop Entry]
Type=Application
Name=Espanso
Comment=Cross-platform Text Expander
Exec=espanso daemon
Icon=espanso
Terminal=false
Categories=Utility;
X-GNOME-Autostart-enabled=true
EOF

# 4. NumLock
cat << 'EOF' > "$AUTOSTART_DIR/numlock.desktop"
[Desktop Entry]
Type=Application
Name=NumLock Auto-On
Exec=/bin/bash -c 'numlockx on 2>/dev/null || true; for led in /sys/class/leds/*::numlock/brightness; do echo 1 > "$led" 2>/dev/null || true; done'
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

chown -R "$REAL_USER:$REAL_USER" "$AUTOSTART_DIR"

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Entradas de autostart criadas para CopyQ, Kando, Espanso e NumLock."
