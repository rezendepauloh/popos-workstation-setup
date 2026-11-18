#!/bin/bash
set -e

# ==============================================================================
# Utilitário: Atualização do Google Antigravity IDE
# ==============================================================================
# Consulta a última versão oficial, baixa e extrai em /opt/antigravity,
# preserva o wrapper Wayland e reaplica o patch binário de cedilha/aspas.
#
# Uso:
#   ./update_antigravity.sh          # Atualiza se houver versão mais nova
#   ./update_antigravity.sh --check  # Apenas verifica se há atualização
#   ./update_antigravity.sh --force  # Reinstala mesmo se já estiver na última versão
# ==============================================================================

C_RESET="\033[0m"
C_BLUE="\033[1;34m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_RED="\033[1;31m"
C_CYAN="\033[1;36m"

CHECK_ONLY=false
FORCE=false
for arg in "$@"; do
    case "$arg" in
        --check) CHECK_ONLY=true ;;
        --force) FORCE=true ;;
    esac
done

log_info() { echo -e "${C_BLUE}[INFO]${C_RESET} $1"; }
log_ok()   { echo -e "${C_GREEN}[OK]${C_RESET} $1"; }
log_warn() { echo -e "${C_YELLOW}[AVISO]${C_RESET} $1"; }
log_err()  { echo -e "${C_RED}[ERRO]${C_RESET} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RELEASES_URL="https://antigravity-ide-auto-updater-974169037036.us-central1.run.app/releases"

echo -e "${C_CYAN}================================================================${C_RESET}"
echo -e "${C_CYAN}   🚀 ATUALIZAÇÃO DO GOOGLE ANTIGRAVITY IDE                     ${C_RESET}"
echo -e "${C_CYAN}================================================================${C_RESET}"

# 1. Versão instalada atualmente
CURRENT_VER="não instalado"
if [ -f /opt/antigravity/resources/app/package.json ]; then
    CURRENT_VER="$(python3 -c 'import json; print(json.load(open("/opt/antigravity/resources/app/package.json")).get("version", "desconhecida"))' 2>/dev/null || echo "desconhecida")"
fi
log_info "Versão instalada: $CURRENT_VER"

# 2. Consulta última versão oficial
log_info "Consultando última versão disponível..."
RELEASE_JSON="$(curl -fsSL --connect-timeout 5 --max-time 15 "$RELEASES_URL" 2>/dev/null || true)"
if [ -z "$RELEASE_JSON" ]; then
    log_err "Não foi possível consultar $RELEASES_URL."
    exit 1
fi

read -r LATEST_VER LATEST_EXEC < <(python3 - "$RELEASE_JSON" <<'PYEOF'
import json, sys
data = json.loads(sys.argv[1])
if isinstance(data, list) and data:
    item = data[0]
elif isinstance(data, dict):
    item = data
else:
    item = {}
print(item.get("version", ""), item.get("execution_id") or item.get("execution", ""))
PYEOF
)

if [ -z "$LATEST_VER" ] || [ -z "$LATEST_EXEC" ]; then
    log_err "Resposta inesperada da API de releases do Antigravity."
    exit 1
fi

log_info "Última versão disponível: $LATEST_VER ($LATEST_EXEC)"

if [ "$CURRENT_VER" = "$LATEST_VER" ] && ! $FORCE; then
    log_ok "O Antigravity IDE já está atualizado na versão $CURRENT_VER."
    exit 0
fi

if $CHECK_ONLY; then
    log_warn "Atualização disponível: $CURRENT_VER -> $LATEST_VER"
    exit 0
fi

# 3. Download e extração
DOWNLOAD_URL="https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/${LATEST_VER}-${LATEST_EXEC}/linux-x64/Antigravity%20IDE.tar.gz"
WORK_TMP="$(mktemp -d)"
trap 'rm -rf "$WORK_TMP"' EXIT

log_info "Baixando Antigravity IDE $LATEST_VER..."
wget -q --show-progress -O "$WORK_TMP/antigravity.tar.gz" "$DOWNLOAD_URL"

log_info "Extraindo para /opt/antigravity..."
sudo mkdir -p /opt/antigravity
sudo tar -xzf "$WORK_TMP/antigravity.tar.gz" -C /opt/antigravity --strip-components=1
sudo chmod -R 755 /opt/antigravity
sudo chmod +x /opt/antigravity/antigravity-ide 2>/dev/null || true

if [ -f /opt/antigravity/chrome-sandbox ]; then
    sudo chown root:root /opt/antigravity/chrome-sandbox
    sudo chmod 4755 /opt/antigravity/chrome-sandbox
fi

# 4. Preserva wrapper Wayland em /opt/antigravity/bin/antigravity-ide
if [ -x /usr/local/bin/antigravity ] && [ ! /usr/local/bin/antigravity -ef /opt/antigravity/bin/antigravity-ide ]; then
    sudo mkdir -p /opt/antigravity/bin
    sudo cp -f /usr/local/bin/antigravity /opt/antigravity/bin/antigravity-ide
    sudo chmod +x /opt/antigravity/bin/antigravity-ide
fi

# 5. Reaplica patch binário de cedilha/aspas no Electron
if [ -x /usr/local/bin/patch-cedilla-electron ]; then
    log_info "Reaplicando patch de cedilha ('+c = ç)..."
    sudo /usr/local/bin/patch-cedilla-electron /opt/antigravity/antigravity-ide || true
elif [ -f "$PROJECT_ROOT/scripts/daemons/patch_cedilla_electron.py" ]; then
    log_info "Reaplicando patch de cedilha ('+c = ç) via script local..."
    sudo python3 "$PROJECT_ROOT/scripts/daemons/patch_cedilla_electron.py" /opt/antigravity/antigravity-ide || true
fi

log_ok "Antigravity IDE atualizado com sucesso para a versão $LATEST_VER!"
log_warn "Reinicie o Antigravity IDE para carregar a nova versão."
