#!/bin/bash
# ==============================================================================
# Módulo 28: Tailscale VPN (Mesh VPN segura, WireGuard & Acesso Remoto)
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="TAILSCALE_VPN"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Tailscale VPN já instalado e configurado anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "28. INSTALAÇÃO E CONFIGURAÇÃO DO TAILSCALE VPN"

# ------------------------------------------------------------------------------
# 1. Instalação Oficial do Tailscale (Repositório Oficial do Tailscale)
# ------------------------------------------------------------------------------
if ! command -v tailscale >/dev/null 2>&1; then
    log_msg "INFO" "Instalando Tailscale via script oficial assinado..."
    curl -fsSL https://tailscale.com/install.sh | sh
    log_msg "SUCCESS" "Pacote do Tailscale instalado com sucesso."
else
    log_msg "INFO" "Tailscale já se encontra instalado no sistema. Atualizando se necessário..."
    sudo apt update -y 2>/dev/null || true
    sudo apt install -y --only-upgrade tailscale 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 2. Habilitação e Inicialização do Serviço systemd (tailscaled)
# ------------------------------------------------------------------------------
log_msg "INFO" "Habilitando e iniciando o serviço tailscaled no systemd..."
sudo systemctl enable --now tailscaled

# ------------------------------------------------------------------------------
# 3. Otimizações de Rede do Kernel (Sysctl para Roteamento e Exit Node)
# ------------------------------------------------------------------------------
log_msg "INFO" "Habilitando encaminhamento de pacotes IPv4 e IPv6 (IP Forwarding para Tailscale)..."
cat << 'EOF' | sudo tee /etc/sysctl.d/99-tailscale.conf > /dev/null
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sudo sysctl --system >/dev/null 2>&1 || true

# ------------------------------------------------------------------------------
# 4. Ajuste no Firewall UFW para a Interface do Tailscale (tailscale0)
# ------------------------------------------------------------------------------
if command -v ufw >/dev/null 2>&1; then
    log_msg "INFO" "Configurando regras de tráfego seguro no firewall UFW para a interface tailscale0..."
    # Permite tráfego de entrada e saída pela interface virtual segura do Tailscale
    sudo ufw allow in on tailscale0 comment 'Tailscale VPN Network' >/dev/null 2>&1 || true
    sudo ufw allow 41641/udp comment 'Tailscale Wireguard Direct UDP' >/dev/null 2>&1 || true
fi

# ------------------------------------------------------------------------------
# 5. Criar Lançador e Utilitário de Conexão Rápida para o COSMIC
# ------------------------------------------------------------------------------
log_msg "INFO" "Criando atalho e script utilitário de conexão para o menu..."
sudo tee /usr/local/bin/tailscale-status > /dev/null << 'EOF'
#!/bin/bash
clear
C_RESET='\033[0m'
C_CYAN='\033[1;36m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_BOLD='\033[1m'

echo -e "${C_CYAN}=======================================================${C_RESET}"
echo -e "${C_BOLD}             🔒 TAILSCALE STATUS & REDE 🔒${C_RESET}"
echo -e "${C_CYAN}=======================================================${C_RESET}"
echo ""

if tailscale status 2>&1 | grep -q "Logged out"; then
    echo -e "${C_YELLOW}➜ O Tailscale não está conectado.${C_RESET}"
    echo -e "Conectando e gerando link de autenticação...\n"
    sudo tailscale up --operator="$USER"
else
    tailscale status
    echo ""
    echo -e "${C_GREEN}IP Tailscale:${C_RESET} $(tailscale ip -4 2>/dev/null || echo 'Desconectado')"
fi

echo ""
echo -e "${C_CYAN}-------------------------------------------------------${C_RESET}"
read -n 1 -s -r -p "Pressione qualquer tecla para sair..."
EOF
sudo chmod +x /usr/local/bin/tailscale-status

mkdir -p "$REAL_HOME/.local/share/applications"
cat << EOF > "$REAL_HOME/.local/share/applications/tailscale.desktop"
[Desktop Entry]
Name=Tailscale
Comment=Mesh VPN WireGuard P2P e Acesso Remoto Seguro
Exec=cosmic-term -- tailscale-status
Icon=network-vpn-symbolic
Terminal=false
Type=Application
Categories=Network;Utility;Office;
Keywords=vpn;tailscale;wireguard;rede;remoto;mesh;
EOF
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.local/share/applications/tailscale.desktop"
chmod +x "$REAL_HOME/.local/share/applications/tailscale.desktop"
update-desktop-database "$REAL_HOME/.local/share/applications" 2>/dev/null || true

# Permite ao usuário operar o Tailscale sem precisar digitar sudo para ver status/conectar
sudo tailscale up --operator="$REAL_USER" 2>/dev/null || true

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Tailscale instalado, ativado e integrado com sucesso."
log_msg "INFO" "Para autenticar na sua conta, execute: 'sudo tailscale up' ou clique no atalho 'Tailscale' no menu COSMIC."
