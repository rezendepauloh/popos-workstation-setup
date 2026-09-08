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

# 2. Localização dos backups
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

# Lista backups disponíveis
mapfile -t BACKUPS < <(ls -td "$BACKUP_BASE_DIR"/android-backup-* 2>/dev/null || true)

if [ ${#BACKUPS[@]} -eq 0 ]; then
    echo -e "${C_RED}[!] Nenhuma pasta de backup encontrada em $BACKUP_BASE_DIR.${C_RESET}"
    exit 1
fi

echo -e "${C_BOLD}Selecione o backup que deseja restaurar:${C_RESET}"
for i in "${!BACKUPS[@]}"; do
    FOLDER_NAME=$(basename "${BACKUPS[$i]}")
    FOLDER_SIZE=$(du -sh "${BACKUPS[$i]}" 2>/dev/null | awk '{print $1}')
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
FOLDERS_TO_RESTORE=("DCIM" "Pictures" "Download" "Documents" "Movies" "Music" "Audiobooks" "Recordings" "Notifications" "Ringtones")

for FOLDER in "${FOLDERS_TO_RESTORE[@]}"; do
    SRC_PATH="$SELECTED_BACKUP/$FOLDER"
    if [ -d "$SRC_PATH" ] && [ "$(ls -A "$SRC_PATH" 2>/dev/null)" ]; then
        echo -e "${C_BOLD}Enviando $FOLDER para /sdcard/$FOLDER/...${C_RESET}"
        adb push "$SRC_PATH/." "/sdcard/$FOLDER/" 2>&1 | tr '\r' '\n' | tail -n 3 || true
        echo -e "${C_GREEN}[✓] $FOLDER restaurado com sucesso!${C_RESET}\n"
    fi
done

# Restauração especial do WhatsApp se desejado
if [ -d "$SELECTED_BACKUP/WhatsApp_Media/com.whatsapp" ]; then
    echo -e "${C_CYAN}Detectado backup local de mídia/bancos do WhatsApp.${C_RESET}"
    read -r -p "Deseja restaurar as mídias do WhatsApp para o celular agora? (s/N): " RESTORE_WA
    if [[ "$RESTORE_WA" =~ ^[sS]$ ]]; then
        echo -e "${C_BOLD}Criando diretório e enviando mídias do WhatsApp para /sdcard/Android/media/com.whatsapp/...${C_RESET}"
        adb shell mkdir -p /sdcard/Android/media/com.whatsapp
        adb push "$SELECTED_BACKUP/WhatsApp_Media/com.whatsapp/." "/sdcard/Android/media/com.whatsapp/" 2>&1 | tr '\r' '\n' | tail -n 3 || true
        echo -e "${C_GREEN}[✓] Mídia do WhatsApp restaurada!${C_RESET}\n"
    fi
fi

# Força o Android Media Scanner a reindexar a Galeria imediatamente
echo -e "${C_BOLD}Atualizando a Galeria de fotos e indexador de arquivos do Android...${C_RESET}"
adb shell "am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file:///sdcard/DCIM" >/dev/null 2>&1 || true
adb shell "am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file:///sdcard/Pictures" >/dev/null 2>&1 || true

echo -e "${C_GREEN}${C_BOLD}"
echo "=============================================================================="
echo "          🎉 RESTAURAÇÃO CONCLUÍDA COM SUCESSO NO CELULAR!                    "
echo "=============================================================================="
echo -e "${C_RESET}"
