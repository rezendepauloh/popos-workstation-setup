#!/bin/bash
# ==============================================================================
# Utilitário: Descoberta Rápida de Dispositivos na Rede (LAN + mDNS + Tailscale)
# ==============================================================================

set -eo pipefail

C_RESET='\033[0m'
C_CYAN='\033[1;36m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_BOLD='\033[1m'

echo -e "${C_CYAN}${C_BOLD}=== DESCOBERTA DE DISPOSITIVOS NA REDE LOCAL & TAILSCALE ===${C_RESET}"

echo -e "\n${C_BOLD}[1/3] Vizinhos ARP / LAN Ativos (ip neigh):${C_RESET}"
ip -4 neigh show | grep -v "FAILED" || echo "  (nenhum registro ARP ativo)"

echo -e "\n${C_BOLD}[2/3] Serviços mDNS / Bonjour (Apple, TVs, Impressoras, Umbrel):${C_RESET}"
if command -v avahi-browse >/dev/null 2>&1; then
    timeout 4 avahi-browse -a -t -r -p 2>/dev/null | grep "^=" | awk -F';' '{printf "  • %-22s | %-28s | %s\n", $4, $5, $8}' | sort -u | head -n 40 || true
else
    echo -e "  ${C_YELLOW}(avahi-browse não disponível)${C_RESET}"
fi

echo -e "\n${C_BOLD}[3/3] Nós na Rede Mesh Tailscale:${C_RESET}"
if command -v tailscale >/dev/null 2>&1; then
    tailscale status 2>/dev/null || echo -e "  ${C_YELLOW}(Tailscale desconectado)${C_RESET}"
else
    echo -e "  ${C_YELLOW}(Tailscale não instalado)${C_RESET}"
fi
