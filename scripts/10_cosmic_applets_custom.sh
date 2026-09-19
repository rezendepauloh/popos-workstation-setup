#!/bin/bash
# ==============================================================================
# Módulo 10: Miniaplicativos Customizados do COSMIC (Mídia na Dock & Minimon no Painel)
# Instala o Now Playing (Dock - Flatpak) e o Minimon System Monitor (Painel)
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="COSMIC_APPLETS_CUSTOM"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Miniaplicativos customizados do COSMIC já instalados. Pulando..."
    exit 0
fi

log_msg "HEADER" "10. MINIAPLICATIVOS DO COSMIC (CONTROLE DE MÍDIA & MONITOR DO SISTEMA)"

# ------------------------------------------------------------------------------
# 1. Miniaplicativo de Mídia (Dock - Now Playing / com.github.DiegoMMR.CosmicExtAppletNowPlaying)
# ------------------------------------------------------------------------------
log_msg "INFO" "Verificando miniaplicativo de controle de mídia Now Playing..."

APPLET_ID="com.github.DiegoMMR.CosmicExtAppletNowPlaying"

# Adiciona o repositório cosmic flatpak para o usuário caso ainda não exista
if ! sudo -u "$REAL_USER" flatpak remotes --user | grep -q "^cosmic"; then
    log_msg "INFO" "Adicionando repositório de applets COSMIC no Flatpak do usuário..."
    sudo -u "$REAL_USER" flatpak remote-add --user --if-not-exists cosmic https://apt.pop-os.org/cosmic/
fi

if ! sudo -u "$REAL_USER" flatpak list --user | grep -q "$APPLET_ID"; then
    log_msg "INFO" "Instalando applet Now Playing ($APPLET_ID) via Flatpak..."
    sudo -u "$REAL_USER" flatpak install -y --user cosmic "$APPLET_ID"
    log_msg "SUCCESS" "Miniaplicativo Now Playing instalado com sucesso."
else
    log_msg "INFO" "Miniaplicativo Now Playing já instalado no Flatpak."
fi

# ------------------------------------------------------------------------------
# 2. Miniaplicativo Minimon (Painel Superior Direito - Dropdown de CPU/RAM/Disco/Rede)
# ------------------------------------------------------------------------------
log_msg "INFO" "Verificando miniaplicativo Minimon (Monitor do Sistema)..."

sudo apt install -y lm-sensors sysstat

if ! command -v cosmic-ext-applet-minimon >/dev/null 2>&1 && [ ! -f /usr/share/applications/io.github.cosmic_utils.minimon-applet.desktop ]; then
    TEMP_MINIMON_DEB=$(mktemp /tmp/minimon_XXXXXX.deb)
    MINIMON_URL="https://github.com/cosmic-utils/minimon-applet/releases/download/v1.2.0/cosmic-ext-applet-minimon_1.2.0_amd64.deb"

    log_msg "INFO" "Baixando pacote oficial do Minimon Applet da cosmic-utils..."
    rm -f "$TEMP_MINIMON_DEB"
    curl -fSL --progress-bar "$MINIMON_URL" -o "$TEMP_MINIMON_DEB"

    log_msg "INFO" "Instalando pacote Minimon no sistema..."
    sudo apt install -y "$TEMP_MINIMON_DEB" || sudo apt-get install -f -y
    rm -f "$TEMP_MINIMON_DEB"
    log_msg "SUCCESS" "Minimon System Monitor Applet instalado com sucesso."
else
    log_msg "INFO" "Minimon Applet já instalado."
fi

# Garante os applets adicionais do COSMIC via Flatpak (Weather, YapCap, Drives)
EXTRA_APPLETS=(
    "io.github.cosmic_utils.weather-applet"
    "io.github.TopiCsarno.YapCap"
    "dev.cappsy.CosmicExtAppletDrives"
)

for applet in "${EXTRA_APPLETS[@]}"; do
    if ! sudo -u "$REAL_USER" flatpak list --user | grep -q "$applet"; then
        log_msg "INFO" "Instalando applet $applet via Flatpak (cosmic)..."
        sudo -u "$REAL_USER" flatpak install -y --user cosmic "$applet" || log_msg "WARN" "Não foi possível instalar $applet automaticamente."
    else
        log_msg "INFO" "Applet $applet já instalado no Flatpak."
    fi
done

# ------------------------------------------------------------------------------
# 3. Registro dos Applets no Painel Superior e na Dock do COSMIC
# ------------------------------------------------------------------------------
log_msg "INFO" "Posicionando applets no Painel Superior (Wings e Centro) e na Dock..."

mkdir -p "$REAL_HOME/.config/cosmic/com.system76.CosmicPanel.Panel/v1"
mkdir -p "$REAL_HOME/.config/cosmic/com.system76.CosmicPanel.Dock/v1"

# Painel Superior - Centro: Relógio e Clima
cat << 'INNER_EOF' > "$REAL_HOME/.config/cosmic/com.system76.CosmicPanel.Panel/v1/plugins_center"
Some([
    "com.system76.CosmicAppletTime",
    "io.github.cosmic_utils.weather-applet",
])
INNER_EOF

# Painel Superior - Wings: Workspaces/AppButton na esquerda e indicadores/utilitários na direita
cat << 'INNER_EOF' > "$REAL_HOME/.config/cosmic/com.system76.CosmicPanel.Panel/v1/plugins_wings"
Some(([
    "com.system76.CosmicPanelWorkspacesButton",
    "com.system76.CosmicPanelAppButton",
], [
    "io.github.TopiCsarno.YapCap",
    "io.github.cosmic_utils.minimon-applet",
    "com.system76.CosmicAppletInputSources",
    "com.system76.CosmicAppletStatusArea",
    "com.system76.CosmicAppletA11y",
    "com.system76.CosmicAppletTiling",
    "com.system76.CosmicAppletAudio",
    "com.system76.CosmicAppletBluetooth",
    "com.system76.CosmicAppletNetwork",
    "com.system76.CosmicAppletNotifications",
    "dev.cappsy.CosmicExtAppletDrives",
    "com.system76.CosmicAppletPower",
]))
INNER_EOF

# Dock: Controle de Mídia Now Playing no canto inferior esquerdo
cat << 'INNER_EOF' > "$REAL_HOME/.config/cosmic/com.system76.CosmicPanel.Dock/v1/plugins_wings"
Some(([
    "com.github.DiegoMMR.CosmicExtAppletNowPlaying",
], [
    "com.system76.CosmicAppletTiling",
    "com.system76.CosmicAppletTime",
    "com.system76.CosmicAppletNotifications",
    "com.system76.CosmicAppletPower",
]))
INNER_EOF

chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/cosmic"
sudo update-desktop-database /usr/share/applications 2>/dev/null || true
pkill -f "cosmic-panel" 2>/dev/null || true

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Miniaplicativos customizados do COSMIC configurados e ativos no painel e dock."
