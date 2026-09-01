#!/bin/bash
# ==============================================================================
# Script de Provisionamento & Pós-Instalação: Pop!_OS 24.04 LTS (COSMIC) - V2
# Orquestrador Modular Desacoplado
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/00_comum.sh"

# Banner Visual
echo -e "${C_CYAN}${C_BOLD}"
cat << "EOF"
================================================================================
          🚀 POP!_OS 24.04 LTS (COSMIC) - POST-INSTALL SETUP V2 🚀
                     Automação Modular & Desacoplada
================================================================================
EOF
echo -e "${C_RESET}"

# Tratamento de Flags Informativas (sem necessidade de sudo)
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo -e "${C_BOLD}Uso:${C_RESET}"
    echo "  sudo ./setup_popos_v2.sh            # Executa todo o provisionamento sequencialmente"
    echo "  sudo ./setup_popos_v2.sh --force    # Limpa checkpoints e força reexecução completa"
    echo "  ./setup_popos_v2.sh --list          # Lista todos os módulos disponíveis"
    echo "  sudo ./setup_popos_v2.sh <modulo>   # Executa apenas um módulo específico (ex: 02 ou 12)"
    echo ""
    exit 0
fi

if [ "$1" == "--list" ] || [ "$1" == "-l" ]; then
    echo -e "${C_BOLD}Módulos disponíveis em scripts/:${C_RESET}"
    for script in "$SCRIPTS_DIR"/[0-9][0-9]_*.sh; do
        if [ -f "$script" ]; then
            name=$(basename "$script")
            desc=$(grep -m 1 "^# Módulo " "$script" | sed 's/^# Módulo [0-9]*: //')
            printf "  ${C_CYAN}%-32s${C_RESET} %s\n" "$name" "$desc"
        fi
    done
    echo ""
    exit 0
fi

# Verificação de privilégios sudo inicial
if [ "$(id -u)" -ne 0 ]; then
    log_msg "INFO" "Solicitando credenciais de administrador (sudo)..."
    sudo -v
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
fi

if [ "$1" == "--force" ] || [ "$1" == "-f" ]; then
    log_msg "WARN" "Limpando arquivo de progresso (.setup_progress.log) para reexecução completa..."
    rm -f "$PROGRESS_LOG"
    shift
fi

# Execução de um módulo individual via argumento
if [ -n "$1" ]; then
    TARGET_MOD="$1"
    MATCHED_SCRIPT=""
    for script in "$SCRIPTS_DIR"/[0-9][0-9]_*.sh; do
        base=$(basename "$script")
        if [[ "$base" == "$TARGET_MOD"* ]] || [[ "$base" == *"$TARGET_MOD"* ]]; then
            MATCHED_SCRIPT="$script"
            break
        fi
    done

    if [ -n "$MATCHED_SCRIPT" ] && [ -f "$MATCHED_SCRIPT" ]; then
        log_msg "INFO" "Executando módulo isolado: $(basename "$MATCHED_SCRIPT")..."
        bash "$MATCHED_SCRIPT"
        exit 0
    else
        log_msg "ERROR" "Módulo '$TARGET_MOD' não encontrado. Use './setup_popos_v2.sh --list' para ver as opções."
        exit 1
    fi
fi

# Trap de Erro Global
trap 'log_msg "ERROR" "❌ Ocorreu um erro no script $CURRENT_SCRIPT na linha $LINENO. Execução interrompida."; exit 1' ERR

START_TIME=$(date +%s)

# Execução Sequencial de Todos os Módulos
MODULES=(
    "01_otimizacao_sistema.sh"
    "02_teclado_cedilha_numlock.sh"
    "03_atualizacao_sistema.sh"
    "04_pacotes_base_dev.sh"
    "05_rclone_storage.sh"
    "06_softwares_workflow.sh"
    "07_powershell7.sh"
    "08_antigravity_ide.sh"
    "09_onlyoffice_padrao.sh"
    "10_cosmic_music_applet.sh"
    "11_mouse_gaming.sh"
    "12_wacom_tablet.sh"
    "13_kando_restore.sh"
    "14_cosmic_restore.sh"
    "15_ide_config_restore.sh"
    "16_zsh_p10k_setup.sh"
    "17_jogos_performance.sh"
    "18_flatpak_permissions.sh"
    "19_manutencao_ssds.sh"
    "20_autostart_config.sh"
    "21_limpeza_otimizacao.sh"
)

TOTAL_MODULES=${#MODULES[@]}
CURRENT_INDEX=0

for mod in "${MODULES[@]}"; do
    CURRENT_INDEX=$((CURRENT_INDEX + 1))
    CURRENT_SCRIPT="$SCRIPTS_DIR/$mod"
    
    if [ -f "$CURRENT_SCRIPT" ]; then
        echo -e "\n${C_BLUE}${C_BOLD}[$CURRENT_INDEX/$TOTAL_MODULES] Executando: $mod${C_RESET}"
        bash "$CURRENT_SCRIPT"
    else
        log_msg "WARN" "Módulo $mod não encontrado em scripts/. Pulando..."
    fi
done

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECONDS=$((ELAPSED % 60))

echo -e "\n${C_GREEN}${C_BOLD}================================================================================${C_RESET}"
echo -e "${C_GREEN}${C_BOLD} 🎉 PROVISIONAMENTO POP!_OS V2 CONCLUÍDO COM SUCESSO! (${MINUTES}m ${SECONDS}s) 🎉${C_RESET}"
echo -e "${C_GREEN}${C_BOLD}================================================================================${C_RESET}"
echo -e "${C_CYAN}ℹ️  Recomenda-se reiniciar a sessão ou o computador para carregar todos os serviços e drivers.${C_RESET}\n"
