#!/bin/bash
# ==============================================================================
# Módulo 17: Manutenção, Saúde e TRIM dos SSDs NVMe/SATA
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="MAINTENANCE_SSD"

if check_flag "$FLAG_NAME"; then
    log_msg "INFO" "⏭️  Manutenção de SSDs (fstrim) já habilitada. Pulando..."
    exit 0
fi

log_msg "HEADER" "17. MANUTENÇÃO E SAÚDE DOS SSDS"

log_msg "INFO" "Habilitando e iniciando o temporizador fstrim.timer..."
sudo systemctl enable fstrim.timer
sudo systemctl start fstrim.timer

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Serviço semanal de TRIM ativado com sucesso para todos os SSDs."
