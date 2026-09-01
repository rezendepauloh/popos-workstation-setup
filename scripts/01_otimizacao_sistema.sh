#!/bin/bash
# ==============================================================================
# Módulo 01: Otimizações de Sistema e Kernel (Swappiness e Inotify)
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="OTIMIZACAO_SISTEMA"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Otimizações de Kernel já aplicadas anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "1. OTIMIZAÇÕES DE KERNEL E SISTEMA"

# Reduz o uso de paginação (Swappiness para 10)
log_msg "INFO" "Ajustando vm.swappiness=10..."
sudo sysctl -w vm.swappiness=10
echo "vm.swappiness=10" | sudo tee /etc/sysctl.d/99-swappiness.conf > /dev/null

# Aumenta o limite de File Watchers (Inotify para 524288)
log_msg "INFO" "Ajustando fs.inotify.max_user_watches=524288..."
sudo sysctl -w fs.inotify.max_user_watches=524288
echo "fs.inotify.max_user_watches=524288" | sudo tee /etc/sysctl.d/99-inotify.conf > /dev/null

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Otimizações de Kernel aplicadas com sucesso."
