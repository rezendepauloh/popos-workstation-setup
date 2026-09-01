#!/bin/bash
# ==============================================================================
# Módulo 06: Instalação de Softwares de Workflow (VS Code, Flatpaks, Espanso, Kando)
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="SOFTWARE_INSTALL"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Softwares de Workflow já instalados anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "6. INSTALAÇÃO DE SOFTWARES DE WORKFLOW"

# 1. Repositório Oficial e Instalação do VS Code
log_msg "INFO" "Configurando repositório oficial do VS Code..."
sudo mkdir -p /etc/apt/keyrings
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor --yes -o /etc/apt/keyrings/packages.microsoft.gpg
echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
sudo apt update
sudo apt install -y code

# 2. Configuração do Flathub e Instalação de Flatpaks
log_msg "INFO" "Configurando Flathub e instalando Flatpaks..."
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install -y --system flathub \
    com.dropbox.Client \
    com.github.hluk.copyq \
    org.onlyoffice.desktopeditors \
    org.jellyfin.JellyfinDesktop \
    org.gimp.GIMP

# 3. Jellyfin Media Server (Repositório Oficial APT)
log_msg "INFO" "Instalando Jellyfin Media Server nativo..."
curl -fsSL https://repo.jellyfin.org/jellyfin_team.gpg.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/jellyfin.gpg
echo "deb [arch=$( dpkg --print-architecture ) signed-by=/etc/apt/keyrings/jellyfin.gpg] https://repo.jellyfin.org/ubuntu noble main" | sudo tee /etc/apt/sources.list.d/jellyfin.list > /dev/null
sudo apt update
sudo apt install -y jellyfin

# 4. Espanso (Wayland Edition) e bibliotecas wxWidgets 3.0 no Ubuntu/Pop!_OS 24.04 (noble)
log_msg "INFO" "Baixando e instalando Espanso (Wayland)..."
wget -qO /tmp/espanso.deb https://github.com/espanso/espanso/releases/download/v2.2.1/espanso-debian-wayland-amd64.deb
sudo apt install -y /tmp/espanso.deb

sudo mkdir -p /usr/local/lib/espanso
sudo rm -rf /tmp/libwx*.deb /tmp/wx_extract
if [ ! -f /usr/local/lib/espanso/libwx_gtk3u_core-3.0.so.0 ]; then
    wget -qO /tmp/libwxbase3.0.deb http://archive.ubuntu.com/ubuntu/pool/universe/w/wxwidgets3.0/libwxbase3.0-0v5_3.0.5.1+dfsg-4_amd64.deb || true
    wget -qO /tmp/libwxgtk3.0.deb http://archive.ubuntu.com/ubuntu/pool/universe/w/wxwidgets3.0/libwxgtk3.0-gtk3-0v5_3.0.5.1+dfsg-4_amd64.deb || true
    if [ -f /tmp/libwxbase3.0.deb ] && [ -f /tmp/libwxgtk3.0.deb ]; then
        mkdir -p /tmp/wx_extract
        dpkg-deb -x /tmp/libwxbase3.0.deb /tmp/wx_extract
        dpkg-deb -x /tmp/libwxgtk3.0.deb /tmp/wx_extract
        sudo cp -rn /tmp/wx_extract/usr/lib/x86_64-linux-gnu/* /usr/local/lib/espanso/
        rm -rf /tmp/wx_extract /tmp/libwx*.deb
    fi
fi
if [ -f /usr/lib/x86_64-linux-gnu/libtiff.so.6.0.1 ] && [ ! -f /usr/local/lib/espanso/libtiff.so.5 ]; then
    sudo ln -sf /usr/lib/x86_64-linux-gnu/libtiff.so.6.0.1 /usr/local/lib/espanso/libtiff.so.5
elif [ -f /usr/lib/x86_64-linux-gnu/libtiff.so.6 ] && [ ! -f /usr/local/lib/espanso/libtiff.so.5 ]; then
    sudo ln -sf /usr/lib/x86_64-linux-gnu/libtiff.so.6 /usr/local/lib/espanso/libtiff.so.5
fi
echo "/usr/local/lib/espanso" | sudo tee /etc/ld.so.conf.d/espanso.conf > /dev/null
sudo ldconfig

# Registra o serviço do Espanso no usuário
if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    sudo -u "$REAL_USER" espanso service register 2>/dev/null || true
    sudo -u "$REAL_USER" espanso start 2>/dev/null || true
else
    espanso service register 2>/dev/null || true
    espanso start 2>/dev/null || true
fi

# 5. Kando
log_msg "INFO" "Baixando e instalando Kando (Pie Menu)..."
KANDO_URL=$(curl -s https://api.github.com/repos/kando-menu/kando/releases/latest | jq -r '.assets[] | select(.name | endswith("amd64.deb")) | .browser_download_url')
wget -qO /tmp/kando.deb "$KANDO_URL"
sudo apt install -y /tmp/kando.deb

# Wrapper de compatibilidade do Kando para COSMIC Desktop / Wayland (XWayland)
cat << 'EOF' | sudo tee /usr/local/bin/kando > /dev/null
#!/bin/bash
export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
exec /usr/lib/kando/kando "$@"
EOF
sudo chmod +x /usr/local/bin/kando

if [ -f /usr/share/applications/menu.kando.Kando.desktop ]; then
    sudo sed -i 's|^Exec=.*|Exec=env XDG_SESSION_TYPE=x11 GDK_BACKEND=x11 /usr/lib/kando/kando %U|' /usr/share/applications/menu.kando.Kando.desktop
    sudo update-desktop-database /usr/share/applications 2>/dev/null || true
fi

# Limpeza
rm -f /tmp/espanso.deb /tmp/kando.deb

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Softwares de workflow instalados e configurados com sucesso."
