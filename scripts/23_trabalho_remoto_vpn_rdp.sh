#!/bin/bash
# ==============================================================================
# Módulo 23: Trabalho Remoto - VPN MPMS (openfortivpn 2FA) & RDP (Remmina)
# Instala e configura ferramentas de trabalho remoto, removendo o FortiClient oficial
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="TRABALHO_REMOTO"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Ferramentas de Trabalho Remoto (VPN MPMS & Remmina) já instaladas. Pulando..."
    exit 0
fi

log_msg "HEADER" "23. TRABALHO REMOTO: VPN MPMS (OPENFORTIVPN 2FA) & RDP (REMMINA)"

# ------------------------------------------------------------------------------
# 1. Remoção e Purga do FortiClient Oficial (Bloqueado sem Licença EMS)
# ------------------------------------------------------------------------------
if dpkg -l | grep -q "forticlient "; then
    log_msg "INFO" "Purgando pacote e repositórios do FortiClient oficial não funcional..."
    sudo apt purge -y forticlient 2>/dev/null || true
    sudo rm -f /etc/apt/sources.list.d/forticlient.list /usr/share/keyrings/forticlient.gpg
    sudo systemctl daemon-reload 2>/dev/null || true
    sudo apt update
    log_msg "SUCCESS" "FortiClient oficial removido com sucesso."
fi

# ------------------------------------------------------------------------------
# 2. Instalação do Cliente Remoto RDP (Remmina Oficial + Plugins RDP/Secret)
# ------------------------------------------------------------------------------
log_msg "INFO" "Instalando Remmina RDP e plugins nativos via APT..."
sudo apt update
sudo apt install -y remmina remmina-plugin-rdp remmina-plugin-secret freerdp2-x11

mkdir -p "$REAL_HOME/.local/share/remmina"
mkdir -p "$REAL_HOME/.config/remmina"
chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.local/share/remmina" "$REAL_HOME/.config/remmina"

# ------------------------------------------------------------------------------
# 3. Ferramenta Aberta SSL-VPN: openfortivpn (Alta Performance com 2FA)
# ------------------------------------------------------------------------------
log_msg "INFO" "Instalando openfortivpn e módulos do NetworkManager..."
sudo apt install -y openfortivpn network-manager-fortisslvpn network-manager-fortisslvpn-gnome 2>/dev/null || true

# ------------------------------------------------------------------------------
# 4. Configuração da Conexão MPMS & Script Facilitador com 2FA
# ------------------------------------------------------------------------------
log_msg "INFO" "Configurando perfil automatizado para a VPN do MPMS..."

VPN_HOST="${VPN_HOST:-}"
VPN_PORT="${VPN_PORT:-}"
VPN_USERNAME="${VPN_USERNAME:-}"
VPN_PASSWORD="${VPN_PASSWORD:-}"
VPN_TRUSTED_CERT="${VPN_TRUSTED_CERT:-}"

sudo mkdir -p /etc/openfortivpn
sudo chmod 700 /etc/openfortivpn

cat << EOF | sudo tee /etc/openfortivpn/mpms.conf > /dev/null
# Configuração VPN Institucional (Gerada dinamicamente via .env)
host = ${VPN_HOST}
port = ${VPN_PORT}
username = ${VPN_USERNAME}
trusted-cert = ${VPN_TRUSTED_CERT}
set-dns = 1
pppd-use-peerdns = 1
EOF

if [ -n "$VPN_PASSWORD" ]; then
    echo "password = ${VPN_PASSWORD}" | sudo tee -a /etc/openfortivpn/mpms.conf > /dev/null
fi
sudo chmod 600 /etc/openfortivpn/mpms.conf

# Cria binário global /usr/local/bin/vpn-mpms
sudo tee /usr/local/bin/vpn-mpms > /dev/null << 'EOF'
#!/bin/bash
clear

C_RESET='\033[0m'
C_CYAN='\033[1;36m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[1;31m'
C_BOLD='\033[1m'

echo -e "${C_CYAN}=======================================================${C_RESET}"
echo -e "${C_BOLD}   🏢 CONECTANDO À VPN DO MPMS (openfortivpn) 🏢${C_RESET}"
echo -e "${C_CYAN}=======================================================${C_RESET}"
echo ""
echo -e " ${C_YELLOW}➜${C_RESET} Digite seu ${C_BOLD}Token / OTP 2FA${C_RESET} quando solicitado."
echo -e " ${C_YELLOW}➜${C_RESET} Para ${C_RED}desconectar${C_RESET} a qualquer momento, pressione ${C_BOLD}Ctrl + C${C_RESET}."
echo -e "${C_CYAN}-------------------------------------------------------${C_RESET}"
echo ""

echo -e " ${C_GREEN}Iniciando túnel seguro...${C_RESET}\n"
sudo openfortivpn -c /etc/openfortivpn/mpms.conf

echo ""
echo -e "${C_YELLOW}🔌 VPN Desconectada.${C_RESET}"
read -n 1 -s -r -p "Pressione qualquer tecla para fechar esta janela..."
EOF
sudo chmod +x /usr/local/bin/vpn-mpms

# Permite ao usuário rodar 'sudo openfortivpn' sem solicitar senha sudo
sudo tee /etc/sudoers.d/openfortivpn-mpms > /dev/null << EOF
$REAL_USER ALL=(ALL) NOPASSWD: /usr/bin/openfortivpn
EOF
sudo chmod 440 /etc/sudoers.d/openfortivpn-mpms

# ------------------------------------------------------------------------------
# 5. Perfil Salvo no Remmina: PC de Trabalho (Carregado do .env)
# ------------------------------------------------------------------------------
RDP_PROFILE_NAME="${RDP_PROFILE_NAME:-}"
RDP_PROFILE_ID="${RDP_PROFILE_ID:-}"
RDP_SERVER="${RDP_SERVER:-}"
RDP_USERNAME="${RDP_USERNAME:-}"
RDP_DOMAIN="${RDP_DOMAIN:-}"

if [ -n "$RDP_SERVER" ]; then
    log_msg "INFO" "Criando perfil de conexão RDP no Remmina para: $RDP_PROFILE_NAME..."
    mkdir -p "$REAL_HOME/.local/share/remmina"

    REMMINA_PROFILE="$REAL_HOME/.local/share/remmina/${RDP_PROFILE_ID}.remmina"

    cat << EOF > "$REMMINA_PROFILE"
[remmina]
name=${RDP_PROFILE_NAME}
group=MPMS
protocol=RDP
server=${RDP_SERVER}
username=${RDP_USERNAME}
domain=${RDP_DOMAIN}
password=
colordepth=32
quality=9
sound=local
sharesmartcard=0
shareprinter=0
sharefolder=
disableclipboard=0
viewmode=1
window_maximize=1
scale=1
glyph-cache=1
relax-order-checks=1
cert_ignore=1
network=lan
enable-autostart=0
EOF
    chown "$REAL_USER:$REAL_USER" "$REMMINA_PROFILE"
    chmod 600 "$REMMINA_PROFILE"
    log_msg "SUCCESS" "Perfil RDP do Remmina configurado a partir das variáveis de ambiente."
fi

# ------------------------------------------------------------------------------
# 6. Criar Lançador .desktop para clicar e conectar direto na VPN
# ------------------------------------------------------------------------------
log_msg "INFO" "Criando lançador gráfico no menu do COSMIC..."
mkdir -p "$REAL_HOME/.local/share/applications"

cat << EOF > "$REAL_HOME/.local/share/applications/vpn-mpms.desktop"
[Desktop Entry]
Name=VPN MPMS
Comment=Conexão Segura com 2FA à rede do MPMS
Exec=cosmic-term -- vpn-mpms
Icon=network-vpn-symbolic
Terminal=false
Type=Application
Categories=Office;Network;Utility;
Keywords=vpn;mpms;fortinet;trabalho;remoto;
EOF
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.local/share/applications/vpn-mpms.desktop"
chmod +x "$REAL_HOME/.local/share/applications/vpn-mpms.desktop"

rm -f "$REAL_HOME/.local/share/applications/forticlient.desktop"

# ------------------------------------------------------------------------------
# 7. Microsoft 365 Web Apps (Portal, Word, Excel, PowerPoint, Outlook)
# ------------------------------------------------------------------------------
log_msg "INFO" "Configurando Web Apps dedicados do Microsoft 365..."

ICONS_DIR="$REAL_HOME/.local/share/icons/hicolor/scalable/apps"
mkdir -p "$ICONS_DIR"

# Baixa ícones vetoriais oficiais SVG da Microsoft (Office Fabric CDN)
curl -sL "https://res-1.cdn.office.net/files/fabric-cdn-prod_20230815.002/assets/brand-icons/product/svg/office_48x1.svg" -o "$ICONS_DIR/ms365.svg" 2>/dev/null || true
curl -sL "https://res-1.cdn.office.net/files/fabric-cdn-prod_20230815.002/assets/brand-icons/product/svg/word_48x1.svg" -o "$ICONS_DIR/ms-word.svg" 2>/dev/null || true
curl -sL "https://res-1.cdn.office.net/files/fabric-cdn-prod_20230815.002/assets/brand-icons/product/svg/excel_48x1.svg" -o "$ICONS_DIR/ms-excel.svg" 2>/dev/null || true
curl -sL "https://res-1.cdn.office.net/files/fabric-cdn-prod_20230815.002/assets/brand-icons/product/svg/powerpoint_48x1.svg" -o "$ICONS_DIR/ms-powerpoint.svg" 2>/dev/null || true
curl -sL "https://res-1.cdn.office.net/files/fabric-cdn-prod_20230815.002/assets/brand-icons/product/svg/outlook_48x1.svg" -o "$ICONS_DIR/ms-outlook.svg" 2>/dev/null || true

# Detecta navegador para execução em modo janela de aplicativo (--app)
BROWSER_CMD="google-chrome"
if ! command -v google-chrome >/dev/null 2>&1; then
    if command -v brave-browser >/dev/null 2>&1; then
        BROWSER_CMD="brave-browser"
    elif command -v chromium >/dev/null 2>&1; then
        BROWSER_CMD="chromium"
    fi
fi

# Cria lançadores dedicados para cada ferramenta do Microsoft 365
declare -A MS_APPS=(
    ["ms365"]="Microsoft 365|Suíte de Produtividade em Nuvem da Microsoft|https://www.office.com/?auth=2|ms365"
    ["ms-word"]="Microsoft Word|Processador de texto da Microsoft|https://www.office.com/launch/word?auth=2|ms-word"
    ["ms-excel"]="Microsoft Excel|Planilhas eletrônicas da Microsoft|https://www.office.com/launch/excel?auth=2|ms-excel"
    ["ms-powerpoint"]="Microsoft PowerPoint|Apresentações de slides da Microsoft|https://www.office.com/launch/powerpoint?auth=2|ms-powerpoint"
    ["ms-outlook"]="Microsoft Outlook|Email e calendário institucional|https://outlook.office.com/mail/|ms-outlook"
)

for app_id in "${!MS_APPS[@]}"; do
    IFS="|" read -r name comment url icon <<< "${MS_APPS[$app_id]}"
    cat << EOF > "$REAL_HOME/.local/share/applications/${app_id}.desktop"
[Desktop Entry]
Name=$name
Comment=$comment
Exec=$BROWSER_CMD --app=$url
Icon=$icon
Terminal=false
Type=Application
Categories=Office;Network;
StartupWMClass=crx_${app_id}
EOF
    chmod +x "$REAL_HOME/.local/share/applications/${app_id}.desktop"
done

chown -R "$REAL_USER:$REAL_USER" "$ICONS_DIR" "$REAL_HOME/.local/share/applications"

# ------------------------------------------------------------------------------
# 8. Ajuste de Permissões e Lançadores no COSMIC Desktop
# ------------------------------------------------------------------------------
log_msg "INFO" "Garantindo integração dos lançadores .desktop no sistema..."
sudo update-desktop-database /usr/share/applications 2>/dev/null || true
update-desktop-database "$REAL_HOME/.local/share/applications" 2>/dev/null || true

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "VPN MPMS (1-clique com 2FA) e Remmina RDP configurados com sucesso."
