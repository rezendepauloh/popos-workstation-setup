#!/bin/bash
# ==============================================================================
# Script de Correção do Kando para COSMIC Desktop / Wayland (XWayland)
# ==============================================================================

set -e

echo "🎡 Aplicando correção de compatibilidade para o Kando no COSMIC Desktop..."

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# 1. Criar wrapper local no ~/.local/bin/kando
mkdir -p "$REAL_HOME/.local/bin" "$REAL_HOME/.local/share/applications"

cat << 'EOF' > "$REAL_HOME/.local/bin/kando"
#!/bin/bash
# Kando Wrapper para COSMIC Desktop / Wayland (força backend X11 via XWayland)
export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
exec /usr/lib/kando/kando "$@"
EOF
chmod +x "$REAL_HOME/.local/bin/kando"
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.local/bin/kando"
echo "  ✅ Wrapper ~/.local/bin/kando criado."

# 2. Criar lançador .desktop local do usuário
cat << 'EOF' > "$REAL_HOME/.local/share/applications/menu.kando.Kando.desktop"
[Desktop Entry]
Name=Kando
Comment=The Cross-Platform Pie Menu.
GenericName=Pie Menu
Exec=env XDG_SESSION_TYPE=x11 GDK_BACKEND=x11 /usr/lib/kando/kando %U
Icon=kando
Type=Application
StartupNotify=true
Categories=Utility;
EOF
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.local/share/applications/menu.kando.Kando.desktop"
update-desktop-database "$REAL_HOME/.local/share/applications" 2>/dev/null || true
echo "  ✅ Lançador de menu menu.kando.Kando.desktop configurado."

# 3. Configurar menus.json para modo centralizado (evita desalinhamento em Wayland)
if [ -f "$REAL_HOME/.config/kando/menus.json" ]; then
    if command -v jq >/dev/null 2>&1; then
        jq 'walk(if type == "object" and has("centered") then .centered = true else . end)' "$REAL_HOME/.config/kando/menus.json" > "$REAL_HOME/.config/kando/menus.json.tmp" && mv "$REAL_HOME/.config/kando/menus.json.tmp" "$REAL_HOME/.config/kando/menus.json"
        chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/kando/menus.json"
        echo "  ✅ Menus configurados com modo centralizado na tela."
    fi
fi

# 4. Se tiver permissão de root (sudo), aplica no sistema (/usr/local/bin e /usr/share)
if [ "$(id -u)" -eq 0 ] || sudo -n true 2>/dev/null; then
    cat << 'EOF' | sudo tee /usr/local/bin/kando > /dev/null
#!/bin/bash
export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
exec /usr/lib/kando/kando "$@"
EOF
    sudo chmod +x /usr/local/bin/kando

    if [ -f /usr/share/applications/menu.kando.Kando.desktop ]; then
        sudo sed -i 's|^Exec=.*|Exec=env XDG_SESSION_TYPE=x11 GDK_BACKEND=x11 /usr/lib/kando/kando %U|' /usr/share/applications/menu.kando.Kando.desktop
        sudo update-desktop-database /usr/share/applications 2>/dev/null || true
    fi
    echo "  ✅ Wrapper global /usr/local/bin/kando e /usr/share atualizados."
fi

# 5. Iniciar o Kando em segundo plano
pkill -f "/usr/lib/kando/kando" 2>/dev/null || true
nohup env XDG_SESSION_TYPE=x11 GDK_BACKEND=x11 /usr/lib/kando/kando >/dev/null 2>&1 &
echo "  ✅ Kando iniciado com sucesso em segundo plano!"

echo ""
echo "🎉 Concluído! O Kando já está rodando e configurado."
echo "   Teste abrir o menu com seu atalho do mouse (Botão 4) ou Ctrl+Shift+F10."
