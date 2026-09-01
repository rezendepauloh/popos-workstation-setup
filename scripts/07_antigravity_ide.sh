#!/bin/bash
# ==============================================================================
# Módulo 07: Instalação e Configuração do Antigravity IDE (Google Antigravity)
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="ANTIGRAVITY_INSTALL"

if check_flag "$FLAG_NAME"; then
    log_msg "INFO" "⏭️  Antigravity IDE já instalado anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "7. INSTALAÇÃO DO ANTIGRAVITY IDE"

ANTIGRAVITY_URL="https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.5.5-4923483625488384/linux-x64/Antigravity%20IDE.tar.gz"
log_msg "INFO" "Baixando tar.gz do Antigravity IDE..."
wget -qO /tmp/antigravity.tar.gz "$ANTIGRAVITY_URL"

sudo mkdir -p /opt/antigravity
sudo tar -xzf /tmp/antigravity.tar.gz -C /opt/antigravity --strip-components=1
sudo chmod -R 755 /opt/antigravity
sudo chmod +x /opt/antigravity/antigravity-ide /opt/antigravity/bin/antigravity-ide 2>/dev/null || true

# Ajuste de permissões do sandbox do Electron
if [ -f /opt/antigravity/chrome-sandbox ]; then
    sudo chown root:root /opt/antigravity/chrome-sandbox
    sudo chmod 4755 /opt/antigravity/chrome-sandbox
fi

# Perfil do AppArmor para Pop!_OS 24.04 (permite User Namespaces do Electron)
if [ -d /etc/apparmor.d ]; then
    cat << 'EOF' | sudo tee /etc/apparmor.d/antigravity > /dev/null
abi <abi/4.0>,
include <tunables/global>

profile antigravity /opt/antigravity/antigravity-ide flags=(unconfined) {
  userns,
  include if exists <local/antigravity>
}
EOF
    sudo apparmor_parser -r /etc/apparmor.d/antigravity 2>/dev/null || true
fi

# Links simbólicos no PATH
sudo ln -sf /opt/antigravity/bin/antigravity-ide /usr/local/bin/antigravity
sudo ln -sf /opt/antigravity/bin/antigravity-ide /usr/local/bin/antigravity-ide
sudo ln -sf /opt/antigravity/bin/antigravity-ide /usr/local/bin/agy

# Ícone e Lançador .desktop no sistema
if [ -f /opt/antigravity/resources/app/resources/linux/code.png ]; then
    sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
    sudo cp /opt/antigravity/resources/app/resources/linux/code.png /usr/share/icons/hicolor/512x512/apps/antigravity.png
fi

cat << 'EOF' | sudo tee /usr/share/applications/antigravity.desktop > /dev/null
[Desktop Entry]
Name=Antigravity
Comment=Google Antigravity IDE (Advanced Agentic Coding)
GenericName=Text Editor
Exec=/opt/antigravity/antigravity-ide %F
Icon=antigravity
Type=Application
StartupNotify=false
StartupWMClass=antigravity-ide
Categories=Development;IDE;TextEditor;
MimeType=text/plain;inode/directory;application/x-code-workspace;
Keywords=vscode;development;ide;antigravity;agy;
EOF

sudo update-desktop-database /usr/share/applications 2>/dev/null || true
update-desktop-database "$REAL_HOME/.local/share/applications" 2>/dev/null || true

rm -f /tmp/antigravity.tar.gz

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Antigravity IDE instalado e integrado ao sistema com sucesso."
