#!/bin/bash

# ==============================================================================
# CONFIGURAÇÕES VISUAIS (Fru-Fru ANSI)
# ==============================================================================
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_CYAN="\033[36m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_RED="\033[31m"
C_MAGENTA="\033[35m"
C_GRAY="\033[90m"

# ==============================================================================
# DIRETÓRIOS E ARQUIVOS DE LOGGING (Salvos na pasta Logs/ local)
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/Logs"
mkdir -p "$LOG_DIR"

STATE_FILE="$LOG_DIR/.setup_estado.log"
LOG_FILE="$LOG_DIR/.setup_execucao.log"
touch "$STATE_FILE" "$LOG_FILE"

# ==============================================================================
# CARREGAR VARIÁVEIS DE AMBIENTE (.env)
# ==============================================================================
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$SCRIPT_DIR/.env"
    set +a
fi

# Função padronizada de logging
log_msg() {
    local LEVEL="$1"
    local MSG="$2"
    local TIMESTAMP
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

    # Gravação no arquivo de log sem caracteres de escape ANSI
    echo "[$TIMESTAMP] [$LEVEL] $MSG" >> "$LOG_FILE"

    # Saída no terminal formatada com cores
    case "$LEVEL" in
        "INFO")    echo -e "${C_CYAN}[$TIMESTAMP] [INFO]${C_RESET} $MSG" ;;
        "SUCCESS") echo -e "${C_GREEN}${C_BOLD}[$TIMESTAMP] [OK]${C_RESET} ${C_GREEN}$MSG${C_RESET}" ;;
        "WARN")    echo -e "${C_YELLOW}[$TIMESTAMP] [WARN]${C_RESET} $MSG" ;;
        "ERROR")   echo -e "${C_RED}${C_BOLD}[$TIMESTAMP] [ERROR]${C_RESET} ${C_RED}$MSG${C_RESET}" ;;
        *)         echo "[$TIMESTAMP] [$LEVEL] $MSG" ;;
    esac
}

# Função para verificar se uma flag já foi concluída
check_flag() {
    grep -q "^$1=1$" "$STATE_FILE"
}

# Função para registrar uma flag como concluída
set_flag() {
    echo "$1=1" >> "$STATE_FILE"
    log_msg "SUCCESS" "Etapa '$1' concluída e registrada com sucesso."
    echo ""
}

# Função para verificar se o Google Drive foi montado com sucesso
verificar_gdrive_montado() {
    local GDRIVE_PATH="$HOME/GoogleDrive_Pessoal"
    
    # 1. Verifica se o caminho é um mountpoint ativo (FUSE / findmnt)
    if mountpoint -q "$GDRIVE_PATH" 2>/dev/null || findmnt "$GDRIVE_PATH" >/dev/null 2>&1; then
        return 0
    fi
    
    # 2. Verifica se a pasta existe e possui conteúdo sincronizado (não está vazia)
    if [ -d "$GDRIVE_PATH" ] && [ -n "$(ls -A "$GDRIVE_PATH" 2>/dev/null)" ]; then
        return 0
    fi
    
    return 1
}

log_msg "INFO" "🚀 Iniciando provisionamento do Pop!_OS..."

# ==============================================================================
# 1. OTMIZAÇÕES DE SISTEMA E KERNEL (Aprimorando a experiência Linux)
# ==============================================================================
if ! check_flag "OTIMIZACAO_SISTEMA"; then
    log_msg "INFO" "⚙️  Aplicando otimizações de Kernel (Swappiness e Inotify)..."
    if {
        # Reduz o uso de paginação (Swappiness). Com 32 GB de RAM, o sistema não 
        # precisa usar o SSD para memória virtual com frequência. (Padrão: 60, Novo: 10)
        sudo sysctl -w vm.swappiness=10
        echo "vm.swappiness=10" | sudo tee /etc/sysctl.d/99-swappiness.conf > /dev/null

        # Aumenta o limite de "File Watchers". Essencial para o VS Code, Git e o seu 
        # Antigravity lidarem com monorepos gigantes sem travar.
        sudo sysctl -w fs.inotify.max_user_watches=524288
        echo "fs.inotify.max_user_watches=524288" | sudo tee /etc/sysctl.d/99-inotify.conf > /dev/null
    }; then
        set_flag "OTIMIZACAO_SISTEMA"
    else
        log_msg "ERROR" "❌ Falha ao aplicar otimizações de sistema. Verifique as permissões de root."
        exit 1
    fi
fi

# ==============================================================================
# 2. CONFIGURAÇÕES DE TECLADO E USABILIDADE (Redragon Horus Pro & Janelas)
# ==============================================================================
if ! check_flag "CONFIG_TECLADO"; then
    log_msg "INFO" "⌨️  Ajustando Backspace ultra-rápido, Layout US-Intl, Cedilha e Aspas Windows..."
    if {
        # Resposta ultra-rápida do teclado (padrão Windows no máximo: 180ms delay / 18ms repetição)
        gsettings set org.gnome.desktop.peripherals.keyboard delay 180
        gsettings set org.gnome.desktop.peripherals.keyboard repeat-interval 18
    
        # Layout US Internacional tradicional com Dead Keys (idêntico ao Windows)
        gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'us+intl')]"

        # Ativação Robusta do Teclado Numérico (NumLock) em múltiplos níveis:
        # 1. COSMIC Compositor nativo (numlock_state)
        mkdir -p "$HOME/.config/cosmic/com.system76.CosmicComp/v1"
        echo "true" > "$HOME/.config/cosmic/com.system76.CosmicComp/v1/numlock_state"

        # 2. GNOME / GSettings
        gsettings set org.gnome.desktop.peripherals.keyboard numlock-state true
        gsettings set org.gnome.desktop.peripherals.keyboard remember-numlock-state true

        # 3. Autostart de Sessão Desktop (COSMIC / GNOME / Wayland / X11)
        mkdir -p "$HOME/.config/autostart"
        cat << 'EOF' > "$HOME/.config/autostart/numlock.desktop"
[Desktop Entry]
Type=Application
Name=NumLock Auto-On
Exec=/bin/bash -c 'numlockx on 2>/dev/null || true; for led in /sys/class/leds/*::numlock/brightness; do echo 1 > "$led" 2>/dev/null || true; done'
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

        # 4. Systemd Service e Udev Rules para Boot e Teclados Sem Fio / USB
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
        fi

        if [ -d /etc/udev/rules.d ]; then
            cat << 'EOF' | sudo tee /etc/udev/rules.d/99-numlock.rules > /dev/null
ACTION=="add", SUBSYSTEM=="leds", KERNEL=="*::numlock", ATTR{brightness}="1"
EOF
            sudo udevadm control --reload-rules 2>/dev/null || true
        fi

        # 5. Ativação Imediata na sessão atual
        numlockx on 2>/dev/null || true
        for led in /sys/class/leds/*::numlock/brightness; do
            echo 1 | sudo tee "$led" >/dev/null 2>&1 || true
        done

        # Botões de Maximizar, Minimizar e Fechar nas janelas (estilo Windows)
        gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close'
        gsettings set org.gnome.desktop.wm.preferences action-middle-click-titlebar 'minimize'

        # Comportamento Idêntico ao Windows (Cedilha direta ' + c = ç, '' e "" sem trema ¨)
        cat << 'EOF' > "$HOME/.XCompose"
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

        # Exporta XCOMPOSEFILE no ambiente do usuário e do sistema
        grep -q "XCOMPOSEFILE" "$HOME/.zshrc" 2>/dev/null || echo 'export XCOMPOSEFILE="$HOME/.XCompose"' >> "$HOME/.zshrc"
        grep -q "XCOMPOSEFILE" "$HOME/.bashrc" 2>/dev/null || echo 'export XCOMPOSEFILE="$HOME/.XCompose"' >> "$HOME/.bashrc"
        grep -q "XCOMPOSEFILE" "$HOME/.profile" 2>/dev/null || echo 'export XCOMPOSEFILE="$HOME/.XCompose"' >> "$HOME/.profile"

        # Corrige a tabela oficial de Compose do sistema (en_US.UTF-8)
        if [ -f /usr/share/X11/locale/en_US.UTF-8/Compose ]; then
            sudo cp -n /usr/share/X11/locale/en_US.UTF-8/Compose /usr/share/X11/locale/en_US.UTF-8/Compose.bak 2>/dev/null || true
            sudo sed -i 's/"ć"\s*U0107/"ç"\tccedilla/g' /usr/share/X11/locale/en_US.UTF-8/Compose
            sudo sed -i 's/"Ć"\s*U0106/"Ç"\tCcedilla/g' /usr/share/X11/locale/en_US.UTF-8/Compose
            sudo sed -i 's/<dead_diaeresis> <dead_diaeresis>\s*:\s*"¨"\s*diaeresis/<dead_diaeresis> <dead_diaeresis>\t: "\\"\\""\tquotedbl/g' /usr/share/X11/locale/en_US.UTF-8/Compose
            sudo sed -i "s/<dead_acute> <dead_acute>\s*:\s*\"´\"\s*acute/<dead_acute> <dead_acute>\t: \"''\"\tapostrophe/g" /usr/share/X11/locale/en_US.UTF-8/Compose
        fi

        # Patch no GTK immodules.cache para suporte a Cedilha em Webviews (Antigravity Chat, Chrome, VS Code)
        for cache in /usr/lib/x86_64-linux-gnu/gtk-3.0/3.0.0/immodules.cache /usr/lib/x86_64-linux-gnu/gtk-2.0/2.10.0/immodules.cache; do
            if [ -f "$cache" ]; then
                sudo sed -i 's/"az:ca:co:fr:gv:oc:pt:sq:tr:wa"/"az:ca:co:fr:gv:oc:pt:sq:tr:wa:en:en_US"/g' "$cache"
            fi
        done

        # Remove módulos legados do /etc/environment que quebram Wayland / GTK4 / COSMIC
        sudo sed -i '/GTK_IM_MODULE/d' /etc/environment 2>/dev/null || true
        sudo sed -i '/QT_IM_MODULE/d' /etc/environment 2>/dev/null || true
        sudo sed -i '/XCOMPOSEFILE/d' /etc/environment 2>/dev/null || true
        echo "XCOMPOSEFILE=$HOME/.XCompose" | sudo tee -a /etc/environment > /dev/null
    }; then
        set_flag "CONFIG_TECLADO"
    else
        log_msg "ERROR" "❌ Falha ao configurar o teclado e usabilidade via gsettings."
        exit 1
    fi
fi

# ==============================================================================
# 3. ATUALIZAÇÃO E DEPENDÊNCIAS BASE, RUST / RCLONE OFICIAL E NAVEGADORES
# ==============================================================================
if ! check_flag "APT_UPDATE"; then
    log_msg "INFO" "📦 Instalando pacotes base, fontes e navegadores..."
    if {
        sudo apt update && sudo apt upgrade -y
        
        # Pré-aceita licença para fontes Microsoft TrueType
        echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | sudo debconf-set-selections 2>/dev/null || true
        
        sudo apt install -y curl git flatpak vlc zsh apt-transport-https wget gpg software-properties-common jq piper ratbagd unzip numlockx fonts-firacode fonts-jetbrains-mono ttf-mscorefonts-installer
        
        # Instalação oficial e binária do Rclone
        sudo -v ; curl -fsSL https://rclone.org/install.sh | sudo bash
        
        sudo install -m 0755 -d /usr/share/keyrings /etc/apt/keyrings
        
        # Google Chrome
        wget -qO- https://dl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor --yes -o /usr/share/keyrings/google-chrome.gpg
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list > /dev/null
        
        # Brave Browser
        sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser-release.list > /dev/null

        sudo apt update
        sudo apt install -y google-chrome-stable brave-browser
    }; then
        set_flag "APT_UPDATE"
    else
        log_msg "ERROR" "❌ Falha ao instalar dependências base."
        exit 1
    fi
fi

# ==============================================================================
# 4. INSTALAÇÃO DO DOCKER ENGINE
# ==============================================================================
if ! check_flag "DOCKER_INSTALL"; then
    log_msg "INFO" "🐳 Instalando Docker Engine (Nativo)..."
    if {
        for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove -y $pkg; done
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        sudo usermod -aG docker $USER
        sudo systemctl enable docker
        sudo systemctl start docker
    }; then
        log_msg "SUCCESS" "Docker instalado! (Rodar 'newgrp docker' depois)."
        set_flag "DOCKER_INSTALL"
    else
        log_msg "ERROR" "❌ Falha na instalação do Docker."
        exit 1
    fi
fi

# ==============================================================================
# 4.1. MONTAGEM DE DISCOS FÍSICOS E REDIRECIONAMENTO DE PASTAS
# ==============================================================================
if ! check_flag "DISKS_MOUNT"; then
    log_msg "INFO" "💽 Configurando montagem automática de discos e redirecionamento de Downloads..."
    if {
        # UUIDs mapeados do seu sistema (Atualizados)
        UUID_STORAGE_930="77458614-fc65-420d-83ef-43d200dfc0f6"
        UUID_STORAGE_700="88689a5b-525e-4abe-a968-22dfb83e202a"
        UUID_NVME_01="72be8ed0-e5d4-424c-a93a-5545d57a48d7"
        
        # Cria os pontos de montagem definitivos
        sudo mkdir -p /mnt/storage_930 /mnt/storage_700 /mnt/nvme_01
        
        # Faz backup do fstab atual por segurança
        sudo cp /etc/fstab /etc/fstab.backup
        
        # Remove entradas anteriores se você rodar o script duas vezes
        sudo sed -i '/storage_930/d' /etc/fstab
        sudo sed -i '/storage_700/d' /etc/fstab
        sudo sed -i '/nvme_01/d' /etc/fstab
        
        # Adiciona as novas regras de montagem no fstab (Todos em ext4)
        echo "UUID=$UUID_STORAGE_930 /mnt/storage_930 ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab
        echo "UUID=$UUID_STORAGE_700 /mnt/storage_700 ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab
        echo "UUID=$UUID_NVME_01 /mnt/nvme_01 ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab
        
        # Recarrega o daemon do systemd para reconhecer o novo fstab e monta
        sudo systemctl daemon-reload
        sudo mount -a
        
        # Concede permissão total de posse e leitura/escrita ao usuário para todos os discos ext4
        sudo chown -R $USER:$USER /mnt/storage_930 /mnt/storage_700 /mnt/nvme_01
        sudo chmod -R 775 /mnt/storage_930 /mnt/storage_700 /mnt/nvme_01
        
        # Cria a pasta Downloads dentro do HD 700 (se ainda não existir)
        mkdir -p /mnt/storage_700/Downloads
        
        # Atualiza o apontamento do sistema para a pasta Downloads
        mkdir -p "$HOME/.config"
        if [ -f "$HOME/.config/user-dirs.dirs" ]; then
            sed -i 's|^XDG_DOWNLOAD_DIR=.*|XDG_DOWNLOAD_DIR="/mnt/storage_700/Downloads"|' "$HOME/.config/user-dirs.dirs"
        else
            echo 'XDG_DOWNLOAD_DIR="/mnt/storage_700/Downloads"' >> "$HOME/.config/user-dirs.dirs"
        fi
        
    }; then
        log_msg "SUCCESS" "Discos montados e pasta Downloads redirecionada. O explorador atualizará após reiniciar a sessão."
        set_flag "DISKS_MOUNT"
    else
        log_msg "ERROR" "Falha ao configurar o fstab ou os diretórios."
        exit 1
    fi
fi

# ==============================================================================
# 4.5. CONFIGURAÇÃO DO RCLONE (Automatizada / Interativa)
# ==============================================================================
if ! check_flag "RCLONE_CONFIG"; then
    log_msg "INFO" "🔑 Verificando configurações do Rclone..."
    if {
        # Tenta fallback 1: Copiar rclone.conf se existir na pasta do script
        if [ -f "$SCRIPT_DIR/rclone.conf" ]; then
            log_msg "INFO" "Arquivo rclone.conf encontrado! Copiando para ~/.config/rclone/..."
            mkdir -p ~/.config/rclone
            cp "$SCRIPT_DIR/rclone.conf" ~/.config/rclone/rclone.conf
            chmod 600 ~/.config/rclone/rclone.conf
        fi

        # REMOTES_NECESSARIOS=("onedrive_mpms" "onedrive_pessoal" "mega_pessoal" "gdrive_pessoal")
        REMOTES_NECESSARIOS=("onedrive_pessoal" "mega_pessoal" "gdrive_pessoal")
        
        for remote in "${REMOTES_NECESSARIOS[@]}"; do
            # Se o remote não existir na lista
            if ! rclone listremotes | grep -q "^${remote}:"; then
                # Se as variaveis de ambiente (.env) não criaram automaticamente o remote, pede iterativo
                log_msg "WARN" "⚠️ Remote '${remote}' não está configurado."
                log_msg "WARN" "Abrindo o assistente interativo do Rclone..."
                log_msg "WARN" "Por favor, crie um novo remote com o nome exato: ${remote}"
                rclone config
            else
                log_msg "INFO" "Remote '${remote}' já configurado."
            fi
        done
    }; then
        set_flag "RCLONE_CONFIG"
    else
        log_msg "ERROR" "❌ Ocorreu um problema ao configurar as nuvens no Rclone."
        exit 1
    fi
fi

# ==============================================================================
# 5. MONTAGEM DE NUVENS (Rclone VFS)
# ==============================================================================
if ! check_flag "RCLONE_SERVICES"; then
    log_msg "INFO" "☁️  Configurando serviços Systemd para Múltiplas Nuvens..."
    if {
        mkdir -p ~/.config/systemd/user/ ~/GoogleDrive_Pessoal ~/OneDrive_Pessoal ~/MEGA_Pessoal

        criar_servico_rclone() {
            cat << EOF > ~/.config/systemd/user/$1.service
[Unit]
Description=Rclone Mount: $2
After=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/rclone mount $2: %h/$3 --vfs-cache-mode full --vfs-cache-max-age 720h --vfs-cache-max-size 50G
ExecStop=/bin/fusermount -u %h/$3
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF
        }

        criar_servico_rclone "gdrive-pessoal" "gdrive_pessoal" "GoogleDrive_Pessoal"
        criar_servico_rclone "onedrive-pessoal" "onedrive_pessoal" "OneDrive_Pessoal"
        criar_servico_rclone "mega-pessoal" "mega_pessoal" "MEGA_Pessoal"

        systemctl --user daemon-reload
        systemctl --user enable gdrive-pessoal.service onedrive-pessoal.service mega-pessoal.service
        systemctl --user start gdrive-pessoal.service onedrive-pessoal.service mega-pessoal.service
        
        # Breve espera para o FUSE montar
        sleep 2
        
        if verificar_gdrive_montado; then
            log_msg "SUCCESS" "Google Drive montado com sucesso em '$HOME/GoogleDrive_Pessoal'."
        else
            log_msg "WARN" "⚠️ Google Drive ainda não montou ou o remote aguarda autenticação. O script continuará normalmente."
        fi
    }; then
        set_flag "RCLONE_SERVICES"
    else
        log_msg "ERROR" "❌ Falha ao criar/iniciar serviços Systemd do Rclone."
        exit 1
    fi
fi

# ==============================================================================
# 6. INSTALAÇÃO DE SOFTWARES DE WORKFLOW (Flatpak, VS Code, Binários)
# ==============================================================================
if ! check_flag "SOFTWARE_INSTALL"; then
    log_msg "INFO" "💽 Instalando aplicativos (VS Code, Dropbox, CopyQ, OnlyOffice, Jellyfin Client/Server, Espanso, Kando)..."
    if {
        
        # Repositório Oficial do VS Code
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor --yes -o /etc/apt/keyrings/packages.microsoft.gpg
        echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
        sudo apt update
        sudo apt install -y code
        
        # Adiciona repositórios Flatpak
        flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
        
        # Flatpaks essenciais (usando system para evitar prompts interativos)
        flatpak install -y --system flathub com.dropbox.Client com.github.hluk.copyq org.onlyoffice.desktopeditors org.jellyfin.JellyfinDesktop org.gimp.GIMP
        
        # Jellyfin Media Server (Repositório Oficial e Pacote Nativo)
        log_msg "INFO" "Instalando repositório e pacote do Jellyfin Server..."
        curl -fsSL https://repo.jellyfin.org/jellyfin_team.gpg.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/jellyfin.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/jellyfin.gpg] https://repo.jellyfin.org/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") main" | sudo tee /etc/apt/sources.list.d/jellyfin.list > /dev/null
        sudo apt update
        sudo apt install -y jellyfin

        # Espanso (Wayland Edition) e dependências de compatibilidade no Ubuntu / Pop!_OS 24.04 (noble)
        log_msg "INFO" "Baixando e instalando Espanso..."
        wget -qO /tmp/espanso.deb https://github.com/espanso/espanso/releases/download/v2.2.1/espanso-debian-wayland-amd64.deb
        sudo apt install -y /tmp/espanso.deb

        # Bibliotecas de compatibilidade wxWidgets 3.0 para o Espanso no Ubuntu 24.04
        sudo mkdir -p /usr/local/lib/espanso
        wget -qO /tmp/libwxbase3.0.deb http://archive.ubuntu.com/ubuntu/pool/universe/w/wxwidgets3.0/libwxbase3.0-0v5_3.0.5.1+dfsg-4_amd64.deb || true
        wget -qO /tmp/libwxgtk3.0.deb http://archive.ubuntu.com/ubuntu/pool/universe/w/wxwidgets3.0/libwxgtk3.0-gtk3-0v5_3.0.5.1+dfsg-4_amd64.deb || true
        if [ -f /tmp/libwxbase3.0.deb ] && [ -f /tmp/libwxgtk3.0.deb ]; then
            mkdir -p /tmp/wx_extract
            dpkg-deb -x /tmp/libwxbase3.0.deb /tmp/wx_extract
            dpkg-deb -x /tmp/libwxgtk3.0.deb /tmp/wx_extract
            sudo cp -rn /tmp/wx_extract/usr/lib/x86_64-linux-gnu/* /usr/local/lib/espanso/
            rm -rf /tmp/wx_extract /tmp/libwx*.deb
        fi
        if [ -f /usr/lib/x86_64-linux-gnu/libtiff.so.6 ] && [ ! -f /usr/local/lib/espanso/libtiff.so.5 ]; then
            sudo ln -sf /usr/lib/x86_64-linux-gnu/libtiff.so.6 /usr/local/lib/espanso/libtiff.so.5
        fi
        echo "/usr/local/lib/espanso" | sudo tee /etc/ld.so.conf.d/espanso.conf > /dev/null
        sudo ldconfig
        
        # Kando
        log_msg "INFO" "Baixando e instalando Kando..."
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

        # Atualiza o lançador .desktop do Kando
        if [ -f /usr/share/applications/menu.kando.Kando.desktop ]; then
            sudo sed -i 's|^Exec=.*|Exec=env XDG_SESSION_TYPE=x11 GDK_BACKEND=x11 /usr/lib/kando/kando %U|' /usr/share/applications/menu.kando.Kando.desktop
            sudo update-desktop-database /usr/share/applications 2>/dev/null || true
        fi
        
        # Registra e inicia o serviço do Espanso da forma nativa
        espanso service register 2>/dev/null || true
        espanso start 2>/dev/null || true
        
        # Limpeza
        rm -f /tmp/espanso.deb /tmp/kando.deb
        
    }; then
        set_flag "SOFTWARE_INSTALL"
    else
        log_msg "ERROR" "❌ Falha ao instalar pacotes de workflow."
        exit 1
    fi
fi

# ==============================================================================
# 6.5. INSTALAÇÃO DO ANTIGRAVITY IDE (Google Antigravity)
# ==============================================================================
if ! check_flag "ANTIGRAVITY_INSTALL"; then
    log_msg "INFO" "🚀 Baixando e instalando o Antigravity IDE..."
    if {
        ANTIGRAVITY_URL="https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.5.5-4923483625488384/linux-x64/Antigravity%20IDE.tar.gz"
        wget -qO /tmp/antigravity.tar.gz "$ANTIGRAVITY_URL"
        
        sudo mkdir -p /opt/antigravity
        sudo tar -xzf /tmp/antigravity.tar.gz -C /opt/antigravity --strip-components=1
        sudo chmod -R 755 /opt/antigravity
        sudo chmod +x /opt/antigravity/antigravity-ide /opt/antigravity/bin/antigravity-ide
        
        # Ajuste de permissões do sandbox do Electron
        if [ -f /opt/antigravity/chrome-sandbox ]; then
            sudo chown root:root /opt/antigravity/chrome-sandbox
            sudo chmod 4755 /opt/antigravity/chrome-sandbox
        fi

        # Perfil do AppArmor para Pop!_OS 24.04 (permite User Namespaces do Electron)
        if [ -d /etc/apparmor.d ]; then
            cat << 'EOF' | sudo tee /etc/apparmor.d/antigravity > /dev/null
abi <abi/4.0>,
include <tunables/global>

profile antigravity /opt/antigravity/antigravity-ide flags=(unconfined) {
  userns,
  include if exists <local/antigravity>
}
EOF
            sudo apparmor_parser -r /etc/apparmor.d/antigravity 2>/dev/null || true
        fi
        
        # Criação de links simbólicos no PATH e na raiz do /opt/antigravity
        sudo ln -sf /opt/antigravity/bin/antigravity-ide /usr/local/bin/antigravity
        sudo ln -sf /opt/antigravity/bin/antigravity-ide /usr/local/bin/antigravity-ide
        sudo ln -sf /opt/antigravity/bin/antigravity-ide /usr/local/bin/agy
        sudo ln -sf /opt/antigravity/antigravity-ide /opt/antigravity/antigravity
        
        # Ícones do sistema (Pixmaps, Hicolor e fallback local)
        if [ -f /opt/antigravity/resources/app/resources/linux/code.png ]; then
            sudo ln -sf /opt/antigravity/resources/app/resources/linux/code.png /opt/antigravity/icon.png
            sudo cp /opt/antigravity/resources/app/resources/linux/code.png /usr/share/pixmaps/antigravity.png
            sudo cp /opt/antigravity/resources/app/resources/linux/code.png /usr/share/pixmaps/antigravity-ide.png
            sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
            sudo cp /opt/antigravity/resources/app/resources/linux/code.png /usr/share/icons/hicolor/512x512/apps/antigravity.png
            sudo cp /opt/antigravity/resources/app/resources/linux/code.png /usr/share/icons/hicolor/512x512/apps/antigravity-ide.png
            sudo gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
        fi
        
        # Remove lançador obsoleto/quebrado na home do usuário que possa sobrepor o sistema
        rm -f "$HOME/.local/share/applications/antigravity.desktop"
        
        # Entrada .desktop para o menu de aplicações
        cat << 'EOF' | sudo tee /usr/share/applications/antigravity.desktop > /dev/null
[Desktop Entry]
Name=Antigravity
Comment=Google Antigravity IDE
GenericName=Text Editor
Exec=/opt/antigravity/antigravity-ide %F
Icon=antigravity
Type=Application
StartupNotify=false
StartupWMClass=antigravity-ide
Categories=Development;IDE;TextEditor;
MimeType=text/plain;inode/directory;application/x-code-workspace;
Keywords=vscode;development;ide;antigravity;agy;
EOF

        sudo update-desktop-database /usr/share/applications 2>/dev/null || true
        update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

        # Limpeza
        rm -f /tmp/antigravity.tar.gz
    }; then
        set_flag "ANTIGRAVITY_INSTALL"
    else
        log_msg "ERROR" "❌ Falha ao instalar o Antigravity IDE."
        exit 1
    fi
fi

# ==============================================================================
# 7. CONFIGURANDO ONLYOFFICE COMO PADRÃO
# ==============================================================================
if ! check_flag "ONLYOFFICE_DEFAULT"; then
    log_msg "INFO" "📄 Definindo OnlyOffice como padrão..."
    if {
        # Associa arquivos .docx, .xlsx e .pptx ao OnlyOffice
        xdg-mime default org.onlyoffice.desktopeditors.desktop application/vnd.openxmlformats-officedocument.wordprocessingml.document
        xdg-mime default org.onlyoffice.desktopeditors.desktop application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
        xdg-mime default org.onlyoffice.desktopeditors.desktop application/vnd.openxmlformats-officedocument.presentationml.presentation
    }; then
        set_flag "ONLYOFFICE_DEFAULT"
    else
        log_msg "ERROR" "❌ Falha ao definir leitor padrão via xdg-mime."
        exit 1
    fi
fi

# ==============================================================================
# 7.5. MINIAPLICATIVO DE CONTROLE DE MÍDIA (cosmic-applet-music-player)
# ==============================================================================
if ! check_flag "COSMIC_MUSIC_APPLET"; then
    log_msg "INFO" "🎵 Baixando e instalando o miniaplicativo de controle de mídia para o COSMIC..."
    if {
        sudo apt update
        sudo apt install -y cargo rustc just pkg-config libssl-dev libdbus-1-dev git libglib2.0-dev libasound2-dev libxkbcommon-dev libwayland-dev libfontconfig1-dev libfreetype6-dev libpipewire-0.3-dev libspa-0.2-dev
        
        BUILD_DIR="/tmp/cosmic-applet-music-player-build"
        rm -rf "$BUILD_DIR"
        git clone --depth 1 https://github.com/Ebbo/cosmic-applet-music-player.git "$BUILD_DIR"
        cd "$BUILD_DIR"
        
        cargo build --release --manifest-path music-player/Cargo.toml
        
        sudo install -Dm755 music-player/target/release/cosmic-ext-applet-music-player /usr/bin/cosmic-ext-applet-music-player
        if [ -f res/com.github.MusicPlayer.desktop ]; then
            sudo install -Dm644 res/com.github.MusicPlayer.desktop /usr/share/applications/com.github.MusicPlayer.desktop
        fi
        if [ -f res/com.github.MusicPlayer.metainfo.xml ]; then
            sudo install -Dm644 res/com.github.MusicPlayer.metainfo.xml /usr/share/metainfo/com.github.MusicPlayer.metainfo.xml
        fi
        if [ -d res/icons ]; then
            sudo cp -r res/icons/* /usr/share/icons/ 2>/dev/null || true
        fi
        sudo update-desktop-database /usr/share/applications 2>/dev/null || true
        rm -rf "$BUILD_DIR"
        
        set_flag "COSMIC_MUSIC_APPLET"
    }; then
        :
    else
        log_msg "ERROR" "❌ Falha ao compilar/instalar o miniaplicativo de mídia."
        exit 1
    fi
fi

# ==============================================================================
# 8. JELLYFIN SERVER (Restauração)
# ==============================================================================
#if ! check_flag "JELLYFIN_RESTORE"; then
#    log_msg "INFO" "🎬 Verificando restauração do Jellyfin Server..."
#    
#    if ! verificar_gdrive_montado; then
#        log_msg "WARN" "⚠️ Google Drive não está montado em '$HOME/GoogleDrive_Pessoal'. Pulando restauração do Jellyfin Server por enquanto..."
#    else
#        BACKUP_ONEDRIVE="$HOME/GoogleDrive_Pessoal/Jellyfin_backup"
#        JELLYFIN_DATA="/var/lib/jellyfin"
#        
#        if [ -d "$BACKUP_ONEDRIVE" ]; then
#            if {
#                sudo systemctl stop jellyfin
#                sudo rsync -avP "$BACKUP_ONEDRIVE/" "$JELLYFIN_DATA/"
#                sudo chown -R jellyfin:jellyfin "$JELLYFIN_DATA"
#                sudo systemctl start jellyfin
#            }; then
#                set_flag "JELLYFIN_RESTORE"
#            else
#                log_msg "ERROR" "❌ Falha na restauração do Jellyfin."
#                exit 1
#            fi
#        else
#            log_msg "WARN" "⚠️ Backup não encontrado. Ignorando..."
#        fi
#    fi
#fi

# ==============================================================================
# 9. CONFIGURAÇÃO DE MACROS LOGITECH G502 X E PERFIL DO MOUSE
# ==============================================================================
if ! check_flag "CONFIG_MOUSE"; then
    log_msg "INFO" "🖱️ Configurando aceleração linear e macros na memória do G502 X..."
    if {
        # Desativa a aceleração de mouse dinâmica (perfil plano linear 1:1 como no Windows)
        gsettings set org.gnome.desktop.peripherals.mouse accel-profile 'flat'

        # Encontra dinamicamente o ID do G502 / G502 X (excluindo headsets como G733)
        MOUSE_ID=$(ratbagctl list 2>/dev/null | grep -i "G502" | awk '{print $1}' | tr -d ':')
        
        if [ -n "$MOUSE_ID" ]; then
            for p in 0 1; do
                # A flag --commit grava fisicamente a macro no hardware do mouse
                
                # Colar (Button 3)
                ratbagctl "$MOUSE_ID" profile $p button 3 action set macro +KEY_LEFTCTRL +KEY_V -KEY_V -KEY_LEFTCTRL --commit 2>/dev/null || true
                
                # Gatilho para o Kando: Ctrl + Shift + F10 (Button 4)
                ratbagctl "$MOUSE_ID" profile $p button 4 action set macro +KEY_LEFTCTRL +KEY_LEFTSHIFT +KEY_F10 -KEY_F10 -KEY_LEFTSHIFT -KEY_LEFTCTRL --commit 2>/dev/null || true
                
                # Copiar (Button 5)
                ratbagctl "$MOUSE_ID" profile $p button 5 action set macro +KEY_LEFTCTRL +KEY_C -KEY_C -KEY_LEFTCTRL --commit 2>/dev/null || true
                
                # Rolagem Horizontal (Tilt Wheel)
                ratbagctl "$MOUSE_ID" profile $p button 6 action set special wheel-left --commit 2>/dev/null || true
                ratbagctl "$MOUSE_ID" profile $p button 7 action set special wheel-right --commit 2>/dev/null || true
            done
            log_msg "SUCCESS" "Macros gravadas na memória do mouse $MOUSE_ID com sucesso."
        else
            log_msg "INFO" "Mouse operando via receptor sem fio ou memória interna on-board. Perfil linear 1:1 (flat) aplicado com sucesso."
        fi
        set_flag "CONFIG_MOUSE"
    }; then
        :
    else
        log_msg "ERROR" "❌ Falha ao aplicar configurações do mouse."
        exit 1
    fi
fi

# ==============================================================================
# 10. RESTAURAÇÃO DO KANDO
# ==============================================================================
if ! check_flag "KANDO_RESTORE"; then
    log_msg "INFO" "🎡 Restaurando configurações do Kando..."
    if {
        if ! verificar_gdrive_montado; then
            log_msg "WARN" "⚠️ Google Drive não está montado em '$HOME/GoogleDrive_Pessoal'. Pulando restauração do Kando por enquanto (será aplicada quando o Google Drive for montado)..."
        else
            KANDO_CONFIG_DIR="$HOME/.config/kando"
            KANDO_BACKUP_DIR="$HOME/GoogleDrive_Pessoal/Organização/Kando/Casa"
            mkdir -p "$KANDO_CONFIG_DIR"
            
            if [ -f "$KANDO_BACKUP_DIR/general-settings-backup.json" ] && [ -f "$KANDO_BACKUP_DIR/menu-settings-backup.json" ]; then
                cp "$KANDO_BACKUP_DIR/general-settings-backup.json" "$KANDO_CONFIG_DIR/config.json"
                jq '.menus[0].shortcut = "Control+Shift+F10" | .menus[0].centered = true' "$KANDO_BACKUP_DIR/menu-settings-backup.json" > "$KANDO_CONFIG_DIR/menus.json"
                set_flag "KANDO_RESTORE"
            else
                log_msg "WARN" "⚠️ Arquivos de backup do Kando não encontrados em '$KANDO_BACKUP_DIR'. Ignorando..."
            fi
        fi
    }; then
        :
    else
        log_msg "ERROR" "❌ Falha ao processar JSONs do Kando."
        exit 1
    fi
fi

# ==============================================================================
# 11. RESTAURAÇÃO DO AMBIENTE COSMIC
# ==============================================================================
if ! check_flag "COSMIC_RESTORE"; then
    log_msg "INFO" "🌌 Verificando backup das configurações do COSMIC..."
    if {
        if ! verificar_gdrive_montado; then
            log_msg "WARN" "⚠️ Google Drive não está montado em '$HOME/GoogleDrive_Pessoal'. Pulando restauração do COSMIC por enquanto (será aplicada quando o Google Drive for montado)..."
        else
            COSMIC_BACKUP_DIR="$HOME/GoogleDrive_Pessoal/Organização/Backup_COSMIC"
            if [ -d "$COSMIC_BACKUP_DIR" ]; then
                if [ -d "$COSMIC_BACKUP_DIR/cosmic" ]; then cp -r "$COSMIC_BACKUP_DIR/cosmic" "$HOME/.config/"; fi
                for dir in "gtk-3.0" "gtk-4.0" "qt5ct" "qt6ct"; do
                    if [ -d "$COSMIC_BACKUP_DIR/$dir" ]; then cp -r "$COSMIC_BACKUP_DIR/$dir" "$HOME/.config/"; fi
                done
                
                # Desativa o modo auto-tiling (mosaico automático de janelas) por padrão
                mkdir -p "$HOME/.config/cosmic/com.system76.CosmicComp/v1"
                echo "false" > "$HOME/.config/cosmic/com.system76.CosmicComp/v1/autotile"
                echo "true" > "$HOME/.config/cosmic/com.system76.CosmicComp/v1/numlock_state"

                # Garante os Grupos / Pastas organizados na Biblioteca de Aplicativos do COSMIC
                mkdir -p "$HOME/.config/cosmic/com.system76.CosmicAppLibrary/v1"
                mkdir -p "$HOME/.config/cosmic/com.system76.CosmicAppList/v1"
                
                cat << 'EOF' > "$HOME/.config/cosmic/com.system76.CosmicAppLibrary/v1/groups"
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

                cat << 'EOF' > "$HOME/.config/cosmic/com.system76.CosmicAppList/v1/favorites"
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

                # Garante o Miniaplicativo de Controle de Mídia no canto inferior esquerdo da Dock
                mkdir -p "$HOME/.config/cosmic/com.system76.CosmicPanel.Dock/v1"
                cat << 'EOF' > "$HOME/.config/cosmic/com.system76.CosmicPanel.Dock/v1/plugins_wings"
Some(([
    "com.github.MusicPlayer",
], [
    "com.system76.CosmicAppletTiling",
    "com.system76.CosmicAppletTime",
    "com.system76.CosmicAppletNotifications",
    "com.system76.CosmicAppletPower",
]))
EOF
                
                set_flag "COSMIC_RESTORE"
            else
                log_msg "WARN" "Nenhum backup do COSMIC encontrado em '$COSMIC_BACKUP_DIR'. Ignorando..."
            fi
        fi
    }; then
        :
    else
        log_msg "ERROR" "❌ Falha ao copiar arquivos do COSMIC."
        exit 1
    fi
fi

# ==============================================================================
# 11.5. RESTAURAÇÃO DE CONFIGURAÇÕES DAS IDES (VS Code & Antigravity IDE)
# ==============================================================================
if ! check_flag "IDE_CONFIG_RESTORE"; then
    log_msg "INFO" "💻 Verificando restauração das configurações do VS Code e Antigravity IDE..."
    if {
        if ! verificar_gdrive_montado; then
            log_msg "WARN" "⚠️ Google Drive não está montado em '$HOME/GoogleDrive_Pessoal'. Pulando restauração das IDEs por enquanto (será aplicada quando o Google Drive for montado)..."
        else
            IDE_BACKUP_DIR="$HOME/GoogleDrive_Pessoal/Organização/VSCode_Antigravity"
            if [ -d "$IDE_BACKUP_DIR" ]; then
                log_msg "INFO" "Restaurando settings.json, keybindings e snippets para VS Code e Antigravity IDE..."
                
                # VS Code User Directory
                VSCODE_USER_DIR="$HOME/.config/Code/User"
                mkdir -p "$VSCODE_USER_DIR"
                if [ -f "$IDE_BACKUP_DIR/settings.json" ]; then
                    cp "$IDE_BACKUP_DIR/settings.json" "$VSCODE_USER_DIR/settings.json"
                fi
                if [ -f "$IDE_BACKUP_DIR/keybindings.json" ]; then
                    cp "$IDE_BACKUP_DIR/keybindings.json" "$VSCODE_USER_DIR/keybindings.json"
                fi
                if [ -d "$IDE_BACKUP_DIR/snippets" ]; then
                    cp -r "$IDE_BACKUP_DIR/snippets" "$VSCODE_USER_DIR/"
                fi

                # Antigravity IDE User Directory
                ANTIGRAVITY_USER_DIR="$HOME/.config/Antigravity IDE/User"
                mkdir -p "$ANTIGRAVITY_USER_DIR"
                if [ -f "$IDE_BACKUP_DIR/settings.json" ]; then
                    cp "$IDE_BACKUP_DIR/settings.json" "$ANTIGRAVITY_USER_DIR/settings.json"
                fi
                if [ -f "$IDE_BACKUP_DIR/keybindings.json" ]; then
                    cp "$IDE_BACKUP_DIR/keybindings.json" "$ANTIGRAVITY_USER_DIR/keybindings.json"
                fi
                if [ -d "$IDE_BACKUP_DIR/snippets" ]; then
                    cp -r "$IDE_BACKUP_DIR/snippets" "$ANTIGRAVITY_USER_DIR/"
                fi

                set_flag "IDE_CONFIG_RESTORE"
            else
                log_msg "WARN" "⚠️ Pasta de backup das IDEs não encontrada em '$IDE_BACKUP_DIR'. Ignorando..."
            fi
        fi
    }; then
        :
    else
        log_msg "ERROR" "❌ Falha ao restaurar configurações das IDEs."
        exit 1
    fi
fi

# ==============================================================================
# 12. CONFIGURAÇÃO DO TERMINAL ZSH (Oh My Zsh + Powerlevel10k + Dotfiles)
# ==============================================================================
if ! check_flag "ZSH_CONFIG"; then
    log_msg "INFO" "💻 Configurando Terminal ZSH (Oh My Zsh, Powerlevel10k, NVM e Dotfiles)..."
    if {
        if ! verificar_gdrive_montado; then
            log_msg "WARN" "⚠️ Google Drive não está montado em '$HOME/GoogleDrive_Pessoal'. Pulando configuração do ZSH por enquanto (será aplicada quando o Google Drive for montado)..."
        else
            ZSH_INSTALL_DIR="$HOME/GoogleDrive_Pessoal/Organização/Terminal ZSH Linux"
            if [ -f "$ZSH_INSTALL_DIR/install.sh" ]; then
                log_msg "INFO" "Executando script de instalação do ZSH a partir do Google Drive..."
                chmod +x "$ZSH_INSTALL_DIR/install.sh"
                bash "$ZSH_INSTALL_DIR/install.sh"
                
                # Garantia adicional de cópia dos dotfiles salvos
                if [ -f "$ZSH_INSTALL_DIR/.zshrc" ]; then
                    cp "$ZSH_INSTALL_DIR/.zshrc" "$HOME/.zshrc"
                fi
                if [ -f "$ZSH_INSTALL_DIR/.p10k.zsh" ]; then
                    cp "$ZSH_INSTALL_DIR/.p10k.zsh" "$HOME/.p10k.zsh"
                fi
                # Instalação automática das fontes MesloLGS NF (Nerd Font) para corrigir ícones do Powerlevel10k
                mkdir -p "$HOME/.local/share/fonts"
                MESLO_URL="https://github.com/romkatv/powerlevel10k-media/raw/master"
                for font in "MesloLGS%20NF%20Regular.ttf" "MesloLGS%20NF%20Bold.ttf" "MesloLGS%20NF%20Italic.ttf" "MesloLGS%20NF%20Bold%20Italic.ttf"; do
                    font_name=$(echo "$font" | sed 's/%20/ /g')
                    if [ ! -f "$HOME/.local/share/fonts/$font_name" ]; then
                        curl -fsSL "$MESLO_URL/$font" -o "$HOME/.local/share/fonts/$font_name" 2>/dev/null || true
                    fi
                done
                fc-cache -f "$HOME/.local/share/fonts" 2>/dev/null || true

                # Define o Zsh como o shell padrão do usuário no sistema
                ZSH_BIN="$(which zsh 2>/dev/null || echo '/usr/bin/zsh')"
                if [ -x "$ZSH_BIN" ]; then
                    sudo chsh -s "$ZSH_BIN" "$USER" 2>/dev/null || sudo usermod -s "$ZSH_BIN" "$USER" 2>/dev/null || true
                    log_msg "INFO" "Zsh definido como shell padrão para o usuário $USER."
                fi

                # Garante os atalhos de produtividade do Zsh (Ctrl+V para colar e ESC para limpar linha)
                if ! grep -q "paste-from-clipboard" "$HOME/.zshrc" 2>/dev/null; then
                    cat << 'EOF' >> "$HOME/.zshrc"

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

                set_flag "ZSH_CONFIG"
            else
                log_msg "WARN" "⚠️ Script de instalação do ZSH não encontrado em '$ZSH_INSTALL_DIR/install.sh'. Ignorando..."
            fi
        fi
    }; then
        :
    else
        log_msg "ERROR" "❌ Falha ao configurar o Terminal ZSH."
        exit 1
    fi
fi

# ==============================================================================
# 13. CONFIGURAÇÃO GLOBAL DO GIT
# ==============================================================================
if ! check_flag "GIT_CONFIG"; then
    log_msg "INFO" "🐙 Configurando o Git..."
    if {
        if [ -n "$GIT_USER_NAME" ] && [ -n "$GIT_USER_EMAIL" ]; then
            git config --global user.name "$GIT_USER_NAME"
            git config --global user.email "$GIT_USER_EMAIL"
            git config --global init.defaultBranch main
            git config --global pull.rebase false
            git config --global core.editor "code --wait"
            log_msg "INFO" "Git configurado para $GIT_USER_NAME ($GIT_USER_EMAIL)."
            set_flag "GIT_CONFIG"
        else
            log_msg "WARN" "⚠️ GIT_USER_NAME ou GIT_USER_EMAIL não definidos no .env. Ignorando..."
        fi
    }; then
        :
    else
        log_msg "ERROR" "❌ Falha ao configurar o Git."
        exit 1
    fi
fi

# ==============================================================================
# 14. PERMISSÕES DE FLATPAK (OVERRIDES)
# ==============================================================================
if ! check_flag "FLATPAK_PERMISSIONS"; then
    log_msg "INFO" "📦 Aplicando permissões adicionais aos Flatpaks..."
    if {
        # Permite acesso aos discos secundários e pastas de jogos
        flatpak override --user --filesystem=/mnt/storage_700 org.onlyoffice.desktopeditors
        flatpak override --user --filesystem=/mnt/storage_930 org.onlyoffice.desktopeditors
        flatpak override --user --filesystem=/mnt org.gimp.GIMP
        
        # Permissões de bandeja do Wayland (StatusNotifierWatcher) para o CopyQ
        flatpak override --user --talk-name=org.kde.StatusNotifierWatcher --talk-name=org.freedesktop.StatusNotifierWatcher com.github.hluk.copyq
        sudo flatpak override --talk-name=org.kde.StatusNotifierWatcher --talk-name=org.freedesktop.StatusNotifierWatcher com.github.hluk.copyq 2>/dev/null || true
        
        set_flag "FLATPAK_PERMISSIONS"
    }; then
        :
    else
        log_msg "ERROR" "❌ Falha ao aplicar overrides do Flatpak."
        exit 1
    fi
fi

# ==============================================================================
# 15. MANUTENÇÃO E SAÚDE DOS SSDS
# ==============================================================================
if ! check_flag "MAINTENANCE_SSD"; then
    log_msg "INFO" "🧹 Configurando otimização de SSD e limpando sistema..."
    if {
        # Ativa o TRIM semanal
        sudo systemctl enable --now fstrim.timer
        
        # Limpeza do APT
        sudo apt autoremove -y && sudo apt clean
        
        # Limpeza de flatpaks não usados
        flatpak uninstall --unused -y
        
        set_flag "MAINTENANCE_SSD"
    }; then
        :
    else
        log_msg "ERROR" "❌ Falha na etapa de manutenção do SSD."
        exit 1
    fi
fi

# ==============================================================================
# 16. PREPARAÇÃO PARA JOGOS
# ==============================================================================
if ! check_flag "GAMING_SETUP"; then
    log_msg "INFO" "🎮 Instalando Steam, Heroic e otimizações de jogos..."
    if {
        # Instala dependências (Steam e ferramentas de otimização no /)
        sudo apt install -y steam gamemode mangohud
        
        # Instala Heroic via Flatpak
        flatpak install -y --system flathub com.heroicgameslauncher.hgl
        
        # Permissão para o Heroic enxergar o nvme_01
        flatpak override --user --filesystem=/mnt/nvme_01 com.heroicgameslauncher.hgl
        
        # Prepara a pasta de jogos no SSD dedicado
        sudo mkdir -p /mnt/nvme_01/Jogos
        sudo chown -R $USER:$USER /mnt/nvme_01/Jogos
        sudo chmod -R 775 /mnt/nvme_01/Jogos
        
        # Força o perfil de performance máxima no Pop!_OS (com fallback caso o hardware SCSI/SATA não suporte ALPM)
        system76-power profile performance 2>/dev/null || powerprofilesctl set performance 2>/dev/null || true
        
        set_flag "GAMING_SETUP"
    }; then
        :
    else
        log_msg "ERROR" "❌ Falha na etapa de preparação para jogos."
        exit 1
    fi
fi

# ==============================================================================
# 17. AUTOSTART DE APLICATIVOS DE WORKFLOW (CopyQ, Kando, Espanso, NumLock)
# ==============================================================================
if ! check_flag "AUTOSTART_CONFIG"; then
    log_msg "INFO" "🔄 Configurando autostart para CopyQ, Kando, Espanso e NumLock..."
    if {
        mkdir -p "$HOME/.config/autostart"

        # CopyQ
        cat << 'EOF' > "$HOME/.config/autostart/com.github.hluk.copyq.desktop"
[Desktop Entry]
Type=Application
Name=CopyQ
GenericName=Clipboard Manager
Comment=Gerenciador de Área de Transferência
Exec=/usr/bin/flatpak run --branch=stable --arch=x86_64 --command=copyq com.github.hluk.copyq --hide
Icon=com.github.hluk.copyq
Terminal=false
Categories=Utility;
X-GNOME-Autostart-enabled=true
EOF

        # Kando
        cat << 'EOF' > "$HOME/.config/autostart/menu.kando.Kando.desktop"
[Desktop Entry]
Type=Application
Name=Kando
Comment=The Cross-Platform Pie Menu.
Exec=env XDG_SESSION_TYPE=x11 GDK_BACKEND=x11 /usr/lib/kando/kando
Icon=kando
Terminal=false
Categories=Utility;
X-GNOME-Autostart-enabled=true
EOF

        # Espanso
        cat << 'EOF' > "$HOME/.config/autostart/espanso.desktop"
[Desktop Entry]
Type=Application
Name=Espanso
Comment=Cross-platform Text Expander
Exec=espanso daemon
Icon=espanso
Terminal=false
Categories=Utility;
X-GNOME-Autostart-enabled=true
EOF

        # NumLock
        cat << 'EOF' > "$HOME/.config/autostart/numlock.desktop"
[Desktop Entry]
Type=Application
Name=NumLock Auto-On
Exec=/bin/bash -c 'numlockx on 2>/dev/null || true; for led in /sys/class/leds/*::numlock/brightness; do echo 1 > "$led" 2>/dev/null || true; done'
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

        set_flag "AUTOSTART_CONFIG"
    }; then
        :
    else
        log_msg "ERROR" "❌ Falha ao configurar entradas de autostart."
        exit 1
    fi
fi

log_msg "SUCCESS" "✅ PROVISIONAMENTO CONCLUÍDO!"