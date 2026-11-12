#!/bin/bash
# ==============================================================================
# Módulo 09: Associação do ArtCraft Suite (WordCraft, GridCraft, DeckCraft) como Padrão
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="OFFICE_DEFAULTS_ARTCRAFT"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  ArtCraft Suite já definido como suíte office padrão. Pulando..."
    exit 0
fi

log_msg "HEADER" "09. DEFININDO ARTCRAFT SUITE COMO APLICATIVO PADRÃO (OFFICE & NAUTILUS)"

# 1. Garantir symlinks para GridCraft e DeckCraft em ~/.local/bin
log_msg "INFO" "Configurando executáveis e atalhos da suíte ArtCraft..."
mkdir -p "$REAL_HOME/.local/bin" "$REAL_HOME/.local/share/applications"

if [ -f "$REAL_HOME/Applications/gridcraft-0.19.1-linux-x86_64.AppImage" ]; then
    ln -sfn "$REAL_HOME/Applications/gridcraft-0.19.1-linux-x86_64.AppImage" "$REAL_HOME/.local/bin/gridcraft"
fi
if [ -f "$REAL_HOME/Applications/deckcraft-0.18.1-linux-x86_64.AppImage" ]; then
    ln -sfn "$REAL_HOME/Applications/deckcraft-0.18.1-linux-x86_64.AppImage" "$REAL_HOME/.local/bin/deckcraft"
fi

# 2. Assegurar definições .desktop de GridCraft e DeckCraft com suporte a MIME Types
cat << 'EOF' > "$REAL_HOME/.local/share/applications/ai.storyteller.gridcraft.desktop"
[Desktop Entry]
Type=Application
Name=GridCraft
GenericName=Spreadsheet
Comment=Spreadsheets and data; open and save Excel files
Exec=/home/rezendepauloh/.local/bin/gridcraft %F
TryExec=/home/rezendepauloh/.local/bin/gridcraft
Icon=ai.storyteller.gridcraft
Terminal=false
Categories=Office;Spreadsheet;
StartupWMClass=ai.storyteller.gridcraft
Keywords=spreadsheet;excel;xlsx;csv;table;data;calc;
MimeType=application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;application/vnd.ms-excel;application/vnd.oasis.opendocument.spreadsheet;text/csv;application/vnd.openxmlformats-officedocument.spreadsheetml.template;application/vnd.ms-excel.sheet.macroEnabled.12;application/vnd.ms-excel.template.macroEnabled.12;text/tab-separated-values;
X-ArtCraft-Launcher=true
EOF

cat << 'EOF' > "$REAL_HOME/.local/share/applications/ai.storyteller.deckcraft.desktop"
[Desktop Entry]
Type=Application
Name=DeckCraft
GenericName=Presentation
Comment=Presentations and slide shows; open and save PowerPoint files
Exec=/home/rezendepauloh/.local/bin/deckcraft %F
TryExec=/home/rezendepauloh/.local/bin/deckcraft
Icon=ai.storyteller.deckcraft
Terminal=false
Categories=Office;Presentation;
StartupWMClass=ai.storyteller.deckcraft
Keywords=presentation;powerpoint;pptx;slides;show;impress;
MimeType=application/vnd.openxmlformats-officedocument.presentationml.presentation;application/vnd.ms-powerpoint;application/vnd.oasis.opendocument.presentation;application/vnd.openxmlformats-officedocument.presentationml.slideshow;application/vnd.openxmlformats-officedocument.presentationml.template;application/vnd.ms-powerpoint.presentation.macroEnabled.12;application/vnd.ms-powerpoint.template.macroEnabled.12;
X-ArtCraft-Launcher=true
EOF

chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.local/bin" "$REAL_HOME/.local/share/applications/ai.storyteller.gridcraft.desktop" "$REAL_HOME/.local/share/applications/ai.storyteller.deckcraft.desktop" 2>/dev/null || true
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$REAL_HOME/.local/share/applications" 2>/dev/null || true
fi

# 3. Associações XDG MIME para a suíte ArtCraft
log_msg "INFO" "Associando tipos de arquivos MIME ao WordCraft, GridCraft e DeckCraft..."
run_as_user() {
    if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
        sudo -u "$REAL_USER" "$@"
    else
        "$@"
    fi
}

# WordCraft (Processador de Texto / Docs / ODT / RTF)
WORD_MIMES=(
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    "application/vnd.openxmlformats-officedocument.wordprocessingml.template"
    "application/vnd.ms-word.document.macroEnabled.12"
    "application/vnd.ms-word.template.macroEnabled.12"
    "application/msword"
    "application/msword-template"
    "application/vnd.oasis.opendocument.text"
    "application/rtf"
    "text/rtf"
)
for mime in "${WORD_MIMES[@]}"; do
    run_as_user xdg-mime default ai.storyteller.wordcraft.desktop "$mime" 2>/dev/null || true
    run_as_user gio mime "$mime" ai.storyteller.wordcraft.desktop 2>/dev/null || true
done

# GridCraft (Planilhas / Excel / ODS / CSV)
GRID_MIMES=(
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    "application/vnd.openxmlformats-officedocument.spreadsheetml.template"
    "application/vnd.ms-excel"
    "application/vnd.ms-excel.sheet.macroEnabled.12"
    "application/vnd.ms-excel.template.macroEnabled.12"
    "application/vnd.oasis.opendocument.spreadsheet"
    "text/csv"
    "text/tab-separated-values"
)
for mime in "${GRID_MIMES[@]}"; do
    run_as_user xdg-mime default ai.storyteller.gridcraft.desktop "$mime" 2>/dev/null || true
    run_as_user gio mime "$mime" ai.storyteller.gridcraft.desktop 2>/dev/null || true
done

# DeckCraft (Apresentações / PowerPoint / ODP / Slides)
DECK_MIMES=(
    "application/vnd.openxmlformats-officedocument.presentationml.presentation"
    "application/vnd.openxmlformats-officedocument.presentationml.slideshow"
    "application/vnd.openxmlformats-officedocument.presentationml.template"
    "application/vnd.ms-powerpoint"
    "application/vnd.ms-powerpoint.presentation.macroEnabled.12"
    "application/vnd.ms-powerpoint.template.macroEnabled.12"
    "application/vnd.oasis.opendocument.presentation"
)
for mime in "${DECK_MIMES[@]}"; do
    run_as_user xdg-mime default ai.storyteller.deckcraft.desktop "$mime" 2>/dev/null || true
    run_as_user gio mime "$mime" ai.storyteller.deckcraft.desktop 2>/dev/null || true
done

# 4. Associa o Nautilus (GNOME Files) como gerenciador de pastas/diretórios padrão (inode/directory)
log_msg "INFO" "Definindo Nautilus como gerenciador de arquivos padrão (inode/directory)..."
run_as_user xdg-mime default org.gnome.Nautilus.desktop inode/directory 2>/dev/null || true
run_as_user gio mime inode/directory org.gnome.Nautilus.desktop 2>/dev/null || true

# 5. Persistência garantida em ~/.config/mimeapps.list e ~/.config/cosmic-mimeapps.list
mkdir -p "$REAL_HOME/.config"
for mime_file in "$REAL_HOME/.config/mimeapps.list" "$REAL_HOME/.config/cosmic-mimeapps.list"; do
    if [ -f "$mime_file" ]; then
        # WordCraft
        for mime in "${WORD_MIMES[@]}"; do
            sed -i "s|^$mime=.*|$mime=ai.storyteller.wordcraft.desktop|g" "$mime_file"
        done
        # GridCraft
        for mime in "${GRID_MIMES[@]}"; do
            sed -i "s|^$mime=.*|$mime=ai.storyteller.gridcraft.desktop|g" "$mime_file"
        done
        # DeckCraft
        for mime in "${DECK_MIMES[@]}"; do
            sed -i "s|^$mime=.*|$mime=ai.storyteller.deckcraft.desktop|g" "$mime_file"
        done
        # Nautilus
        sed -i 's|^inode/directory=.*|inode/directory=org.gnome.Nautilus.desktop|g' "$mime_file"
    fi
    chown "$REAL_USER:$REAL_USER" "$mime_file" 2>/dev/null || true
done

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "ArtCraft Suite configurado com sucesso como padrão (WordCraft, GridCraft, DeckCraft e Nautilus)!"
