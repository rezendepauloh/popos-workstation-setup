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

# Tenta obter automaticamente o hash SHA256 atualizado do certificado do Gateway MPMS
if [ -n "$VPN_HOST" ]; then
    LIVE_CERT=$(echo | timeout 5 openssl s_client -connect "${VPN_HOST}:${VPN_PORT:-443}" 2>/dev/null | openssl x509 -noout -fingerprint -sha256 2>/dev/null | cut -d'=' -f2 | tr -d ':' | tr '[:upper:]' '[:lower:]')
    if [[ "$LIVE_CERT" =~ ^[0-9a-f]{64}$ ]]; then
        VPN_TRUSTED_CERT="$LIVE_CERT"
        log_msg "INFO" "Certificado SSL do Gateway detectado dinamicamente: $VPN_TRUSTED_CERT"
    fi
fi

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
pppd-accept-remote = 1
EOF

if [ -n "$VPN_PASSWORD" ]; then
    echo "password = ${VPN_PASSWORD}" | sudo tee -a /etc/openfortivpn/mpms.conf > /dev/null
fi
sudo chmod 600 /etc/openfortivpn/mpms.conf

# Cria binário global /usr/local/bin/vpn-mpms
sudo tee /usr/local/bin/vpn-mpms > /dev/null << EOF
#!/bin/bash
VPN_HOST="${VPN_HOST}"
VPN_PORT="${VPN_PORT}"
VPN_USERNAME="${VPN_USERNAME}"
VPN_TRUSTED_CERT="${VPN_TRUSTED_CERT}"
EOF

sudo tee -a /usr/local/bin/vpn-mpms > /dev/null << 'EOF'
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
echo -e " ${C_YELLOW}➜${C_RESET} Informe o ${C_BOLD}Token / OTP 2FA${C_RESET} abaixo (Senha já configurada com segurança)."
echo -e " ${C_YELLOW}➜${C_RESET} Para ${C_RED}desconectar${C_RESET} a qualquer momento, pressione ${C_BOLD}Ctrl + C${C_RESET}."
echo -e "${C_CYAN}-------------------------------------------------------${C_RESET}"
echo ""

# Solicita a Senha apenas se não estiver previamente salva em /etc/openfortivpn/mpms.conf
if ! sudo grep -q "^password\s*=" /etc/openfortivpn/mpms.conf 2>/dev/null; then
    echo -ne " ${C_CYAN}🔑 Digite sua Senha do MPMS:${C_RESET} "
    read -r -s VPN_INPUT_PASS
    echo ""
fi

echo -ne " ${C_CYAN}📱 Digite o código Token / OTP 2FA:${C_RESET} "
read -r VPN_INPUT_OTP
echo ""

# Captura dinamicamente o hash SHA256 atual do certificado do Gateway MPMS (caso tenha sido renovado)
LIVE_CERT=$(echo | timeout 4 openssl s_client -connect "${VPN_HOST}:${VPN_PORT}" 2>/dev/null | openssl x509 -noout -fingerprint -sha256 2>/dev/null | cut -d'=' -f2 | tr -d ':' | tr '[:upper:]' '[:lower:]')

EXTRA_ARGS=("--pppd-accept-remote=1")
if [[ "$LIVE_CERT" =~ ^[0-9a-f]{64}$ ]]; then
    EXTRA_ARGS+=("--trusted-cert" "$LIVE_CERT")
fi
if [ -n "$VPN_INPUT_OTP" ]; then
    EXTRA_ARGS+=("-o" "$VPN_INPUT_OTP")
fi

CONF_TO_USE="/etc/openfortivpn/mpms.conf"
if [ -n "${VPN_INPUT_PASS:-}" ]; then
    RUNTIME_CONF="/dev/shm/openfortivpn-mpms-$$.conf"
    trap 'rm -f "$RUNTIME_CONF"' EXIT INT TERM
    cat << CONF_EOF > "$RUNTIME_CONF"
host = ${VPN_HOST}
port = ${VPN_PORT}
username = ${VPN_USERNAME}
trusted-cert = ${LIVE_CERT:-$VPN_TRUSTED_CERT}
set-dns = 1
pppd-use-peerdns = 1
pppd-accept-remote = 1
password = ${VPN_INPUT_PASS}
CONF_EOF
    chmod 600 "$RUNTIME_CONF"
    CONF_TO_USE="$RUNTIME_CONF"
fi
unset VPN_INPUT_PASS VPN_INPUT_OTP

echo -e " ${C_GREEN}Iniciando túnel seguro...${C_RESET}"

# Filtra os logs técnicos do openfortivpn/pppd e exibe um painel amigável em verde
VPN_IP=""
VPN_IFACE="ppp0"

while IFS= read -r line; do
    case "$line" in
        *"Connected to gateway"*)
            echo -e " ${C_CYAN}➜${C_RESET} Conectado ao servidor do MPMS. Validando credenciais..."
            ;;
        *"Authenticated"*)
            echo -e " ${C_GREEN}✔${C_RESET} Autenticação 2FA aprovada! Configurando rotas e DNS..."
            ;;
        *"Remote gateway has allocated a VPN"*)
            echo -e " ${C_CYAN}➜${C_RESET} Túnel alocado pelo gateway. Negociando IP na rede..."
            ;;
        *"Using interface"*)
            VPN_IFACE=$(echo "$line" | awk '{print $3}')
            ;;
        *"local  IP address"*)
            VPN_IP=$(echo "$line" | awk '{print $4}')
            ;;
        *"Tunnel is up and running"*)
            echo ""
            echo -e "${C_GREEN}=======================================================${C_RESET}"
            echo -e "${C_GREEN}${C_BOLD}   ✅ CONEXÃO VPN ESTABELECIDA COM SUCESSO!${C_RESET}"
            echo -e "${C_GREEN}=======================================================${C_RESET}"
            [ -n "$VPN_IP" ] && echo -e " ${C_CYAN}• IP na Rede MPMS:${C_RESET} ${C_BOLD}${VPN_IP}${C_RESET} (${VPN_IFACE})"
            echo -e " ${C_CYAN}• DNS Interno:${C_RESET}     Ativo (in.mpe.ms.gov.br)"
            echo -e " ${C_CYAN}• Status:${C_RESET}          ${C_GREEN}Túnel seguro e ativo 🔒${C_RESET}"
            echo -e "${C_GREEN}-------------------------------------------------------${C_RESET}"
            echo -e " ${C_YELLOW}💡 Mantenha esta janela aberta enquanto estiver trabalhando.${C_RESET}"
            echo -e " ${C_YELLOW}💡 Pressione ${C_BOLD}Ctrl + C${C_RESET}${C_YELLOW} quando quiser encerrar a VPN.${C_RESET}"
            echo ""
            ;;
        *"Peer refused to agree to our IP address"*)
            echo -e " ${C_RED}✖ Erro de negociação IP (IPCP): O gateway recusou atribuir endereço IP para esta sessão.${C_RESET}"
            echo -e " ${C_YELLOW}💡 Dica: Sua sessão anterior no FortiGate pode ter ficado presa ou o token 2FA já havia sido consumido. Aguarde o próximo código 2FA virar no celular e tente novamente.${C_RESET}"
            ;;
        *"Cancelling"*|*"Terminating"*|*"Closed connection"*|*"You should not pass the password"*)
            ;;
        *"ERROR:"*|*"WARN:"*|*"Could not authenticate"*)
            echo -e " ${C_RED}✖ ${line}${C_RESET}"
            ;;
    esac
done < <(sudo openfortivpn -c "$CONF_TO_USE" "${EXTRA_ARGS[@]}" 2>&1)

[ -n "${RUNTIME_CONF:-}" ] && rm -f "$RUNTIME_CONF"

echo ""
echo -e "${C_YELLOW}🔌 VPN Desconectada com segurança.${C_RESET}"
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
RDP_PASSWORD="${RDP_PASSWORD:-${VPN_PASSWORD:-}}"

if [ -n "$RDP_SERVER" ]; then
    log_msg "INFO" "Criando perfil de conexão RDP no Remmina para: $RDP_PROFILE_NAME..."
    mkdir -p "$REAL_HOME/.local/share/remmina"

    REMMINA_PROFILE="$REAL_HOME/.local/share/remmina/${RDP_PROFILE_ID}.remmina"

    # Calcula a senha ofuscada com a chave local do remmina.pref e grava no GNOME Keyring do usuário real
    ENCRYPTED_RDP_PASS="."
    if [ -n "$RDP_PASSWORD" ]; then
        REAL_UID=$(id -u "$REAL_USER")
        ENCRYPTED_RDP_PASS=$(sudo -u "$REAL_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${REAL_UID}/bus" python3 - "$REAL_HOME/.config/remmina/remmina.pref" "$REMMINA_PROFILE" "$RDP_PASSWORD" << 'PYEOF'
import sys, os, base64, ctypes

pref_file, profile_path, password = sys.argv[1], sys.argv[2], sys.argv[3]

# 1. Tenta armazenar no GNOME Keyring (formato nativo do remmina-plugin-secret)
try:
    import gi
    gi.require_version('Secret', '1')
    from gi.repository import Secret
    schema = Secret.Schema.new(
        "org.remmina.Password",
        Secret.SchemaFlags.NONE,
        {"filename": Secret.SchemaAttributeType.STRING, "key": Secret.SchemaAttributeType.STRING}
    )
    Secret.password_store_sync(
        schema,
        {"filename": profile_path, "key": "password"},
        Secret.COLLECTION_DEFAULT,
        f"Remmina: {os.path.basename(profile_path)} - password",
        password,
        None
    )
except Exception:
    pass

# 2. Criptografa também com 3DES usando o secret de remmina.pref para fallback imediato
try:
    secret_b64 = ""
    if os.path.exists(pref_file):
        with open(pref_file, "r") as f:
            for line in f:
                if line.startswith("secret="):
                    secret_b64 = line.strip().split("=", 1)[1]
                    break
    if secret_b64:
        raw_secret = base64.b64decode(secret_b64)
        if len(raw_secret) == 32:
            libgcrypt = ctypes.CDLL("libgcrypt.so.20")
            hd = ctypes.c_void_p()
            # GCRY_CIPHER_3DES = 2, GCRY_CIPHER_MODE_CBC = 3
            if libgcrypt.gcry_cipher_open(ctypes.byref(hd), 2, 3, 0) == 0:
                libgcrypt.gcry_cipher_setkey(hd, raw_secret[:24], 24)
                libgcrypt.gcry_cipher_setiv(hd, raw_secret[24:32], 8)
                pw_bytes = password.encode("utf-8")
                pad_len = ((len(pw_bytes) // 8) + 1) * 8
                buf = ctypes.create_string_buffer(pw_bytes, pad_len)
                if libgcrypt.gcry_cipher_encrypt(hd, buf, pad_len, None, 0) == 0:
                    libgcrypt.gcry_cipher_close(hd)
                    print(base64.b64encode(buf.raw).decode("ascii"))
                    sys.exit(0)
                libgcrypt.gcry_cipher_close(hd)
except Exception:
    pass

print(".")
PYEOF
)
    fi

    cat << EOF > "$REMMINA_PROFILE"
[remmina]
name=${RDP_PROFILE_NAME}
group=MPMS
protocol=RDP
server=${RDP_SERVER}
username=${RDP_USERNAME}
domain=${RDP_DOMAIN}
password=${ENCRYPTED_RDP_PASS}
colordepth=32
quality=9
sound=local
sharesmartcard=0
shareprinter=0
sharefolder=
disableclipboard=0
disablepasswordstoring=0
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
    log_msg "SUCCESS" "Perfil RDP do Remmina configurado com senha salva automaticamente."
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
    ["ms365"]="Microsoft 365 (Web)|Suíte de Produtividade em Nuvem da Microsoft|https://www.office.com/?auth=2|ms365"
    ["ms-word"]="Microsoft Word (Web)|Processador de texto da Microsoft|https://www.office.com/launch/word?auth=2|ms-word"
    ["ms-excel"]="Microsoft Excel (Web)|Planilhas eletrônicas da Microsoft|https://www.office.com/launch/excel?auth=2|ms-excel"
    ["ms-powerpoint"]="Microsoft PowerPoint (Web)|Apresentações de slides da Microsoft|https://www.office.com/launch/powerpoint?auth=2|ms-powerpoint"
    ["ms-outlook"]="Microsoft Outlook (Web)|Email e calendário institucional|https://outlook.office.com/mail/|ms-outlook"
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
