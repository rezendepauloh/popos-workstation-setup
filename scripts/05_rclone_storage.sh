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

RCLONE_CONF_SRC="$BASE_DIR/rclone.conf"
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
    --buffer-size 64M \
    --dir-cache-time 72h \
    --poll-interval 15s \
    --attr-timeout 1s \
    --allow-other \
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
    --buffer-size 64M \
    --dir-cache-time 72h \
    --poll-interval 15s \
    --attr-timeout 1s \
    --allow-other \
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
    --buffer-size 64M \
    --dir-cache-time 72h \
    --poll-interval 15s \
    --attr-timeout 1s \
    --allow-other \
    --log-level INFO
ExecStop=/bin/fusermount -u -z %h/Mega_Pessoal
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/systemd" 2>/dev/null || true

# Habilita allow_other no /etc/fuse.conf
if [ -f /etc/fuse.conf ]; then
    sudo sed -i 's/#user_allow_other/user_allow_other/g' /etc/fuse.conf
fi

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

# 5. Instalação de GUIs e Bandeja de Nuvem (Celeste Tray & Rclone Web Dashboard)
log_msg "INFO" "Instalando Celeste (Cliente de Nuvem com Ícone na Bandeja)..."
flatpak install -y --system flathub com.ranfdev.Celeste 2>/dev/null || true

# Criação do Lançador Desktop para o Rclone Web Dashboard (Gráficos e Monitoramento de Envio)
log_msg "INFO" "Configurando lançador do Rclone Web Dashboard..."
USER_APPS_DIR="$REAL_HOME/.local/share/applications"
mkdir -p "$USER_APPS_DIR"

cat << 'EOF' > "$USER_APPS_DIR/rclone-webui.desktop"
[Desktop Entry]
Name=Rclone Web Dashboard
Comment=Painel Gráfico do Rclone com Monitoramento de Upload/Download em Tempo Real
Exec=sh -c "rclone rcd --rc-web-gui --rc-web-gui-no-open-browser & sleep 2 && xdg-open http://127.0.0.1:5572"
Icon=folder-remote
Terminal=false
Type=Application
Categories=Network;Utility;FileTransfer;
StartupNotify=true
EOF

chown -R "$REAL_USER:$REAL_USER" "$USER_APPS_DIR/rclone-webui.desktop" 2>/dev/null || true

sleep 2
if verificar_gdrive_montado; then
    log_msg "SUCCESS" "Google Drive montado com sucesso em '$REAL_HOME/GoogleDrive_Pessoal'."
else
    log_msg "WARN" "Google Drive ainda não montado ou aguardando autenticação. Continuando..."
fi

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Serviços Rclone, Celeste (Tray), Web Dashboard e Discos Secundários configurados com sucesso."
