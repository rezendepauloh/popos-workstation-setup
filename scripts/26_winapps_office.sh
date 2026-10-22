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
if [ -f "$BASE_DIR/.env" ]; then
    set -a
    source "$BASE_DIR/.env"
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
CONTAINER="winapps-windows"

fix_smb_routing() {
    for i in {1..30}; do
        if docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q "true"; then
            while docker exec "$CONTAINER" iptables -t nat -L QEMU_DNAT -n --line-numbers 2>/dev/null | grep -E "dpt:(139|445)" >/dev/null; do
                LINE=$(docker exec "$CONTAINER" iptables -t nat -L QEMU_DNAT -n --line-numbers 2>/dev/null | grep -E "dpt:(139|445)" | head -n1 | awk '{print $1}')
                [ -n "$LINE" ] && docker exec "$CONTAINER" iptables -t nat -D QEMU_DNAT "$LINE" 2>/dev/null || break
            done
            gio mount "smb://172.20.0.2/onedrive-mpms" 2>/dev/null || true
            return 0
        fi
        sleep 2
    done
}

case "$1" in
    start)
        echo "🚀 Iniciando VM/Container Windows..."
        docker compose -f "$COMPOSE_DIR/docker-compose.yml" up -d
        (fix_smb_routing) &
        echo "Acesse http://127.0.0.1:8006 no navegador para acompanhar o progresso de inicialização."
        ;;
    stop)
        echo "🛑 Desligando VM/Container Windows..."
        docker compose -f "$COMPOSE_DIR/docker-compose.yml" stop
        ;;
    restart)
        echo "🔄 Reiniciando VM/Container Windows..."
        docker compose -f "$COMPOSE_DIR/docker-compose.yml" restart
        (fix_smb_routing) &
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
    fix-smb)
        echo "🔧 Ajustando roteamento SMB e montagem no Nautilus..."
        fix_smb_routing
        ;;
    *)
        echo "Uso: winapps-vm {start|stop|restart|status|logs|web|setup-apps|fix-smb}"
        exit 1
        ;;
esac
EOF

chmod +x "$WINAPPS_HELPER"
chown "$REAL_USER:$REAL_USER" "$WINAPPS_HELPER"

# ------------------------------------------------------------------------------
# 5.1 Serviço Systemd de Usuário para Sincronização SMB e Automount do OneDrive
# ------------------------------------------------------------------------------
SMB_SYNC_SCRIPT="$REAL_HOME/.local/bin/winapps-smb-sync.sh"
cat <<'EOF' > "$SMB_SYNC_SCRIPT"
#!/bin/bash
# ==============================================================================
# Sincronizador de regras de firewall SMB e automount GVFS para WinApps
# ==============================================================================
CONTAINER="winapps-windows"

for i in {1..30}; do
    if docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q "true"; then
        while docker exec "$CONTAINER" iptables -t nat -L QEMU_DNAT -n --line-numbers 2>/dev/null | grep -E "dpt:(139|445)" >/dev/null; do
            LINE=$(docker exec "$CONTAINER" iptables -t nat -L QEMU_DNAT -n --line-numbers 2>/dev/null | grep -E "dpt:(139|445)" | head -n1 | awk '{print $1}')
            [ -n "$LINE" ] && docker exec "$CONTAINER" iptables -t nat -D QEMU_DNAT "$LINE" 2>/dev/null || break
        done
        gio mount "smb://172.20.0.2/onedrive-mpms" 2>/dev/null || true
        exit 0
    fi
    sleep 2
done
EOF

chmod +x "$SMB_SYNC_SCRIPT"
chown "$REAL_USER:$REAL_USER" "$SMB_SYNC_SCRIPT"

USER_SYSTEMD_DIR="$REAL_HOME/.config/systemd/user"
mkdir -p "$USER_SYSTEMD_DIR"
cat <<EOF > "$USER_SYSTEMD_DIR/winapps-smb-sync.service"
[Unit]
Description=WinApps SMB Firewall Router & OneDrive Automount
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$SMB_SYNC_SCRIPT
RemainAfterExit=yes

[Install]
WantedBy=default.target
EOF

chown -R "$REAL_USER:$REAL_USER" "$USER_SYSTEMD_DIR"

if [ -n "$REAL_UID" ]; then
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user daemon-reload 2>/dev/null || true
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user enable winapps-smb-sync.service 2>/dev/null || true
fi

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
    # Garantir marcador SMB direto no Nautilus
    if ! grep -q "smb://172.20.0.2/onedrive-mpms" "$GTK_BOOKMARKS"; then
        echo "smb://172.20.0.2/onedrive-mpms OneDrive-MPMS" >> "$GTK_BOOKMARKS"
    fi
    chown "$REAL_USER:$REAL_USER" "$GTK_BOOKMARKS"
fi

# ------------------------------------------------------------------------------
# 8. Criar Ícone Oficial do Windows e Lançador Desktop para o WinApps
# ------------------------------------------------------------------------------
ICON_DIR="$REAL_HOME/.local/share/icons/hicolor/scalable/apps"
mkdir -p "$ICON_DIR"
cat << 'EOF' > "$ICON_DIR/windows-11.svg"
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 88 88">
  <path fill="#0078d4" d="M0 0h41.6v41.6H0zM46.4 0H88v41.6H46.4zM0 46.4h41.6V88H0zM46.4 46.4H88V88H46.4z"/>
</svg>
EOF

DESKTOP_DIR="$REAL_HOME/.local/share/applications"
mkdir -p "$DESKTOP_DIR"
cat << EOF > "$DESKTOP_DIR/winapps-windows.desktop"
[Desktop Entry]
Name=Windows 11 (WinApps VM)
Comment=Acessar o Windows 11 virtualizado via navegador / web viewer
Exec=xdg-open http://127.0.0.1:8006
Icon=windows-11
Terminal=false
Type=Application
Categories=System;Utility;Office;
Keywords=windows;winapps;vm;rdp;office;onedrive;
StartupNotify=true
Actions=DesktopRDP;RestartVM;StopVM;FixSMB;

[Desktop Action DesktopRDP]
Name=Conectar via Desktop RDP (WinApps)
Exec=$REAL_HOME/.local/bin/winapps windows

[Desktop Action RestartVM]
Name=Reiniciar Container Windows
Exec=$REAL_HOME/.local/bin/winapps-vm restart

[Desktop Action StopVM]
Name=Desligar Container Windows
Exec=$REAL_HOME/.local/bin/winapps-vm stop

[Desktop Action FixSMB]
Name=Desbloquear Roteamento SMB (OneDrive)
Exec=$REAL_HOME/.local/bin/winapps-vm fix-smb
EOF

chown -R "$REAL_USER:$REAL_USER" "$ICON_DIR" "$DESKTOP_DIR/winapps-windows.desktop"
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
fi

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "🎉 WinApps e stack de virtualização Windows provisionados com sucesso!"
log_msg "INFO" "Para iniciar o Windows na primeira vez, use: 'winapps-vm start' e acesse http://127.0.0.1:8006"
