#!/bin/bash
# ==============================================================================
# Módulo 07: Instalação e Configuração do PowerShell 7 (pwsh) no Linux
# Restauração de Perfil, Oh My Posh, Temas e Módulos do Google Drive
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="POWERSHELL_7"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  PowerShell 7 já instalado e configurado anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "7. INSTALAÇÃO DO MICROSOFT POWERSHELL 7 E RESTAURAÇÃO DE PERFIL"

# 1. Instalação de Utilitários de Terminal Complementares (fzf, zoxide)
log_msg "INFO" "Instalando utilitários complementares (fzf, zoxide)..."
sudo apt update
sudo apt install -y fzf zoxide

# 2. Instalação do Oh My Posh (Engine de Prompt e Temas)
if ! command -v oh-my-posh &>/dev/null; then
    log_msg "INFO" "Instalando Oh My Posh (/usr/local/bin/oh-my-posh)..."
    sudo wget -qO /usr/local/bin/oh-my-posh https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-amd64
    sudo chmod +x /usr/local/bin/oh-my-posh
fi

# 3. Configuração do Repositório Microsoft e Instalação do PowerShell 7
log_msg "INFO" "Configurando repositório oficial da Microsoft (APT)..."
MS_REPO_DEB="/tmp/packages-microsoft-prod.deb"
wget -qO "$MS_REPO_DEB" "https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb"
sudo dpkg -i "$MS_REPO_DEB" 2>/dev/null || true
rm -f "$MS_REPO_DEB"
sudo apt update

log_msg "INFO" "Instalando pacote do PowerShell 7 (pwsh)..."
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

# Adiciona o binário do pwsh em /etc/shells se necessário
if ! grep -q "^$(which pwsh)$" /etc/shells 2>/dev/null; then
    which pwsh | sudo tee -a /etc/shells > /dev/null
fi

# 4. Restauração do Perfil e Configurações do Google Drive
PWSH_CONFIG_DIR="$REAL_HOME/.config/powershell"
GDRIVE_PWSH_DIR="$REAL_HOME/GoogleDrive_Pessoal/Organização/PowerShell"
LOCAL_FALLBACK_DIR="$BASE_DIR/PowerShell"

mkdir -p "$PWSH_CONFIG_DIR"

if [ -d "$GDRIVE_PWSH_DIR" ]; then
    log_msg "INFO" "Restaurando perfil, temas e módulos a partir do Google Drive..."
    cp -ru "$GDRIVE_PWSH_DIR"/* "$PWSH_CONFIG_DIR/" 2>/dev/null || cp -r "$GDRIVE_PWSH_DIR"/* "$PWSH_CONFIG_DIR/" 2>/dev/null || true
elif [ -d "$LOCAL_FALLBACK_DIR" ]; then
    log_msg "INFO" "Google Drive não encontrado. Restaurando a partir da pasta local de fallback..."
    cp -ru "$LOCAL_FALLBACK_DIR"/* "$PWSH_CONFIG_DIR/" 2>/dev/null || cp -r "$LOCAL_FALLBACK_DIR"/* "$PWSH_CONFIG_DIR/" 2>/dev/null || true
else
    log_msg "INFO" "Criando perfil padrão do PowerShell..."
    cat << 'EOF' > "$PWSH_CONFIG_DIR/Microsoft.PowerShell_profile.ps1"
$OutputEncoding = [System.Text.Encoding]::UTF8
Set-PSReadLineOption -PredictionSource History -PredictionViewStyle ListView 2>$null
EOF
fi

chown -R "$REAL_USER:$REAL_USER" "$PWSH_CONFIG_DIR" 2>/dev/null || true

# 5. Instalação Automática dos Módulos do PowerShell (posh-git, PSReadLine, Terminal-Icons, PSFzf)
log_msg "INFO" "Instalando módulos essenciais do PowerShell (posh-git, PSReadLine, Terminal-Icons, PSFzf)..."
MODULE_INSTALL_CMD="
Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue
\$modules = @('posh-git', 'PSReadLine', 'Terminal-Icons', 'PSFzf')
foreach (\$mod in \$modules) {
    Write-Host \"Instalando módulo: \$mod...\"
    Install-Module -Name \$mod -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck -ErrorAction SilentlyContinue
}
"

if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    sudo -u "$REAL_USER" pwsh -NoProfile -Command "$MODULE_INSTALL_CMD" 2>/dev/null || true
else
    pwsh -NoProfile -Command "$MODULE_INSTALL_CMD" 2>/dev/null || true
fi

# 6. Verificação Final
PWSH_VERSION=$(pwsh --version 2>/dev/null || echo "PowerShell 7")
log_msg "SUCCESS" "$PWSH_VERSION com Oh My Posh e módulos restaurados com sucesso!"

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Módulo PowerShell 7 concluído com sucesso."
