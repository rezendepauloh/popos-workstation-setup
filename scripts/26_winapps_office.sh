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
      - "127.0.0.1:8006:8006"
      - "127.0.0.1:3389:3389/tcp"
      - "127.0.0.1:3389:3389/udp"
    volumes:
      - ./data:/storage
      - $REAL_HOME/Compartilhado_VM:/shared
    restart: unless-stopped
    stop_grace_period: 2m
EOF

chmod 600 "$WINAPPS_COMPOSE_DIR/docker-compose.yml"
chown -R "$REAL_USER:$REAL_USER" "$WINAPPS_COMPOSE_DIR"

# Criar pasta compartilhada bidirecional host <-> guest
mkdir -p "$REAL_HOME/Compartilhado_VM"
if [ -d "$BASE_DIR/util/winapps" ]; then
    cp -u "$BASE_DIR/util/winapps/"* "$REAL_HOME/Compartilhado_VM/" 2>/dev/null || true
fi

# Gerar script de AutoLogon e bypass de tela de bloqueio com as credenciais do .env
cat <<EOF > "$REAL_HOME/Compartilhado_VM/setup_autologon.bat"
@echo off
:: ==============================================================================
:: WinApps AutoLogon & Lock Screen Bypass Setup for Windows 11
:: Configura o login automatico e desativa a tela de bloqueio do Windows
:: ==============================================================================

setlocal enabledelayedexpansion
set "LOG_FILE=\\\\host.lan\\Data\\autologon_result.log"
echo [%DATE% %TIME%] Iniciando configuracao de AutoLogon... > "%LOG_FILE%"

set "RDP_USER=$WINAPPS_USER"
set "RDP_PASS=$WINAPPS_PASS"
if not "%~1"=="" set "RDP_USER=%~1"
if not "%~2"=="" set "RDP_PASS=%~2"

:: 1. Credenciais no Winlogon para RDP transparente
reg.exe add "HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon" /v "DefaultUserName" /t REG_SZ /d "%RDP_USER%" /f >> "%LOG_FILE%" 2>&1
reg.exe add "HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon" /v "DefaultPassword" /t REG_SZ /d "%RDP_PASS%" /f >> "%LOG_FILE%" 2>&1
reg.exe add "HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon" /v "DefaultDomainName" /t REG_SZ /d "" /f >> "%LOG_FILE%" 2>&1
reg.exe delete "HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon" /v "ForceAutoLogon" /f >> "%LOG_FILE%" 2>&1
reg.exe add "HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon" /v "AutoAdminLogon" /t REG_SZ /d "0" /f >> "%LOG_FILE%" 2>&1

:: 2. Desativar Tela de Bloqueio (NoLockScreen)
reg.exe add "HKLM\\SOFTWARE\\Policies\\Microsoft\\Windows\\Personalization" /v "NoLockScreen" /t REG_DWORD /d 1 /f >> "%LOG_FILE%" 2>&1

:: 3. Desativar solicitacao de senha ao conectar via RDP / Terminal Services
reg.exe add "HKLM\\SOFTWARE\\Policies\\Microsoft\\Windows NT\\Terminal Services" /v "fPromptForPassword" /t REG_DWORD /d 0 /f >> "%LOG_FILE%" 2>&1
reg.exe add "HKLM\\SYSTEM\\CurrentControlSet\\Control\\Terminal Server\\WinStations\\RDP-Tcp" /v "fPromptForPassword" /t REG_DWORD /d 0 /f >> "%LOG_FILE%" 2>&1

:: 4. Desativar protecao por senha no protetor de tela
reg.exe add "HKLM\\SOFTWARE\\Policies\\Microsoft\\Windows\\Control Panel\\Desktop" /v "ScreenSaverIsSecure" /t REG_SZ /d 0 /f >> "%LOG_FILE%" 2>&1
reg.exe add "HKCU\\Control Panel\\Desktop" /v "ScreenSaverIsSecure" /t REG_SZ /d 0 /f >> "%LOG_FILE%" 2>&1

:: 5. Desativar suspensao e desligamento de tela via PowerCFG
powercfg.exe -x -monitor-timeout-ac 0 >> "%LOG_FILE%" 2>&1
powercfg.exe -x -standby-timeout-ac 0 >> "%LOG_FILE%" 2>&1
powercfg.exe -h off >> "%LOG_FILE%" 2>&1

:: 6. Impedir expiracao de senha da conta local
net.exe accounts /maxpwage:unlimited >> "%LOG_FILE%" 2>&1

echo [%DATE% %TIME%] AutoLogon configurado com sucesso! >> "%LOG_FILE%"
exit /b 0
EOF

chmod 600 "$REAL_HOME/Compartilhado_VM/setup_autologon.bat"
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

case "$1" in
    start)
        echo "🚀 Iniciando VM/Container Windows..."
        docker compose -f "$COMPOSE_DIR/docker-compose.yml" up -d
        if [ -x "$HOME/.local/bin/winapps-smb-sync.sh" ]; then
            (sleep 3 && "$HOME/.local/bin/winapps-smb-sync.sh" --once) &
        fi
        echo "Acesse http://127.0.0.1:8006 no navegador para acompanhar o progresso de inicialização."
        ;;
    stop)
        echo "🛑 Desligando VM/Container Windows..."
        docker compose -f "$COMPOSE_DIR/docker-compose.yml" stop
        ;;
    restart)
        echo "🔄 Reiniciando VM/Container Windows..."
        docker compose -f "$COMPOSE_DIR/docker-compose.yml" restart
        if [ -x "$HOME/.local/bin/winapps-smb-sync.sh" ]; then
            (sleep 3 && "$HOME/.local/bin/winapps-smb-sync.sh" --once) &
        fi
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
        if [ -x "$HOME/.local/bin/winapps-smb-sync.sh" ]; then
            "$HOME/.local/bin/winapps-smb-sync.sh" --once
        fi
        ;;
    fix-autologon)
        echo "🔑 Aplicando AutoLogon e desativando tela de bloqueio do Windows..."
        if [ -f "$HOME/.config/winapps/winapps.conf" ]; then
            source "$HOME/.config/winapps/winapps.conf"
        fi
        USER_RDP="${RDP_USER:-winapps}"
        PASS_RDP="${RDP_PASS:-}"
        IP_RDP="${RDP_IP:-127.0.0.1}"
        PORT_RDP="${RDP_PORT:-3389}"
        if [ -z "$PASS_RDP" ]; then
            echo "❌ Erro: RDP_PASS não definido em ~/.config/winapps/winapps.conf" >&2
            exit 1
        fi
        xfreerdp3 /cert:ignore /u:"$USER_RDP" /p:"$PASS_RDP" /app:program:"C:\\Windows\\System32\\cmd.exe",cmd:"/C \\\\host.lan\\Data\\setup_autologon.bat" /v:"$IP_RDP":"$PORT_RDP" &>/dev/null &
        echo "Comando enviado para a VM. Log disponível em ~/Compartilhado_VM/autologon_result.log"
        ;;
    onedrive)
        echo "📂 Abrindo OneDrive Corporativo (MPMS) no Nautilus..."
        gio open "smb://172.20.0.2/onedrive-mpms" 2>/dev/null || xdg-open "$HOME/OneDrive_MPMS"
        ;;
    *)
        echo "Uso: winapps-vm {start|stop|restart|status|logs|web|setup-apps|fix-smb|fix-autologon|onedrive}"
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
# Monitora eventos do Docker para reconfigurar automaticamente quando o container subir
# ==============================================================================
CONTAINER="winapps-windows"

apply_smb_fix() {
    # Aguarda o container estar rodando
    local running=0
    for attempt in {1..30}; do
        if docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q "true"; then
            running=1
            break
        fi
        sleep 2
    done

    if [ "$running" -eq 1 ]; then
        # Remove as regras de bloqueio (RETURN) para 139 e 445 se existirem
        while docker exec "$CONTAINER" iptables -t nat -L QEMU_DNAT -n --line-numbers 2>/dev/null | grep -E "dpt:(139|445)" >/dev/null; do
            local line
            line=$(docker exec "$CONTAINER" iptables -t nat -L QEMU_DNAT -n --line-numbers 2>/dev/null | grep -E "dpt:(139|445)" | head -n1 | awk '{print $1}')
            [ -n "$line" ] && docker exec "$CONTAINER" iptables -t nat -D QEMU_DNAT "$line" 2>/dev/null || break
        done

        # Tenta montar via GVFS no Nautilus silenciosamente
        gio mount "smb://172.20.0.2/onedrive-mpms" 2>/dev/null || true

        # Garantir link simbólico amigável em ~/OneDrive_MPMS apontando para o GVFS
        local gvfs_dir="/run/user/$(id -u)/gvfs/smb-share:server=172.20.0.2,share=onedrive-mpms"
        if [ -d "$gvfs_dir" ]; then
            if [ -d "$HOME/OneDrive_MPMS" ] && [ ! -L "$HOME/OneDrive_MPMS" ]; then
                rmdir "$HOME/OneDrive_MPMS" 2>/dev/null || true
            fi
            ln -sfn "$gvfs_dir" "$HOME/OneDrive_MPMS"
        fi
    fi
}

# Se for passado o argumento --once, executa apenas uma vez e sai
if [ "$1" == "--once" ]; then
    apply_smb_fix
    exit 0
fi

# Execução inicial
apply_smb_fix

# Fica em loop ouvindo eventos do Docker (start, restart, unpause)
docker events --filter "container=$CONTAINER" --filter "event=start" --filter "event=unpause" --format '{{.Status}}' 2>/dev/null | while read -r event; do
    apply_smb_fix
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
Type=simple
ExecStart=$SMB_SYNC_SCRIPT
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

chown -R "$REAL_USER:$REAL_USER" "$USER_SYSTEMD_DIR"

if [ -n "$REAL_UID" ]; then
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user daemon-reload 2>/dev/null || true
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user enable --now winapps-smb-sync.service 2>/dev/null || true
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
GVFS_SMB_DIR="/run/user/${REAL_UID:-1000}/gvfs/smb-share:server=172.20.0.2,share=onedrive-mpms"

if [ -d "$GVFS_SMB_DIR" ]; then
    if [ -d "$ONEDRIVE_MOUNT_POINT" ] && [ ! -L "$ONEDRIVE_MOUNT_POINT" ]; then
        rmdir "$ONEDRIVE_MOUNT_POINT" 2>/dev/null || true
    fi
    ln -sfn "$GVFS_SMB_DIR" "$ONEDRIVE_MOUNT_POINT"
else
    mkdir -p "$ONEDRIVE_MOUNT_POINT"
fi
chown -h "$REAL_USER:$REAL_USER" "$ONEDRIVE_MOUNT_POINT"

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
# 8. Criar Ícone Oficial do Windows e Lançadores Desktop (WinApps e OneDrive MPMS)
# ------------------------------------------------------------------------------
ICON_DIR="$REAL_HOME/.local/share/icons/hicolor/scalable/apps"
mkdir -p "$ICON_DIR"
cat << 'EOF' > "$ICON_DIR/windows-11.svg"
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 88 88">
  <path fill="#0078d4" d="M0 0h41.6v41.6H0zM46.4 0H88v41.6H46.4zM0 46.4h41.6V88H0zM46.4 46.4H88V88H46.4z"/>
</svg>
EOF

if [ -f "$SCRIPT_DIR/../util/winapps/onedrive.svg" ]; then
    cp -f "$SCRIPT_DIR/../util/winapps/onedrive.svg" "$ICON_DIR/onedrive.svg"
    cp -f "$SCRIPT_DIR/../util/winapps/onedrive.svg" "$ICON_DIR/microsoft-onedrive.svg"
    cp -f "$SCRIPT_DIR/../util/winapps/onedrive.svg" /usr/share/pixmaps/onedrive.svg 2>/dev/null || true
fi

# Gerar ícones rasterizados e atualizar cache do tema
if [ -f /usr/share/icons/hicolor/index.theme ] && [ ! -f "$REAL_HOME/.local/share/icons/hicolor/index.theme" ]; then
    cp -f /usr/share/icons/hicolor/index.theme "$REAL_HOME/.local/share/icons/hicolor/index.theme" 2>/dev/null || true
fi
python3 -c '
import os, sys, gi
gi.require_version("Rsvg", "2.0")
from gi.repository import Rsvg
import cairo
svg_path = sys.argv[1]
hicolor_base = sys.argv[2]
if os.path.exists(svg_path):
    handle = Rsvg.Handle.new_from_file(svg_path)
    for sz in [16, 24, 32, 48, 64, 128, 256]:
        sz_dir = os.path.join(hicolor_base, f"{sz}x{sz}", "apps")
        os.makedirs(sz_dir, exist_ok=True)
        surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, sz, sz)
        ctx = cairo.Context(surface)
        ctx.scale(sz / 32.0, sz / 32.0)
        handle.render_cairo(ctx)
        surface.write_to_png(os.path.join(sz_dir, "onedrive.png"))
        surface.write_to_png(os.path.join(sz_dir, "microsoft-onedrive.png"))
' "$ICON_DIR/onedrive.svg" "$REAL_HOME/.local/share/icons/hicolor" 2>/dev/null || true

cp -f "$REAL_HOME/.local/share/icons/hicolor/48x48/apps/onedrive.png" /usr/share/pixmaps/onedrive.png 2>/dev/null || true
gtk-update-icon-cache -f "$REAL_HOME/.local/share/icons/hicolor" 2>/dev/null || true

DESKTOP_DIR="$REAL_HOME/.local/share/applications"
mkdir -p "$DESKTOP_DIR"
cat << EOF > "$DESKTOP_DIR/winapps-windows.desktop"
[Desktop Entry]
Name=Windows 11 (WinApps VM)
Comment=Acessar o Windows 11 virtualizado via Remmina ou console web
Exec=remmina -c $REAL_HOME/.local/share/remmina/winapps_windows11.remmina
Icon=windows-11
Terminal=false
Type=Application
Categories=System;Utility;Office;
Keywords=windows;winapps;vm;rdp;vnc;remmina;office;onedrive;
StartupNotify=true
Actions=RemminaVNC;RemminaRDP;WebConsole;RestartVM;StopVM;FixSMB;FixAutoLogon;

[Desktop Action RemminaVNC]
Name=Abrir no Remmina (Console Direto VNC)
Exec=remmina -c $REAL_HOME/.local/share/remmina/winapps_windows11.remmina

[Desktop Action RemminaRDP]
Name=Abrir no Remmina (Sessão RDP)
Exec=remmina -c $REAL_HOME/.local/share/remmina/winapps_windows11_rdp.remmina

[Desktop Action WebConsole]
Name=Abrir Console Web (:8006)
Exec=xdg-open http://127.0.0.1:8006

[Desktop Action RestartVM]
Name=Reiniciar Container Windows
Exec=$REAL_HOME/.local/bin/winapps-vm restart

[Desktop Action StopVM]
Name=Desligar Container Windows
Exec=$REAL_HOME/.local/bin/winapps-vm stop

[Desktop Action FixSMB]
Name=Desbloquear Roteamento SMB (OneDrive)
Exec=$REAL_HOME/.local/bin/winapps-vm fix-smb

[Desktop Action FixAutoLogon]
Name=Reparar Login Automatico Sem Senha
Exec=$REAL_HOME/.local/bin/winapps-vm fix-autologon
EOF

# Lançador nativo do OneDrive Corporativo para abrir diretamente no Nautilus
cat << EOF > "$DESKTOP_DIR/onedrive-x86.desktop"
[Desktop Entry]
Name=Microsoft OneDrive (MPMS)
GenericName=Armazenamento em Nuvem MPMS
Comment=Acessar arquivos do OneDrive corporativo (MPMS) diretamente pelo Nautilus
Exec=gio open smb://172.20.0.2/onedrive-mpms
Icon=onedrive
Terminal=false
Type=Application
Categories=Office;Network;FileManager;
Keywords=onedrive;mpms;nuvem;arquivos;nautilus;share;
StartupNotify=true
Actions=OpenLocalFolder;SyncSMB;WebOneDrive;WindowsRemmina;

[Desktop Action OpenLocalFolder]
Name=Abrir Pasta Local (~/OneDrive_MPMS)
Exec=nautilus $REAL_HOME/OneDrive_MPMS

[Desktop Action SyncSMB]
Name=Remontar Compartilhamento SMB
Exec=$REAL_HOME/.local/bin/winapps-smb-sync.sh --once

[Desktop Action WebOneDrive]
Name=Abrir OneDrive no Navegador (Web)
Exec=xdg-open https://www.office.com/launch/onedrive?auth=2

[Desktop Action WindowsRemmina]
Name=Abrir Windows 11 no Remmina
Exec=remmina -c $REAL_HOME/.local/share/remmina/winapps_windows11.remmina
EOF

ln -sfn "$DESKTOP_DIR/onedrive-x86.desktop" "$DESKTOP_DIR/microsoft-onedrive.desktop"

chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.local/share/icons" "$DESKTOP_DIR/winapps-windows.desktop" "$DESKTOP_DIR/onedrive-x86.desktop" "$DESKTOP_DIR/microsoft-onedrive.desktop"
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 9. Configurar e Ativar o Indicador de Bandeja (Top Panel Tray AppIndicator)
# ------------------------------------------------------------------------------
log_msg "INFO" "Configurando indicador nativo de bandeja do OneDrive no painel COSMIC..."
mkdir -p "$REAL_HOME/.local/bin" "$REAL_HOME/.config/systemd/user"
cp -f "$SCRIPT_DIR/daemons/onedrive-indicator.py" "$REAL_HOME/.local/bin/onedrive-indicator.py"
chmod +x "$REAL_HOME/.local/bin/onedrive-indicator.py"
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.local/bin/onedrive-indicator.py"

cp -f "$SCRIPT_DIR/../config/systemd/user/onedrive-indicator.service" "$REAL_HOME/.config/systemd/user/" 2>/dev/null || true
chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/systemd" 2>/dev/null || true

if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    sudo -u "$REAL_USER" systemctl --user daemon-reload 2>/dev/null || true
    sudo -u "$REAL_USER" systemctl --user enable --now onedrive-indicator.service 2>/dev/null || true
else
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable --now onedrive-indicator.service 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 10. Provisionar Perfis de Conexão do Remmina (Console VNC e RDP)
# ------------------------------------------------------------------------------
log_msg "INFO" "Provisionando perfis de conexão direta no Remmina (WinApps VM)..."
REMMINA_DIR="$REAL_HOME/.local/share/remmina"
mkdir -p "$REMMINA_DIR"

cat << EOF > "$REMMINA_DIR/winapps_windows11.remmina"
[remmina]
name=Windows 11 (WinApps VM)
group=WinApps
protocol=VNC
server=172.20.0.2:5900
viewmode=1
window_maximize=1
scale=1
colordepth=32
quality=9
disableclipboard=0
enable-autostart=0
EOF

cat << EOF > "$REMMINA_DIR/winapps_windows11_rdp.remmina"
[remmina]
name=Windows 11 (WinApps VM - RDP)
group=WinApps
protocol=RDP
server=127.0.0.1:3389
username=$WINAPPS_USER
password=.
colordepth=32
quality=9
sound=local
sharesmartcard=0
shareprinter=0
sharefolder=$REAL_HOME/Compartilhado_VM
disableclipboard=0
disablepasswordstoring=0
viewmode=1
window_maximize=1
scale=1
glyph-cache=1
relax-order-checks=1
cert_ignore=1
network=lan
enable-autostart=0
EOF

chmod 600 "$REMMINA_DIR"/winapps_windows11*.remmina
chown -R "$REAL_USER:$REAL_USER" "$REMMINA_DIR"

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "🎉 WinApps e stack de virtualização Windows provisionados com sucesso!"
log_msg "INFO" "Para iniciar o Windows na primeira vez, use: 'winapps-vm start' e acesse http://127.0.0.1:8006"
