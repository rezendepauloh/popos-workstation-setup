#!/bin/bash
# ==============================================================================
# Utilitário: Restauração de Arquivos e Mídias para Dispositivo Android via ADB
# ==============================================================================
# Envia de volta para a memória do celular (/sdcard/) as fotos, documentos,
# downloads, músicas e mídias previamente salvas pelo backup_android.sh.
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
echo "          📲 RESTAURAÇÃO DE DADOS PARA ANDROID (ADB HIGH-SPEED)               "
echo "=============================================================================="
echo -e "${C_RESET}"

# 1. Checa dependência do ADB
if ! command -v adb >/dev/null 2>&1; then
    echo -e "${C_RED}[!] ADB não encontrado no sistema.${C_RESET}"
    exit 1
fi

# 2. Localização dos backups e Logs
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOGS_DIR="$PROJECT_ROOT/Logs"
mkdir -p "$LOGS_DIR"

TIMESTAMP=$(date +"%d-%m-%Y_%H-%M-%S")
RESTORE_LOG_FILE="$LOGS_DIR/restore_android_$TIMESTAMP.log"

# Grava execução completa também no arquivo de log do sistema
exec > >(tee -a "$RESTORE_LOG_FILE") 2>&1

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

BACKUP_BASE_DIR=""
if [ -d "/mnt/storage_930/Backups_Android" ]; then
    BACKUP_BASE_DIR="/mnt/storage_930/Backups_Android"
elif [ -d "/mnt/storage_700/Backups_Android" ]; then
    BACKUP_BASE_DIR="/mnt/storage_700/Backups_Android"
elif [ -d "/mnt/nvme_01/Backups_Android" ]; then
    BACKUP_BASE_DIR="/mnt/nvme_01/Backups_Android"
else
    BACKUP_BASE_DIR="$HOME/Backups_Android"
fi

if [ ! -d "$BACKUP_BASE_DIR" ]; then
    echo -e "${C_RED}[!] Nenhum diretório de backups encontrado em $BACKUP_BASE_DIR.${C_RESET}"
    exit 1
fi

echo -e "${C_CYAN}📝 Arquivo de Log:${C_RESET} ${C_BOLD}$RESTORE_LOG_FILE${C_RESET}"
echo ""

# Lista backups disponíveis
mapfile -t BACKUPS < <(ls -td "$BACKUP_BASE_DIR"/android-backup-* 2>/dev/null || true)

if [ ${#BACKUPS[@]} -eq 0 ]; then
    echo -e "${C_RED}[!] Nenhuma pasta de backup encontrada em $BACKUP_BASE_DIR.${C_RESET}"
    exit 1
fi

echo -e "${C_BOLD}Selecione o backup que deseja restaurar:${C_RESET}"
for i in "${!BACKUPS[@]}"; do
    FOLDER_NAME=$(basename "${BACKUPS[$i]}")
    RAW_FOLDER_SIZE=$(du -sh "${BACKUPS[$i]}" 2>/dev/null | awk '{print $1}')
    FOLDER_SIZE=$(format_human_size "$RAW_FOLDER_SIZE")
    echo -e "  [$((i + 1))] $FOLDER_NAME ($FOLDER_SIZE)"
done

echo ""
read -r -p "Digite o número do backup desejado (padrão: 1 para o mais recente): " CHOICE
CHOICE=${CHOICE:-1}

INDEX=$((CHOICE - 1))
if [ "$INDEX" -lt 0 ] || [ "$INDEX" -ge "${#BACKUPS[@]}" ]; then
    echo -e "${C_RED}[!] Opção inválida.${C_RESET}"
    exit 1
fi

SELECTED_BACKUP="${BACKUPS[$INDEX]}"
echo -e "\n${C_GREEN}[✓] Backup selecionado:${C_RESET} ${C_BOLD}$SELECTED_BACKUP${C_RESET}\n"

# 3. Aguarda conexão ADB com o celular novo/formatado
echo -e "${C_YELLOW}[*] Conecte o celular formatado via cabo USB com Depuração USB ativada...${C_RESET}"
adb wait-for-device

DEVICE_MODEL=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r\n' || echo "Dispositivo_Android")
echo -e "${C_GREEN}[✓] Dispositivo Conectado:${C_RESET} ${C_BOLD}$DEVICE_MODEL${C_RESET}\n"

# 4. Processo de Envio das Pastas (adb push)
FOLDERS_TO_RESTORE=(
    "DCIM"
    "Pictures"
    "Download"
    "Documents"
    "Movies"
    "Music"
    "Audiobooks"
    "Podcasts"
    "Recordings"
    "VoiceRecorder"
    "Sounds"
    "Notifications"
    "Ringtones"
    "Alarms"
    "Telegram"
    "WhatsApp"
    "com.xiaomi.bluetooth"
    "MIUI"
)

# Função de monitoramento de envio (push) em tempo real
run_push_with_progress_monitor() {
    local src_folder="$1"
    local dest_target="$2"
    local log_file
    log_file=$(mktemp /tmp/adb_push_XXXXXX.log)

    local raw_folder_size
    raw_folder_size=$(du -sh "$src_folder" 2>/dev/null | awk '{print $1}' || echo "N/A")
    local folder_size
    folder_size=$(format_human_size "$raw_folder_size")

    # Pré-cria a árvore de subdiretórios no Android para evitar que o daemon MTP/FUSE
    # do Android falhe ao tentar criar arquivos dentro de pastas inexistentes
    find "$src_folder" -mindepth 1 -type d 2>/dev/null | while read -r local_sub; do
        rel_sub="${local_sub#$src_folder/}"
        adb shell mkdir -p "$dest_target/$rel_sub" >/dev/null 2>&1 || true
    done

    # Executa o comando adb push em segundo plano gravando saída em log
    adb push "$src_folder/." "$dest_target/" > "$log_file" 2>&1 &
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

        echo -ne "\r  ${C_CYAN}${spin[$spin_idx]}${C_RESET} ${C_BOLD}Enviando para o celular...${C_RESET} [⏱️ Tempo: ${time_formatted} | 📦 Tamanho do lote: ${folder_size}]    "
        spin_idx=$(( (spin_idx + 1) % 10 ))
        sleep 1
    done

    wait "$adb_pid" || true
    echo -ne "\r\033[K" # Limpa a linha do spinner

    # Exibe as linhas relevantes do log com grandezas de dados formatadas
    if [ -f "$log_file" ]; then
        while IFS= read -r line; do
            # Ignora erros conhecidos de cache transitório (.thumbnails/.nomedia) caso ocorram
            if [[ "$line" == *".thumbnails"* ]] && [[ "$line" == *"failed to copy"* ]]; then
                continue
            fi
            if [[ "$line" == *"failed to read copy response"* ]]; then
                continue
            fi
            [ -n "$line" ] && format_adb_output "$line"
        done < <(tail -n 6 "$log_file")
        rm -f "$log_file"
    fi
}

echo -e "${C_CYAN}🚀 Restaurando arquivos e mídias do usuário...${C_RESET}"
for FOLDER in "${FOLDERS_TO_RESTORE[@]}"; do
    SRC_PATH="$SELECTED_BACKUP/$FOLDER"
    if [ -d "$SRC_PATH" ] && [ "$(ls -A "$SRC_PATH" 2>/dev/null)" ]; then
        echo -e "${C_BOLD}Restaurando $FOLDER para /sdcard/$FOLDER/...${C_RESET}"
        adb shell mkdir -p "/sdcard/$FOLDER"
        run_push_with_progress_monitor "$SRC_PATH" "/sdcard/$FOLDER"
        echo -e "${C_GREEN}[✓] $FOLDER restaurado com sucesso!${C_RESET}\n"
    fi
done

# Restaurações especiais de Mensageiros (Android/media)
if [ -d "$SELECTED_BACKUP/WhatsApp_Media/com.whatsapp" ]; then
    echo -e "${C_CYAN}Detectado backup de mídia do WhatsApp moderno.${C_RESET}"
    read -r -p "Deseja restaurar as mídias do WhatsApp agora? (S/n): " RESTORE_WA
    RESTORE_WA=${RESTORE_WA:-S}
    if [[ "$RESTORE_WA" =~ ^[sS]$ ]]; then
        echo -e "${C_BOLD}Restaurando mídia para /sdcard/Android/media/com.whatsapp/...${C_RESET}"
        adb shell mkdir -p /sdcard/Android/media/com.whatsapp
        run_push_with_progress_monitor "$SELECTED_BACKUP/WhatsApp_Media/com.whatsapp" "/sdcard/Android/media/com.whatsapp"
        echo -e "${C_GREEN}[✓] Mídia do WhatsApp restaurada!${C_RESET}\n"
    fi
fi

if [ -d "$SELECTED_BACKUP/WhatsApp_Business_Media/com.whatsapp.w4b" ]; then
    echo -e "${C_CYAN}Detectado backup de mídia do WhatsApp Business.${C_RESET}"
    read -r -p "Deseja restaurar as mídias do WhatsApp Business agora? (S/n): " RESTORE_WAB
    RESTORE_WAB=${RESTORE_WAB:-S}
    if [[ "$RESTORE_WAB" =~ ^[sS]$ ]]; then
        echo -e "${C_BOLD}Restaurando mídia para /sdcard/Android/media/com.whatsapp.w4b/...${C_RESET}"
        adb shell mkdir -p /sdcard/Android/media/com.whatsapp.w4b
        run_push_with_progress_monitor "$SELECTED_BACKUP/WhatsApp_Business_Media/com.whatsapp.w4b" "/sdcard/Android/media/com.whatsapp.w4b"
        echo -e "${C_GREEN}[✓] Mídia do WhatsApp Business restaurada!${C_RESET}\n"
    fi
fi

if [ -d "$SELECTED_BACKUP/Telegram_Android_Media/org.telegram.messenger" ]; then
    echo -e "${C_CYAN}Detectado backup de mídia do Telegram moderno.${C_RESET}"
    read -r -p "Deseja restaurar as mídias do Telegram agora? (S/n): " RESTORE_TG
    RESTORE_TG=${RESTORE_TG:-S}
    if [[ "$RESTORE_TG" =~ ^[sS]$ ]]; then
        echo -e "${C_BOLD}Restaurando mídia para /sdcard/Android/media/org.telegram.messenger/...${C_RESET}"
        adb shell mkdir -p /sdcard/Android/media/org.telegram.messenger
        run_push_with_progress_monitor "$SELECTED_BACKUP/Telegram_Android_Media/org.telegram.messenger" "/sdcard/Android/media/org.telegram.messenger"
        echo -e "${C_GREEN}[✓] Mídia do Telegram restaurada!${C_RESET}\n"
    fi
fi

# 5. Reinstalação de Aplicativos em Lote (APKs extraídos)
if [ -d "$SELECTED_BACKUP/APKs" ] && [ "$(ls -A "$SELECTED_BACKUP/APKs" 2>/dev/null)" ]; then
    TOTAL_APKS=$(ls -1 "$SELECTED_BACKUP/APKs"/*.apk 2>/dev/null | wc -l)
    echo -e "${C_CYAN}📦 Detectados $TOTAL_APKS arquivos APK salvos neste backup.${C_RESET}"
    read -r -p "Deseja reinstalar todos esses aplicativos no aparelho agora via ADB? (S/n): " INSTALL_APPS
    INSTALL_APPS=${INSTALL_APPS:-S}
    
    if [[ "$INSTALL_APPS" =~ ^[sS]$ ]]; then
        echo -e "${C_YELLOW}[*] Dica: Se o celular pedir permissão de instalação na tela, aprove.${C_RESET}"
        CURRENT_APK=0
        for apk_file in "$SELECTED_BACKUP/APKs"/*.apk; do
            CURRENT_APK=$((CURRENT_APK + 1))
            APK_NAME=$(basename "$apk_file")
            echo -ne "  [$CURRENT_APK/$TOTAL_APKS] Instalando $APK_NAME... \r"
            adb install -r -d "$apk_file" >/dev/null 2>&1 || true
        done
        echo -e "\n${C_GREEN}[✓] Processo de instalação de APKs finalizado!${C_RESET}\n"
    fi
elif [ -f "$SELECTED_BACKUP/lista_aplicativos_instalados.txt" ]; then
    echo -e "${C_CYAN}ℹ️  Lista de apps instalados disponível em: $SELECTED_BACKUP/lista_aplicativos_instalados.txt${C_RESET}"
fi

# 6. Força o Android Media Scanner a reindexar todo o armazenamento interno
echo -e "${C_BOLD}🔄 Atualizando a Galeria de fotos, biblioteca de músicas e arquivos do Android...${C_RESET}"
adb shell "find /sdcard/ -maxdepth 2 -type d 2>/dev/null" | while read -r dir; do
    [ -n "$dir" ] && adb shell "am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file://$dir" >/dev/null 2>&1 || true
done

echo -e "${C_GREEN}${C_BOLD}"
echo "=============================================================================="
echo "          🎉 RESTAURAÇÃO CONCLUÍDA COM SUCESSO NO CELULAR!                    "
echo "=============================================================================="
echo -e "${C_RESET}"
echo -e "  📲 ${C_BOLD}Arquivos e Mídias:${C_RESET} Enviados de volta para /sdcard/"
echo -e "  🔄 ${C_BOLD}Indexador de Mídia:${C_RESET} Executado (suas fotos, vídeos e áudios já aparecem nos apps)"
echo ""

