#!/bin/bash
# ==============================================================================
# Módulo 22: Limpeza Final, Otimização de Recursos e Hardening
# Implementa as melhorias de performance, docker sob demanda, rede e backups
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="LIMPEZA_FINAL"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Limpeza final e otimizações já realizadas anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "22. LIMPEZA FINAL, OTIMIZAÇÕES E HARDENING DO SISTEMA"

# ------------------------------------------------------------------------------
# 1. Limpeza de Pacotes e Runtimes
# ------------------------------------------------------------------------------
log_msg "INFO" "Removendo pacotes residuais e limpando cache do APT..."
sudo apt autoremove -y --purge
sudo apt clean

if command -v flatpak >/dev/null 2>&1; then
    log_msg "INFO" "Removendo runtimes Flatpak não utilizados..."
    flatpak uninstall --unused -y 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 2. Otimização de Memória e I/O (Sysctl & ZRAM)
# ------------------------------------------------------------------------------
log_msg "INFO" "Configurando limites de Inotify, File Descriptors e Dirty Ratios..."
cat << 'EOF' | sudo tee /etc/sysctl.d/99-dev-limits.conf > /dev/null
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 1024
fs.file-max = 2097152
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
EOF
sudo sysctl --system >/dev/null 2>&1 || true

# Garante ZRAM no sistema caso não esteja presente (Pop!_OS usa pop-default-settings-zram)
if ! dpkg -s pop-default-settings-zram >/dev/null 2>&1 && ! dpkg -s systemd-zram-generator >/dev/null 2>&1; then
    log_msg "INFO" "Instalando gerador de ZRAM para compressão em memória..."
    sudo apt install -y systemd-zram-generator || true
fi

# ------------------------------------------------------------------------------
# 3. Docker sob Demanda (Socket Activation) e Limpeza
# ------------------------------------------------------------------------------
if command -v docker >/dev/null 2>&1; then
    log_msg "INFO" "Configurando inicialização do Docker sob demanda (docker.socket)..."
    # Habilita o socket para que o daemon suba apenas ao rodar o comando docker
    sudo systemctl stop docker.service 2>/dev/null || true
    sudo systemctl disable docker.service 2>/dev/null || true
    sudo systemctl enable docker.socket 2>/dev/null || true
    sudo systemctl start docker.socket 2>/dev/null || true

    log_msg "INFO" "Executando limpeza de recursos órfãos do Docker..."
    docker system prune -f 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 4. Ajustes de Áudio de Baixa Latência (PipeWire Quantum)
# ------------------------------------------------------------------------------
log_msg "INFO" "Configurando latência otimizada do PipeWire (quantum = 512)..."
mkdir -p "$REAL_HOME/.config/pipewire/pipewire.conf.d"
cat << 'EOF' > "$REAL_HOME/.config/pipewire/pipewire.conf.d/99-low-latency.conf"
context.properties = {
    default.clock.quantum = 512
    default.clock.min-quantum = 256
    default.clock.max-quantum = 1024
}
EOF
chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/pipewire"

# ------------------------------------------------------------------------------
# 5. Segurança e Firewall (UFW) com Regras para Dev e Rede Local
# ------------------------------------------------------------------------------
if command -v ufw >/dev/null 2>&1; then
    log_msg "INFO" "Configurando firewall UFW para ambiente de desenvolvimento..."
    sudo ufw default deny incoming >/dev/null 2>&1 || true
    sudo ufw default allow outgoing >/dev/null 2>&1 || true

    # Regras locais: Jellyfin, KDE Connect e portas comuns de desenvolvimento
    sudo ufw allow 8096/tcp comment 'Jellyfin Media Server' >/dev/null 2>&1 || true
    sudo ufw allow 1714:1764/udp comment 'KDE Connect' >/dev/null 2>&1 || true
    sudo ufw allow 1714:1764/tcp comment 'KDE Connect' >/dev/null 2>&1 || true
    sudo ufw allow 3000:3010/tcp comment 'Dev Web (React/Node)' >/dev/null 2>&1 || true
    sudo ufw allow 5173/tcp comment 'Vite Dev Server' >/dev/null 2>&1 || true
    sudo ufw allow 8000:8080/tcp comment 'APIs locais / Backend' >/dev/null 2>&1 || true

    # Habilita firewall de forma não interativa
    echo "y" | sudo ufw enable >/dev/null 2>&1 || true
fi

# ------------------------------------------------------------------------------
# 6. Script e Timer de Backup Semanal Automatizado (Dotfiles & Configs)
# ------------------------------------------------------------------------------
log_msg "INFO" "Criando script utilitário de backup de dotfiles e automações..."
sudo tee /usr/local/bin/backup-workstation > /dev/null << 'EOF'
#!/bin/bash
set -e

BACKUP_USER="$(whoami)"
BACKUP_HOME="$HOME"
TIMESTAMP="$(date +'%Y%m%d_%H%M%S')"
BACKUP_DEST="$BACKUP_HOME/GoogleDrive_Pessoal/Backups_Workstation"

# Fallback para disco secundário se a nuvem não estiver montada
if [ ! -d "$BACKUP_DEST" ]; then
    BACKUP_DEST="/mnt/storage_930/Backups_Workstation"
    mkdir -p "$BACKUP_DEST" 2>/dev/null || BACKUP_DEST="/tmp/Backups_Workstation"
fi

mkdir -p "$BACKUP_DEST"
ARCHIVE_NAME="dotfiles_backup_${TIMESTAMP}.tar.gz"

echo "[$(date)] Iniciando backup das configurações do usuário $BACKUP_USER..."

tar -czf "$BACKUP_DEST/$ARCHIVE_NAME" \
    --exclude="$BACKUP_HOME/.config/google-chrome" \
    --exclude="$BACKUP_HOME/.config/BraveSoftware" \
    --exclude="$BACKUP_HOME/.config/Slack" \
    --exclude="$BACKUP_HOME/.config/discord" \
    -C "$BACKUP_HOME" \
    .config/espanso \
    .config/copyq \
    .config/kando \
    .config/cosmic \
    .ssh \
    Documentos/Scripts \
    2>/dev/null || true

# Mantém apenas os últimos 5 backups para não inflar o armazenamento
ls -1t "$BACKUP_DEST"/dotfiles_backup_*.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm -f --

echo "[$(date)] Backup concluído com sucesso: $BACKUP_DEST/$ARCHIVE_NAME"
EOF
sudo chmod +x /usr/local/bin/backup-workstation

# Serviço e Timer no Systemd do Usuário
log_msg "INFO" "Criando Systemd Timer para backup semanal automatizado..."
mkdir -p "$REAL_HOME/.config/systemd/user"

cat << 'EOF' > "$REAL_HOME/.config/systemd/user/backup-workstation.service"
[Unit]
Description=Backup Semanal de Dotfiles e Automacoes da Workstation
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup-workstation
EOF

cat << 'EOF' > "$REAL_HOME/.config/systemd/user/backup-workstation.timer"
[Unit]
Description=Executar Backup Semanal de Dotfiles
Persistent=true

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF

chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/systemd" 2>/dev/null || true
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable --now backup-workstation.timer 2>/dev/null || true

# ------------------------------------------------------------------------------
# Conclusão
# ------------------------------------------------------------------------------
set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Limpeza, otimizações de I/O, Docker sob demanda, UFW e backup configurados com sucesso."
