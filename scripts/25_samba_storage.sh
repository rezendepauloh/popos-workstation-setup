#!/bin/bash
# ==============================================================================
# Módulo 25: Servidor Samba e Compartilhamento de Rede Local (/mnt/storage_700/samba)
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="CONFIG_SAMBA_STORAGE"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Servidor Samba e compartilhamento de rede já configurados. Pulando..."
    exit 0
fi

log_msg "HEADER" "25. CONFIGURAÇÃO DO SERVIDOR SAMBA E COMPARTILHAMENTO DE ARMAZENAMENTO"

# ------------------------------------------------------------------------------
# 1. Instalação do Samba
# ------------------------------------------------------------------------------
log_msg "INFO" "Instalando pacotes do servidor Samba..."
sudo apt update
sudo apt install -y samba samba-common-bin smbclient

# ------------------------------------------------------------------------------
# 2. Criação do Diretório Compartilhado
# ------------------------------------------------------------------------------
SAMBA_PATH="${SAMBA_SHARE_PATH:-/mnt/storage_700/samba}"

log_msg "INFO" "Garantindo diretório compartilhado: $SAMBA_PATH..."
sudo mkdir -p "$SAMBA_PATH"
sudo chown -R "$REAL_USER:$REAL_USER" "$SAMBA_PATH"
sudo chmod -R 0775 "$SAMBA_PATH"

# ------------------------------------------------------------------------------
# 3. Configuração do /etc/samba/smb.conf
# ------------------------------------------------------------------------------
log_msg "INFO" "Configurando compartilhamento no /etc/samba/smb.conf..."

if [ -f /etc/samba/smb.conf ] && [ ! -f /etc/samba/smb.conf.bak_original ]; then
    sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.bak_original
fi

# Remove bloco antigo do Storage700 se já existir para garantir idempotência
sudo sed -i '/^\[Storage700\]/,/^\[/ { /^\[Storage700\]/d; /^\[/!d }' /etc/samba/smb.conf 2>/dev/null || true

cat << EOF | sudo tee -a /etc/samba/smb.conf > /dev/null

[Storage700]
   comment = Compartilhamento Storage 700 - Pop!_OS Workstation
   path = $SAMBA_PATH
   valid users = $REAL_USER
   read only = no
   writable = yes
   browsable = yes
   create mask = 0775
   directory mask = 0775
   force user = $REAL_USER
EOF

# ------------------------------------------------------------------------------
# 4. Configuração do Usuário e Senha no Samba
# ------------------------------------------------------------------------------
log_msg "INFO" "Configurando credenciais do usuário '$REAL_USER' no Samba..."

SMB_PASS="${SAMBA_PASSWORD:-}"

if [ -n "$SMB_PASS" ]; then
    printf "%s\n%s\n" "$SMB_PASS" "$SMB_PASS" | sudo smbpasswd -s -a "$REAL_USER"
    sudo smbpasswd -e "$REAL_USER" >/dev/null 2>&1 || true
    log_msg "SUCCESS" "Senha do Samba configurada via variável SAMBA_PASSWORD."
else
    # Verifica se o usuário já existe na base do Samba
    if sudo pdbedit -L | grep -q "^$REAL_USER:"; then
        log_msg "INFO" "Usuário '$REAL_USER' já cadastrado no Samba. Mantendo credenciais existentes."
    else
        log_msg "WARN" "Variável SAMBA_PASSWORD não definida no .env."
        if [ -t 0 ]; then
            log_msg "INFO" "Digite a senha desejada para o usuário Samba '$REAL_USER':"
            sudo smbpasswd -a "$REAL_USER"
            sudo smbpasswd -e "$REAL_USER" >/dev/null 2>&1 || true
        else
            log_msg "WARN" "Ambiente não interativo e SAMBA_PASSWORD vazia. Habilitando usuário sem senha provisória..."
            sudo smbpasswd -a -n "$REAL_USER" 2>/dev/null || true
            sudo smbpasswd -e "$REAL_USER" >/dev/null 2>&1 || true
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 5. Firewall UFW para a Subrede Local
# ------------------------------------------------------------------------------
if command -v ufw >/dev/null 2>&1; then
    log_msg "INFO" "Liberando portas do Samba (137,138/udp, 139,445/tcp) no firewall para 192.168.0.0/24..."
    sudo ufw allow from 192.168.0.0/24 to any port 137,138 proto udp comment 'Samba NetBIOS UDP' >/dev/null 2>&1 || true
    sudo ufw allow from 192.168.0.0/24 to any port 139,445 proto tcp comment 'Samba SMB TCP' >/dev/null 2>&1 || true
fi

# ------------------------------------------------------------------------------
# 6. Reinicialização e Habilitação dos Serviços
# ------------------------------------------------------------------------------
log_msg "INFO" "Habilitando e reiniciando serviços smbd e nmbd..."
sudo systemctl enable smbd nmbd
sudo systemctl restart smbd nmbd

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Servidor Samba configurado com sucesso! Compartilhamento ativo em $SAMBA_PATH."
