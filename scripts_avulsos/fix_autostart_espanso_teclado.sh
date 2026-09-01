#!/bin/bash
# ==============================================================================
# Script de Correção Completa:
# 1. NumLock Definitivo (COSMIC Desktop + Systemd + Udev + Autostart)
# 2. Cedilha no Chat / Webviews / Chrome (GTK immodules.cache + ~/.xinputrc)
# 3. Autostart & Inicialização Automática: Espanso, Kando e CopyQ
# ==============================================================================

set -e

echo "🚀 Aplicando correções de Teclado, NumLock, Cedilha e Autostart..."

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
REAL_UID=$(id -u "$REAL_USER" 2>/dev/null || echo 1000)

set_user_gsetting() {
    local SCHEMA="$1"
    local KEY="$2"
    local VALUE="$3"

    if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
        sudo -u "$REAL_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" gsettings set "$SCHEMA" "$KEY" "$VALUE" 2>/dev/null || true
    else
        gsettings set "$SCHEMA" "$KEY" "$VALUE" 2>/dev/null || true
    fi
}

# ==============================================================================
# 1. NUMLOCK NO COSMIC DESKTOP & SYSTEMD
# ==============================================================================
echo "🔢 1. Configurando NumLock permanente..."

# COSMIC Compositor nativo
mkdir -p "$REAL_HOME/.config/cosmic/com.system76.CosmicComp/v1"
echo "true" > "$REAL_HOME/.config/cosmic/com.system76.CosmicComp/v1/numlock_state"
chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/cosmic"

# Backup do Google Drive (se montado)
if [ -d "$REAL_HOME/GoogleDrive_Pessoal/Organização/Backup_COSMIC/cosmic/com.system76.CosmicComp/v1" ]; then
    echo "true" > "$REAL_HOME/GoogleDrive_Pessoal/Organização/Backup_COSMIC/cosmic/com.system76.CosmicComp/v1/numlock_state" 2>/dev/null || true
fi

# GNOME / XWayland flags
set_user_gsetting "org.gnome.desktop.peripherals.keyboard" "numlock-state" "true"
set_user_gsetting "org.gnome.desktop.peripherals.keyboard" "remember-numlock-state" "true"

# Disparo imediato para a sessão atual
numlockx on 2>/dev/null || true
for led in /sys/class/leds/*::numlock/brightness; do
    if [ -w "$led" ]; then
        echo 1 > "$led" 2>/dev/null || true
    elif [ "$(id -u)" -eq 0 ] || sudo -n true 2>/dev/null; then
        echo 1 | sudo tee "$led" >/dev/null 2>&1 || true
    fi
done

# Serviço Systemd no Boot
if [ "$(id -u)" -eq 0 ] || sudo -n true 2>/dev/null; then
    cat << 'EOF' | sudo tee /etc/systemd/system/numlock.service > /dev/null
[Unit]
Description=Ativar NumLock na Inicializacao do Sistema
DefaultDependencies=no
After=systemd-udev-settle.service
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'for tty in /dev/tty[1-6]; do /usr/bin/setleds -D +num < "$tty" 2>/dev/null || true; done; for led in /sys/class/leds/*::numlock/brightness; do echo 1 | tee "$led" >/dev/null 2>&1 || true; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable numlock.service 2>/dev/null || true
    sudo systemctl start numlock.service 2>/dev/null || true

    cat << 'EOF' | sudo tee /etc/udev/rules.d/99-numlock.rules > /dev/null
ACTION=="add", SUBSYSTEM=="leds", KERNEL=="*::numlock", ATTR{brightness}="1"
EOF
    sudo udevadm control --reload-rules 2>/dev/null || true
fi
echo "  ✅ NumLock configurado no COSMIC, Systemd e Udev."

# ==============================================================================
# 2. CEDILHA NO CHAT / WEBVIEWS / CHROMIUM / GTK
# ==============================================================================
echo "ç 2. Configurando Cedilha em Webviews (Antigravity Chat, Chrome, VS Code)..."

# Criar ~/.XCompose completo
cat << 'EOF' > "$REAL_HOME/.XCompose"
include "%L"

# Cedilha (' + c = ç e ' + C = Ç)
<dead_acute> <c> : "ç" ccedilla
<dead_acute> <C> : "Ç" Ccedilla

# Aspas simples duplas (' 2x = '')
<dead_acute> <dead_acute> : "''"
<dead_acute> <space> : "'" apostrophe

# Aspas duplas (" 2x = "")
<dead_diaeresis> <dead_diaeresis> : "\"\""
<dead_diaeresis> <space> : "\"" quotedbl

# Símbolos duplicados estilo Windows
<dead_tilde> <dead_tilde> : "~~"
<dead_tilde> <space> : "~" asciitilde
<dead_grave> <dead_grave> : "``"
<dead_grave> <space> : "`" grave
<dead_circumflex> <dead_circumflex> : "^^"
<dead_circumflex> <space> : "^" asciicircum
EOF
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.XCompose"

# Patch no GTK immodules.cache para incluir 'en' e 'en_US' no módulo de cedilha
if [ "$(id -u)" -eq 0 ] || sudo -n true 2>/dev/null; then
    for cache in /usr/lib/x86_64-linux-gnu/gtk-3.0/3.0.0/immodules.cache /usr/lib/x86_64-linux-gnu/gtk-2.0/2.10.0/immodules.cache; do
        if [ -f "$cache" ]; then
            sudo sed -i 's/"az:ca:co:fr:gv:oc:pt:sq:tr:wa"/"az:ca:co:fr:gv:oc:pt:sq:tr:wa:en:en_US"/g' "$cache"
        fi
    done

    if [ -f /usr/share/X11/locale/en_US.UTF-8/Compose ]; then
        sudo sed -i 's/"ć"\s*U0107/"ç"\tccedilla/g' /usr/share/X11/locale/en_US.UTF-8/Compose
        sudo sed -i 's/"Ć"\s*U0106/"Ç"\tCcedilla/g' /usr/share/X11/locale/en_US.UTF-8/Compose
        sudo sed -i 's/<dead_diaeresis> <dead_diaeresis>\s*:\s*"¨"\s*diaeresis/<dead_diaeresis> <dead_diaeresis>\t: "\\"\\""\tquotedbl/g' /usr/share/X11/locale/en_US.UTF-8/Compose
        sudo sed -i "s/<dead_acute> <dead_acute>\s*:\s*\"´\"\s*acute/<dead_acute> <dead_acute>\t: \"''\"\tapostrophe/g" /usr/share/X11/locale/en_US.UTF-8/Compose
    fi
fi
echo "  ✅ Cedilha e GTK immodules configurados."

# ==============================================================================
# 3. CORREÇÃO DE BIBLIOTECAS DO ESPANSO (Ubuntu / Pop!_OS 24.04 noble)
# ==============================================================================
echo "📦 3. Configurando bibliotecas de compatibilidade do Espanso..."

if [ "$(id -u)" -eq 0 ] || sudo -n true 2>/dev/null; then
    sudo mkdir -p /usr/local/lib/espanso
    
    # Limpa downloads anteriores para evitar conflito de permissões
    sudo rm -rf /tmp/libwx*.deb /tmp/wx_extract
    
    if [ ! -f /usr/local/lib/espanso/libwx_gtk3u_core-3.0.so.0 ]; then
        sudo wget -qO /tmp/libwxbase3.0.deb http://archive.ubuntu.com/ubuntu/pool/universe/w/wxwidgets3.0/libwxbase3.0-0v5_3.0.5.1+dfsg-4_amd64.deb || true
        sudo wget -qO /tmp/libwxgtk3.0.deb http://archive.ubuntu.com/ubuntu/pool/universe/w/wxwidgets3.0/libwxgtk3.0-gtk3-0v5_3.0.5.1+dfsg-4_amd64.deb || true
        
        if [ -f /tmp/libwxbase3.0.deb ] && [ -f /tmp/libwxgtk3.0.deb ]; then
            sudo mkdir -p /tmp/wx_extract
            sudo dpkg-deb -x /tmp/libwxbase3.0.deb /tmp/wx_extract
            sudo dpkg-deb -x /tmp/libwxgtk3.0.deb /tmp/wx_extract
            sudo cp -r /tmp/wx_extract/usr/lib/x86_64-linux-gnu/* /usr/local/lib/espanso/
            sudo rm -rf /tmp/wx_extract /tmp/libwx*.deb
        fi
    fi
    
    # Symlink para libtiff.so.5 -> libtiff.so.6.0.1
    sudo rm -f /usr/local/lib/espanso/libtiff.so*
    if [ -f /usr/lib/x86_64-linux-gnu/libtiff.so.6.0.1 ]; then
        sudo ln -sf /usr/lib/x86_64-linux-gnu/libtiff.so.6.0.1 /usr/local/lib/espanso/libtiff.so.5
    elif [ -f /usr/lib/x86_64-linux-gnu/libtiff.so.6 ]; then
        sudo ln -sf /usr/lib/x86_64-linux-gnu/libtiff.so.6 /usr/local/lib/espanso/libtiff.so.5
    fi
    
    echo "/usr/local/lib/espanso" | sudo tee /etc/ld.so.conf.d/espanso.conf > /dev/null
    sudo ldconfig
fi

# Iniciar / registrar serviço de usuário do Espanso
if command -v espanso >/dev/null 2>&1; then
    sudo -u "$REAL_USER" espanso service register 2>/dev/null || true
    sudo -u "$REAL_USER" espanso start 2>/dev/null || true
    echo "  ✅ Espanso registrado e iniciado com sucesso."
fi

# ==============================================================================
# 4. AUTOSTART: ESPANSO, KANDO, COPYQ E NUMLOCK
# ==============================================================================
echo "🔄 4. Criando entradas de Autostart na inicialização do sistema..."

mkdir -p "$REAL_HOME/.config/autostart"

# 4.1. CopyQ
cat << 'EOF' > "$REAL_HOME/.config/autostart/com.github.hluk.copyq.desktop"
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

# 4.2. Kando
cat << 'EOF' > "$REAL_HOME/.config/autostart/menu.kando.Kando.desktop"
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

# 4.3. Espanso
cat << 'EOF' > "$REAL_HOME/.config/autostart/espanso.desktop"
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

# 4.4. NumLock
cat << 'EOF' > "$REAL_HOME/.config/autostart/numlock.desktop"
[Desktop Entry]
Type=Application
Name=NumLock Auto-On
Exec=/bin/bash -c 'numlockx on 2>/dev/null || true; for led in /sys/class/leds/*::numlock/brightness; do echo 1 > "$led" 2>/dev/null || true; done'
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/autostart"
echo "  ✅ Entradas de autostart criadas para CopyQ, Kando, Espanso e NumLock."

echo ""
echo "🎉 Concluído com sucesso!"
