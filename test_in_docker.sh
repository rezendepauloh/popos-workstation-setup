#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Se não estiver rodando dentro do container, executa o build e roda via docker no host
if [ "$1" != "--inside" ] && [ ! -f "/.dockerenv" ]; then
    echo "============================================================"
    echo "🐳 [HOST WSL] Construindo e executando container de teste..."
    echo "============================================================"
    
    docker build -t popos-provision-test -f "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR"
    
    CA_MOUNT=""
    if [ -d "/usr/local/share/ca-certificates" ]; then
        CA_MOUNT="-v /usr/local/share/ca-certificates:/usr/local/share/ca-certificates:ro"
    fi
    
    echo ""
    echo "🚀 [HOST WSL] Iniciando testes do setup_popos.sh no container..."
    docker run --rm $CA_MOUNT -v "$SCRIPT_DIR:/workspace" popos-provision-test /bin/bash /workspace/test_in_docker.sh --inside
    exit 0
fi

# ==============================================================================
# EXECUÇÃO DENTRO DO CONTAINER
# ==============================================================================
echo "============================================================"
echo "🧪 [CONTAINER] Preparando ambiente de teste mockado..."
echo "============================================================"

export DEBIAN_FRONTEND=noninteractive

# 1. Atualizar certificados CA se montados do host ou locais
if [ -d "/usr/local/share/ca-certificates" ]; then
    update-ca-certificates 2>/dev/null || true
fi

# 2. Garantir usuário de teste
if ! id "paulogoncalves" &>/dev/null; then
    (userdel -r ubuntu 2>/dev/null || true)
    useradd -m -s /bin/bash -u 1000 paulogoncalves
    echo "paulogoncalves ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
fi

# 3. Garantir mocks de hardware/desktop
mkdir -p /usr/local/mock-bin

cat << 'MOCK' > /usr/local/mock-bin/gsettings
#!/bin/bash
echo "[MOCK gsettings] Chamado com: $@"
exit 0
MOCK

cat << 'MOCK' > /usr/local/mock-bin/ratbagctl
#!/bin/bash
echo "[MOCK ratbagctl] Chamado com: $@"
if [ "$1" = "list" ]; then
    echo "singing-hare: Logitech G502 X"
fi
exit 0
MOCK

cat << 'MOCK' > /usr/local/mock-bin/mount
#!/bin/bash
echo "[MOCK mount] Chamado com: $@"
exit 0
MOCK

cat << 'MOCK' > /usr/local/mock-bin/systemctl
#!/bin/bash
echo "[MOCK systemctl] Chamado com: $@"
exit 0
MOCK

cat << 'MOCK' > /usr/local/mock-bin/sysctl
#!/bin/bash
echo "[MOCK sysctl] Chamado com: $@"
exit 0
MOCK

cat << 'MOCK' > /usr/local/mock-bin/espanso
#!/bin/bash
echo "[MOCK espanso] Chamado com: $@"
exit 0
MOCK

cat << 'MOCK' > /usr/local/mock-bin/xdg-mime
#!/bin/bash
echo "[MOCK xdg-mime] Chamado com: $@"
exit 0
MOCK

cat << 'MOCK' > /usr/local/mock-bin/rclone
#!/bin/bash
if [ "$1" = "listremotes" ]; then
    echo "onedrive_pessoal:"
    echo "mega_pessoal:"
    echo "gdrive_pessoal:"
    exit 0
elif [ "$1" = "config" ]; then
    echo "[MOCK rclone config] Remote configurado."
    exit 0
elif [ "$1" = "mount" ]; then
    echo "[MOCK rclone mount] Montagem simulada."
    exit 0
fi
exit 0
MOCK

cat << 'MOCK' > /usr/local/mock-bin/flatpak
#!/bin/bash
echo "[MOCK flatpak] Chamado com: $@"
exit 0
MOCK

chmod +x /usr/local/mock-bin/*

# Configurar sudoers secure_path para incluir o mock-bin na frente
sed -i 's|secure_path="\(.*\)"|secure_path="/usr/local/mock-bin:\1"|' /etc/sudoers

# 4. Criar mocks de estrutura de diretórios e arquivos que seriam restaurados
su - paulogoncalves -c "mkdir -p ~/GoogleDrive_Pessoal/Organização/Kando/Casa ~/GoogleDrive_Pessoal/Organização/Backup_COSMIC/cosmic ~/GoogleDrive_Pessoal/Organização/VSCode_Antigravity ~/.config"
cat << 'JSON' > /home/paulogoncalves/GoogleDrive_Pessoal/Organização/Kando/Casa/general-settings-backup.json
{"theme": "dark"}
JSON
cat << 'JSON' > /home/paulogoncalves/GoogleDrive_Pessoal/Organização/Kando/Casa/menu-settings-backup.json
{"menus": [{"name": "Main", "shortcut": "Ctrl+Space"}]}
JSON
cat << 'JSON' > /home/paulogoncalves/GoogleDrive_Pessoal/Organização/VSCode_Antigravity/settings.json
{"editor.fontSize": 20, "terminal.integrated.fontFamily": "MesloLGS NF"}
JSON
cat << 'JSON' > /home/paulogoncalves/GoogleDrive_Pessoal/Organização/VSCode_Antigravity/keybindings.json
[{"key": "ctrl+'", "command": "workbench.action.terminal.toggleTerminal"}]
JSON

# Mock do Terminal ZSH Linux dentro do Google Drive
if [ -d "/workspace/Terminal ZSH Linux" ]; then
    cp -r "/workspace/Terminal ZSH Linux" /home/paulogoncalves/GoogleDrive_Pessoal/Organização/
fi

chown -R paulogoncalves:paulogoncalves /home/paulogoncalves

# 5. Criar cópia de trabalho do setup_popos.sh para o teste
TEST_SCRIPT_DIR="/home/paulogoncalves/test_run"
mkdir -p "$TEST_SCRIPT_DIR"
cp /workspace/setup_popos.sh "$TEST_SCRIPT_DIR/setup_popos.sh"
chown -R paulogoncalves:paulogoncalves "$TEST_SCRIPT_DIR"
chmod +x "$TEST_SCRIPT_DIR/setup_popos.sh"

echo "============================================================"
echo "▶️ [CONTAINER] Executando setup_popos.sh como paulogoncalves..."
echo "============================================================"

su - paulogoncalves -c "export PATH=/usr/local/mock-bin:\$PATH; export DEBIAN_FRONTEND=noninteractive; bash /home/paulogoncalves/test_run/setup_popos.sh"

echo ""
echo "============================================================"
echo "🔍 [CONTAINER] Verificando validações pós-instalação..."
echo "============================================================"

ERRORS=0

# Validar Antigravity
if [ -f "/opt/antigravity/antigravity-ide" ]; then
    echo "  ✅ /opt/antigravity/antigravity-ide existe."
else
    echo "  ❌ ERRO: /opt/antigravity/antigravity-ide não encontrado!"
    ERRORS=$((ERRORS + 1))
fi

if [ -L "/usr/local/bin/antigravity" ]; then
    echo "  ✅ /usr/local/bin/antigravity link simbólico criado."
else
    echo "  ❌ ERRO: /usr/local/bin/antigravity não encontrado!"
    ERRORS=$((ERRORS + 1))
fi

if [ -f "/usr/share/applications/antigravity.desktop" ]; then
    echo "  ✅ /usr/share/applications/antigravity.desktop criado."
else
    echo "  ❌ ERRO: /usr/share/applications/antigravity.desktop não encontrado!"
    ERRORS=$((ERRORS + 1))
fi

if [ -f "/usr/share/pixmaps/antigravity.png" ]; then
    echo "  ✅ /usr/share/pixmaps/antigravity.png ícone copiado."
else
    echo "  ❌ ERRO: /usr/share/pixmaps/antigravity.png não encontrado!"
    ERRORS=$((ERRORS + 1))
fi

# Validar Restauração de IDEs (VS Code & Antigravity)
if [ -f "/home/paulogoncalves/.config/Code/User/settings.json" ] && [ -f "/home/paulogoncalves/.config/Antigravity IDE/User/settings.json" ]; then
    echo "  ✅ Configurações das IDEs (VS Code e Antigravity IDE) restauradas com sucesso."
else
    echo "  ❌ ERRO: settings.json do VS Code ou Antigravity IDE não encontrado!"
    ERRORS=$((ERRORS + 1))
fi

# Validar Jellyfin
if [ -f "/etc/apt/sources.list.d/jellyfin.list" ]; then
    echo "  ✅ Repositório Jellyfin Server configurado em /etc/apt/sources.list.d/jellyfin.list."
else
    echo "  ❌ ERRO: Repositório Jellyfin Server não encontrado!"
    ERRORS=$((ERRORS + 1))
fi

if dpkg -l | grep -q jellyfin; then
    echo "  ✅ Pacote jellyfin instalado no sistema."
else
    echo "  ❌ ERRO: Pacote jellyfin não instalado!"
    ERRORS=$((ERRORS + 1))
fi

# Validar ZSH e Dotfiles
if [ -f "/home/paulogoncalves/.zshrc" ] && [ -f "/home/paulogoncalves/.p10k.zsh" ]; then
    echo "  ✅ Dotfiles do Zsh (.zshrc e .p10k.zsh) restaurados com sucesso na home."
else
    echo "  ❌ ERRO: Dotfiles do Zsh não encontrados na home do usuário!"
    ERRORS=$((ERRORS + 1))
fi

# Validar Flags de Estado
STATE_FILE="$TEST_SCRIPT_DIR/Logs/.setup_estado.log"
if [ -f "$STATE_FILE" ]; then
    echo "  ✅ Arquivo de estado gerado: $STATE_FILE"
    cat "$STATE_FILE"
else
    echo "  ❌ ERRO: Arquivo de estado não encontrado!"
    ERRORS=$((ERRORS + 1))
fi

if [ $ERRORS -eq 0 ]; then
    echo ""
    echo "============================================================"
    echo "🎉 [CONTAINER] TESTE FINALIZADO COM 100% DE SUCESSO!"
    echo "============================================================"
    exit 0
else
    echo ""
    echo "============================================================"
    echo "❌ [CONTAINER] TESTE FINALIZADO COM $ERRORS ERROS!"
    echo "============================================================"
    exit 1
fi
