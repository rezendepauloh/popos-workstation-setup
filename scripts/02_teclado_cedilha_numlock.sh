#!/bin/bash
# ==============================================================================
# Módulo 02: Configuração do Teclado US-Intl, Cedilha ('+c = ç) e NumLock
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="CONFIG_TECLADO"

if check_flag "$FLAG_NAME" "$@"; then
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
    options: Some("numpad:mac"),
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

for compose_file in /usr/share/X11/locale/en_US.UTF-8/Compose /usr/share/X11/locale/pt_BR.UTF-8/Compose; do
    if [ -f "$compose_file" ]; then
        sudo sed -i 's/"ć"\s*U0107/"ç"\tccedilla/g' "$compose_file"
        sudo sed -i 's/"Ć"\s*U0106/"Ç"\tCcedilla/g' "$compose_file"
        sudo sed -i 's/<dead_diaeresis> <dead_diaeresis>\s*:\s*"¨"\s*diaeresis/<dead_diaeresis> <dead_diaeresis>\t: "\\"\\""\tquotedbl/g' "$compose_file"
        sudo sed -i "s/<dead_acute> <dead_acute>\s*:\s*\"´\"\s*acute/<dead_acute> <dead_acute>\t: \"''\"\tapostrophe/g" "$compose_file"
    fi
done

# Configuração de flags para Electron / Chromium / IDEs utilizarem o motor XCompose do XWayland ('+c = ç)
for conf in "$REAL_HOME/.config/antigravity-flags.conf" "$REAL_HOME/.config/antigravity-ide-flags.conf" "$REAL_HOME/.config/code-flags.conf" "$REAL_HOME/.config/chrome-flags.conf" "$REAL_HOME/.config/brave-flags.conf" "$REAL_HOME/.config/electron-flags.conf"; do
    cat << 'EOF' > "$conf"
--ozone-platform=x11
EOF
done
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/"*-flags.conf 2>/dev/null || true

# Configura keyboard.dispatch nos editores para mapear keycodes nativos
python3 -c "
import json, os
for p in [
    os.path.expanduser('~/.config/Antigravity IDE/User/settings.json'),
    os.path.expanduser('~/.config/Code/User/settings.json')
]:
    if os.path.exists(p):
        with open(p, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        if not any('keyboard.dispatch' in l for l in lines):
            for i, line in enumerate(lines):
                if '{' in line:
                    lines.insert(i + 1, '  \"keyboard.dispatch\": \"keyCode\",\n')
                    break
            with open(p, 'w', encoding='utf-8') as f:
                f.writelines(lines)
" 2>/dev/null || true

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
ACTION=="add|change", SUBSYSTEM=="leds", KERNEL=="*::numlock", ATTR{brightness}="1", MODE="0666"
EOF
sudo udevadm control --reload-rules 2>/dev/null || true
sudo udevadm trigger --subsystem-match=leds 2>/dev/null || true

# 7. Configuração do NumLock no COSMIC Greeter (Tela de Login) e Perfil do Usuário
log_msg "INFO" "Configurando persistência do NumLock no COSMIC Greeter e Sessão do Usuário..."
USER_COSMIC_DIR="$REAL_HOME/.config/cosmic/com.system76.CosmicComp/v1"
mkdir -p "$USER_COSMIC_DIR"
echo "true" > "$USER_COSMIC_DIR/numlock_state"
chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/cosmic" 2>/dev/null || true

GREETER_COSMIC_DIR="/var/lib/cosmic-greeter/.config/cosmic/com.system76.CosmicComp/v1"
sudo mkdir -p "$GREETER_COSMIC_DIR"
echo "true" | sudo tee "$GREETER_COSMIC_DIR/numlock_state" > /dev/null

if [ -f "$USER_COSMIC_DIR/xkb_config" ]; then
    sudo cp "$USER_COSMIC_DIR/xkb_config" "$GREETER_COSMIC_DIR/xkb_config" 2>/dev/null || true
fi
sudo chown -R cosmic-greeter:cosmic-greeter /var/lib/cosmic-greeter/.config 2>/dev/null || true

# Criação do utilitário numlock-on via uinput para sincronização do LED físico
cat << 'EOF' | sudo tee /usr/local/bin/numlock-on > /dev/null
#!/usr/bin/env python3
import evdev, time, sys

try:
    ui = evdev.UInput({evdev.ecodes.EV_KEY: [evdev.ecodes.KEY_NUMLOCK]}, name="NumLock-Enabler")
    time.sleep(0.2)
    ui.write(evdev.ecodes.EV_KEY, evdev.ecodes.KEY_NUMLOCK, 1)
    ui.syn()
    time.sleep(0.05)
    ui.write(evdev.ecodes.EV_KEY, evdev.ecodes.KEY_NUMLOCK, 0)
    ui.syn()
    time.sleep(0.1)
    ui.close()
except Exception:
    sys.exit(0)
EOF
sudo chmod +x /usr/local/bin/numlock-on

# Liga imediatamente o NumLock para a sessão atual
/usr/local/bin/numlock-on 2>/dev/null || true
numlockx on 2>/dev/null || true
for led in /sys/class/leds/*::numlock/brightness; do
    if [ -w "$led" ]; then echo 1 > "$led" 2>/dev/null || true; fi
done

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Teclado US-Intl, Cedilha e NumLock (Boot, Login Greeter, LED e Sessão) configurados com sucesso."
