#!/bin/bash
# ==============================================================================
# Módulo 02: Configuração do Teclado US-Intl, Cedilha ('+c = ç) e NumLock
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="CONFIG_TECLADO"

if check_flag "$FLAG_NAME"; then
    log_msg "INFO" "⏭️  Configurações de Teclado, Cedilha e NumLock já aplicadas. Pulando..."
    exit 0
fi

log_msg "HEADER" "2. CONFIGURAÇÃO DE TECLADO, CEDILHA E NUMLOCK"

# 1. Instalação do numlockx
sudo apt update
sudo apt install -y numlockx

# 2. Definição do layout do teclado US-International com Dead Keys no sistema e no COSMIC
log_msg "INFO" "Configurando layout US-International com Dead Keys e resposta ultra-rápida..."
sudo localectl set-x11-keymap us pc105 alt-intl 2>/dev/null || true

set_user_gsetting "org.gnome.desktop.peripherals.keyboard" "delay" "180"
set_user_gsetting "org.gnome.desktop.peripherals.keyboard" "repeat-interval" "18"
set_user_gsetting "org.gnome.desktop.input-sources" "sources" "[('xkb', 'us+intl')]"
set_user_gsetting "org.gnome.desktop.peripherals.keyboard" "numlock-state" "true"
set_user_gsetting "org.gnome.desktop.peripherals.keyboard" "remember-numlock-state" "true"

# Salva configuração de teclado e NumLock permanente no COSMIC Desktop (Wayland)
mkdir -p "$REAL_HOME/.config/cosmic/com.system76.CosmicComp/v1"
echo "true" > "$REAL_HOME/.config/cosmic/com.system76.CosmicComp/v1/numlock_state"
cat << 'EOF' > "$REAL_HOME/.config/cosmic/com.system76.CosmicComp/v1/xkb_config"
(
    rules: "",
    model: "pc105",
    layout: "us",
    variant: "intl",
    options: None,
    repeat_delay: 180,
    repeat_rate: 18,
)
EOF
chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/cosmic"

# 3. Mapeamento de Cedilha e aspas duplas via ~/.XCompose
log_msg "INFO" "Gerando ~/.XCompose com mapeamento Windows ('+c = ç, '' = '', \"\" = \"\")..."
cat << 'EOF' > "$REAL_HOME/.XCompose"
include "%L"

# Cedilha (' + c = ç e ' + C = Ç)
<dead_acute> <c> : "ç" ccedilla
<dead_acute> <C> : "Ç" Ccedilla

# Aspas simples duplas (' 2x = '')
<dead_acute> <dead_acute> : "''"
<dead_acute> <space> : "'" apostrophe

# Aspas duplas (" 2x = "")
<dead_diaeresis> <dead_diaeresis> : "\"\""
<dead_diaeresis> <space> : "\"" quotedbl

# Símbolos duplicados estilo Windows
<dead_tilde> <dead_tilde> : "~~"
<dead_tilde> <space> : "~" asciitilde
<dead_grave> <dead_grave> : "``"
<dead_grave> <space> : "`" grave
<dead_circumflex> <dead_circumflex> : "^^"
<dead_circumflex> <space> : "^" asciicircum
EOF
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.XCompose"

# 4. Configura ~/.xinputrc e variáveis de ambiente GTK/QT
echo 'run_im default' > "$REAL_HOME/.xinputrc"
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.xinputrc"

sudo sed -i '/GTK_IM_MODULE/d' /etc/environment 2>/dev/null || true
sudo sed -i '/QT_IM_MODULE/d' /etc/environment 2>/dev/null || true
sudo sed -i '/XMODIFIERS/d' /etc/environment 2>/dev/null || true
echo "GTK_IM_MODULE=cedilla" | sudo tee -a /etc/environment > /dev/null
echo "QT_IM_MODULE=cedilla" | sudo tee -a /etc/environment > /dev/null
echo "XMODIFIERS=@im=cedilla" | sudo tee -a /etc/environment > /dev/null

# 5. Patch no GTK immodules.cache para incluir 'en' e 'en_US' (cedilha no Chromium/Electron/Chat)
for cache in /usr/lib/x86_64-linux-gnu/gtk-3.0/3.0.0/immodules.cache /usr/lib/x86_64-linux-gnu/gtk-2.0/2.10.0/immodules.cache; do
    if [ -f "$cache" ]; then
        sudo sed -i 's/"az:ca:co:fr:gv:oc:pt:sq:tr:wa"/"az:ca:co:fr:gv:oc:pt:sq:tr:wa:en:en_US"/g' "$cache"
    fi
done

if [ -f /usr/share/X11/locale/en_US.UTF-8/Compose ]; then
    sudo sed -i 's/"ć"\s*U0107/"ç"\tccedilla/g' /usr/share/X11/locale/en_US.UTF-8/Compose
    sudo sed -i 's/"Ć"\s*U0106/"Ç"\tCcedilla/g' /usr/share/X11/locale/en_US.UTF-8/Compose
    sudo sed -i 's/<dead_diaeresis> <dead_diaeresis>\s*:\s*"¨"\s*diaeresis/<dead_diaeresis> <dead_diaeresis>\t: "\\"\\""\tquotedbl/g' /usr/share/X11/locale/en_US.UTF-8/Compose
    sudo sed -i "s/<dead_acute> <dead_acute>\s*:\s*\"´\"\s*acute/<dead_acute> <dead_acute>\t: \"''\"\tapostrophe/g" /usr/share/X11/locale/en_US.UTF-8/Compose
fi

# 6. Ativação física e persistente do NumLock no Boot (Systemd e Udev)
log_msg "INFO" "Criando serviço Systemd e regras Udev para o NumLock..."
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
sudo systemctl enable numlock.service
sudo systemctl start numlock.service 2>/dev/null || true

cat << 'EOF' | sudo tee /etc/udev/rules.d/99-numlock.rules > /dev/null
ACTION=="add", SUBSYSTEM=="leds", KERNEL=="*::numlock", ATTR{brightness}="1"
EOF
sudo udevadm control --reload-rules 2>/dev/null || true

# Liga imediatamente o NumLock para a sessão atual
numlockx on 2>/dev/null || true
for led in /sys/class/leds/*::numlock/brightness; do
    if [ -w "$led" ]; then echo 1 > "$led" 2>/dev/null || true; fi
done

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Teclado US-Intl, Cedilha e NumLock configurados com sucesso."
