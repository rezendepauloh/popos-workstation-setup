#!/bin/bash
# ==============================================================================
# Módulo 08: Associação do OnlyOffice como Leitor Padrão de Documentos
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="ONLYOFFICE_DEFAULT"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  OnlyOffice já definido como padrão anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "8. DEFININDO ONLYOFFICE COMO APLICATIVO PADRÃO"

# 1. Associa arquivos .docx, .xlsx e .pptx ao OnlyOffice
if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    sudo -u "$REAL_USER" xdg-mime default org.onlyoffice.desktopeditors.desktop application/vnd.openxmlformats-officedocument.wordprocessingml.document 2>/dev/null || true
    sudo -u "$REAL_USER" xdg-mime default org.onlyoffice.desktopeditors.desktop application/vnd.openxmlformats-officedocument.spreadsheetml.sheet 2>/dev/null || true
    sudo -u "$REAL_USER" xdg-mime default org.onlyoffice.desktopeditors.desktop application/vnd.openxmlformats-officedocument.presentationml.presentation 2>/dev/null || true
else
    xdg-mime default org.onlyoffice.desktopeditors.desktop application/vnd.openxmlformats-officedocument.wordprocessingml.document 2>/dev/null || true
    xdg-mime default org.onlyoffice.desktopeditors.desktop application/vnd.openxmlformats-officedocument.spreadsheetml.sheet 2>/dev/null || true
    xdg-mime default org.onlyoffice.desktopeditors.desktop application/vnd.openxmlformats-officedocument.presentationml.presentation 2>/dev/null || true
fi

# 2. Associa o Nautilus (GNOME Files) como gerenciador de pastas/diretórios padrão (inode/directory)
log_msg "INFO" "Definindo Nautilus como gerenciador de arquivos padrão (inode/directory)..."
if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    sudo -u "$REAL_USER" xdg-mime default org.gnome.Nautilus.desktop inode/directory 2>/dev/null || true
    sudo -u "$REAL_USER" gio mime inode/directory org.gnome.Nautilus.desktop 2>/dev/null || true
else
    xdg-mime default org.gnome.Nautilus.desktop inode/directory 2>/dev/null || true
    gio mime inode/directory org.gnome.Nautilus.desktop 2>/dev/null || true
fi

# Persistência garantida no mimeapps.list do usuário
mkdir -p "$REAL_HOME/.config"
MIMEAPPS_CONF="$REAL_HOME/.config/mimeapps.list"
if [ -f "$MIMEAPPS_CONF" ]; then
    if grep -q "inode/directory=" "$MIMEAPPS_CONF"; then
        sed -i 's|^inode/directory=.*|inode/directory=org.gnome.Nautilus.desktop|g' "$MIMEAPPS_CONF"
    else
        sed -i '/\[Default Applications\]/a inode/directory=org.gnome.Nautilus.desktop' "$MIMEAPPS_CONF"
    fi
fi
chown "$REAL_USER:$REAL_USER" "$MIMEAPPS_CONF" 2>/dev/null || true

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Aplicativos padrão configurados com sucesso (OnlyOffice para docs, Nautilus para pastas)."
