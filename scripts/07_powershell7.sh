#!/bin/bash
# ==============================================================================
# Módulo 07: Instalação e Configuração do PowerShell 7 (pwsh) no Linux
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="POWERSHELL_7"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  PowerShell 7 já instalado anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "7. INSTALAÇÃO DO MICROSOFT POWERSHELL 7 (PWSH)"

# 1. Configuração do Repositório Microsoft para Ubuntu 24.04 (Noble)
log_msg "INFO" "Configurando repositório oficial da Microsoft (APT)..."
MS_REPO_DEB="/tmp/packages-microsoft-prod.deb"
wget -qO "$MS_REPO_DEB" "https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb"
sudo dpkg -i "$MS_REPO_DEB" 2>/dev/null || true
rm -f "$MS_REPO_DEB"

sudo apt update

# 2. Instalação do pacote oficial powershell (com fallback para download direto do GitHub)
log_msg "INFO" "Instalando pacote do PowerShell 7..."
if ! sudo apt install -y powershell; then
    log_msg "WARN" "Repositório APT indisponível no momento. Baixando .deb direto do GitHub Releases..."
    PWSH_DEB_URL=$(curl -s https://api.github.com/repos/PowerShell/PowerShell/releases/latest | grep -o 'https://.*powershell_.*amd64\.deb' | head -n 1 || true)
    if [ -z "$PWSH_DEB_URL" ]; then
        PWSH_DEB_URL="https://github.com/PowerShell/PowerShell/releases/download/v7.6.5/powershell_7.6.5-1.deb_amd64.deb"
    fi
    wget -qO /tmp/powershell.deb "$PWSH_DEB_URL"
    sudo apt install -y /tmp/powershell.deb
    rm -f /tmp/powershell.deb
fi

# 3. Adiciona o binário do pwsh em /etc/shells se necessário
if ! grep -q "^$(which pwsh)$" /etc/shells 2>/dev/null; then
    which pwsh | sudo tee -a /etc/shells > /dev/null
fi

# 4. Criação do Diretório de Perfil do Usuário (~/.config/powershell)
log_msg "INFO" "Configurando perfil padrão do PowerShell para o usuário..."
PWSH_CONFIG_DIR="$REAL_HOME/.config/powershell"
mkdir -p "$PWSH_CONFIG_DIR"

if [ ! -f "$PWSH_CONFIG_DIR/Microsoft.PowerShell_profile.ps1" ]; then
    cat << 'EOF' > "$PWSH_CONFIG_DIR/Microsoft.PowerShell_profile.ps1"
# PowerShell 7 Profile - Pop!_OS Custom
$OutputEncoding = [System.Text.Encoding]::UTF8
Set-PSReadLineOption -PredictionSource History -PredictionViewStyle ListView 2>$null
EOF
fi
chown -R "$REAL_USER:$REAL_USER" "$PWSH_CONFIG_DIR" 2>/dev/null || true

# 5. Verificação da versão instalada
PWSH_VERSION=$(pwsh --version 2>/dev/null || echo "PowerShell 7")
log_msg "SUCCESS" "$PWSH_VERSION instalado e configurado com sucesso."

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Módulo PowerShell 7 concluído com sucesso."
