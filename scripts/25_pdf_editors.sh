#!/bin/bash
# ==============================================================================
# Módulo 25: Editores Profissionais de PDF (Master PDF Editor & Okular)
# Ferramentas completas de leitura com marcadores avançados e edição direta de PDF
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="PDF_EDITORS_OKULAR_MASTER"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Editores de PDF (Master PDF Editor & Okular) já instalados. Pulando..."
    exit 0
fi

log_msg "HEADER" "25. EDITORES PROFISSIONAIS DE PDF (MASTER PDF EDITOR & OKULAR)"

# ------------------------------------------------------------------------------
# 1. Instalação do Okular (Leitura, Marcadores Avançados & Anotações)
# ------------------------------------------------------------------------------
log_msg "INFO" "Instalando Okular via repositório APT oficial..."
sudo apt update
sudo apt install -y okular okular-extra-backends

# ------------------------------------------------------------------------------
# 2. Instalação do Master PDF Editor (Edição Direta de PDF, Textos & Sumários)
# ------------------------------------------------------------------------------
log_msg "INFO" "Verificando instalação do Master PDF Editor..."

if ! command -v masterpdfeditor5 >/dev/null 2>&1; then
    TEMP_DEB=$(mktemp /tmp/masterpdf_XXXXXX.deb)
    MASTER_PDF_URL="https://code-industry.net/public/master-pdf-editor-5.9.99-qt5.x86_64.deb"

    log_msg "INFO" "Baixando pacote oficial do Master PDF Editor 5 (Qt5)..."
    rm -f "$TEMP_DEB"
    curl -fSL --progress-bar "$MASTER_PDF_URL" -o "$TEMP_DEB"

    log_msg "INFO" "Instalando pacote Master PDF Editor e dependências..."
    sudo apt install -y "$TEMP_DEB" libqt5svg5 libqt5gui5 libqt5network5 libqt5printsupport5 || sudo apt-get install -f -y
    rm -f "$TEMP_DEB"
    log_msg "SUCCESS" "Master PDF Editor instalado com sucesso."
else
    log_msg "INFO" "Master PDF Editor já instalado no sistema."
fi

# ------------------------------------------------------------------------------
# 3. Atualização do Banco de Aplicativos e Lançadores
# ------------------------------------------------------------------------------
log_msg "INFO" "Atualizando cache de lançadores do sistema..."
sudo update-desktop-database /usr/share/applications 2>/dev/null || true
update-desktop-database "$REAL_HOME/.local/share/applications" 2>/dev/null || true

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Master PDF Editor e Okular instalados e integrados com sucesso."
