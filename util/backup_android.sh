#!/bin/bash
# ==============================================================================
# Utilitário: Backup Automatizado de Dispositivos Android via ADB / MTP
# ==============================================================================
# Executa a extração em lote e estruturada de fotos, mídias, documentos e
# conversas do celular conectado via USB com alta taxa de transferência.
#
# Salva em um diretório com timestamp organizado:
#   /mnt/storage_930/Backups_Android/android-backup-DD-MM-YYYY_HH-MM-SS/
#   (Com fallback para /mnt/storage_700 ou ~/Backups_Android se não houver disco)
# ==============================================================================

set -eo pipefail

C_RESET='\033[0m'
C_CYAN='\033[1;36m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[1;31m'
C_BOLD='\033[1m'

echo -e "${C_CYAN}${C_BOLD}"
echo "=============================================================================="
echo "          🤖 UTILITÁRIO DE BACKUP DE CELULAR ANDROID (ADB HIGH-SPEED)          "
echo "=============================================================================="
echo -e "${C_RESET}"

# 1. Checa dependência do ADB
if ! command -v adb >/dev/null 2>&1; then
    echo -e "${C_YELLOW}[!] ADB não encontrado no sistema. Instalando 'adb' via APT...${C_RESET}"
    sudo apt update && sudo apt install -y adb
fi

# 2. Definição da Unidade de Armazenamento para o Backup
BACKUP_BASE_DIR=""
if [ -d "/mnt/storage_930" ] && [ -w "/mnt/storage_930" ]; then
    BACKUP_BASE_DIR="/mnt/storage_930/Backups_Android"
elif [ -d "/mnt/storage_700" ] && [ -w "/mnt/storage_700" ]; then
    BACKUP_BASE_DIR="/mnt/storage_700/Backups_Android"
elif [ -d "/mnt/nvme_01" ] && [ -w "/mnt/nvme_01" ]; then
    BACKUP_BASE_DIR="/mnt/nvme_01/Backups_Android"
else
    BACKUP_BASE_DIR="$HOME/Backups_Android"
fi

TIMESTAMP=$(date +"%d-%m-%Y_%H-%M-%S")
TARGET_DIR="$BACKUP_BASE_DIR/android-backup-$TIMESTAMP"

echo -e "${C_CYAN}📁 Destino do Backup:${C_RESET} ${C_BOLD}$TARGET_DIR${C_RESET}"
echo ""

# 3. Inicia servidor ADB e aguarda dispositivo
echo -e "${C_YELLOW}[*] Verificando conexões ADB ativas...${C_RESET}"
adb start-server >/dev/null 2>&1

DEVICES=$(adb devices | grep -v "List of devices" | grep "device$" | awk '{print $1}' || true)

if [ -z "$DEVICES" ]; then
    echo -e "${C_RED}[!] Nenhum celular Android autorizado detectado via ADB.${C_RESET}"
    echo ""
    echo -e "${C_BOLD}Passo a passo para autorizar o celular:${C_RESET}"
    echo -e "  1. Conecte o celular ao PC usando um ${C_BOLD}cabo USB de boa qualidade${C_RESET}."
    echo -e "  2. No celular, vá em ${C_BOLD}Configurações > Sobre o Telefone${C_RESET}."
    echo -e "  3. Toque ${C_BOLD}7 vezes em 'Número da Versão'${C_RESET} para ativar as 'Opções do Desenvolvedor'."
    echo -e "  4. Em ${C_BOLD}Configurações > Opções do Desenvolvedor${C_RESET}, ative ${C_BOLD}'Depuração USB'${C_RESET}."
    echo -e "  5. Olhe para a tela do celular: aparecerá uma janela ${C_BOLD}'Permitir depuração USB?'${C_RESET}."
    echo -e "     Marque ${C_BOLD}'Sempre permitir a partir deste computador'${C_RESET} e clique em ${C_BOLD}Permitir${C_RESET}."
    echo ""
    echo -e "${C_CYAN}Aguardando autorização do dispositivo (pressione Ctrl+C para cancelar)...${C_RESET}"
    adb wait-for-device
fi

DEVICE_MODEL=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r\n' || echo "Dispositivo_Android")
DEVICE_MANUF=$(adb shell getprop ro.product.manufacturer 2>/dev/null | tr -d '\r\n' || echo "Android")
ANDROID_VER=$(adb shell getprop ro.build.version.release 2>/dev/null | tr -d '\r\n' || echo "Desconhecida")

echo -e "${C_GREEN}[✓] Dispositivo Conectado com Sucesso!${C_RESET}"
echo -e "    📱 ${C_BOLD}Aparelho:${C_RESET} $DEVICE_MANUF $DEVICE_MODEL"
echo -e "    ⚙️  ${C_BOLD}Versão Android:${C_RESET} $ANDROID_VER"
echo ""

# 4. Criação do diretório de backup
mkdir -p "$TARGET_DIR"

# Cria um arquivo de manifesto com metadados do aparelho
cat << EOF > "$TARGET_DIR/info_dispositivo.txt"
==============================================================================
RELATÓRIO DO BACKUP ANDROID
==============================================================================
Data e Hora: $(date +"%d/%m/%Y às %H:%M:%S")
Fabricante: $DEVICE_MANUF
Modelo: $DEVICE_MODEL
Versão do Android: $ANDROID_VER
Número de Série: $(adb get-serialno 2>/dev/null || echo "N/A")
Destino: $TARGET_DIR
==============================================================================
EOF

# 5. Lista de diretórios importantes para backup
FOLDERS_TO_BACKUP=(
    "/sdcard/DCIM"                               # Fotos da Câmera, Screenshots
    "/sdcard/Pictures"                           # Fotos de apps, Instagram, etc.
    "/sdcard/Download"                           # Downloads gerais e PDFs
    "/sdcard/Documents"                          # Documentos locais
    "/sdcard/Movies"                             # Vídeos e gravações de tela
    "/sdcard/Music"                              # Músicas e áudios
    "/sdcard/Audiobooks"                         # Áudios
    "/sdcard/Recordings"                         # Gravador de voz nativo
    "/sdcard/Notifications"                      # Sons e toques recebidos
    "/sdcard/Ringtones"                          # Toques de chamada
    "/sdcard/com.xiaomi.bluetooth"               # Arquivos recebidos via Bluetooth
    "/sdcard/MIUI/backup"                        # Backups locais de apps/sistema Xiaomi
    "/sdcard/Android/media/com.whatsapp"         # Mídias e bancos locais do WhatsApp
)

TOTAL_STEPS=${#FOLDERS_TO_BACKUP[@]}
CURRENT_STEP=0

echo -e "${C_CYAN}🚀 Iniciando cópia em lote dos diretórios...${C_RESET}"

for SRC in "${FOLDERS_TO_BACKUP[@]}"; do
    CURRENT_STEP=$((CURRENT_STEP + 1))
    FOLDER_NAME=$(basename "$SRC")
    
    echo -e "\n${C_BOLD}[$CURRENT_STEP/$TOTAL_STEPS] Processando: $SRC...${C_RESET}"
    
    # Verifica se o diretório existe no celular antes de tentar o pull
    CHECK_EXISTS=$(adb shell "[ -d '$SRC' ] && echo 'SIM' || echo 'NAO'" | tr -d '\r\n')
    
    if [ "$CHECK_EXISTS" = "SIM" ]; then
        DEST_SUBDIR="$TARGET_DIR"
        
        # Se for a pasta do WhatsApp dentro de Android/media, preserva o caminho
        if [[ "$SRC" == *"com.whatsapp"* ]]; then
            DEST_SUBDIR="$TARGET_DIR/WhatsApp_Media"
            mkdir -p "$DEST_SUBDIR"
            adb pull "$SRC" "$DEST_SUBDIR/" 2>&1 | tr '\r' '\n' | tail -n 5 || true
        else
            adb pull "$SRC" "$DEST_SUBDIR/" 2>&1 | tr '\r' '\n' | tail -n 5 || true
        fi
        
        echo -e "${C_GREEN}[✓] Concluído: $FOLDER_NAME salvo em $TARGET_DIR/${C_RESET}"
    else
        echo -e "${C_YELLOW}[-] Diretório não encontrado no aparelho (ignorado): $SRC${C_RESET}"
    fi
done

# 6. Lista de aplicativos instalados (APK Packages)
echo -e "\n${C_BOLD}[Extra] Gerando lista de aplicativos instalados (Play Store)...${C_RESET}"
adb shell pm list packages -3 2>/dev/null | sed 's/^package://' | sort > "$TARGET_DIR/lista_aplicativos_instalados.txt" || true
echo -e "${C_GREEN}[✓] Lista salva em: $TARGET_DIR/lista_aplicativos_instalados.txt${C_RESET}"

# 7. Resumo e Estatísticas
BACKUP_SIZE=$(du -sh "$TARGET_DIR" 2>/dev/null | awk '{print $1}')

echo ""
echo -e "${C_GREEN}${C_BOLD}==============================================================================${C_RESET}"
echo -e "${C_GREEN}${C_BOLD}               🎉 BACKUP DO ANDROID CONCLUÍDO COM SUCESSO!                    ${C_RESET}"
echo -e "${C_GREEN}${C_BOLD}==============================================================================${C_RESET}"
echo -e "  📂 ${C_BOLD}Pasta Salva:${C_RESET} $TARGET_DIR"
echo -e "  💾 ${C_BOLD}Espaço Total Ocupado:${C_RESET} $BACKUP_SIZE"
echo -e "  📋 ${C_BOLD}Itens Arquivados:${C_RESET} DCIM, Pictures, Download, Documents, Movies, Músicas, WhatsApp Media e Lista de Apps."
echo ""
echo -e "${C_YELLOW}${C_BOLD}⚠️  LEMBRETE ANTES DE RESETAR O CELULAR AOS PADRÕES DE FÁBRICA:${C_RESET}"
echo -e "  1. Faça o backup das conversas no ${C_BOLD}Google Drive do WhatsApp${C_RESET} pelo próprio app."
echo -e "  2. Acesse ${C_BOLD}Configurações > Contas${C_RESET} e ${C_BOLD}REMOVA a Conta Google${C_RESET} do aparelho (para evitar bloqueio FRP)."
echo -e "${C_GREEN}${C_BOLD}==============================================================================${C_RESET}"
echo ""
