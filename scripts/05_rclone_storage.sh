#!/bin/bash
# ==============================================================================
# Módulo 05: Configuração do Rclone e Serviços de Nuvem (GDrive, OneDrive, MEGA)
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="RCLONE_SERVICES"

if check_flag "$FLAG_NAME"; then
    log_msg "INFO" "⏭️  Serviços do Rclone já configurados anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "5. CONFIGURAÇÃO DO RCLONE E SERVIÇOS SYSTEMD"

RCLONE_CONF_SRC="$BASE_DIR/rclone.conf"
RCLONE_CONF_DST="$REAL_HOME/.config/rclone/rclone.conf"

mkdir -p "$REAL_HOME/.config/rclone"
mkdir -p "$REAL_HOME/.config/systemd/user"

for dir in "$REAL_HOME/GoogleDrive_Pessoal" "$REAL_HOME/OneDrive_Pessoal" "$REAL_HOME/Mega_Pessoal" "$REAL_HOME/MEGA_Pessoal"; do
    if ! mountpoint -q "$dir" 2>/dev/null && [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        chown "$REAL_USER:$REAL_USER" "$dir" 2>/dev/null || true
    fi
done

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

sleep 2
if verificar_gdrive_montado; then
    log_msg "SUCCESS" "Google Drive montado com sucesso em '$REAL_HOME/GoogleDrive_Pessoal'."
else
    log_msg "WARN" "Google Drive ainda não montado ou aguardando autenticação. Continuando..."
fi

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Serviços Systemd do Rclone provisionados com sucesso."
