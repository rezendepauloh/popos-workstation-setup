#!/bin/bash
# ==============================================================================
# Módulo 26: WinApps (Microsoft 365, Office e Apps Windows em Container/KVM)
# Integração transparente de aplicativos Windows e OneDrive corporativo ao Pop!_OS
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="WINAPPS_OFFICE"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  WinApps e ferramentas de integração Windows já configuradas. Pulando..."
    exit 0
fi

log_msg "HEADER" "26. CONFIGURAÇÃO DO WINAPPS (MICROSOFT 365 & WINDOWS SEAMLESS)"

# Carregar variáveis de ambiente se existirem
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

WINAPPS_USER="${WINAPPS_RDP_USER:-winapps}"
WINAPPS_PASS="${WINAPPS_RDP_PASSWORD:-winapps}"
WINAPPS_IP="${WINAPPS_RDP_IP:-127.0.0.1}"
WINAPPS_PORT="${WINAPPS_RDP_PORT:-3389}"
WINAPPS_VERSION="${WINAPPS_WINDOWS_VERSION:-win11}"
WINAPPS_RAM="${WINAPPS_RAM_SIZE:-4G}"
WINAPPS_CPU="${WINAPPS_CPU_CORES:-4}"

# ------------------------------------------------------------------------------
# 1. Dependências do Host (FreeRDP 3 / FreeRDP 2, Docker, utilitários RDP)
# ------------------------------------------------------------------------------
log_msg "INFO" "Instalando dependências do host (FreeRDP, dialog, iproute2, cifs-utils)..."
sudo apt update -y
sudo apt install -y \
    freerdp3-x11 \
    freerdp3-wayland \
    dialog \
    iproute2 \
    cifs-utils \
    smbclient \
    curl \
    git \
    libnotify-bin

# ------------------------------------------------------------------------------
# 2. Configurar Repositório Local do WinApps
# ------------------------------------------------------------------------------
WINAPPS_DIR="$REAL_HOME/.local/share/winapps"
WINAPPS_CONFIG_DIR="$REAL_HOME/.config/winapps"

log_msg "INFO" "Preparando diretório e repositório do WinApps..."
mkdir -p "$WINAPPS_CONFIG_DIR"
chown -R "$REAL_USER:$REAL_USER" "$WINAPPS_CONFIG_DIR"

if [ ! -d "$WINAPPS_DIR" ]; then
    log_msg "INFO" "Clonando repositório oficial do WinApps (winapps-org/winapps)..."
    sudo -u "$REAL_USER" git clone --depth 1 https://github.com/winapps-org/winapps.git "$WINAPPS_DIR"
else
    log_msg "INFO" "Atualizando repositório existente do WinApps..."
    (cd "$WINAPPS_DIR" && sudo -u "$REAL_USER" git pull origin main || true)
fi

# ------------------------------------------------------------------------------
# 3. Gerar Arquivo de Configuração do WinApps (~/.config/winapps/winapps.conf)
# ------------------------------------------------------------------------------
WINAPPS_CONF="$WINAPPS_CONFIG_DIR/winapps.conf"

log_msg "INFO" "Gerando configuração padrão: $WINAPPS_CONF..."
cat <<EOF > "$WINAPPS_CONF"
# WinApps Configuration File
RDP_USER="$WINAPPS_USER"
RDP_PASS="$WINAPPS_PASS"
RDP_DOMAIN=""
RDP_IP="$WINAPPS_IP"
RDP_PORT="$WINAPPS_PORT"
RDP_SCALE="100"
RDP_FLAGS="/cert:ignore /clipboard /sound:sys:alsa /drive:home,$REAL_HOME"
DEBUG="false"
WAFLAVOR="manual"
AUTOPAUSE="off"
AUTOPAUSE_TIME="300"
EOF

chown "$REAL_USER:$REAL_USER" "$WINAPPS_CONF"
chmod 600 "$WINAPPS_CONF"

# ------------------------------------------------------------------------------
# 4. Configurar Docker Compose para o Windows Container (dockurr/windows)
# ------------------------------------------------------------------------------
WINAPPS_COMPOSE_DIR="$REAL_HOME/Docker/winapps-windows"
log_msg "INFO" "Criando stack Docker Compose em $WINAPPS_COMPOSE_DIR..."
mkdir -p "$WINAPPS_COMPOSE_DIR"

cat <<EOF > "$WINAPPS_COMPOSE_DIR/docker-compose.yml"
services:
  windows:
    image: dockurr/windows
    container_name: winapps-windows
    environment:
      VERSION: "$WINAPPS_VERSION"
      RAM_SIZE: "$WINAPPS_RAM"
      CPU_CORES: "$WINAPPS_CPU"
      USERNAME: "$WINAPPS_USER"
      PASSWORD: "$WINAPPS_PASS"
      DISK_SIZE: "64G"
    devices:
      - /dev/kvm
    cap_add:
      - NET_ADMIN
    ports:
      - "8006:8006"
      - "3389:3389/tcp"
      - "3389:3389/udp"
    volumes:
      - ./data:/storage
      - $REAL_HOME/Compartilhado_VM:/shared
    restart: unless-stopped
    stop_grace_period: 2m
EOF

chown -R "$REAL_USER:$REAL_USER" "$WINAPPS_COMPOSE_DIR"

# Criar pasta compartilhada bidirecional host <-> guest
mkdir -p "$REAL_HOME/Compartilhado_VM"
chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/Compartilhado_VM"

# ------------------------------------------------------------------------------
# 5. Criar Script Auxiliar de Gerenciamento da VM Windows (~/.local/bin/winapps-vm)
# ------------------------------------------------------------------------------
mkdir -p "$REAL_HOME/.local/bin"
WINAPPS_HELPER="$REAL_HOME/.local/bin/winapps-vm"

cat <<'EOF' > "$WINAPPS_HELPER"
#!/bin/bash
# ==============================================================================
# Helper de Gerenciamento do Container Windows para o WinApps
# ==============================================================================
COMPOSE_DIR="$HOME/Docker/winapps-windows"

case "$1" in
    start)
        echo "🚀 Iniciando VM/Container Windows..."
        docker compose -f "$COMPOSE_DIR/docker-compose.yml" up -d
        echo "Acesse http://127.0.0.1:8006 no navegador para acompanhar o progresso de inicialização."
        ;;
    stop)
        echo "🛑 Desligando VM/Container Windows..."
        docker compose -f "$COMPOSE_DIR/docker-compose.yml" stop
        ;;
    restart)
        echo "🔄 Reiniciando VM/Container Windows..."
        docker compose -f "$COMPOSE_DIR/docker-compose.yml" restart
        ;;
    status)
        docker compose -f "$COMPOSE_DIR/docker-compose.yml" ps
        ;;
    logs)
        docker compose -f "$COMPOSE_DIR/docker-compose.yml" logs -f
        ;;
    web)
        xdg-open "http://127.0.0.1:8006" 2>/dev/null || sensible-browser "http://127.0.0.1:8006" &
        ;;
    setup-apps)
        echo "🔍 Detectando e instalando atalhos de aplicativos com WinApps..."
        cd "$HOME/.local/share/winapps" && ./setup.sh --user
        ;;
    *)
        echo "Uso: winapps-vm {start|stop|restart|status|logs|web|setup-apps}"
        exit 1
        ;;
esac
EOF

chmod +x "$WINAPPS_HELPER"
chown "$REAL_USER:$REAL_USER" "$WINAPPS_HELPER"

# ------------------------------------------------------------------------------
# 6. Atualizar Categorias do COSMIC App Library para Incluir o WinApps e Office
# ------------------------------------------------------------------------------
COSMIC_COMP_DIR="$REAL_HOME/.config/cosmic/com.system76.CosmicAppList"
V1_FILE="$COSMIC_COMP_DIR/v1/all"

if [ -f "$V1_FILE" ]; then
    log_msg "INFO" "Verificando se os aplicativos WinApps estão na categoria 'Office' do COSMIC..."
    if ! grep -q "microsoft-word" "$V1_FILE" 2>/dev/null; then
        log_msg "INFO" "Adicionando Word, Excel, PowerPoint e OneDrive à lista de inclusão do COSMIC..."
        # Injeção segura de IDs de apps nas inclusões do Office
        sed -i '/"ms-outlook",/a \                "microsoft-word",\n                "microsoft-excel",\n                "microsoft-powerpoint",\n                "microsoft-onedrive",' "$V1_FILE" || true
    fi
fi

# ------------------------------------------------------------------------------
# 7. Criar Ponto de Montagem e Marcador no Nautilus para o OneDrive Corporativo
# ------------------------------------------------------------------------------
ONEDRIVE_MOUNT_POINT="$REAL_HOME/OneDrive_MPMS"
mkdir -p "$ONEDRIVE_MOUNT_POINT"
chown "$REAL_USER:$REAL_USER" "$ONEDRIVE_MOUNT_POINT"

# Adicionar marcador no Nautilus GTK bookmarks se ainda não existir
GTK_BOOKMARKS="$REAL_HOME/.config/gtk-3.0/bookmarks"
if [ -f "$GTK_BOOKMARKS" ]; then
    if ! grep -q "$ONEDRIVE_MOUNT_POINT" "$GTK_BOOKMARKS"; then
        echo "file://$ONEDRIVE_MOUNT_POINT OneDrive (MPMS)" >> "$GTK_BOOKMARKS"
        chown "$REAL_USER:$REAL_USER" "$GTK_BOOKMARKS"
    fi
fi

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "🎉 WinApps e stack de virtualização Windows provisionados com sucesso!"
log_msg "INFO" "Para iniciar o Windows na primeira vez, use: 'winapps-vm start' e acesse http://127.0.0.1:8006"
