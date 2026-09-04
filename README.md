# Pop!_OS 24.04 LTS - Automated Provisioning & Setup

Script de automação e provisionamento idempotente para configuração completa do ambiente de desenvolvimento, produtividade, mídia e jogos no **Pop!_OS 24.04 LTS** (com suporte total ao **COSMIC Desktop** e GNOME).

---

## 🚀 O que o script automatiza:

### 1. Otimizações de Sistema & Kernel
*   **Swappiness (`vm.swappiness=10`):** Reduz a frequência de uso do swap em disco, aproveitando os 32 GB de RAM para máxima performance.
*   **File Watchers (`fs.inotify.max_user_watches=524288`):** Eleva o teto de monitoramento de arquivos em tempo real para o VS Code, Antigravity IDE, Git e monorepos pesados.

### 2. Configurações de Periféricos, Teclado & Usabilidade
*   **Teclado (Redragon Horus Pro):**
    *   Delay do Backspace ajustado para 180ms (resposta imediata) e taxa de repetição para 18ms (~55 caracteres/seg).
    *   **Fix Oficial do Cedilha & Aspas do Windows:** Configuração com `~/.XCompose`, correção das tabelas de Compose (`/usr/share/X11/locale/pt_BR.UTF-8/Compose` e `en_US.UTF-8/Compose`) e exportação de `XCOMPOSEFILE`. Garante `' + c = ç` nativo em terminais e apps do sistema.
    *   **Nota Técnica sobre Chromium & Electron no Wayland (`' + c = ć`):** Devido à tabela estática interna do Chromium (`ui::CharacterComposer`), navegadores (Chrome/Brave) e IDEs Electron (Antigravity/VS Code) geram `ć` via Wayland. Nesses aplicativos, utilize o atalho universal de hardware <kbd>AltGr</kbd>+<kbd>,</kbd> (para `ç`) e <kbd>AltGr</kbd>+<kbd>Shift</kbd>+<kbd>'</kbd> (para `"`). Diagnóstico completo e issues oficiais documentadas em [`Docs/issue_chromium_electron_cedilha_wayland.md`](file:///home/rezendepauloh/Documentos/Scripts/Docs/issue_chromium_electron_cedilha_wayland.md).
    *   **NumLock Permanente & Consistente (XKB + LED Sync):**
        *   Configuração nativa no motor de layout do COSMIC (`xkb_config` com `options: Some("numpad:mac")`) garantindo que o teclado numérico emita números em 100% das vezes, sem depender de modificadores instáveis.
        *   Persistência sincronizada em `/var/lib/cosmic-greeter/.config/cosmic/com.system76.CosmicComp/v1/` para ativação desde a tela de login.
        *   Utilitário nativo `/usr/local/bin/numlock-on` (Python/evdev/uinput) e serviço no autostart para acender imediatamente o LED físico do teclado no login. Documentação em [`Docs/issue_cosmic_numlock_boot.md`](file:///home/rezendepauloh/Documentos/Scripts/Docs/issue_cosmic_numlock_boot.md).
*   **Janelas (Estilo Windows):** Ativa botões de Minimizar, Maximizar e Fechar na barra de título e minimização com clique do botão do meio.
*   **Mouse (Logitech G502 X):**
    *   Desativa a aceleração dinâmica de ponteiro (perfil plano linear `flat` 1:1).
    *   Grava macros físicas permanentes na memória EEPROM do hardware (`--commit`):
        *   **Botão 3:** Colar (<kbd>Ctrl</kbd>+<kbd>V</kbd>)
        *   **Botão 4:** Gatilho do Kando (<kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>F10</kbd>)
        *   **Botão 5:** Copiar (<kbd>Ctrl</kbd>+<kbd>C</kbd>)
        *   **Botões 6 e 7:** Rolagem horizontal (*Tilt Wheel* esquerda/direita).
*   **Mesa Digitalizadora (Wacom Intuos Pro S / PTH-460):**
    *   **Configuração Atual (Daemon OpenTabletDriver Headless):**
        *   Opera via `otd-daemon` rodando silenciosamente em segundo plano (com inicialização automática em `~/.config/autostart/otd-daemon.desktop` e `systemctl --user`), sem a interface gráfica para evitar resets indesejados.
        *   **Modo Absoluto 180° (Modo Canhoto):** Rotação matemática de 180° e trava de aspecto 1:1 aplicadas via `/dev/uinput` para a Caneta (Pro Pen 2) com níveis completos de pressão e inclinação.
        *   **Mapeamento dos 6 Botões Físicos (ExpressKeys) e Touch Ring:**
            *   `AuxButton 0`: <kbd>Ctrl</kbd>+<kbd>Z</kbd> *(Desfazer)*
            *   `AuxButton 1`: <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>Z</kbd> *(Refazer)*
            *   `AuxButton 2`: <kbd>Espaço</kbd> *(Pan / Arrastar tela)*
            *   `AuxButton 3`: <kbd>Ctrl</kbd>+<kbd>S</kbd> *(Salvar)*
            *   `AuxButton 4`: <kbd>Ctrl</kbd>+<kbd>C</kbd> *(Copiar)*
            *   `AuxButton 5`: <kbd>Ctrl</kbd>+<kbd>V</kbd> *(Colar)*
            *   `Touch Ring`: Rotação para Zoom In (<kbd>Ctrl</kbd>+<kbd>+</kbd>) e Zoom Out (<kbd>Ctrl</kbd>+<kbd>-</kbd>).
        *   **Suporte a Bluetooth & USB:** Definições para os identificadores USB (`056a:0392`) e Bluetooth (`056a:0393`) com confiança automática no BlueZ.
    *   **Nota Técnica & Roadmap Futuro (COSMIC Desktop / Wayland):**
        *   O compositor do **COSMIC Desktop (`cosmic-comp` / Smithay)** ainda está em desenvolvimento ativo e atualmente não possui suporte nativo implementado para rotação 180° (Modo Canhoto) nem repasse do protocolo `zwp_tablet_pad_v2` (botões físicos) no driver nativo do kernel.
        *   Issues oficiais da System76 para acompanhamento:
            *   [pop-os/cosmic-settings #141](https://github.com/pop-os/cosmic-settings/issues/141) — *Feature request/brainstorming: Drawing tablet support (wacom)*
            *   [pop-os/cosmic-comp #313](https://github.com/pop-os/cosmic-comp/issues/313) — *Support for Graphic & Display Drawing Tablets*
        *   **Planejamento de Migração Futura:** Assim que o COSMIC Desktop implementar nativamente essas funcionalidades, o módulo 12 será refatorado para o driver 100% nativo do kernel (`wacom.ko` + `libinput`), unificando Caneta, Touch multitoque de 1 a 4 dedos, ExpressKeys e Modo Canhoto sem necessidade de daemons adicionais.

### 3. Pacotes Base, Repositórios & Navegadores
*   **Atualização do Sistema & Fontes:** `apt update && upgrade -y`, pré-aceite da licença EULA para fontes Microsoft TrueType (`Arial`, `Times New Roman` para OnlyOffice), fontes de código (`Fira Code`, `JetBrains Mono`), utilitários essenciais (`git`, `curl`, `jq`, `vlc`, `piper`, `ratbagd`, `numlockx`, `unzip`) e instalação binária oficial do **Rclone**.
*   **Configuração do Git:** Configuração global automatizada (nome, email, default branch `main`, pull rebase e editor `code --wait`) através das variáveis do `.env`.
*   **Navegadores:** Instalação nativa via repositórios oficiais APT do **Google Chrome** e **Brave Browser**.

### 4. Docker Engine
*   Remoção preventiva de pacotes conflitantes legados.
*   Configuração do repositório oficial da Docker e instalação do `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin` e `docker-compose-plugin`.
*   Adição automática do usuário atual ao grupo `docker` e habilitação do serviço systemd.

### 5. Gestão de Armazenamento, Discos Físicos & Saúde dos SSDs
*   **Mapeamento por UUID & Montagem no `/etc/fstab`:**
    *   **NVMe 01 (Sistema):** `/`
    *   **NVMe 02 (Secundário/Jogos):** `/mnt/nvme_01` (ext4 com `defaults,noatime`)
    *   **HD Storage 930:** `/mnt/storage_930` (ext4 com `defaults,noatime`)
    *   **HD Storage 700:** `/mnt/storage_700` (ext4 com `defaults,noatime`)
*   **Permissões Automáticas:** Concede propriedade total ao usuário (`chown -R $USER:$USER`) e permissões de leitura/escrita (`chmod -R 775`) em todos os discos.
*   **Redirecionamento de Diretórios:** Altera o `~/.config/user-dirs.dirs` para ancorar a pasta nativa **Downloads** no HD Storage 700 (`/mnt/storage_700/Downloads`).
*   **Manutenção de SSDs & Otimizações Globais:** Ativação do TRIM semanal (`fstrim.timer`) para preservação dos NVMes, limites elevados de I/O e file watchers (`vm.dirty_ratio`, `inotify`), Docker socket sob demanda, quantum reduzido do PipeWire (512), firewall UFW protegido para Dev, backup semanal agendado de dotfiles/automações e limpeza profunda com `apt autoremove/clean` e remoção de flatpaks órfãos.

### 6. Sincronização de Múltiplas Nuvens (Rclone VFS)
*   **Versão Oficial Completa do Rclone (v1.75+):** Instalação automatizada via script oficial da Rclone com suporte nativo completo a todos os backends (Google Drive, OneDrive e MEGA), prevenindo loops de falha e travamentos de I/O no boot.
*   **Autenticação Automatizada & Fallback:** Leitura inteligente de variáveis do `.env`. Possui sistema de fallbacks com cópia automática de `rclone.conf` local ou abertura graciosa do assistente interativo `rclone config` se faltar algum remote.
*   **Serviços em Background Otimizados (Systemd User):** Configuração com cache VFS sob demanda (`--vfs-cache-mode full`, retenção de 72h e limite de 50GB, `--attr-timeout 10m` e `--vfs-fast-fingerprint`) para evitar engasgos e travamentos de UI em gerenciadores de arquivos como o COSMIC Files.
    *   `gdrive_pessoal` -> `~/GoogleDrive_Pessoal`
    *   `onedrive_pessoal` -> `~/OneDrive_Pessoal`
    *   `mega_pessoal` -> `~/MEGA_Pessoal`
*   **Diagnóstico de Performance no COSMIC Files:** Documentação técnica sobre I/O em discos secundários e FUSE disponível em [`Docs/issue_cosmic_files_fuse_freeze.md`](file:///home/rezendepauloh/Documentos/Scripts/Docs/issue_cosmic_files_fuse_freeze.md).
*   **Validação de Montagem:** Função `verificar_gdrive_montado` que checa pontos FUSE e conteúdo antes de disparar etapas dependentes de backup.

### 7. Softwares de Workflow, Produtividade & Mídia
*   **VS Code:** Repositório oficial APT da Microsoft e instalação do pacote nativo `code`.
*   **Espanso (Wayland) & Suíte de Automações STI:**
    *   Text Expander nativo integrado diretamente com o repositório de automações [`espanso-automacoes-sti`](https://github.com/rezendepauloh/espanso-automacoes-sti) clonado em `~/.config/espanso`.
    *   **Formulários Dinâmicos Nativos no Linux:** Executor de interface gráfica nativa (`form_runner.py` em Tkinter/Zenity) para formulários interativos (`:ola`, `:transporte`, `:viagem`, `:diaria`, `:cel`, `:limpar`, `:analisar`).
    *   **Motor NLP de Correção e Limpeza:** Correção ortográfica de contexto com spaCy (`:arrumar`), atalhos de clipboard e sincronização universal com CopyQ e Kando.
    *   **Compatibilidade Wayland:** Operação em modo daemon em background (`show_icon: false`, `backend: EVDEV`), permissões `cap_dac_override` e layout `us-intl` garantidos.
*   **Kando & CopyQ:** Pie menu com atalho <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>F10</kbd> e gerenciador de área de transferência com servidor ativo e ícone integrado na bandeja superior do painel COSMIC.
*   **Autostart Fluido e Escalonado:** Entradas de inicialização automática otimizadas com pequenos atrasos escalonados (`X-GNOME-Autostart-Delay`) para eliminar sobrecarga no D-Bus e engasgos de carregamento da área de trabalho.
*   **Google Antigravity IDE:**
    *   Download e extração do pacote oficial em `/opt/antigravity`.
    *   Ajuste de permissões do sandbox do Electron (`chrome-sandbox` com suid 4755).
    *   Configuração do perfil **AppArmor** (`/etc/apparmor.d/antigravity`) para permitir namespaces de usuário sem restrições no Ubuntu/Pop!_OS 24.04.
    *   Links simbólicos no PATH do sistema: `antigravity`, `antigravity-ide` e `agy`.
    *   Instalação de ícones hicolor de alta resolução e entrada `.desktop` com categorias e mimetypes no menu de aplicativos.
*   **Aplicativos Flatpak & Overrides:**
    *   Instalação de **Dropbox**, **CopyQ**, **OnlyOffice Desktop Editors**, **Jellyfin Desktop** e **GIMP**.
    *   Aplicação automática de overrides de permissão de sistema de arquivos para acesso aos discos `/mnt/storage_700`, `/mnt/storage_930`, `/mnt` e integração com a bandeja do Wayland (`StatusNotifierWatcher` para o CopyQ).
    *   Associação do **OnlyOffice** como leitor padrão para documentos (`.docx`, `.xlsx`, `.pptx`).
*   **Jellyfin Media Server:** Instalação nativa via repositório oficial da equipe Jellyfin.
*   **Miniaplicativos Customizados (COSMIC):**
    *   **Controle de Mídia:** Compilação do `cosmic-applet-music-player` (capa de álbum, título, botões MPRIS e controle por scroll) posicionado no **canto inferior esquerdo da Dock**.
    *   **Monitor de Sistema (Minimon):** Instalação do `cosmic-ext-applet-minimon` (da comunidade cosmic-utils), posicionado no **canto superior direito do Painel**, com menu dropdown exibindo uso e temperatura de CPU, memória RAM/Swap, discos, tráfego de rede e GPU/VRAM em tempo real.
*   **Espanso (Wayland):** Download do pacote `.deb` oficial, bibliotecas de compatibilidade wxWidgets 3.0 para o Pop!_OS 24.04 (noble), instalação e registro de serviço nativo (`espanso service register && espanso start`).
*   **Kando:** Download dinâmico da última versão `.deb` diretamente da API do GitHub, com wrapper automático de compatibilidade para COSMIC Desktop / Wayland (forçando o backend XWayland).
*   **Autostart do Sistema:** Configuração de inicialização automática no login do usuário (`~/.config/autostart`) para **CopyQ**, **Kando**, **Espanso** e **NumLock**.

### 8. Restauração de Backups, Customizações e Dotfiles
*   **Kando:** Restaura configurações gerais (`config.json`) e menus (`menus.json` com o atalho `Control+Shift+F10` injetado via `jq`) a partir de `~/GoogleDrive_Pessoal/Organização/Kando/Casa`.
*   **COSMIC DE, Temas, Dock & Biblioteca de Apps:** Restaura configurações do painel COSMIC (`~/.config/cosmic`) e pontes visuais legadas (`gtk-3.0`, `gtk-4.0`, `qt5ct`, `qt6ct`) a partir de `~/GoogleDrive_Pessoal/Organização/Backup_COSMIC`, garantindo:
    *   Modo **auto-tiling desligado** por padrão.
    *   **NumLock ativado** por padrão no boot do compositor.
    *   Miniaplicativo de **Controle de Mídia** no canto inferior esquerdo da Dock.
    *   Organização automática do **Menu / Biblioteca de Aplicativos** em pastas e categorias inteligentes (*Jogos, Desenvolvimento, Escritório, Mídia, Utilitários, Sistema*) e favoritos fixados.
*   **IDEs (VS Code & Antigravity IDE):** Restaura de forma sincronizada os arquivos `settings.json`, `keybindings.json` (atalhos customizados) e pasta de `snippets/` a partir de `~/GoogleDrive_Pessoal/Organização/VSCode_Antigravity/` para os diretórios de configuração de ambos os editores (`~/.config/Code/User/` e `~/.config/Antigravity IDE/User/`), incluindo suporte a **colar com botão direito do mouse** no terminal integrado e atalho `Ctrl+V`.
*   **Terminal ZSH & Powerlevel10k:**
    *   Execução do instalador a partir de `~/GoogleDrive_Pessoal/Organização/Terminal ZSH Linux/install.sh`.
    *   Restauração dos dotfiles `~/.zshrc` e `~/.p10k.zsh` com suporte nativo ao **`Ctrl+V` para colar a área de transferência** (via `wl-paste` no Wayland e `xclip` no X11) e `ESC` para limpar a linha.
    *   Download automatizado das 4 variantes completas da fonte **MesloLGS NF** (*Regular, Bold, Italic, Bold Italic*) do repositório oficial do Powerlevel10k diretamente para `~/.local/share/fonts/`, com atualização de cache (`fc-cache -f`).
    *   Definição automática do **Zsh como shell padrão** do usuário (`chsh -s` / `usermod -s`).

### 9. Jogos & Performance
*   Instalação da **Steam** (pacote nativo APT), **Gamemode** (escalonador de prioridade de kernel) e **MangoHud**.
*   Instalação do **Heroic Games Launcher** (Flatpak) com override de permissão para o SSD de jogos (`/mnt/nvme_01`).
*   Criação prévia da pasta física `/mnt/nvme_01/Jogos` com posse e permissão `775`.
*   Configuração do perfil de **Performance Máxima** no Pop!_OS via `system76-power profile performance` (com fallback para `powerprofilesctl`).

### 10. Trabalho Remoto (MPMS) & Conexão Windows
*   **VPN Aberta MPMS (openfortivpn):** Conexão SSL-VPN de alta performance nativa, substituindo com sucesso o cliente oficial proprietário (que exige licença paga EMS).
*   **VPN MPMS Automatizada (`vpn-mpms` & Lançador Gráfico):** Conexão via `openfortivpn` com configuração em `/etc/openfortivpn/mpms.conf`, permissão sudoer sem senha, **saída colorida no terminal com destaque verde visual imediato ao atingir `Tunnel is up and running`**, e suporte a salvar senha fixa para pedir apenas o token 2FA/OTP.
*   **Remmina Remote Desktop (RDP):** Cliente oficial configurado com perfil automático **`MPE-80703 (Trabalho MPMS)`** salvo em `~/.local/share/remmina/mpms_mpe_80703.remmina` (servidor `MPE-80703.in.mpe.ms.gov.br`, usuário `paulogoncalves`, domínio `in.mpe.ms.gov.br`, clipboard compartilhado e áudio local).

---

## 🏗️ Arquitetura Modular V2 (`setup_popos_v2.sh` & `scripts/`)

O projeto foi totalmente refatorado para uma **arquitetura modular desacoplada**. Agora você pode orquestrar a execução completa ou executar cada módulo de forma individual:

```
.
├── setup_popos_v2.sh                   # Orquestrador Principal Modular
├── scripts/                            # Módulos Independentes
│   ├── 00_comum.sh                     # Biblioteca de logs, usuário real e idempotência
│   ├── 01_otimizacao_sistema.sh        # Swappiness e Inotify file watchers
│   ├── 02_teclado_cedilha_numlock.sh   # US-Intl, Cedilha ('+c = ç) e NumLock permanente
│   ├── 03_atualizacao_sistema.sh       # Atualização de pacotes APT, Pop recovery e firmware
│   ├── 04_pacotes_base_dev.sh          # Pacotes CLI essenciais, NVM, Rust e compilação
│   ├── 05_rclone_storage.sh            # Montagens FUSE do Rclone (GDrive, OneDrive, MEGA)
│   ├── 06_softwares_workflow.sh        # VS Code, Flatpaks, Jellyfin Server, Espanso e Kando
│   ├── 07_powershell7.sh               # Instalação e perfil do Microsoft PowerShell 7 (pwsh)
│   ├── 08_antigravity_ide.sh           # Google Antigravity IDE (/opt, AppArmor, .desktop)
│   ├── 09_onlyoffice_padrao.sh         # Associação do OnlyOffice como leitor padrão
│   ├── 10_cosmic_applets_custom.sh      # Mídia na Dock e Minimon Monitor de Sistema no Painel
│   ├── 11_mouse_gaming.sh              # Logitech G502 X (DPIs, 1000Hz, macros on-board)
│   ├── 12_wacom_tablet.sh              # Suporte, drivers e pareamento da Wacom Intuos Pro
│   ├── 13_kando_restore.sh             # Sincronização de configurações do Kando
│   ├── 14_cosmic_theme_restore.sh      # Restauração de temas visuais e GTK/Qt do Google Drive
│   ├── 15_cosmic_menu_dock.sh          # Configuração instantânea do menu e dock do COSMIC
│   ├── 16_ide_config_restore.sh        # Sincronização de atalhos e configurações das IDEs
│   ├── 17_zsh_p10k_setup.sh            # Instalação do Zsh, Oh-My-Zsh, P10k e fontes Meslo
│   ├── 18_jogos_performance.sh         # Steam, Heroic, jstest-gtk, AntiMicroX e modo de energia
│   ├── 19_flatpak_permissions.sh       # Permissões de discos e barramento D-Bus para Flatpaks
│   ├── 20_manutencao_ssds.sh           # Ativação do fstrim.timer para TRIM semanal
│   ├── 21_autostart_config.sh          # Configuração de apps na inicialização da sessão
│   ├── 22_limpeza_otimizacao.sh        # Limpeza, otimizações de kernel, Docker e backups
│   ├── 23_openrgb_iluminacao.sh        # OpenRGB, regras udev ASUS Aura e controle ARGB
│   ├── 24_trabalho_remoto_vpn_rdp.sh   # VPN MPMS (openfortivpn 2FA) e Remmina RDP
│   └── 25_pdf_editors.sh               # Master PDF Editor (Edição) e Okular (Leitura/Marcadores)
```

### 📋 Módulos e Responsabilidades:

| Módulo | Descrição / Função |
| :--- | :--- |
| `setup_popos_v2.sh` | **Orquestrador Central:** Executa todos os módulos sequencialmente, suporta flags `--list`, `--help`, `--force` e execução de módulos isolados. |
| `scripts/00_comum.sh` | **Biblioteca Central:** Cores, timestamps, funções `log_msg`, sistema de checkpoints (`check_flag`/`set_flag`), resolução de `REAL_USER`/`REAL_HOME` e validação do Google Drive. |
| `scripts/01_otimizacao_sistema.sh` | Módulo de Swappiness (`vm.swappiness=10`) e File Watchers inotify (`524288`). |
| `scripts/02_teclado_cedilha_numlock.sh` | Módulo de layout US-Intl, resposta rápida (180ms/18ms), Cedilha (`'+c = ç`), `~/.XCompose`, immodules GTK e NumLock Systemd/Udev. |
| `scripts/03_atualizacao_sistema.sh` | Módulo de atualização de pacotes APT, Pop recovery e firmware. |
| `scripts/04_pacotes_base_dev.sh` | Módulo de utilitários base, compiladores, NVM, Cargo/Rust e dependências de desenvolvimento. |
| `scripts/05_rclone_storage.sh` | Módulo de serviços systemd do Rclone (GDrive, OneDrive, MEGA), Celeste (Tray), Web Dashboard, Rclone Browser e Discos no COSMIC Files. |
| `scripts/06_softwares_workflow.sh` | Módulo de instalação do VS Code, Telegram, ZapZap (WhatsApp), OnlyOffice, Jellyfin Server, Espanso e Kando. |
| `scripts/07_powershell7.sh` | Módulo de instalação oficial do Microsoft PowerShell 7 (`pwsh`), repositórios Microsoft e perfil do usuário. |
| `scripts/08_antigravity_ide.sh` | Módulo de instalação completa e isolada do Google Antigravity IDE (`/opt/antigravity`, AppArmor e `.desktop`). |
| `scripts/09_onlyoffice_padrao.sh` | Módulo de associação do OnlyOffice como manipulador padrão de documentos office. |
| `scripts/10_cosmic_applets_custom.sh` | Módulo de miniaplicativos customizados do COSMIC: controle de mídia na Dock e Minimon (monitor de CPU, RAM, Disco, Rede e GPU com dropdown) no painel. |
| `scripts/11_mouse_gaming.sh` | Módulo de gravação de polling rate 1000Hz, DPIs e macros na memória do mouse Logitech G502 X. |
| `scripts/12_wacom_tablet.sh` | Módulo de suporte, regras udev, OpenTabletDriver Daemon Headless (Modo Canhoto 180° e atalhos) e pareamento da Wacom Intuos Pro. |
| `scripts/13_kando_restore.sh` | Módulo de restauração de menus e atalho `Ctrl+Shift+F10` do Kando a partir do Google Drive. |
| `scripts/14_cosmic_theme_restore.sh` | Módulo de restauração de temas visuais do COSMIC, GTK e Qt a partir do Google Drive. |
| `scripts/15_cosmic_menu_dock.sh` | Módulo de configuração instantânea (< 1s) das categorias da App Library (*Jogos, Dev, Comunicação, Escritório, Mídia, Utilitários, Sistema*), Favoritos e Dock. |
| `scripts/16_ide_config_restore.sh` | Módulo de sincronização de settings, atalhos (`Ctrl+V`, colar com botão direito) e snippets para VS Code e Antigravity. |
| `scripts/17_zsh_p10k_setup.sh` | Módulo de instalação e configuração do Zsh, Powerlevel10k, fontes MesloLGS NF, shell padrão e `Ctrl+V`. |
| `scripts/18_jogos_performance.sh` | Módulo de Steam, Gamemode, MangoHud, Heroic, jstest-gtk, AntiMicroX e perfil de Performance Máxima. |
| `scripts/19_flatpak_permissions.sh` | Módulo de overrides de filesystem (`/mnt/storage_*`, host para Rclone UI) e liberação de bandeja (`StatusNotifierWatcher`). |
| `scripts/20_manutencao_ssds.sh` | Módulo de ativação do TRIM semanal (`fstrim.timer`) para os SSDs. |
| `scripts/21_autostart_config.sh` | Módulo de provisionamento de inicialização automática no login (CopyQ, Kando, Espanso, NumLock). |
| `scripts/22_limpeza_otimizacao.sh` | Módulo de limpeza, otimizações de kernel/inotify, Docker sob demanda, latência PipeWire, firewall UFW e backup automatizado de dotfiles. |
| `scripts/23_openrgb_iluminacao.sh` | Módulo de instalação do OpenRGB, regras udev para ASUS AURA LED Controller, módulos i2c e autostart na bandeja. |
| `scripts/24_trabalho_remoto_vpn_rdp.sh` | Módulo de trabalho remoto: VPN MPMS (openfortivpn 2FA) e cliente RDP Remmina com clipboard e áudio. |
| `scripts/25_pdf_editors.sh` | Módulo de editores de PDF profissionais: Master PDF Editor (edição direta de textos e páginas) e Okular (leitura com marcadores e anotações). |

---

## ⚙️ Guia de Execução

### 🚀 Modo Automatizado Completo (V2):
Executa todos os 25 módulos em sequência, pulando automaticamente o que já estiver concluído:
```bash
sudo ./setup_popos_v2.sh
```

### 📋 Listar Módulos Disponíveis:
```bash
./setup_popos_v2.sh --list
```

### 🎯 Executar um Módulo Específico:
Você pode executar diretamente pelo orquestrador ou chamar o script dentro de `scripts/`:
```bash
# Pelo orquestrador (por número ou nome):
sudo ./setup_popos_v2.sh 02
sudo ./setup_popos_v2.sh 12

# Ou diretamente pelo módulo individual:
sudo ./scripts/01_otimizacao_sistema.sh
sudo ./scripts/09_cosmic_music_applet.sh
./scripts/12_cosmic_restore.sh
```

### 🔄 Forçar Reexecução Completa (Limpar Checkpoints):
```bash
sudo ./setup_popos_v2.sh --force
```

---

### 🧪 Testando em Ambiente Seguro (Docker no WSL / Ubuntu):

Para validar o script com segurança e sem alterar nada no seu sistema operacional hospedeiro, utilize a suíte de testes em container:

#### 🟢 Opção 1: Teste Automatizado com Relatório Completo (Recomendado)
O script `test_in_docker.sh` constrói a imagem Ubuntu 24.04, configura todos os mocks de hardware/desktop (gsettings, ratbagctl, rclone, flatpak, estrutura do Google Drive), executa o setup e valida todas as asserções:
```bash
chmod +x test_in_docker.sh
./test_in_docker.sh
```

#### 🟡 Opção 2: Teste Manual Interativo
Se desejar entrar no terminal do container e acompanhar manualmente a execução:
```bash
# 1. Construir a imagem Docker de teste:
docker build -t popos-provision-test -f Dockerfile .

# 2. Iniciar o container interativo (com pasta montada e certificados):
docker run -it --rm \
  --privileged \
  -v "$(pwd)":/workspace \
  -v /usr/local/share/ca-certificates:/usr/local/share/ca-certificates:ro \
  popos-provision-test bash
```
Dentro do container:
```bash
# Alternar para o usuário de teste e rodar o script:
su - paulogoncalves
bash /workspace/setup_popos.sh
```

---

## 📚 Documentação Técnica & Diagnósticos Especiais (`Docs/`)

O repositório conta com relatórios técnicos aprofundados sobre comportamentos específicos do hardware, desktop COSMIC e roadmap de melhorias:

1. 📄 [**NumLock Permanente & LED Físico no COSMIC**](file:///home/rezendepauloh/Documentos/Scripts/Docs/issue_cosmic_numlock_boot.md): Diagnóstico completo do motor XKB e sincronização do LED via udev.
2. 📄 [**Mesa Wacom Intuos Pro no Wayland**](file:///home/rezendepauloh/Documentos/Scripts/Docs/issue_opentabletdriver_wacom_bluetooth.md): Mapeamento de ExpressKeys, pareamento Bluetooth e modo canhoto 180°.
3. 📄 [**Cedilha no Chromium & Electron (`'+c = ć`)**](file:///home/rezendepauloh/Documentos/Scripts/Docs/issue_chromium_electron_cedilha_wayland.md): Causa raiz no código C++ do Chromium e atalhos de hardware.
4. 📄 [**Engasgos no COSMIC Files & Otimização FUSE**](file:///home/rezendepauloh/Documentos/Scripts/Docs/issue_cosmic_files_fuse_freeze.md): Otimizações de I/O e cache de atributos do Rclone.
5. 🚀 [**Roadmap de Melhorias Futuras**](file:///home/rezendepauloh/Documentos/Scripts/Docs/melhorias_futuras_workstation.md): Sugestões de alto valor para ZRAM, limites de inotify, Docker sob demanda, PipeWire e backup automático.

