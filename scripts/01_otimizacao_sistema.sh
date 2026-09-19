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

# Configuração de DNS Local Permanente & Routing Domains (~pk.local)
DNS_PRIMARY="${LOCAL_DNS_PRIMARY:-}"
DNS_SECONDARY="${LOCAL_DNS_SECONDARY:-}"
DNS_DOMAIN="${LOCAL_DNS_SEARCH_DOMAIN:-}"

if [ -n "$DNS_PRIMARY" ]; then
    log_msg "INFO" "Configurando DNS Local Permanente ($DNS_PRIMARY), Fallback ($DNS_SECONDARY) e domínio ($DNS_DOMAIN)..."
    
    # 1. Configuração Persistente via systemd-resolved drop-in
    sudo mkdir -p /etc/systemd/resolved.conf.d
    cat << EOF | sudo tee /etc/systemd/resolved.conf.d/99-local-dns.conf > /dev/null
[Resolve]
DNS=$DNS_PRIMARY
FallbackDNS=$DNS_SECONDARY
Domains=$DNS_DOMAIN
EOF

    # Reinicia o resolved para aplicar imediatamente a nível de sistema
    sudo systemctl restart systemd-resolved 2>/dev/null || true

    # 2. Configuração Persistente na Conexão Ativa do NetworkManager (se existir)
    if command -v nmcli >/dev/null 2>&1; then
        DEFAULT_CON=$(nmcli -t -f NAME,DEVICE con show --active 2>/dev/null | grep -E ':eno1|:eth0|:wlp' | head -n1 | cut -d: -f1 || true)
        if [ -z "$DEFAULT_CON" ]; then
            DEFAULT_CON=$(nmcli -t -f NAME con show 2>/dev/null | grep -v 'docker\|br-\|lo' | head -n1 || true)
        fi
        
        if [ -n "$DEFAULT_CON" ]; then
            log_msg "INFO" "Atualizando perfil do NetworkManager '$DEFAULT_CON'..."
            nmcli connection modify "$DEFAULT_CON" \
                ipv4.dns "$DNS_PRIMARY" \
                ipv4.dns-search "$DNS_DOMAIN" \
                ipv4.ignore-auto-dns yes 2>/dev/null || true
            nmcli connection up "$DEFAULT_CON" 2>/dev/null || true
        fi
    fi
    log_msg "SUCCESS" "DNS Local ($DNS_PRIMARY) e domínio ($DNS_DOMAIN) configurados com sucesso."
fi

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Otimizações de Kernel e Rede aplicadas com sucesso."

