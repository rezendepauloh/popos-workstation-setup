#!/bin/bash
# ==============================================================================
# Módulo 07: Instalação e Configuração do Antigravity IDE (Google Antigravity)
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="ANTIGRAVITY_INSTALL"

if check_flag "$FLAG_NAME" "$@"; then
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

# Links e wrappers no PATH com suporte dinâmico a Wayland e X11
cat << 'EOF' | sudo tee /usr/local/bin/antigravity > /dev/null
#!/bin/bash
# Detecta se o argumento --ozone-platform já foi fornecido
HAS_OZONE=0
for arg in "$@"; do
    if [[ "$arg" == --ozone-platform* ]]; then
        HAS_OZONE=1
        break
    fi
done

if [ "$HAS_OZONE" -eq 0 ]; then
    if [ -n "$WAYLAND_DISPLAY" ] || [ "$XDG_SESSION_TYPE" = "wayland" ]; then
        exec /opt/antigravity/antigravity-ide --ozone-platform=wayland "$@"
    fi
fi

exec /opt/antigravity/antigravity-ide "$@"
EOF
sudo chmod +x /usr/local/bin/antigravity
sudo ln -sf /usr/local/bin/antigravity /usr/local/bin/antigravity-ide
sudo ln -sf /usr/local/bin/antigravity /usr/local/bin/agy

# Atualiza também o wrapper interno em /opt/antigravity/bin
sudo mkdir -p /opt/antigravity/bin
sudo cp -f /usr/local/bin/antigravity /opt/antigravity/bin/antigravity-ide
sudo chmod +x /opt/antigravity/bin/antigravity-ide

# Configuração de flags de inicialização para Wayland nativo (evita crashes caso XWayland falhe)
mkdir -p "$REAL_HOME/.config"
cat << 'EOF' > "$REAL_HOME/.config/antigravity-flags.conf"
--ozone-platform=wayland
EOF
cat << 'EOF' > "$REAL_HOME/.config/antigravity-ide-flags.conf"
--ozone-platform=wayland
EOF
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/antigravity"*-flags.conf 2>/dev/null || true

# Limpeza preventiva de locks e caches residuais em reinstalações
rm -f "$REAL_HOME/.config/Antigravity IDE/code.lock" 2>/dev/null || true
rm -rf "$REAL_HOME/.config/Antigravity IDE/GPUCache" \
       "$REAL_HOME/.config/Antigravity IDE/DawnGraphiteCache" \
       "$REAL_HOME/.config/Antigravity IDE/DawnWebGPUCache" 2>/dev/null || true
rm -f "$REAL_HOME/.config/Antigravity IDE/Crashpad/pending"/* 2>/dev/null || true

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
Exec=/usr/local/bin/antigravity %F
Icon=antigravity
Type=Application
StartupNotify=false
StartupWMClass=antigravity-ide
Categories=Development;IDE;TextEditor;
MimeType=text/plain;inode/directory;application/x-code-workspace;
Keywords=vscode;development;ide;antigravity;agy;
EOF

# Garante cópia do lançador no diretório de usuário (prioridade máxima no COSMIC)
mkdir -p "$REAL_HOME/.local/share/applications"
cp -f /usr/share/applications/antigravity.desktop "$REAL_HOME/.local/share/applications/antigravity.desktop"
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.local/share/applications/antigravity.desktop" 2>/dev/null || true

sudo update-desktop-database /usr/share/applications 2>/dev/null || true
update-desktop-database "$REAL_HOME/.local/share/applications" 2>/dev/null || true

rm -f /tmp/antigravity.tar.gz

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Antigravity IDE instalado e integrado ao sistema com sucesso."
