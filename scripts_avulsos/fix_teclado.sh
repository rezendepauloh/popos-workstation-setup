#!/bin/bash
# ==============================================================================
# Script de Correção Imediata: Teclado US-Internacional (Estilo Windows) & NumLock
# Corrige:
# 1. Cedilha: ' + c = ç e ' + C = Ç (em vez de ć / Ć)
# 2. Aspas Duplas: " pressionado 2x = "" (em vez do trema ¨)
# 3. Aspas Simples: ' pressionado 2x = '' (em vez do acento agudo ´)
# 4. Tio, Crase e Circunflexo: 2x solta ~~, `` e ^^
# 5. NumLock: Ativação permanente no boot (systemd), udev, login e sessão
# ==============================================================================

set -e

echo "⌨️  Aplicando configurações do teclado estilo Windows e NumLock..."

# Determina o usuário real da sessão (mesmo quando rodando via sudo)
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
REAL_UID=$(id -u "$REAL_USER" 2>/dev/null || echo 1000)

set_user_gsetting() {
    local SCHEMA="$1"
    local KEY="$2"
    local VALUE="$3"

    if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
        sudo -u "$REAL_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" gsettings set "$SCHEMA" "$KEY" "$VALUE" 2>/dev/null || true
    else
        gsettings set "$SCHEMA" "$KEY" "$VALUE" 2>/dev/null || true
    fi
}

# 1. Criar o arquivo ~/.XCompose completo na home do usuário
cat << 'EOF' > "$REAL_HOME/.XCompose"
include "%L"

# ==============================================================================
# Comportamento Idêntico ao Windows (US-Internacional)
# ==============================================================================

# 1. Cedilha direta (' + c = ç e ' + C = Ç)
<dead_acute> <c> : "ç" ccedilla
<dead_acute> <C> : "Ç" Ccedilla

# 2. Aspas simples duplas (' pressionado 2x solta '')
<dead_acute> <dead_acute> : "''"
<dead_acute> <space> : "'" apostrophe

# 3. Aspas duplas (" [Shift + '] pressionado 2x solta "")
<dead_diaeresis> <dead_diaeresis> : "\"\""
<dead_diaeresis> <space> : "\"" quotedbl

# 4. Tio, Crase e Circunflexo duplicados (estilo Windows)
<dead_tilde> <dead_tilde> : "~~"
<dead_tilde> <space> : "~" asciitilde

<dead_grave> <dead_grave> : "``"
<dead_grave> <space> : "`" grave

<dead_circumflex> <dead_circumflex> : "^^"
<dead_circumflex> <space> : "^" asciicircum
EOF
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.XCompose" 2>/dev/null || true
echo "  ✅ ~/.XCompose atualizado com sucesso."

# 2. Definir layout US Internacional tradicional no GNOME/COSMIC
set_user_gsetting "org.gnome.desktop.input-sources" "sources" "[('xkb', 'us+intl')]"
set_user_gsetting "org.gnome.desktop.peripherals.keyboard" "delay" "180"
set_user_gsetting "org.gnome.desktop.peripherals.keyboard" "repeat-interval" "18"
echo "  ✅ Layout US Internacional ('us+intl') e resposta rápida configurados."

# 3. Exportar XCOMPOSEFILE no ambiente do usuário
for file in "$REAL_HOME/.zshrc" "$REAL_HOME/.bashrc" "$REAL_HOME/.profile"; do
    if [ -f "$file" ]; then
        if ! grep -q "XCOMPOSEFILE" "$file" 2>/dev/null; then
            echo "" >> "$file"
            echo 'export XCOMPOSEFILE="$HOME/.XCompose"' >> "$file"
        fi
    fi
done
export XCOMPOSEFILE="$REAL_HOME/.XCompose"
echo "  ✅ Variável XCOMPOSEFILE exportada nos dotfiles."

# 4. Ativação Robusta do Teclado Numérico (NumLock)
set_user_gsetting "org.gnome.desktop.peripherals.keyboard" "numlock-state" "true"
set_user_gsetting "org.gnome.desktop.peripherals.keyboard" "remember-numlock-state" "true"

mkdir -p "$REAL_HOME/.config/autostart"
cat << 'EOF' > "$REAL_HOME/.config/autostart/numlock.desktop"
[Desktop Entry]
Type=Application
Name=NumLock Auto-On
Exec=/bin/bash -c 'numlockx on 2>/dev/null || true; for led in /sys/class/leds/*::numlock/brightness; do echo 1 > "$led" 2>/dev/null || true; done'
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/autostart" 2>/dev/null || true

numlockx on 2>/dev/null || true
for led in /sys/class/leds/*::numlock/brightness; do
    if [ -w "$led" ]; then
        echo 1 > "$led" 2>/dev/null || true
    elif [ "$(id -u)" -eq 0 ] || sudo -n true 2>/dev/null; then
        echo 1 | sudo tee "$led" >/dev/null 2>&1 || true
    fi
done
echo "  ✅ NumLock ativado e entrada de autostart criada."

# 5. Corrigir tabela do sistema, /etc/environment e serviços de boot (se tiver sudo)
if [ "$(id -u)" -eq 0 ] || sudo -n true 2>/dev/null; then
    # Patch no Compose oficial do sistema
    if [ -f /usr/share/X11/locale/en_US.UTF-8/Compose ]; then
        sudo cp -n /usr/share/X11/locale/en_US.UTF-8/Compose /usr/share/X11/locale/en_US.UTF-8/Compose.bak 2>/dev/null || true
        sudo sed -i 's/"ć"\s*U0107/"ç"\tccedilla/g' /usr/share/X11/locale/en_US.UTF-8/Compose
        sudo sed -i 's/"Ć"\s*U0106/"Ç"\tCcedilla/g' /usr/share/X11/locale/en_US.UTF-8/Compose
        sudo sed -i 's/<dead_diaeresis> <dead_diaeresis>\s*:\s*"¨"\s*diaeresis/<dead_diaeresis> <dead_diaeresis>\t: "\\"\\""\tquotedbl/g' /usr/share/X11/locale/en_US.UTF-8/Compose
        sudo sed -i "s/<dead_acute> <dead_acute>\s*:\s*\"´\"\s*acute/<dead_acute> <dead_acute>\t: \"''\"\tapostrophe/g" /usr/share/X11/locale/en_US.UTF-8/Compose
        echo "  ✅ /usr/share/X11/locale/en_US.UTF-8/Compose corrigido."
    fi

    # Remover variáveis que forçam módulos legados incompatíveis
    sudo sed -i '/GTK_IM_MODULE/d' /etc/environment 2>/dev/null || true
    sudo sed -i '/QT_IM_MODULE/d' /etc/environment 2>/dev/null || true
    sudo sed -i '/XCOMPOSEFILE/d' /etc/environment 2>/dev/null || true
    echo "XCOMPOSEFILE=$REAL_HOME/.XCompose" | sudo tee -a /etc/environment > /dev/null
    echo "  ✅ /etc/environment limpo e configurado com XCOMPOSEFILE."

    # Serviço Systemd para NumLock permanente no boot
    if [ -d /etc/systemd/system ]; then
        cat << 'EOF' | sudo tee /etc/systemd/system/numlock.service > /dev/null
[Unit]
Description=Ativar NumLock na Inicializacao do Sistema
DefaultDependencies=no
After=systemd-udev-settle.service
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'for tty in /dev/tty[1-6]; do /usr/bin/setleds -D +num < "$tty" 2>/dev/null || true; done; for led in /sys/class/leds/*::numlock/brightness; do echo 1 | tee "$led" >/dev/null 2>&1 || true; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        sudo systemctl daemon-reload
        sudo systemctl enable numlock.service 2>/dev/null || true
        sudo systemctl start numlock.service 2>/dev/null || true
        echo "  ✅ Serviço systemd numlock.service ativado para boot."
    fi

    # Regra Udev para teclados USB e receptores sem fio
    if [ -d /etc/udev/rules.d ]; then
        cat << 'EOF' | sudo tee /etc/udev/rules.d/99-numlock.rules > /dev/null
ACTION=="add", SUBSYSTEM=="leds", KERNEL=="*::numlock", ATTR{brightness}="1"
EOF
        sudo udevadm control --reload-rules 2>/dev/null || true
        echo "  ✅ Regra udev 99-numlock.rules configurada."
    fi
else
    echo "  ℹ️  Para aplicar as correções em nível de sistema (Systemd, udev, /usr/share e /etc), execute com sudo."
fi

echo ""
echo "🎉 Concluído! Para testar no terminal atual:"
echo "   1. Abra uma nova aba de terminal ou recarregue a sessão (exec zsh)."
echo "   2. Pressione: ' + c -> ç"
echo "   3. Pressione: Shift + ' duas vezes -> \"\""
echo "   4. Pressione: ' duas vezes -> ''"
