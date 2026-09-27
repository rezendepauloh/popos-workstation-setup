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

# 2. Definição dos Diretórios de Armazenamento e Logs
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOGS_DIR="$PROJECT_ROOT/Logs"
mkdir -p "$LOGS_DIR"

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
BACKUP_LOG_FILE="$LOGS_DIR/backup_android_$TIMESTAMP.log"

# Grava execução completa também no arquivo de log do sistema
exec > >(tee -a "$BACKUP_LOG_FILE") 2>&1

# Funções auxiliares para formatação de dados em grandezas humanas (GB, MB, KB, bytes)
format_human_size() {
    local raw="$1"
    python3 -c "
import sys, re
s = '''$raw'''.strip()
m = re.match(r'^([\d,\.]+)\s*([KMGTkmgt])(?:[iI]?[bB])?$', s)
if m:
    print(f'{m.group(1)} {m.group(2).upper()}B')
else:
    print(s)
" 2>/dev/null || echo "$raw"
}

format_adb_output() {
    local text="$1"
    python3 -c "
import sys, re
line = '''$text'''
def repl_bytes(m):
    b = float(m.group(1))
    sec = m.group(2)
    for u in ['bytes', 'KB', 'MB', 'GB', 'TB']:
        if b < 1024.0 or u == 'TB':
            if u == 'bytes':
                return f'({int(b)} bytes in {sec}s)'
            return f'({b:.1f} {u} in {sec}s)'
        b /= 1024.0
print(re.sub(r'\((\d+)\s+bytes\s+in\s+([\d\.]+)s\)', repl_bytes, line))
" 2>/dev/null || echo "$text"
}

echo -e "${C_CYAN}📁 Destino do Backup:${C_RESET} ${C_BOLD}$TARGET_DIR${C_RESET}"
echo -e "${C_CYAN}📝 Arquivo de Log:${C_RESET} ${C_BOLD}$BACKUP_LOG_FILE${C_RESET}"
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
    "/sdcard/Podcasts"                           # Podcasts baixados
    "/sdcard/Recordings"                         # Gravador de voz nativo
    "/sdcard/VoiceRecorder"                      # Gravador de voz alternativo (Samsung/LG)
    "/sdcard/Sounds"                             # Sons e gravações
    "/sdcard/Notifications"                      # Sons e toques recebidos
    "/sdcard/Ringtones"                          # Toques de chamada
    "/sdcard/Alarms"                             # Sons de alarme personalizados
    "/sdcard/com.xiaomi.bluetooth"               # Arquivos recebidos via Bluetooth
    "/sdcard/MIUI/backup"                        # Backups locais de apps/sistema Xiaomi
    "/sdcard/WhatsApp"                           # WhatsApp legado (Databases/msgstore e Backups)
    "/sdcard/Telegram"                           # Mídias salvas do Telegram
    "/sdcard/Android/media/com.whatsapp"         # Mídias do WhatsApp moderno
    "/sdcard/Android/media/com.whatsapp.w4b"     # WhatsApp Business
    "/sdcard/Android/media/org.telegram.messenger" # Telegram oficial
)

TOTAL_STEPS=${#FOLDERS_TO_BACKUP[@]}
CURRENT_STEP=0

echo -e "${C_CYAN}🚀 Iniciando cópia em lote dos diretórios de mídia e arquivos...${C_RESET}"

# Função de monitoramento de cópia em tempo real
run_with_progress_monitor() {
    local cmd=("$@")
    local watch_dir="${cmd[-1]}" # O destino é sempre o último argumento
    local log_file
    log_file=$(mktemp /tmp/adb_transfer_XXXXXX.log)

    # Executa o comando adb em segundo plano gravando saída em log
    "${cmd[@]}" > "$log_file" 2>&1 &
    local adb_pid=$!

    local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local spin_idx=0
    local start_sec=$SECONDS

    # Loop de feedback visual enquanto o processo ADB estiver ativo
    while kill -0 "$adb_pid" 2>/dev/null; do
        local elapsed=$(( SECONDS - start_sec ))
        local mins=$(( elapsed / 60 ))
        local secs=$(( elapsed % 60 ))
        local time_formatted
        printf -v time_formatted "%02d:%02d" "$mins" "$secs"

        local current_size="0B"
        if [ -d "$watch_dir" ]; then
            current_size=$(du -sh "$watch_dir" 2>/dev/null | awk '{print $1}' || echo "0B")
        fi

        echo -ne "\r  ${C_CYAN}${spin[$spin_idx]}${C_RESET} ${C_BOLD}Transferindo...${C_RESET} [⏱️ Tempo: ${time_formatted} | 💾 No destino: ${current_size}]    "
        spin_idx=$(( (spin_idx + 1) % 10 ))
        sleep 1
    done

    wait "$adb_pid" || true
    echo -ne "\r\033[K" # Limpa a linha do spinner

    # Exibe as últimas linhas do log do ADB com grandezas de dados formatadas
    if [ -f "$log_file" ]; then
        while IFS= read -r line; do
            [ -n "$line" ] && format_adb_output "$line"
        done < <(tail -n 5 "$log_file")
        rm -f "$log_file"
    fi
}

for SRC in "${FOLDERS_TO_BACKUP[@]}"; do
    CURRENT_STEP=$((CURRENT_STEP + 1))
    FOLDER_NAME=$(basename "$SRC")
    
    echo -e "\n${C_BOLD}[$CURRENT_STEP/$TOTAL_STEPS] Processando: $SRC...${C_RESET}"
    
    # Verifica se o diretório existe no celular antes de tentar o pull
    CHECK_EXISTS=$(adb shell "[ -d '$SRC' ] && echo 'SIM' || echo 'NAO'" | tr -d '\r\n')
    
    if [ "$CHECK_EXISTS" = "SIM" ]; then
        DEST_SUBDIR="$TARGET_DIR"
        
        # Mapeamentos organizados para pastas especiais
        if [[ "$SRC" == *"com.whatsapp.w4b"* ]]; then
            DEST_SUBDIR="$TARGET_DIR/WhatsApp_Business_Media"
            mkdir -p "$DEST_SUBDIR"
            run_with_progress_monitor adb pull "$SRC" "$DEST_SUBDIR/"
        elif [[ "$SRC" == *"com.whatsapp"* ]]; then
            DEST_SUBDIR="$TARGET_DIR/WhatsApp_Media"
            mkdir -p "$DEST_SUBDIR"
            run_with_progress_monitor adb pull "$SRC" "$DEST_SUBDIR/"
        elif [[ "$SRC" == *"org.telegram.messenger"* ]]; then
            DEST_SUBDIR="$TARGET_DIR/Telegram_Android_Media"
            mkdir -p "$DEST_SUBDIR"
            run_with_progress_monitor adb pull "$SRC" "$DEST_SUBDIR/"
        else
            run_with_progress_monitor adb pull "$SRC" "$DEST_SUBDIR/"
        fi
        
        RAW_SIZE=$(du -sh "$DEST_SUBDIR/$FOLDER_NAME" 2>/dev/null | awk '{print $1}' || echo "")
        FINAL_SIZE=$(format_human_size "$RAW_SIZE")
        [ -n "$FINAL_SIZE" ] && FINAL_SIZE=" ($FINAL_SIZE)"
        echo -e "${C_GREEN}[✓] Concluído: $FOLDER_NAME salvo em $DEST_SUBDIR/${FINAL_SIZE}${C_RESET}"
    else
        echo -e "${C_YELLOW}[-] Diretório não encontrado no aparelho (ignorado): $SRC${C_RESET}"
    fi
done

# 6. Lista de aplicativos e Extração de APKs
echo -e "\n${C_BOLD}[Extra] Gerando lista de aplicativos instalados (Play Store / Terceiros)...${C_RESET}"
PACKAGES=$(adb shell pm list packages -3 2>/dev/null | sed 's/^package://' | tr -d '\r' | sort || true)
echo "$PACKAGES" > "$TARGET_DIR/lista_aplicativos_instalados.txt"
TOTAL_APPS=$(echo "$PACKAGES" | grep -c . || true)
echo -e "${C_GREEN}[✓] Lista com $TOTAL_APPS aplicativos salva em: $TARGET_DIR/lista_aplicativos_instalados.txt${C_RESET}"

# Extração dos instaladores reais (.apk) dos aplicativos de usuário
echo ""
read -r -p "Deseja também extrair e salvar os instaladores APK de todos esses apps para reinstalação automática offline? (S/n): " EXTRACT_APKS
EXTRACT_APKS=${EXTRACT_APKS:-S}

if [[ "$EXTRACT_APKS" =~ ^[sS]$ ]]; then
    APK_DIR="$TARGET_DIR/APKs"
    mkdir -p "$APK_DIR"
    echo -e "${C_CYAN}📦 Extraindo APKs para $APK_DIR...${C_RESET}"
    
    IDX=0
    while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue
        IDX=$((IDX + 1))
        echo -ne "  [${IDX}/${TOTAL_APPS}] Extraindo $pkg... \r"
        
        # Obtém o caminho do base.apk
        APK_PATH=$(adb shell pm path "$pkg" 2>/dev/null | head -n 1 | sed 's/^package://' | tr -d '\r')
        if [ -n "$APK_PATH" ]; then
            adb pull "$APK_PATH" "$APK_DIR/${pkg}.apk" >/dev/null 2>&1 || true
        fi
    done <<< "$PACKAGES"
    echo -e "\n${C_GREEN}[✓] Extração de APKs concluída com sucesso em: $APK_DIR${C_RESET}"
fi

# 7. Resumo e Estatísticas
BACKUP_RAW_SIZE=$(du -sh "$TARGET_DIR" 2>/dev/null | awk '{print $1}')
BACKUP_SIZE=$(format_human_size "$BACKUP_RAW_SIZE")

echo ""
echo -e "${C_GREEN}${C_BOLD}==============================================================================${C_RESET}"
echo -e "${C_GREEN}${C_BOLD}               🎉 BACKUP DO ANDROID CONCLUÍDO COM SUCESSO!                    ${C_RESET}"
echo -e "${C_GREEN}${C_BOLD}==============================================================================${C_RESET}"
echo -e "  📂 ${C_BOLD}Pasta Salva:${C_RESET} $TARGET_DIR"
echo -e "  💾 ${C_BOLD}Espaço Total Ocupado:${C_RESET} $BACKUP_SIZE"
echo -e "  📋 ${C_BOLD}Itens Arquivados:${C_RESET} DCIM, Pictures, Download, Documents, Movies, Músicas, Mensageiros e Lista/APKs de Apps."
echo ""
echo -e "${C_YELLOW}${C_BOLD}⚠️  LEMBRETE ANTES DE RESETAR O CELULAR AOS PADRÕES DE FÁBRICA:${C_RESET}"
echo -e "  1. Faça o backup das conversas no ${C_BOLD}Google Drive do WhatsApp${C_RESET} pelo próprio app."
echo -e "  2. Acesse ${C_BOLD}Configurações > Contas${C_RESET} e ${C_BOLD}REMOVA a Conta Google${C_RESET} do aparelho (para evitar bloqueio FRP)."
echo -e "  3. Para senhas e logins em apps: verifique se estão sincronizados no ${C_BOLD}Gerenciador de Senhas do Google / Bitwarden${C_RESET}."
echo -e "${C_GREEN}${C_BOLD}==============================================================================${C_RESET}"
echo ""

