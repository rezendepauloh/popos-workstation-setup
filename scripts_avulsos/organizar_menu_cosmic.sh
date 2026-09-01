#!/bin/bash
# ==============================================================================
# Script para Organização do Menu / Biblioteca de Aplicativos do COSMIC Desktop
# Cria grupos organizados (Jogos, Desenvolvimento, Escritório, Mídia, Utilitários, Sistema)
# ==============================================================================

set -e

echo "🗂️  Organizando o Menu de Aplicativos do COSMIC em grupos separados..."

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

mkdir -p "$REAL_HOME/.config/cosmic/com.system76.CosmicAppLibrary/v1"
mkdir -p "$REAL_HOME/.config/cosmic/com.system76.CosmicAppList/v1"

# 1. Configuração dos Grupos / Pastas da Biblioteca de Aplicativos (App Library)
cat << 'EOF' > "$REAL_HOME/.config/cosmic/com.system76.CosmicAppLibrary/v1/groups"
[
    (
        name: "Jogos",
        icon: "input-gaming-symbolic",
        filter: Categories(
            categories: [
                "Game",
            ],
            include: [
                "steam",
                "com.heroicgameslauncher.hgl",
            ],
            exclude: [],
        ),
    ),
    (
        name: "Desenvolvimento",
        icon: "applications-engineering-symbolic",
        filter: Categories(
            categories: [
                "Development",
            ],
            include: [
                "antigravity-ide",
                "code",
            ],
            exclude: [],
        ),
    ),
    (
        name: "Escritório",
        icon: "applications-office-symbolic",
        filter: Categories(
            categories: [
                "Office",
            ],
            include: [
                "org.onlyoffice.desktopeditors",
                "com.dropbox.Client",
            ],
            exclude: [],
        ),
    ),
    (
        name: "Mídia",
        icon: "applications-multimedia-symbolic",
        filter: Categories(
            categories: [
                "AudioVideo",
                "Graphics",
            ],
            include: [
                "org.jellyfin.JellyfinDesktop",
                "org.gimp.GIMP",
            ],
            exclude: [],
        ),
    ),
    (
        name: "cosmic-utilities",
        icon: "folder-symbolic",
        filter: Categories(
            categories: [
                "Utility",
            ],
            include: [
                "nm-connection-editor",
                "com.github.hluk.copyq",
                "menu.kando.Kando",
            ],
            exclude: [
                "com.system76.CosmicEdit",
                "com.system76.CosmicFiles",
            ],
        ),
    ),
    (
        name: "cosmic-system",
        icon: "folder-symbolic",
        filter: Categories(
            categories: [
                "System",
            ],
            include: [
                "gnome-language-selector",
                "im-config",
                "org.freedesktop.IBus.Setup",
                "system76-driver",
            ],
            exclude: [
                "com.system76.CosmicStore",
                "com.system76.CosmicTerm",
            ],
        ),
    ),
]
EOF

# 2. Configuração dos Aplicativos Favoritos (Fixos no topo / Dock)
cat << 'EOF' > "$REAL_HOME/.config/cosmic/com.system76.CosmicAppList/v1/favorites"
[
    "firefox",
    "com.system76.CosmicFiles",
    "antigravity-ide",
    "code",
    "com.system76.CosmicTerm",
    "com.system76.CosmicStore",
    "com.system76.CosmicSettings",
]
EOF

chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/cosmic/com.system76.CosmicAppLibrary"
chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/cosmic/com.system76.CosmicAppList"

# 3. Salvar cópia no Google Drive (se montado) para persistência em restaurações
if [ -d "$REAL_HOME/GoogleDrive_Pessoal/Organização/Backup_COSMIC/cosmic" ]; then
    mkdir -p "$REAL_HOME/GoogleDrive_Pessoal/Organização/Backup_COSMIC/cosmic/com.system76.CosmicAppLibrary/v1"
    mkdir -p "$REAL_HOME/GoogleDrive_Pessoal/Organização/Backup_COSMIC/cosmic/com.system76.CosmicAppList/v1"
    
    cp "$REAL_HOME/.config/cosmic/com.system76.CosmicAppLibrary/v1/groups" "$REAL_HOME/GoogleDrive_Pessoal/Organização/Backup_COSMIC/cosmic/com.system76.CosmicAppLibrary/v1/groups" 2>/dev/null || true
    cp "$REAL_HOME/.config/cosmic/com.system76.CosmicAppList/v1/favorites" "$REAL_HOME/GoogleDrive_Pessoal/Organização/Backup_COSMIC/cosmic/com.system76.CosmicAppList/v1/favorites" 2>/dev/null || true
    echo "  ✅ Backup sincronizado na pasta do Google Drive."
fi

# Reiniciar o processo da biblioteca de aplicativos do COSMIC para recarregar visualmente
pkill -f "cosmic-app-library" 2>/dev/null || true

echo "  ✅ Grupos 'Jogos', 'Desenvolvimento', 'Escritório', 'Mídia', 'Utilitários' e 'Sistema' separados com sucesso!"
echo "🎉 Menu de Aplicativos do COSMIC atualizado!"
