#!/bin/bash
# ==============================================================================
# Módulo 05: Configuração do Rclone e Serviços de Nuvem (GDrive, OneDrive, MEGA)
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="RCLONE_SERVICES"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Serviços do Rclone já configurados anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "5. CONFIGURAÇÃO DO RCLONE E SERVIÇOS SYSTEMD"

RCLONE_CONF_SRC="$BASE_DIR/config/rclone/rclone.conf"
[ ! -f "$RCLONE_CONF_SRC" ] && [ -f "$BASE_DIR/rclone.conf" ] && RCLONE_CONF_SRC="$BASE_DIR/rclone.conf"
RCLONE_CONF_DST="$REAL_HOME/.config/rclone/rclone.conf"

if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    sudo -u "$REAL_USER" mkdir -p "$REAL_HOME/.config/rclone" "$REAL_HOME/.config/systemd/user" 2>/dev/null || true
    for dir in "$REAL_HOME/GoogleDrive_Pessoal" "$REAL_HOME/OneDrive_Pessoal" "$REAL_HOME/Mega_Pessoal" "$REAL_HOME/MEGA_Pessoal"; do
        if ! grep -qs " $dir " /proc/mounts; then
            sudo -u "$REAL_USER" mkdir -p "$dir" 2>/dev/null || true
        fi
    done
else
    mkdir -p "$REAL_HOME/.config/rclone" "$REAL_HOME/.config/systemd/user" 2>/dev/null || true
    for dir in "$REAL_HOME/GoogleDrive_Pessoal" "$REAL_HOME/OneDrive_Pessoal" "$REAL_HOME/Mega_Pessoal" "$REAL_HOME/MEGA_Pessoal"; do
        if ! grep -qs " $dir " /proc/mounts; then
            mkdir -p "$dir" 2>/dev/null || true
        fi
    done
fi

# Garante versão oficial binária completa do Rclone (com todos os backends incluindo MEGA)
if [ ! -f /usr/bin/rclone ] || rclone version 2>&1 | grep -q "DEV"; then
    log_msg "INFO" "Instalando versão binária oficial completa do Rclone..."
    curl -fsSL https://rclone.org/install.sh | sudo bash 2>/dev/null || true
fi

# Copia arquivo rclone.conf local se presente e não existente no destino
if [ -f "$RCLONE_CONF_SRC" ] && [ ! -f "$RCLONE_CONF_DST" ]; then
    cp "$RCLONE_CONF_SRC" "$RCLONE_CONF_DST"
    chmod 600 "$RCLONE_CONF_DST"
    log_msg "INFO" "Arquivo rclone.conf copiado para ~/.config/rclone/."
fi

chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/rclone" 2>/dev/null || true

# 1. Serviço Google Drive
cat << 'EOF' > "$REAL_HOME/.config/systemd/user/gdrive-pessoal.service"
[Unit]
Description=Montagem FUSE do Google Drive (Pessoal) via Rclone
After=network-online.target
Wants=network-online.target
AssertPathExists=%h/.config/rclone/rclone.conf

[Service]
Type=notify
ExecStart=/usr/bin/rclone mount gdrive_pessoal: %h/GoogleDrive_Pessoal \
    --vfs-cache-mode full \
    --vfs-cache-max-age 24h \
    --vfs-read-chunk-size 32M \
    --vfs-read-chunk-size-limit 2G \
    --vfs-fast-fingerprint \
    --buffer-size 64M \
    --dir-cache-time 72h \
    --poll-interval 15s \
    --attr-timeout 10m \
    --log-level INFO
ExecStop=/bin/fusermount -u -z %h/GoogleDrive_Pessoal
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

# 2. Serviço OneDrive
cat << 'EOF' > "$REAL_HOME/.config/systemd/user/onedrive-pessoal.service"
[Unit]
Description=Montagem FUSE do OneDrive (Pessoal) via Rclone
After=network-online.target
Wants=network-online.target
AssertPathExists=%h/.config/rclone/rclone.conf

[Service]
Type=notify
ExecStart=/usr/bin/rclone mount onedrive_pessoal: %h/OneDrive_Pessoal \
    --vfs-cache-mode full \
    --vfs-cache-max-age 24h \
    --vfs-read-chunk-size 32M \
    --vfs-read-chunk-size-limit 2G \
    --vfs-fast-fingerprint \
    --buffer-size 64M \
    --dir-cache-time 72h \
    --poll-interval 15s \
    --attr-timeout 10m \
    --log-level INFO
ExecStop=/bin/fusermount -u -z %h/OneDrive_Pessoal
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

# 3. Serviço MEGA
cat << 'EOF' > "$REAL_HOME/.config/systemd/user/mega-pessoal.service"
[Unit]
Description=Montagem FUSE do MEGA (Pessoal) via Rclone
After=network-online.target
Wants=network-online.target
AssertPathExists=%h/.config/rclone/rclone.conf

[Service]
Type=notify
ExecStart=/usr/bin/rclone mount mega_pessoal: %h/Mega_Pessoal \
    --vfs-cache-mode full \
    --vfs-cache-max-age 24h \
    --vfs-read-chunk-size 32M \
    --vfs-read-chunk-size-limit 2G \
    --vfs-fast-fingerprint \
    --buffer-size 64M \
    --dir-cache-time 72h \
    --poll-interval 15s \
    --attr-timeout 10m \
    --log-level INFO
ExecStop=/bin/fusermount -u -z %h/Mega_Pessoal
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/systemd" 2>/dev/null || true

# Inicia os serviços se executado em sessão ativa
if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user daemon-reload 2>/dev/null || true
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user enable gdrive-pessoal.service onedrive-pessoal.service mega-pessoal.service 2>/dev/null || true
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user start gdrive-pessoal.service onedrive-pessoal.service mega-pessoal.service 2>/dev/null || true
else
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable gdrive-pessoal.service onedrive-pessoal.service mega-pessoal.service 2>/dev/null || true
    systemctl --user start gdrive-pessoal.service onedrive-pessoal.service mega-pessoal.service 2>/dev/null || true
fi

# 4. Configuração de Visibilidade dos Discos Secundários no Gerenciador de Arquivos (COSMIC Files)
log_msg "INFO" "Configurando exibição dos discos secundários no COSMIC Files..."

# Atualiza /etc/fstab para exibir os discos no navegador de arquivos com nomes amigáveis
if [ -f /etc/fstab ]; then
    sudo sed -i 's|/mnt/storage_930 ext4 defaults,noatime|/mnt/storage_930 ext4 defaults,noatime,x-gvfs-show,x-gvfs-name=hd_storage_930|g' /etc/fstab
    sudo sed -i 's|/mnt/storage_700 ext4 defaults,noatime|/mnt/storage_700 ext4 defaults,noatime,x-gvfs-show,x-gvfs-name=hd_storage_700|g' /etc/fstab
    sudo sed -i 's|/mnt/nvme_01 ext4 defaults,noatime|/mnt/nvme_01 ext4 defaults,noatime,x-gvfs-show,x-gvfs-name=nvme_01|g' /etc/fstab
    sudo systemctl daemon-reload 2>/dev/null || true
fi

# Adiciona atalhos favoritos no bookmarks do usuário para a barra lateral do COSMIC Files
BOOKMARKS_FILE="$REAL_HOME/.config/gtk-3.0/bookmarks"
mkdir -p "$REAL_HOME/.config/gtk-3.0"
touch "$BOOKMARKS_FILE"

for disk_entry in "file:///mnt/nvme_01 nvme_01" "file:///mnt/storage_930 hd_storage_930" "file:///mnt/storage_700 hd_storage_700"; do
    disk_path=$(echo "$disk_entry" | awk '{print $1}')
    if ! grep -q "$disk_path" "$BOOKMARKS_FILE" 2>/dev/null; then
        echo "$disk_entry" >> "$BOOKMARKS_FILE"
    fi
done
chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/gtk-3.0" 2>/dev/null || true

# 5. Instalação de GUIs e Bandeja de Nuvem (Rclone Browser, Celeste Tray & Web Dashboard)
log_msg "INFO" "Instalando Rclone Browser (GUI Nativa Desktop) via APT..."
sudo apt install -y rclone-browser

log_msg "INFO" "Instalando Celeste e Rclone UI via Flatpak..."
flatpak install -y --system flathub com.ranfdev.Celeste com.rcloneui.RcloneUI 2>/dev/null || true

# Criação do Lançador Desktop para o Rclone Web Dashboard (Gráficos e Monitoramento de Envio)
log_msg "INFO" "Configurando lançador do Rclone Web Dashboard..."
USER_APPS_DIR="$REAL_HOME/.local/share/applications"
mkdir -p "$USER_APPS_DIR"

cat << 'EOF' > "$USER_APPS_DIR/rclone-webui.desktop"
[Desktop Entry]
Name=Rclone Web Dashboard
Comment=Painel Gráfico do Rclone com Monitoramento de Upload/Download em Tempo Real
Exec=sh -c "rclone rcd --rc-web-gui --rc-addr 127.0.0.1:5572 --rc-web-gui-no-open-browser & sleep 2 && xdg-open http://127.0.0.1:5572"
Icon=folder-remote
Terminal=false
Type=Application
Categories=Network;Utility;FileTransfer;
StartupNotify=true
EOF

chown -R "$REAL_USER:$REAL_USER" "$USER_APPS_DIR/rclone-webui.desktop" 2>/dev/null || true

# 6. Indicadores Nativos de Bandeja (StatusNotifierItem / AyatanaAppIndicator3)
log_msg "INFO" "Configurando indicadores nativos de bandeja (Google Drive, OneDrive Pessoal e MEGA)..."
sudo apt install -y python3-gi gir1.2-ayatanaappindicator3-0.1 gir1.2-rsvg-2.0 python3-cairo 2>/dev/null || true

ICON_SCALABLE_DIR="$REAL_HOME/.local/share/icons/hicolor/scalable/apps"
mkdir -p "$ICON_SCALABLE_DIR" "$REAL_HOME/.local/bin" "$REAL_HOME/.config/systemd/user"
if [ -f /usr/share/icons/hicolor/index.theme ] && [ ! -f "$REAL_HOME/.local/share/icons/hicolor/index.theme" ]; then
    cp -f /usr/share/icons/hicolor/index.theme "$REAL_HOME/.local/share/icons/hicolor/index.theme" 2>/dev/null || true
fi

for icon_name in google-drive onedrive-pessoal mega; do
    SRC_SVG="$BASE_DIR/config/icons/${icon_name}.svg"
    if [ -f "$SRC_SVG" ]; then
        cp -f "$SRC_SVG" "$ICON_SCALABLE_DIR/${icon_name}.svg"
        cp -f "$SRC_SVG" "/usr/share/pixmaps/${icon_name}.svg" 2>/dev/null || true

        python3 - "$SRC_SVG" "$REAL_HOME/.local/share/icons/hicolor" "$icon_name" 2>/dev/null << 'PYEOF' || true
import os
import sys
import gi
gi.require_version("Rsvg", "2.0")
from gi.repository import Rsvg
import cairo

svg_path, hicolor_base, icon_name = sys.argv[1], sys.argv[2], sys.argv[3]
if os.path.exists(svg_path):
    handle = Rsvg.Handle.new_from_file(svg_path)
    for sz in [16, 24, 32, 48, 64, 128, 256]:
        sz_dir = os.path.join(hicolor_base, f"{sz}x{sz}", "apps")
        os.makedirs(sz_dir, exist_ok=True)
        surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, sz, sz)
        ctx = cairo.Context(surface)
        ctx.scale(sz / 32.0, sz / 32.0)
        handle.render_cairo(ctx)
        surface.write_to_png(os.path.join(sz_dir, f"{icon_name}.png"))
PYEOF

        if [ -f "$REAL_HOME/.local/share/icons/hicolor/48x48/apps/${icon_name}.png" ]; then
            cp -f "$REAL_HOME/.local/share/icons/hicolor/48x48/apps/${icon_name}.png" "/usr/share/pixmaps/${icon_name}.png" 2>/dev/null || true
        fi
    fi
done

chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.local/share/icons" 2>/dev/null || true
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f "$REAL_HOME/.local/share/icons/hicolor" 2>/dev/null || true
fi

cp -f "$SCRIPT_DIR/daemons/rclone-cloud-indicator.py" "$REAL_HOME/.local/bin/rclone-cloud-indicator.py"
chmod +x "$REAL_HOME/.local/bin/rclone-cloud-indicator.py"
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.local/bin/rclone-cloud-indicator.py"

for ind_svc in gdrive-indicator.service onedrive-pessoal-indicator.service mega-indicator.service; do
    if [ -f "$BASE_DIR/config/systemd/user/$ind_svc" ]; then
        cp -f "$BASE_DIR/config/systemd/user/$ind_svc" "$REAL_HOME/.config/systemd/user/"
    fi
done
chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/systemd" 2>/dev/null || true

if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user daemon-reload 2>/dev/null || true
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user enable gdrive-indicator.service onedrive-pessoal-indicator.service mega-indicator.service 2>/dev/null || true
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user restart gdrive-indicator.service onedrive-pessoal-indicator.service mega-indicator.service 2>/dev/null || true
else
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable gdrive-indicator.service onedrive-pessoal-indicator.service mega-indicator.service 2>/dev/null || true
    systemctl --user restart gdrive-indicator.service onedrive-pessoal-indicator.service mega-indicator.service 2>/dev/null || true
fi

sleep 2
if verificar_gdrive_montado; then
    log_msg "SUCCESS" "Google Drive montado com sucesso em '$REAL_HOME/GoogleDrive_Pessoal'."
else
    log_msg "WARN" "Google Drive ainda não montado ou aguardando autenticação. Continuando..."
fi

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Serviços Rclone, Celeste (Tray), Web Dashboard e Discos Secundários configurados com sucesso."
