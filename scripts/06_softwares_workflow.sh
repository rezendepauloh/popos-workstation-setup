#!/bin/bash
# ==============================================================================
# Módulo 06: Instalação de Softwares de Workflow (VS Code, Flatpaks, Espanso, Kando)
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="SOFTWARE_INSTALL"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Softwares de Workflow já instalados anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "6. INSTALAÇÃO DE SOFTWARES DE WORKFLOW"

# 1. Repositório Oficial e Instalação do VS Code
log_msg "INFO" "Configurando repositório oficial do VS Code..."
sudo mkdir -p /etc/apt/keyrings
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor --yes -o /etc/apt/keyrings/packages.microsoft.gpg
echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
sudo apt update
sudo apt install -y code copyq

# Configurações do CopyQ para monitoramento contínuo da área de transferência
COPYQ_CONFIG_DIR="$REAL_HOME/.config/copyq"
mkdir -p "$COPYQ_CONFIG_DIR"
cat << 'EOF' > "$COPYQ_CONFIG_DIR/copyq.conf"
[Options]
check_clipboard=true
check_selection=false
copy_clipboard=true
copy_selection=false
always_on_top=false
autostart=false
clipboard_tab=&clipboard
item_data_threshold=1024
max_items=500
save_filter_history=true
show_simple_items=true
tray_items=10
EOF
chown -R "$REAL_USER:$REAL_USER" "$COPYQ_CONFIG_DIR" 2>/dev/null || true

# 2. Configuração do Flathub e Instalação de Flatpaks
log_msg "INFO" "Configurando Flathub e instalando Flatpaks..."
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install -y --system flathub \
    com.dropbox.Client \
    org.onlyoffice.desktopeditors \
    org.jellyfin.JellyfinDesktop \
    org.gimp.GIMP \
    org.telegram.desktop \
    com.rtosta.zapzap

# 3. Jellyfin Media Server (Repositório Oficial APT)
log_msg "INFO" "Instalando Jellyfin Media Server nativo..."
curl -fsSL https://repo.jellyfin.org/jellyfin_team.gpg.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/jellyfin.gpg
echo "deb [arch=$( dpkg --print-architecture ) signed-by=/etc/apt/keyrings/jellyfin.gpg] https://repo.jellyfin.org/ubuntu noble main" | sudo tee /etc/apt/sources.list.d/jellyfin.list > /dev/null
sudo apt update
sudo apt install -y jellyfin

# 4. Espanso (Wayland Edition) e bibliotecas wxWidgets 3.0 no Ubuntu/Pop!_OS 24.04 (noble)
log_msg "INFO" "Baixando e instalando Espanso (Wayland)..."
wget -qO /tmp/espanso.deb https://github.com/espanso/espanso/releases/download/v2.2.1/espanso-debian-wayland-amd64.deb
sudo apt install -y /tmp/espanso.deb

sudo mkdir -p /usr/local/lib/espanso
sudo rm -rf /tmp/libwx*.deb /tmp/wx_extract
if [ ! -f /usr/local/lib/espanso/libwx_gtk3u_core-3.0.so.0 ]; then
    wget -qO /tmp/libwxbase3.0.deb http://archive.ubuntu.com/ubuntu/pool/universe/w/wxwidgets3.0/libwxbase3.0-0v5_3.0.5.1+dfsg-4_amd64.deb || true
    wget -qO /tmp/libwxgtk3.0.deb http://archive.ubuntu.com/ubuntu/pool/universe/w/wxwidgets3.0/libwxgtk3.0-gtk3-0v5_3.0.5.1+dfsg-4_amd64.deb || true
    if [ -f /tmp/libwxbase3.0.deb ] && [ -f /tmp/libwxgtk3.0.deb ]; then
        mkdir -p /tmp/wx_extract
        dpkg-deb -x /tmp/libwxbase3.0.deb /tmp/wx_extract
        dpkg-deb -x /tmp/libwxgtk3.0.deb /tmp/wx_extract
        sudo cp -rn /tmp/wx_extract/usr/lib/x86_64-linux-gnu/* /usr/local/lib/espanso/
        rm -rf /tmp/wx_extract /tmp/libwx*.deb
    fi
fi
if [ -f /usr/lib/x86_64-linux-gnu/libtiff.so.6 ]; then
    sudo ln -sf /usr/lib/x86_64-linux-gnu/libtiff.so.6 /usr/lib/x86_64-linux-gnu/libtiff.so.5
    sudo ln -sf /usr/lib/x86_64-linux-gnu/libtiff.so.6 /usr/local/lib/espanso/libtiff.so.5 2>/dev/null || true
fi
echo "/usr/local/lib/espanso" | sudo tee /etc/ld.so.conf.d/espanso.conf > /dev/null
sudo ldconfig 2>/dev/null || true

# Instala dependências Python e utilitários de Clipboard/GUI para automações
sudo apt install -y python3-tk python3-pyperclip python3-pip python3-yaml wl-clipboard xclip

# Permite acesso evdev com capabilities
ESPANSO_BIN=$(which espanso || true)
if [ -n "$ESPANSO_BIN" ]; then
    sudo setcap "cap_dac_override+p" "$ESPANSO_BIN" 2>/dev/null || true
fi

ESPANSO_CONFIG_DIR="$REAL_HOME/.config/espanso"
ESPANSO_REPO_URL="https://github.com/rezendepauloh/espanso-automacoes-sti.git"

log_msg "INFO" "Sincronizando repositório de automações do Espanso (espanso-automacoes-sti)..."
if [ ! -d "$ESPANSO_CONFIG_DIR/.git" ]; then
    rm -rf "$ESPANSO_CONFIG_DIR"
    git clone "$ESPANSO_REPO_URL" "$ESPANSO_CONFIG_DIR"
else
    git -C "$ESPANSO_CONFIG_DIR" pull --rebase 2>/dev/null || true
fi

# Configuração global para Pop!_OS Wayland
cat << 'EOF' > "$ESPANSO_CONFIG_DIR/config/default.yml"
# ==============================================================================
# CONFIGURAÇÕES GLOBAIS DO ESPANSO (Pop!_OS / COSMIC Desktop / Wayland)
# ==============================================================================

backend: EVDEV
show_icon: false
show_notifications: true

keyboard_layout:
  layout: "us"
  variant: "intl"

toggle_key: LEFT_ALT
clipboard_threshold: 0
search_shortcut: CTRL+ALT+SPACE
undo_backspace: true
restore_clipboard: true
EOF

# Ajusta caminhos do Windows para Linux nos arquivos de match
python3 -c "
import os, glob
match_dir = '$ESPANSO_CONFIG_DIR/match'
for yml in glob.glob(f'{match_dir}/*.yml'):
    with open(yml, 'r', encoding='utf-8') as f:
        content = f.read()
    content = content.replace('%CONFIG%\\\\', '\$CONFIG/').replace('%CONFIG%\\', '\$CONFIG/').replace('\\\\', '/')
    content = content.replace('- python\n', '- python3\n')
    with open(yml, 'w', encoding='utf-8') as f:
        f.write(content)
" 2>/dev/null || true

# Cria executor nativo de formulários no Linux (form_runner.py)
cat << 'EOF' > "$ESPANSO_CONFIG_DIR/scripts/lib/form_runner.py"
# -*- coding: utf-8 -*-
import sys, os, yaml
from pathlib import Path

def run_gui_form(form_config_path):
    config_path = Path(form_config_path)
    if not config_path.exists():
        return {}
    try:
        form_data = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    properties = form_data.get("schema", {}).get("properties", {})
    defaults = form_data.get("data", {}) or {}
    try:
        import tkinter as tk
        from tkinter import ttk
        root = tk.Tk()
        root.title(f"Espanso - {config_path.stem.replace('_', ' ').title()}")
        root.configure(bg="#24283b")
        root.attributes("-topmost", True)
        root.geometry("480x520")
        root.eval('tk::PlaceWindow . center')
        style = ttk.Style()
        style.theme_use("clam")
        style.configure(".", background="#24283b", foreground="#c0caf5", font=("Cantarell", 10))
        style.configure("TLabel", background="#24283b", foreground="#c0caf5", font=("Cantarell", 10, "bold"))
        style.configure("TEntry", fieldbackground="#1f2335", foreground="#ffffff")
        style.configure("TCombobox", fieldbackground="#1f2335", foreground="#ffffff")
        style.configure("TButton", background="#7aa2f7", foreground="#1a1b26", font=("Cantarell", 10, "bold"))
        main_frame = ttk.Frame(root, padding="20")
        main_frame.pack(fill=tk.BOTH, expand=True)
        entries = {}
        row = 0
        for field_name, field_info in properties.items():
            title = field_info.get("title", field_name)
            lbl = ttk.Label(main_frame, text=title)
            lbl.grid(row=row, column=0, sticky="w", pady=(8, 2))
            row += 1
            enums = field_info.get("enum")
            default_val = defaults.get(field_name, "")
            if enums:
                combo = ttk.Combobox(main_frame, values=enums, state="readonly")
                if default_val and default_val in enums:
                    combo.set(default_val)
                elif enums:
                    combo.current(0)
                combo.grid(row=row, column=0, sticky="ew", pady=(0, 6))
                entries[field_name] = combo
            else:
                entry = ttk.Entry(main_frame)
                if default_val:
                    entry.insert(0, str(default_val))
                entry.grid(row=row, column=0, sticky="ew", pady=(0, 6))
                entries[field_name] = entry
            row += 1
        result_data = {}
        def on_submit(event=None):
            for fname, widget in entries.items():
                result_data[fname] = widget.get()
            root.destroy()
        def on_cancel(event=None):
            root.destroy()
        btn_frame = ttk.Frame(main_frame)
        btn_frame.grid(row=row, column=0, sticky="e", pady=(15, 0))
        cancel_btn = ttk.Button(btn_frame, text="Cancelar", command=on_cancel)
        cancel_btn.pack(side=tk.RIGHT, padx=(8, 0))
        ok_btn = ttk.Button(btn_frame, text="Preencher", command=on_submit)
        ok_btn.pack(side=tk.RIGHT)
        root.bind("<Return>", on_submit)
        root.bind("<Escape>", on_cancel)
        for widget in entries.values():
            widget.focus_set()
            break
        root.mainloop()
        return result_data
    except Exception:
        cmd = ["zenity", "--forms", f"--title=Espanso - {config_path.stem}", "--text=Preencha as informações:"]
        fields_order = []
        for field_name, field_info in properties.items():
            cmd.append(f"--add-entry={field_info.get('title', field_name)}")
            fields_order.append(field_name)
        import subprocess
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
            if res.returncode != 0 or not res.stdout.strip():
                return {}
            values = res.stdout.strip().split("|")
            return {fname: (values[i] if i < len(values) else "") for i, fname in enumerate(fields_order)}
        except Exception:
            return {}
EOF

# Atualiza utils.py para suportar uinput e lazy loading de spacy
python3 -c "
utils_path = '$ESPANSO_CONFIG_DIR/scripts/lib/utils.py'
if os.path.exists(utils_path):
    with open(utils_path, 'r', encoding='utf-8') as f:
        code = f.read()
    code = code.replace('import spacy\n', '')
    if 'def paste_text():' in code:
        code = code.replace('def paste_text():\n    os.system(\x27powershell -NoProfile', 'def paste_text():\n    if sys.platform.startswith(\"win\"): return\n    # Linux paste\n    os.system(\x27#\x27')
    if 'run_gui_form' not in code:
        code = code.replace('if not os.path.exists(edf_path):', 'if not os.path.exists(edf_path):\n        from lib.form_runner import run_gui_form\n        return run_gui_form(form_config_to_run)')
    with open(utils_path, 'w', encoding='utf-8') as f:
        f.write(code)
" 2>/dev/null || true

chown -R "$REAL_USER:$REAL_USER" "$ESPANSO_CONFIG_DIR" 2>/dev/null || true

# Registra e inicia o serviço do Espanso no usuário
if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    sudo -u "$REAL_USER" espanso service register 2>/dev/null || true
    sudo -u "$REAL_USER" espanso start 2>/dev/null || true
else
    espanso service register 2>/dev/null || true
    espanso start 2>/dev/null || true
fi

# 5. Kando
log_msg "INFO" "Baixando e instalando Kando (Pie Menu)..."
KANDO_URL=$(curl -s https://api.github.com/repos/kando-menu/kando/releases/latest | jq -r '.assets[] | select(.name | endswith("amd64.deb")) | .browser_download_url')
wget -qO /tmp/kando.deb "$KANDO_URL"
sudo apt install -y /tmp/kando.deb

# Wrapper de compatibilidade do Kando para COSMIC Desktop / Wayland (XWayland)
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

# Limpeza
rm -f /tmp/espanso.deb /tmp/kando.deb

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Softwares de workflow instalados e configurados com sucesso."
