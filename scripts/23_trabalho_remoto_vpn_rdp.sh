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
# 2.1. Suporte a Smartcard / Certificado Digital A3 (SafeNet eToken / PKCS#11)
# ------------------------------------------------------------------------------
log_msg "INFO" "Instalando infraestrutura PC/SC, driver CCID, OpenSC e ferramentas NSS/PKCS#11..."
sudo apt install -y pcscd pcsc-tools libccid opensc opensc-pkcs11 libnss3-tools p11-kit p11-kit-modules

# Habilita socket e serviço PC/SC para detecção hotplug do token USB (ex: 0529:0620 Token JC)
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    sudo systemctl enable --now pcscd.socket 2>/dev/null || true
    sudo systemctl enable --now pcscd.service 2>/dev/null || true
fi

run_as_real_user() {
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        sudo -u "$REAL_USER" "$@"
    else
        "$@"
    fi
}

# Instala SafeNet Authentication Client (.deb opcional colocado em config/safenet/) se ainda não instalado
SAFENET_DEB_DIR="$BASE_DIR/config/safenet"
if [ -d "$SAFENET_DEB_DIR" ] && \
   ! dpkg-query -W -f='${Status}' safenetauthenticationclient 2>/dev/null | grep -q "install ok installed" && \
   ! dpkg-query -W -f='${Status}' safenetauthenticationclient-core 2>/dev/null | grep -q "install ok installed"; then
    for sac_deb in "$SAFENET_DEB_DIR"/*.deb; do
        if [ -f "$sac_deb" ]; then
            log_msg "INFO" "Instalando SafeNet Authentication Client a partir de $(basename "$sac_deb")..."
            sudo apt install -y "$sac_deb" || true
            break
        fi
    done
fi

# Registra biblioteca PKCS#11 proprietária da SafeNet no p11-kit caso instalada no sistema
SAFENET_P11_LIB=""
for candidate_lib in /usr/lib/libeTPkcs11.so /usr/lib/x86_64-linux-gnu/libeTPkcs11.so /usr/lib/libeToken.so; do
    if [ -f "$candidate_lib" ]; then
        SAFENET_P11_LIB="$candidate_lib"
        break
    fi
done

if [ -n "$SAFENET_P11_LIB" ]; then
    sudo mkdir -p /etc/pkcs11/modules
    cat << EOF | sudo tee /etc/pkcs11/modules/safenet-etoken.module > /dev/null
# Módulo PKCS#11 proprietário SafeNet Authentication Client (eToken 5110 / Token JC)
module: ${SAFENET_P11_LIB}
EOF
    sudo chmod 644 /etc/pkcs11/modules/safenet-etoken.module
    log_msg "SUCCESS" "Módulo PKCS#11 SafeNet registrado no p11-kit: $SAFENET_P11_LIB"
fi

# Configura NSS DB (~/.pki/nssdb) para navegadores Chromium/Chrome/Brave via p11-kit-proxy.so
NSSDB_DIR="$REAL_HOME/.pki/nssdb"
mkdir -p "$NSSDB_DIR"
chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.pki"
chmod 700 "$NSSDB_DIR"

if [ ! -f "$NSSDB_DIR/cert9.db" ] && command -v certutil >/dev/null 2>&1; then
    run_as_real_user certutil -N --empty-password -d "sql:$NSSDB_DIR" >/dev/null 2>&1 || true
fi

P11_PROXY_LIB=""
for p11_candidate in /usr/lib/x86_64-linux-gnu/p11-kit-proxy.so /usr/lib/x86_64-linux-gnu/pkcs11/p11-kit-proxy.so; do
    if [ -f "$p11_candidate" ]; then
        P11_PROXY_LIB="$p11_candidate"
        break
    fi
done

if [ -n "$P11_PROXY_LIB" ] && command -v modutil >/dev/null 2>&1 && { [ -f "$NSSDB_DIR/pkcs11.txt" ] || [ -f "$NSSDB_DIR/cert9.db" ]; }; then
    if ! run_as_real_user modutil -list -dbdir "sql:$NSSDB_DIR" 2>/dev/null | grep -Fq "p11-kit-proxy"; then
        run_as_real_user modutil -dbdir "sql:$NSSDB_DIR" -add "p11-kit-proxy" -libfile "$P11_PROXY_LIB" -force >/dev/null 2>&1 || true
        log_msg "SUCCESS" "Módulo p11-kit-proxy registrado no NSS DB (~/.pki/nssdb) para uso em navegadores."
    fi
fi

# Garante acesso ao socket PC/SC e p11-kit-server caso Firefox esteja instalado via Flatpak
if command -v flatpak >/dev/null 2>&1; then
    run_as_real_user flatpak override --user --socket=pcsc --filesystem=xdg-run/p11-kit/pkcs11 org.mozilla.firefox 2>/dev/null || true
    if [ "$(id -u)" -eq 0 ] || sudo -n true 2>/dev/null; then
        sudo flatpak override --socket=pcsc --filesystem=xdg-run/p11-kit/pkcs11 org.mozilla.firefox 2>/dev/null || true
    fi
fi

# Instala serviço de usuário p11-kit-server para expor o token a apps Flatpak (ex: Firefox)
P11_SVC_SRC="$BASE_DIR/config/systemd/user/p11-kit-server.service"
if [ -f "$P11_SVC_SRC" ]; then
    mkdir -p "$REAL_HOME/.config/systemd/user"
    cp -f "$P11_SVC_SRC" "$REAL_HOME/.config/systemd/user/p11-kit-server.service"
    if [ -z "$SAFENET_P11_LIB" ] && [ -f /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so ]; then
        sed -i 's|--provider /usr/lib/libeTPkcs11.so|--provider /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so|' "$REAL_HOME/.config/systemd/user/p11-kit-server.service"
    fi
    chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/systemd"
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        run_as_real_user DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user daemon-reload 2>/dev/null || true
        run_as_real_user DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" systemctl --user enable --now p11-kit-server.service 2>/dev/null || true
    fi
fi

# Registra p11-kit-client.so nos perfis do Firefox Flatpak
FIREFOX_FLATPAK_DIR="$REAL_HOME/.var/app/org.mozilla.firefox/config/mozilla/firefox"
if command -v modutil >/dev/null 2>&1 && [ -d "$FIREFOX_FLATPAK_DIR" ] && [ -f /usr/lib/x86_64-linux-gnu/pkcs11/p11-kit-client.so ]; then
    for ff_profile in "$FIREFOX_FLATPAK_DIR"/*default*; do
        if [ -d "$ff_profile" ] && [ -f "$ff_profile/pkcs11.txt" ]; then
            if ! run_as_real_user modutil -list -dbdir "sql:$ff_profile" 2>/dev/null | grep -Fq "p11-kit-client"; then
                run_as_real_user modutil -dbdir "sql:$ff_profile" -add "p11-kit-client" -libfile /usr/lib/x86_64-linux-gnu/pkcs11/p11-kit-client.so -force >/dev/null 2>&1 || true
            fi
        fi
    done
fi

chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.pki"

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

# Respeita o certificado fixado (Certificate Pinning) no .env; apenas faz descoberta TOFU se ausente
if [ -n "$VPN_HOST" ] && { [ -z "$VPN_TRUSTED_CERT" ] || [ "$VPN_TRUSTED_CERT" = "certificado_aqui" ]; }; then
    LIVE_CERT=$(echo | timeout 5 openssl s_client -connect "${VPN_HOST}:${VPN_PORT:-443}" 2>/dev/null | openssl x509 -noout -fingerprint -sha256 2>/dev/null | cut -d'=' -f2 | tr -d ':' | tr '[:upper:]' '[:lower:]')
    if [[ "$LIVE_CERT" =~ ^[0-9a-f]{64}$ ]]; then
        VPN_TRUSTED_CERT="$LIVE_CERT"
        log_msg "INFO" "Certificado SSL do Gateway detectado (TOFU): $VPN_TRUSTED_CERT"
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

VPN_HAS_SAVED_PASS="0"
if [ -n "$VPN_PASSWORD" ]; then
    echo "password = ${VPN_PASSWORD}" | sudo tee -a /etc/openfortivpn/mpms.conf > /dev/null
    VPN_HAS_SAVED_PASS="1"
fi
sudo chown root:root /etc/openfortivpn/mpms.conf
sudo chmod 600 /etc/openfortivpn/mpms.conf

# Cria wrapper privilegiado seguro (/usr/local/sbin/openfortivpn-mpms-helper)
# Impede escalação de privilégio via flags arbitrárias (--pppd-plugin / -c) e oculta OTP/Senha de ps aux
sudo tee /usr/local/sbin/openfortivpn-mpms-helper > /dev/null << 'EOF'
#!/bin/bash
set -euo pipefail
umask 077

BASE_CONF="/etc/openfortivpn/mpms.conf"
if [ ! -f "$BASE_CONF" ]; then
    echo "ERROR: Arquivo $BASE_CONF não encontrado." >&2
    exit 1
fi

IFS= read -r VPN_OTP_STDIN || VPN_OTP_STDIN=""
IFS= read -r VPN_PASS_STDIN || VPN_PASS_STDIN=""

# Sanitiza eventuais quebras de linha ou caracteres de controle
VPN_OTP_STDIN="${VPN_OTP_STDIN//[$'\r\n']/}"
VPN_PASS_STDIN="${VPN_PASS_STDIN//[$'\r\n']/}"

RUNTIME_CONF=$(mktemp /run/openfortivpn-mpms.XXXXXX.conf)
chmod 600 "$RUNTIME_CONF"
trap 'rm -f "$RUNTIME_CONF"' EXIT INT TERM

cp "$BASE_CONF" "$RUNTIME_CONF"

if [ -n "$VPN_PASS_STDIN" ]; then
    sed -i '/^password\s*=/d' "$RUNTIME_CONF"
    printf "password = %s\n" "$VPN_PASS_STDIN" >> "$RUNTIME_CONF"
fi

if [ -n "$VPN_OTP_STDIN" ]; then
    sed -i '/^otp\s*=/d' "$RUNTIME_CONF"
    printf "otp = %s\n" "$VPN_OTP_STDIN" >> "$RUNTIME_CONF"
fi

unset VPN_OTP_STDIN VPN_PASS_STDIN

exec /usr/bin/openfortivpn -c "$RUNTIME_CONF" --pppd-accept-remote=1
EOF
sudo chown root:root /usr/local/sbin/openfortivpn-mpms-helper
sudo chmod 750 /usr/local/sbin/openfortivpn-mpms-helper

# Cria binário global /usr/local/bin/vpn-mpms
sudo tee /usr/local/bin/vpn-mpms > /dev/null << EOF
#!/bin/bash
VPN_HOST="${VPN_HOST}"
VPN_PORT="${VPN_PORT}"
VPN_USERNAME="${VPN_USERNAME}"
VPN_TRUSTED_CERT="${VPN_TRUSTED_CERT}"
VPN_HAS_SAVED_PASS="${VPN_HAS_SAVED_PASS}"
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

VPN_INPUT_PASS=""
if [ "${VPN_HAS_SAVED_PASS:-0}" != "1" ]; then
    echo -ne " ${C_CYAN}🔑 Digite sua Senha do MPMS:${C_RESET} "
    read -r -s VPN_INPUT_PASS
    echo ""
fi

echo -ne " ${C_CYAN}📱 Digite o código Token / OTP 2FA:${C_RESET} "
read -r VPN_INPUT_OTP
echo ""

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
done < <(printf "%s\n%s\n" "${VPN_INPUT_OTP:-}" "${VPN_INPUT_PASS:-}" | sudo /usr/local/sbin/openfortivpn-mpms-helper 2>&1)

unset VPN_INPUT_PASS VPN_INPUT_OTP

echo ""
echo -e "${C_YELLOW}🔌 VPN Desconectada com segurança.${C_RESET}"
read -n 1 -s -r -p "Pressione qualquer tecla para fechar esta janela..."
EOF
sudo chmod +x /usr/local/bin/vpn-mpms

# Permite ao usuário executar apenas o wrapper restrito (sem argumentos arbitrários)
sudo tee /etc/sudoers.d/openfortivpn-mpms > /dev/null << EOF
$REAL_USER ALL=(root) NOPASSWD: /usr/local/sbin/openfortivpn-mpms-helper
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
        ENCRYPTED_RDP_PASS=$(sudo -u "$REAL_USER" RDP_PASSWORD_ENV="$RDP_PASSWORD" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${REAL_UID}/bus" python3 - "$REAL_HOME/.config/remmina/remmina.pref" "$REMMINA_PROFILE" << 'PYEOF'
import sys, os, base64, ctypes

pref_file, profile_path = sys.argv[1], sys.argv[2]
password = os.environ.get("RDP_PASSWORD_ENV", "")

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
sharesmartcard=1
smartcardname=
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
    log_msg "SUCCESS" "Perfil RDP do Remmina configurado com senha salva e redirecionamento de Smartcard ativo."
fi

# Garante redirecionamento de Smartcard ativo em qualquer perfil RDP do MPMS já existente no Remmina
for remmina_file in "$REAL_HOME/.local/share/remmina"/*.remmina; do
    [ -f "$remmina_file" ] || continue
    if grep -q "^protocol=RDP" "$remmina_file" && grep -q "^group=MPMS" "$remmina_file"; then
        if grep -q "^sharesmartcard=" "$remmina_file"; then
            sed -i 's/^sharesmartcard=.*/sharesmartcard=1/' "$remmina_file"
        else
            echo "sharesmartcard=1" >> "$remmina_file"
        fi
        if ! grep -q "^smartcardname=" "$remmina_file"; then
            echo "smartcardname=" >> "$remmina_file"
        fi
        chown "$REAL_USER:$REAL_USER" "$remmina_file"
        chmod 600 "$remmina_file"
    fi
done

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
