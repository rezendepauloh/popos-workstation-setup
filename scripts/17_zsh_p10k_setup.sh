#!/bin/bash
# ==============================================================================
# Módulo 14: Configuração do Terminal ZSH, Powerlevel10k e Fontes MesloLGS NF
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="ZSH_CONFIG"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Configuração do Terminal ZSH já aplicada anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "17. CONFIGURAÇÃO DO TERMINAL ZSH E POWERLEVEL10K"

ZSH_INSTALL_DIR="$REAL_HOME/GoogleDrive_Pessoal/Organização/Terminal ZSH Linux"

if [ -f "$ZSH_INSTALL_DIR/install.sh" ]; then
    log_msg "INFO" "Executando script de instalação do ZSH a partir do Google Drive..."
    chmod +x "$ZSH_INSTALL_DIR/install.sh"
    sudo -u "$REAL_USER" bash "$ZSH_INSTALL_DIR/install.sh" 2>/dev/null || bash "$ZSH_INSTALL_DIR/install.sh"
    
    # Restauração dos dotfiles
    if [ -f "$ZSH_INSTALL_DIR/.zshrc" ]; then
        cp "$ZSH_INSTALL_DIR/.zshrc" "$REAL_HOME/.zshrc"
    fi
    if [ -f "$ZSH_INSTALL_DIR/.p10k.zsh" ]; then
        cp "$ZSH_INSTALL_DIR/.p10k.zsh" "$REAL_HOME/.p10k.zsh"
    fi
fi

# Instalação automática das 4 variantes completas da fonte MesloLGS NF (Nerd Font)
log_msg "INFO" "Instalando fontes MesloLGS NF para o Powerlevel10k..."
mkdir -p "$REAL_HOME/.local/share/fonts"
MESLO_URL="https://github.com/romkatv/powerlevel10k-media/raw/master"
for font in "MesloLGS%20NF%20Regular.ttf" "MesloLGS%20NF%20Bold.ttf" "MesloLGS%20NF%20Italic.ttf" "MesloLGS%20NF%20Bold%20Italic.ttf"; do
    font_name=$(echo "$font" | sed 's/%20/ /g')
    if [ ! -f "$REAL_HOME/.local/share/fonts/$font_name" ]; then
        curl -fsSL "$MESLO_URL/$font" -o "$REAL_HOME/.local/share/fonts/$font_name" 2>/dev/null || true
    fi
done
fc-cache -f "$REAL_HOME/.local/share/fonts" 2>/dev/null || true

# Define o Zsh como o shell padrão do usuário no sistema
ZSH_BIN="$(which zsh 2>/dev/null || echo '/usr/bin/zsh')"
if [ -x "$ZSH_BIN" ]; then
    sudo chsh -s "$ZSH_BIN" "$REAL_USER" 2>/dev/null || sudo usermod -s "$ZSH_BIN" "$REAL_USER" 2>/dev/null || true
    log_msg "INFO" "Zsh definido como shell padrão para o usuário $REAL_USER."
fi

# Garante atalhos de produtividade no ~/.zshrc (Ctrl+V para colar via wl-paste/xclip e ESC para limpar linha)
if ! grep -q "paste-from-clipboard" "$REAL_HOME/.zshrc" 2>/dev/null; then
    cat << 'EOF' >> "$REAL_HOME/.zshrc"

# Limpar a linha atual ao pressionar ESC (comportamento estilo PowerShell / Windows)
bindkey -M emacs '\e' kill-whole-line
bindkey -M viins '\e' kill-whole-line
export XCOMPOSEFILE="$HOME/.XCompose"

# Colar da Área de Transferência com Ctrl+V no Terminal ZSH (Wayland / wl-paste & X11 / xclip)
paste-from-clipboard() {
    local text
    if command -v wl-paste >/dev/null 2>&1; then
        text=$(wl-paste --no-newline 2>/dev/null)
    elif command -v xclip >/dev/null 2>&1; then
        text=$(xclip -selection clipboard -o 2>/dev/null)
    fi
    LBUFFER="${LBUFFER}${text}"
}
zle -N paste-from-clipboard
bindkey '^V' paste-from-clipboard
bindkey -M emacs '^V' paste-from-clipboard
bindkey -M viins '^V' paste-from-clipboard
EOF
fi

chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.local/share/fonts"
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.zshrc" 2>/dev/null || true
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.p10k.zsh" 2>/dev/null || true

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Terminal ZSH, Powerlevel10k e atalhos de produtividade configurados com sucesso."
