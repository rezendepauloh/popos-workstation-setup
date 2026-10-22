#!/bin/bash
# ==============================================================================
# Módulo 14: Restauração de Temas Visuais do COSMIC, GTK, Qt e Exceções de Janelas
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="COSMIC_THEME_RESTORE"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Temas visuais e regras do COSMIC já restaurados anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "14. RESTAURAÇÃO DE TEMAS, PONTES VISUAIS E REGRAS DE JANELAS"

# ------------------------------------------------------------------------------
# 1. Regras de Exceção do Auto-Tiling (Janelas Flutuantes Automáticas)
# ------------------------------------------------------------------------------
log_msg "INFO" "Configurando regras customizadas de janelas flutuantes (Tiling Exceptions)..."

mkdir -p "$REAL_HOME/.config/cosmic/com.system76.CosmicSettings.WindowRules/v1"

cat << 'EOF' > "$REAL_HOME/.config/cosmic/com.system76.CosmicSettings.WindowRules/v1/tiling_exception_custom"
[
	// Gerenciador de Arquivos
	(appid: "org.gnome.Nautilus", titles: [".*"]),
	(appid: "org.gnome.NautilusDialog", titles: [".*"]),
	(appid: "com.system76.CosmicFiles", titles: [".*"]),
	(appid: "com.system76.CosmicFilesDialog", titles: [".*"]),

	// Acesso Remoto
	(appid: "org.remmina.Remmina", titles: [".*"]),

	// Utilitários do Sistema e Hardware
	(appid: "org.gnome.Calculator", titles: [".*"]),
	(appid: "com.github.tchx84.Flatseal", titles: [".*"]),
	(appid: "com.github.hluk.copyq", titles: [".*"]),
	(appid: "menu.kando.Kando", titles: [".*"]),
	(appid: "org.openrgb.OpenRGB", titles: [".*"]),
	(appid: "piper", titles: [".*"]),
	(appid: "jstest-gtk", titles: [".*"]),
	(appid: "io.github.antimicrox.antimicrox", titles: [".*"]),
	(appid: "com.ranfdev.Celeste", titles: [".*"]),
	(appid: "rclone-browser", titles: [".*"]),
	(appid: "balena-etcher", titles: [".*"]),
	(appid: "balenaEtcher", titles: [".*"]),
	(appid: "org.kde.kdeconnect.app", titles: [".*"]),
	(appid: "org.kde.kdeconnect-indicator", titles: [".*"]),

	// Visualizadores e Ferramentas Rápidas
	(appid: "io.github.cosmic_utils.camera", titles: [".*"]),
	(appid: "org.gnome.Loupe", titles: [".*"]),
	(appid: "org.gnome.eog", titles: [".*"]),
	(appid: "org.gnome.Evince", titles: [".*"]),
	(appid: "nm-connection-editor", titles: [".*"]),
]
EOF

# ------------------------------------------------------------------------------
# 2. Restauração de Temas a partir do Google Drive
# ------------------------------------------------------------------------------
COSMIC_BACKUP_DIR="$REAL_HOME/GoogleDrive_Pessoal/Organização/Backup_COSMIC"

if [ -d "$COSMIC_BACKUP_DIR" ]; then
    log_msg "INFO" "Restaurando temas e pontes visuais (GTK 3/4, Qt5/6, COSMIC)..."
    
    if command -v rsync >/dev/null 2>&1; then
        if [ -d "$COSMIC_BACKUP_DIR/cosmic" ]; then
            rsync -au --info=progress2 "$COSMIC_BACKUP_DIR/cosmic/" "$REAL_HOME/.config/cosmic/" 2>/dev/null || cp -rn "$COSMIC_BACKUP_DIR/cosmic"/* "$REAL_HOME/.config/cosmic/" 2>/dev/null || true
        fi
        for dir in "gtk-3.0" "gtk-4.0" "qt5ct" "qt6ct" "vlc"; do
            if [ -d "$COSMIC_BACKUP_DIR/$dir" ]; then
                mkdir -p "$REAL_HOME/.config/$dir"
                rsync -au "$COSMIC_BACKUP_DIR/$dir/" "$REAL_HOME/.config/$dir/" 2>/dev/null || cp -rn "$COSMIC_BACKUP_DIR/$dir"/* "$REAL_HOME/.config/$dir/" 2>/dev/null || true
            fi
        done
    else
        if [ -d "$COSMIC_BACKUP_DIR/cosmic" ]; then cp -rn "$COSMIC_BACKUP_DIR/cosmic" "$REAL_HOME/.config/" 2>/dev/null || true; fi
        for dir in "gtk-3.0" "gtk-4.0" "qt5ct" "qt6ct" "vlc"; do
            if [ -d "$COSMIC_BACKUP_DIR/$dir" ]; then cp -rn "$COSMIC_BACKUP_DIR/$dir" "$REAL_HOME/.config/" 2>/dev/null || true; fi
        done
    fi
    log_msg "SUCCESS" "Temas e perfis restaurados do Google Drive com sucesso."
else
    log_msg "WARN" "Diretório '$COSMIC_BACKUP_DIR' não encontrado ou Google Drive não montado. Pulando restauração de temas da nuvem."
fi

# ------------------------------------------------------------------------------
# 3. Atalhos Customizados de Teclado do COSMIC (ex: Super+Shift+S para Captura de Tela)
# ------------------------------------------------------------------------------
log_msg "INFO" "Configurando atalhos de teclado customizados do COSMIC..."
SHORTCUTS_DIR="$REAL_HOME/.config/cosmic/com.system76.CosmicSettings.Shortcuts/v1"
mkdir -p "$SHORTCUTS_DIR"

cat << 'EOF' > "$SHORTCUTS_DIR/custom"
{
    (
        modifiers: [
            Super,
        ],
    ): System(Launcher),
    (
        modifiers: [
            Super,
            Shift,
        ],
        key: "s",
    ): System(Screenshot),
    (
        modifiers: [
            Super,
            Shift,
        ],
        key: "g",
    ): ToggleSticky,
}
EOF

# ------------------------------------------------------------------------------
# 4. Otimização de Tema Escuro e Contraste para o VLC Media Player (Qt5 / QSS)
# ------------------------------------------------------------------------------
log_msg "INFO" "Configurando folha de estilos (QSS) de alto contraste para o VLC Media Player..."

mkdir -p "$REAL_HOME/.config/qt5ct/qss"
mkdir -p "$REAL_HOME/.config/vlc"

cat << 'EOF' > "$REAL_HOME/.config/qt5ct/qss/vlc-dark-fix.qss"
/* ==========================================================================
   VLC Media Player - Dark Mode Controls & Contrast Fix
   Aplica contraste nítido a todos os botões (nativos e customizados) e timeline.
   ========================================================================== */

/* 1. Botões do Controlador de Mídia (Play, Pause, Stop, Prev, Next, etc.) */
QToolButton {
    background-color: #585c66;
    color: #ffffff;
    border: 1px solid #7a7f8c;
    border-radius: 5px;
    margin: 2px 1px;
    padding: 3px;
    min-width: 22px;
    min-height: 22px;
}

QToolButton:hover {
    background-color: #6f7482;
    border: 1px solid #7b68ee;
}

QToolButton:pressed {
    background-color: #3b3e45;
    border: 1px solid #7b68ee;
}

/* 2. Barra de Progresso / Slider de Linha do Tempo e Volume */
QSlider::groove:horizontal {
    height: 6px;
    background: #484c55;
    border: 1px solid #5b5f6a;
    border-radius: 3px;
}

QSlider::sub-page:horizontal {
    background: #6c5ce7;
    border-radius: 3px;
}

QSlider::handle:horizontal {
    background: #ffffff;
    border: 1px solid #2b2e34;
    width: 14px;
    margin-top: -4px;
    margin-bottom: -4px;
    border-radius: 7px;
}

QSlider::handle:horizontal:hover {
    background: #ffffff;
    border: 2px solid #6c5ce7;
}

/* 3. Marcadores e Labels de Tempo */
QLabel {
    color: #f0f0f0;
}
EOF

# Injeta a folha de estilos no qt5ct.conf de forma idempotente
python3 - << PYEOF
import configparser
import os

qt5ct_conf = os.path.expanduser("$REAL_HOME/.config/qt5ct/qt5ct.conf")
qss_file = os.path.expanduser("$REAL_HOME/.config/qt5ct/qss/vlc-dark-fix.qss")

config = configparser.ConfigParser()
if os.path.exists(qt5ct_conf):
    config.read(qt5ct_conf)

if not config.has_section('Interface'):
    config.add_section('Interface')

config.set('Interface', 'stylesheets', qss_file)

with open(qt5ct_conf, 'w') as f:
    config.write(f, space_around_delimiters=False)
PYEOF

# Garante que o VLC use qt5ct-style como motor de renderização
VLC_CONF="$REAL_HOME/.config/vlc/vlc-qt-interface.conf"
if [ ! -f "$VLC_CONF" ]; then
    cat << 'EOF' > "$VLC_CONF"
[MainWindow]
QtStyle=qt5ct-style
EOF
else
    if grep -q "^\[MainWindow\]" "$VLC_CONF"; then
        if grep -q "^QtStyle=" "$VLC_CONF"; then
            sed -i 's/^QtStyle=.*/QtStyle=qt5ct-style/' "$VLC_CONF"
        else
            sed -i '/^\[MainWindow\]/a QtStyle=qt5ct-style' "$VLC_CONF"
        fi
    else
        cat << 'EOF' >> "$VLC_CONF"

[MainWindow]
QtStyle=qt5ct-style
EOF
    fi
fi

# Garante sincronização de configurações também para a sandbox do Flatpak
VLC_FLATPAK_DIR="$REAL_HOME/.var/app/org.videolan.VLC/config/vlc"
if [ -d "$REAL_HOME/.var/app/org.videolan.VLC" ]; then
    mkdir -p "$VLC_FLATPAK_DIR"
    cp -rn "$REAL_HOME/.config/vlc/"* "$VLC_FLATPAK_DIR/" 2>/dev/null || true
fi

# Configura estabilidade de vídeo e comportamento de tela cheia para XWayland / COSMIC / NVIDIA
for vrc in "$REAL_HOME/.config/vlc/vlcrc" "$VLC_FLATPAK_DIR/vlcrc"; do
    if [ -f "$vrc" ]; then
        sed -i 's/^#*avcodec-hw=.*/avcodec-hw=none/' "$vrc"
        sed -i 's/^#*vout=.*/vout=any/' "$vrc"
        sed -i 's/^#*video-on-top=.*/video-on-top=1/' "$vrc"
        sed -i 's/^#*qt-fs-opacity=.*/qt-fs-opacity=1.000000/' "$vrc"
        sed -i 's/^#*aout=.*/aout=alsa/' "$vrc"
        sed -i 's/^#*audio-resampler=.*/audio-resampler=speex_resampler/' "$vrc"
    fi
done

for vconf in "$VLC_CONF" "$VLC_FLATPAK_DIR/vlc-qt-interface.conf"; do
    if [ -f "$vconf" ]; then
        sed -i 's/^wide=.*/wide=true/' "$vconf" 2>/dev/null || true
    fi
done

# Garante que o VLC use o backend XCB (XWayland) e funcione no terminal e menu
mkdir -p "$REAL_HOME/.local/share/applications"
mkdir -p "$REAL_HOME/.local/bin"

if [ -f "/usr/share/applications/vlc.desktop" ]; then
    cp "/usr/share/applications/vlc.desktop" "$REAL_HOME/.local/share/applications/vlc.desktop"
    sed -i 's|^Exec=/usr/bin/vlc|Exec=env QT_QPA_PLATFORM=xcb /usr/bin/vlc|' "$REAL_HOME/.local/share/applications/vlc.desktop"
    update-desktop-database "$REAL_HOME/.local/share/applications" 2>/dev/null || true
fi

cat << 'EOF' > "$REAL_HOME/.local/bin/vlc"
#!/bin/bash
if command -v /usr/bin/vlc >/dev/null 2>&1; then
    exec env QT_QPA_PLATFORM=xcb /usr/bin/vlc "$@"
elif flatpak info org.videolan.VLC >/dev/null 2>&1; then
    exec flatpak run org.videolan.VLC "$@"
fi
EOF
# 7. Tema de Cursores Moderno (Bibata Modern Classic)
log_msg "INFO" "Configurando tema de cursores Bibata Modern Classic..."
sudo apt install -y bibata-cursor-theme 2>/dev/null || true

# Configura cursor nas interfaces GTK/GNOME e fallback X11/XWayland
if [ -n "$REAL_UID" ]; then
    sudo -u "$REAL_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Classic' 2>/dev/null || true
    sudo -u "$REAL_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" gsettings set org.gnome.desktop.interface cursor-size 24 2>/dev/null || true
fi

mkdir -p "$REAL_HOME/.icons/default"
cat << 'EOF' > "$REAL_HOME/.icons/default/index.theme"
[Icon Theme]
Name=Default
Comment=Default Cursor Theme
Inherits=Bibata-Modern-Classic
EOF
chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.icons" 2>/dev/null || true

# Configura variáveis de ambiente globais lidas pelo compositor cosmic-comp no login
mkdir -p "$REAL_HOME/.config/environment.d"
cat << 'EOF' > "$REAL_HOME/.config/environment.d/10-cursor.conf"
XCURSOR_THEME="Bibata-Modern-Classic"
XCURSOR_SIZE="24"
EOF

if ! grep -q 'export XCURSOR_THEME="Bibata-Modern-Classic"' "$REAL_HOME/.profile" 2>/dev/null; then
    cat << 'EOF' >> "$REAL_HOME/.profile"
export XCURSOR_THEME="Bibata-Modern-Classic"
export XCURSOR_SIZE="24"
EOF
fi

chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/cosmic" "$REAL_HOME/.config/gtk-3.0" "$REAL_HOME/.config/gtk-4.0" "$REAL_HOME/.config/qt5ct" "$REAL_HOME/.config/qt6ct" "$REAL_HOME/.config/vlc" "$REAL_HOME/.local/share/applications/vlc.desktop" "$REAL_HOME/.local/bin/vlc" "$REAL_HOME/.var/app/org.videolan.VLC" 2>/dev/null || true

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Etapa de temas visuais, regras de janelas, contraste do VLC e cursores Bibata concluída com sucesso."
