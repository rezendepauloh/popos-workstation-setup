# 🚀 Pop!_OS 24.04 LTS (COSMIC) - Automated Workstation Setup

[![OS](https://img.shields.io/badge/OS-Pop!__OS%2024.04%20LTS-48B9C7.svg)](https://system76.com/pop)
[![Desktop](https://img.shields.io/badge/Desktop-COSMIC%20(Wayland%20Native)-orange.svg)](https://github.com/pop-os/cosmic-epoch)
[![Display](https://img.shields.io/badge/Display-Ultrawide%203440x1440-9cf.svg)](#)
[![FreeRDP](https://img.shields.io/badge/FreeRDP-v3.x%20WinApps-blue.svg)](https://freerdp.com)
[![Docker](https://img.shields.io/badge/Docker-KVM%20%2B%20Services-2496ED.svg)](https://www.docker.com)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](#)

> Ecossistema completo de automação pós-instalação, Infraestrutura como Código (IaC) e provisionamento idempotente para transformar uma estação de trabalho Linux de alta performance sob **COSMIC Desktop (`cosmic-comp` / Wayland nativo)** em um ambiente integrado para desenvolvimento de software, suíte de produtividade, engenharia, trabalho remoto e jogos.

---

## 📋 Sumário
1. [Destaques & O que o Projeto Automatiza](#-destaques--o-que-o-projeto-automatiza)
   - [1. Sistema, Kernel & I/O](#1-sistema-kernel--io)
   - [2. Periféricos, Ergonomia & Wayland Native](#2-periféricos-ergonomia--wayland-native)
   - [3. Suíte ArtCraft & Produtividade Office](#3-suíte-artcraft--produtividade-office)
   - [4. Ferramentas Avançadas de PDF](#4-ferramentas-avançadas-de-pdf)
   - [5. Automações de Digitação, Clipboard & Kando](#5-automações-de-digitação-clipboard--kando)
   - [6. Armazenamento, Nuvem & Rede Local](#6-armazenamento-nuvem--rede-local)
   - [7. Trabalho Remoto (MPMS), WinApps & OneDrive Integrado](#7-trabalho-remoto-mpms-winapps--onedrive-integrado)
   - [8. Jogos, Streaming & Mídia](#8-jogos-streaming--mídia)
2. [Estrutura do Repositório & Módulos](#️-estrutura-do-repositório--módulos)
3. [Guia de Uso & Execução](#️-guia-de-uso--execução)
   - [Execução Completa Automatizada](#-execução-completa-automatizada)
   - [Listar Módulos Disponíveis](#-listar-módulos-disponíveis)
   - [Execução de Módulo Isolado](#-execução-de-módulo-isolado)
   - [Suíte de Testes Automatizados](#-executar-a-suíte-de-testes-automatizados)
   - [Reparo Rápido de IDEs (Wayland/GPU)](#-reparo-rápido-de-ides-google-antigravity--vs-code)
4. [Créditos & Projetos de Código Aberto](#-créditos--projetos-de-código-aberto)
5. [Licença & Isenção de Responsabilidade](#-licença--isenção-de-responsabilidade)

---

## 🚀 Destaques & O que o Projeto Automatiza

### 1. Sistema, Kernel & I/O
* **Swappiness Otimizado (`vm.swappiness=10`):** Aproveita a capacidade de 32 GB de RAM para máxima responsividade, mantendo o kernel focado em manter páginas ativas em cache.
* **File Watchers Elevados (`fs.inotify.max_user_watches=524288`):** Evita falhas de monitoramento em tempo real de grandes monorepos no Google Antigravity IDE, VS Code e ferramentas de build.
* **DNS Local Permanente & Domínio de Roteamento (`~pk.local`):** Drop-in no `systemd-resolved` (`/etc/systemd/resolved.conf.d/99-local-dns.conf`) apontando para o servidor DNS local (`192.168.0.8`) com fallback seguro para `1.1.1.1` e resolução do domínio `~pk.local` sem conflito com mDNS.
* **Swap ZRAM Compactado (`zstd`):** Compressão ultra-rápida de memória com prioridade máxima.
* **TRIM Semanal Automatizado (`fstrim.timer`):** Preservação contínua da vida útil e performance de leitura/escrita dos SSDs NVMe.

### 2. Periféricos, Ergonomia & Wayland Native
* **Patch Binário Cirúrgico de Cedilha & Aspas no Electron/Chromium:**
  * Sob Wayland nativo (`--ozone-platform=wayland`), motores Chromium/Electron utilizam tabelas estáticas onde `' + c` resultava em `ć` (U+0107) e pressionar `"` (<kbd>Shift</kbd>+<kbd>'</kbd>) duas vezes gerava o trema `¨` (U+00A8).
  * O utilitário `/usr/local/bin/patch-cedilla-electron` ([scripts/daemons/patch_cedilla_electron.py](scripts/daemons/patch_cedilla_electron.py)) aplica substituição atômica de bytes em **Google Antigravity IDE**, **VS Code**, **Google Chrome** e **Brave**:
    * <kbd>'</kbd> + <kbd>c</kbd> = **`ç`** e <kbd>'</kbd> + <kbd>C</kbd> = **`Ç`**
    * <kbd>"</kbd> 2x = **`"`** (em vez de `¨`)
    * <kbd>'</kbd> 2x = **`'`** (em vez de `´`)
  * **APT Post-Invoke Hook** (`/etc/apt/apt.conf.d/99-patch-cedilla-electron`) garantindo reaplicação transparente em qualquer atualização do sistema ([Docs/issues/issue_chromium_electron_cedilha_wayland.md](Docs/issues/issue_chromium_electron_cedilha_wayland.md)).
* **NumLock no Boot & Sincronização de LED:**
  * Layout XKB do COSMIC configurado com `options: Some("numpad:mac")` e script evdev/uinput `/usr/local/bin/numlock-on` para acender o LED físico do teclado no login ([Docs/issues/issue_cosmic_numlock_boot.md](Docs/issues/issue_cosmic_numlock_boot.md)).
* **Alt Codes do Windows no Teclado Numérico (Wayland Native):**
  * Daemon de usuário gerenciado pelo systemd (`alt-numpad.service`) capturando eventos de tecla via evdev/uinput:
    * <kbd>Alt</kbd> + <kbd>1</kbd><kbd>6</kbd><kbd>7</kbd> = **`º`** | <kbd>Alt</kbd> + <kbd>1</kbd><kbd>6</kbd><kbd>6</kbd> = **`ª`**
    * <kbd>Alt</kbd> + <kbd>0</kbd><kbd>1</kbd><kbd>6</kbd><kbd>7</kbd> = **`§`** | <kbd>Alt</kbd> + <kbd>0</kbd><kbd>1</kbd><kbd>7</kbd><kbd>6</kbd> = **`°`**
    * <kbd>Alt</kbd> + <kbd>0</kbd><kbd>1</kbd><kbd>5</kbd><kbd>3</kbd> = **`™`** | <kbd>Alt</kbd> + <kbd>0</kbd><kbd>1</kbd><kbd>6</kbd><kbd>9</kbd> = **`©`** | <kbd>Alt</kbd> + <kbd>0</kbd><kbd>1</kbd><kbd>7</kbd><kbd>4</kbd> = **`®`**
    * <kbd>Alt</kbd> + <kbd>0</kbd><kbd>1</kbd><kbd>5</kbd><kbd>1</kbd> = **`—`** | <kbd>Alt</kbd> + <kbd>0</kbd><kbd>1</kbd><kbd>4</kbd><kbd>9</kbd> = **`•`**
    * <kbd>Alt</kbd> + <kbd>8</kbd><kbd>8</kbd> = **`⭡`** | <kbd>Alt</kbd> + <kbd>6</kbd><kbd>6</kbd> = **`⭢`** | <kbd>Alt</kbd> + <kbd>2</kbd><kbd>2</kbd> = **`⭣`** | <kbd>Alt</kbd> + <kbd>4</kbd><kbd>4</kbd> = **`⭠`**
    * <kbd>Alt</kbd> + <kbd>2</kbd><kbd>4</kbd> = **`↑`** | <kbd>Alt</kbd> + <kbd>2</kbd><kbd>6</kbd> = **`→`** | <kbd>Alt</kbd> + <kbd>2</kbd><kbd>5</kbd> = **`↓`** | <kbd>Alt</kbd> + <kbd>2</kbd><kbd>7</kbd> = **`←`**
* **Mouse Gamer Logitech G502 X:**
  * Polling rate em 1000Hz, perfil plano linear `flat` 1:1 sem aceleração de ponteiro via `ratbagctl`.
  * Gravação onboard na EEPROM do mouse: Botão 3 = Colar, Botão 4 = Gatilho do Kando (<kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>F10</kbd>), Botão 5 = Copiar, Botões 6 e 7 = Rolagem horizontal (Tilt Wheel).
* **Mesa Digitalizadora Wacom Intuos Pro S (PTH-460):**
  * Driver nativo do kernel `wacom.ko` com permissões udev e pareamento Bluetooth confiável.
  * Mapeamento de proporção ultrawide (DP-1), Modo Canhoto 180° configurado nativamente no compositor COSMIC.
  * Daemon de ExpressKeys e Touch Ring em Python/uinput com zoom in/out e atalhos configurados.

### 3. Suíte ArtCraft & Produtividade Office
* **ArtCraft Suite como Padrão do Sistema Operacional:**
  * **WordCraft (`ai.storyteller.wordcraft`)**: Editor de texto moderno e padrão para documentos `.docx`, `.doc`, `.odt`, `.rtf` e templates.
  * **GridCraft (`ai.storyteller.gridcraft`)**: Planilha eletrônica de alta produtividade padrão para planilhas `.xlsx`, `.xls`, `.ods`, `.csv` e `.tsv`.
  * **DeckCraft (`ai.storyteller.deckcraft`)**: Apresentador moderno padrão para `.pptx`, `.ppt`, `.odp` e slides.
  * **ArtCraft Launcher**: Central unificada de atualizações e inicialização dos aplicativos.
  * Sincronização automatizada em `~/.config/mimeapps.list` e `~/.config/cosmic-mimeapps.list`.

### 4. Ferramentas Avançadas de PDF
* **Stirling-PDF (Self-Hosted Docker WebApp):**
  * Servidor web local de ferramentas completas para PDF (mesclagem, compressão, divisão, conversão, OCR, assinatura e remoção de senhas) executando sob demanda em contêiner Docker (`frooodle/s-pdf`).
  * Lançador integrado no menu COSMIC em janela de aplicativo nativo (PWA) via script `~/.local/bin/stirling-pdf-launcher`.
* **PDFsam (Basic & Visual):**
  * Divisão, junção, rotação e reorganização visual de páginas de documentos PDF integrada ao menu de produtividade.
* **Master PDF Editor 5 & Okular:**
  * Leitura técnica com marcadores complexos (Okular) e edição direta de texto, campos e assinaturas em PDFs (Master PDF Editor 5).

### 5. Automações de Digitação, Clipboard & Kando
* **Espanso v2.4.1 (Wayland Edition):**
  * Text expander moderno integrado com repositório privado de snippets (`espanso-automacoes-sti`), backend `EVDEV` nativo e formulários gráficos interativos GTK3 ([scripts/daemons/form_runner.py](scripts/daemons/form_runner.py)).
  * **Indicador Nativo no Painel COSMIC (StatusNotifierItem):** Daemon dedicado [scripts/daemons/espanso-indicator.py](scripts/daemons/espanso-indicator.py) trazendo menu interativo (Buscar Snippets, Pausar/Retomar, Abrir Configurações e Reiniciar) sem criar janelas fantasmas.
* **Kando v3.0.0 (Pie Menu):**
  * Menu circular radial ativado via <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>F10</kbd> e botão de polegar do mouse G502 X.
  * Modo centrado desativado (`useFixedPosition: false`), abrindo diretamente sob o ponteiro do mouse na tela ultrawide.
* **CopyQ:** Gerenciador avançado de área de transferência com histórico, abas e integração com o barramento `StatusNotifierWatcher`.

### 6. Armazenamento, Nuvem & Rede Local
* **Pontos de Montagem Fixos (`/etc/fstab`):**
  * SSD NVMe 01 (Sistema): `/`
  * SSD NVMe 02 (Jogos): `/mnt/nvme_01`
  * HD Storage 930: `/mnt/storage_930`
  * HD Storage 700: `/mnt/storage_700` (com ancoragem automática da pasta `~/Downloads`)
* **Nuvens Sincronizadas (Rclone VFS):**
  * Google Drive Pessoal (`~/GoogleDrive_Pessoal`), OneDrive Pessoal (`~/OneDrive_Pessoal`) e MEGA Pessoal (`~/MEGA_Pessoal`) montados como serviços systemd com cache VFS sob demanda.
* **Servidor Samba Local (`/mnt/storage_700/samba`):**
  * Compartilhamento de rede (`192.168.0.0/24`) com o share `[Storage700]` compatível com a rede do UmbrelOS.
* **Tailscale (Mesh VPN WireGuard):** VPN ponto a ponto segura entre computadores, celulares e servidores.
* **Backup & Restauração de Dispositivos Android via ADB ([util/android-backup/backup_android.sh](util/android-backup/backup_android.sh) e [util/android-backup/restore_android.sh](util/android-backup/restore_android.sh)):**
  * Extração e restauração em alta velocidade de fotos, documentos, mídias e aplicativos instalados com reindexação imediata no Android.

### 7. Trabalho Remoto (MPMS), WinApps & OneDrive Integrado
* **OneDrive Corporativo (MPMS) Acessível Nativamente no Linux:**
  * Acesso direto aos arquivos corporativos através do Nautilus e do gerenciador de arquivos via montagem local SMB/GVFS, sem precisar abrir a VM Windows.
  * **Indicador de Bandeja Oficial:** Daemon [scripts/daemons/onedrive-indicator.py](scripts/daemons/onedrive-indicator.py) (`onedrive-indicator.service`) com ícone oficial SVG na barra de status superior do COSMIC e menu com atalhos rápidos para abrir pasta local, sincronização, web SharePoint e máquina virtual.
  * Overrides Flatpak aplicados para permitir que aplicativos isolados (como o ZapZap) acessem e anexem arquivos diretamente da montagem do OneDrive.
* **WinApps & Windows 11 KVM:**
  * Provisionamento de contêiner Windows com aceleração KVM (`dockurr/windows`) e integração de aplicativos via FreeRDP 3 com login automático transparente (AutoLogon).
  * Conexão RDP salva e integrada ao Remmina para suporte e manutenção da VM com um clique.
* **VPN Corporativa MPMS (openfortivpn):**
  * Conexão SSL-VPN com autenticação em dois fatores (2FA/OTP) sem clientes proprietários pesados.

### 8. Jogos, Streaming & Mídia
* **Epic Games Launcher & Heroic:** Lançador da Epic Games integrado à categoria "Jogos" da COSMIC App Library com prefixo Proton inicializado.
* **Steam, Gamemode & MangoHud:** Aceleração máxima de jogos e monitoramento de FPS e métricas de hardware.
* **Sunshine Game Streamer (Host GameStream):** Servidor de streaming self-hosted de baixíssima latência pareado com Smart TVs Samsung (Moonlight Tizen) com alternância automática entre 21:9 e 16:9 ([Docs/guias/como-parear-sunshine-moonlight-samsung-tv.md](Docs/guias/como-parear-sunshine-moonlight-samsung-tv.md)).
* **VLC Media Player:** Perfil customizado com tema escuro e correção de botões em Qt Style Sheets ([Docs/guias/tema_escuro_botoes_vlc.md](Docs/guias/tema_escuro_botoes_vlc.md)).
* **GIMP com PhotoGIMP:** Interface gráfica espelhada no Adobe Photoshop com todos os atalhos clássicos.
* **Gravador de Tela Nativo (Kooha):** Captura em alta taxa de quadros (MP4/WebM) via atalho global e integração com Kando.

---

## 🏗️ Estrutura do Repositório & Módulos

```text
.
├── AGENTS.md                           # Diretrizes para Agentes de IA & Engenharia Autônoma
├── setup_popos.sh                      # Orquestrador Central Modular (--list, --test, --force, --repair-ides)
├── Dockerfile                          # Ambiente de testes e sandbox headless
├── .dockerignore                       # Exclusão de segredos (.env, rclone.conf, chaves) do build Docker
├── config/                             # Arquivos de Configuração Centralizados
│   ├── rclone/                         # Perfis e credenciais do Rclone
│   ├── ssl/                            # Certificados CA corporativos (MPMS)
│   └── systemd/                        # Drop-ins e configurações adicionais do systemd
├── scripts/                            # Módulos de Provisionamento Independentes
│   ├── 00_comum.sh                     # Biblioteca base (cores, checkpoints, REAL_USER e funções utilitárias)
│   ├── 01_otimizacao_sistema.sh        # Swappiness=10, inotify=524288 e DNS local (~pk.local)
│   ├── 02_teclado_cedilha_numlock.sh   # Layout US-Intl, Cedilha ('+c = ç) e NumLock permanente
│   ├── 03_atualizacao_sistema.sh       # Atualização APT, Pop Recovery e firmware
│   ├── 04_pacotes_base_dev.sh          # CLI tools, compiladores, NVM, Node.js e Rust
│   ├── 05_rclone_storage.sh            # Montagens FUSE do Rclone (GDrive, OneDrive, MEGA)
│   ├── 06_softwares_workflow.sh        # Apps essenciais, Espanso v2.4.1, Kando v3.0.0 e Flatpaks
│   ├── 07_powershell7.sh               # Microsoft PowerShell 7 (pwsh) oficial e Oh My Posh
│   ├── 08_antigravity_ide.sh           # Google Antigravity IDE (AppArmor, Wayland flags e atalhos)
│   ├── 09_onlyoffice_padrao.sh         # ArtCraft Suite (WordCraft, GridCraft, DeckCraft) como padrão
│   ├── 10_cosmic_applets_custom.sh     # Applets COSMIC (Now Playing, Minimon, Clima)
│   ├── 11_mouse_gaming.sh              # Logitech G502 X (1000Hz, perfil flat, macros onboard)
│   ├── 12_wacom_tablet.sh              # Driver kernel wacom.ko, Modo Canhoto e daemon de ExpressKeys
│   ├── 13_kando_restore.sh             # Restauração e conversão de menus Kando v3 (modo sob cursor)
│   ├── 14_cosmic_theme_restore.sh      # Temas COSMIC/GTK/Qt, regras de janelas flutuantes e fix VLC
│   ├── 15_cosmic_menu_dock.sh          # Categorias inteligentes da App Library e itens fixados na Dock
│   ├── 16_ide_config_restore.sh        # Sincronização de configurações do VS Code e Antigravity
│   ├── 17_zsh_p10k_setup.sh            # Zsh, Oh-My-Zsh, Powerlevel10k e fontes MesloLGS NF
│   ├── 18_jogos_performance.sh         # Steam, Heroic, Epic Games, Gamemode, MangoHud e Sunshine
│   ├── 19_flatpak_permissions.sh       # Overrides de sistema de arquivos (/run/user/gvfs) e D-Bus
│   ├── 20_manutencao_ssds.sh           # Ativação do fstrim.timer semanal
│   ├── 21_autostart_config.sh          # Gerenciamento de autostart escalonado no login
│   ├── 22_openrgb_iluminacao.sh        # OpenRGB e regras udev para ASUS Aura
│   ├── 23_trabalho_remoto_vpn_rdp.sh   # VPN MPMS (openfortivpn 2FA), Remmina e PWAs Office
│   ├── 24_pdf_editors.sh               # Master PDF Editor 5 e Okular
│   ├── 25_samba_storage.sh             # Servidor Samba local (/mnt/storage_700/samba)
│   ├── 26_winapps_office.sh            # WinApps (Windows KVM acelerado, FreeRDP 3 e OneDrive SMB)
│   ├── 27_tailscale.sh                 # Mesh VPN Tailscale (WireGuard)
│   ├── 28_limpeza_otimizacao.sh        # Limpeza, Docker socket on-demand, latência PipeWire e backups
│   └── daemons/                        # Daemons e Utilitários em Python (Background Services)
│       ├── alt-numpad-daemon.py        # Daemon de Alt Codes do Windows sob Wayland (evdev/uinput)
│       ├── bt-audio-switcher.py        # Comutação automática para fone Bluetooth (QCY H3S) e caixas de som
│       ├── espanso-indicator.py        # Tray Indicator nativo StatusNotifierItem para Espanso
│       ├── form_runner.py              # Formulários gráficos GTK3 com injeção de foco para Espanso
│       ├── onedrive-indicator.py       # Indicador de bandeja com menu oficial para o OneDrive corporativo
│       ├── patch_cedilla_electron.py   # Patch de cedilha e aspas em binários Chromium/Electron
│       └── wacom-expresskeys-daemon.py # Daemon de ExpressKeys e Touch Ring da Wacom Intuos Pro S
├── tests/                              # Suíte de Testes Automatizados (Unitários & Integração)
│   ├── run_all.py                      # Executor unificado com relatório colorido ANSI
│   ├── test_in_docker.sh               # Sandbox completo em container Docker com mocks
│   ├── unit/                           # Testes de sintaxe Bash/Python, 00_comum.sh e daemons
│   └── integration/                    # Testes do orquestrador CLI e regras de módulos
├── util/                               # Utilitários de Manutenção e Hardware
│   ├── android-backup/
│   │   ├── backup_android.sh           # Backup automatizado de celular Android via ADB
│   │   └── restore_android.sh          # Restauração assistida no celular formatado via ADB
│   └── docker-update/
│       └── update_containers.sh        # Atualização automatizada de containers Docker (Compose & Standalone)
│   └── winapps/                        # Scripts de debloat e otimização para VM Windows (WinApps)
│       ├── onedrive.svg                # Ícone oficial em vetor do Microsoft OneDrive
│       ├── otimizar_winapps_vm.cmd     # Launcher com elevação automática de Administrador
│       ├── otimizar_winapps_vm.ps1     # Script de remoção de telemetria, bloatware e serviços
│       └── setup_autologon.bat         # Configuração de AutoLogon e bypass de tela de bloqueio
├── Logs/                               # Logs de Execução e Checkpoints do Setup
│   └── .setup_progress.log             # Histórico de módulos concluídos
└── Docs/                               # Relatórios Técnicos e Manuais Especializados
    ├── guias/                          # Manuais Práticos e Guias de Configuração
    │   ├── como-fazer-backup-android.md
    │   ├── como-atualizar-containers-docker.md
    │   ├── como-parear-sunshine-moonlight-samsung-tv.md
    │   ├── gravacao_de_tela_cosmic_kooha.md
    │   ├── nautilus_gerenciador_arquivos_padrao.md
    │   ├── onedrive_winapps_mpms_guia.md
    │   ├── otimizacao_debloat_winapps_vm.md
    │   └── tema_escuro_botoes_vlc.md
    ├── issues/                         # Diagnósticos e Soluções de Bugs (Wayland/Hardware/Upstream)
    │   ├── issue_alt_codes_numpad_wayland.md
    │   ├── issue_antigravity_dock_cosmic_launch.md
    │   ├── issue_chromium_electron_cedilha_wayland.md
    │   ├── issue_cosmic_files_fuse_freeze.md
    │   ├── issue_cosmic_numlock_boot.md
    │   ├── issue_cursor_blurry_gtk4_wayland.md
    │   ├── issue_edf_espanso_kando_cosmic.md
    │   ├── issue_espanso_wayland_tray_cosmic.md
    │   └── issue_opentabletdriver_wacom_bluetooth.md
    ├── planejamento/                   # Roadmaps e Melhorias Futuras
    │   └── melhorias_futuras_workstation.md
    └── relatorios/                     # Históricos de Sessão, Auditorias e Contexto
        ├── auditoria_seguranca_workstation.md
        └── contexto_proxima_conversa.md
```

---

## ⚙️ Guia de Uso & Execução

### 🚀 Execução Completa Automatizada:
Executa todos os módulos de forma sequencial e idempotente, pulando automaticamente o que já estiver concluído:
```bash
sudo ./setup_popos.sh
```

### 📋 Listar Todos os Módulos:
```bash
./setup_popos.sh --list
```

### 🧪 Executar a Suíte de Testes Automatizados:
Valida sintaxe de todos os scripts Bash e daemons Python, biblioteca de idempotência, patches binários e coerência dos módulos (executado em ~0.4s):
```bash
./setup_popos.sh --test
```

### 🎯 Executar um Módulo Isolado:
```bash
# Pelo número ou nome via orquestrador:
sudo ./setup_popos.sh 06
sudo ./setup_popos.sh 12

# Ou chamando o script diretamente:
sudo ./scripts/06_softwares_workflow.sh
sudo ./scripts/12_wacom_tablet.sh
```

### 🔄 Forçar Reexecução (Limpar Checkpoints):
```bash
sudo ./setup_popos.sh --force
```

### 🔧 Reparo Rápido de IDEs (Google Antigravity & VS Code):
Limpa travas residuais (`code.lock`), caches corrompidos de GPU/Dawn do Wayland e reaplica flags de estabilidade:
```bash
./setup_popos.sh --repair-ides
```

---

## 🌟 Créditos & Projetos de Código Aberto

Este ecossistema de provisionamento é construído sobre projetos de código aberto de excelência e da comunidade Linux. Registramos nossos agradecimentos aos autores originais:

| Software / Projeto | Descrição / Uso no Setup | Repositório / Link Oficial |
| :--- | :--- | :--- |
| **System76 COSMIC Desktop** | Ambiente de desktop de próxima geração em Rust (`cosmic-comp`, `cosmic-settings`, `cosmic-panel`, `cosmic-files`) | [pop-os/cosmic-epoch](https://github.com/pop-os/cosmic-epoch) |
| **ArtCraft Suite** | Suíte moderna de produtividade documental (WordCraft, GridCraft, DeckCraft e Launcher) | [ArtCraft Suite](https://artcraft.ai) |
| **Stirling-PDF** | Central robusta self-hosted para manipulação, conversão, OCR e assinatura de PDFs | [Stirling-Tools/Stirling-PDF](https://github.com/Stirling-Tools/Stirling-PDF) |
| **PDFsam (Basic & Visual)** | Divisão, mesclagem e rotação visual intuitiva de páginas em documentos PDF | [torakiki/pdfsam](https://github.com/torakiki/pdfsam) |
| **Master PDF Editor** | Editor avançado para criação e modificação direta de conteúdo e anotações em PDFs | [Code Industry Master PDF](https://code-industry.net/masterpdfeditor/) |
| **Okular** | Leitor de documentos universal da comunidade KDE com suporte avançado a marcadores | [KDE/okular](https://invent.kde.org/graphics/okular) |
| **Espanso** | Text expander em Rust focado em privacidade utilizado para automações de digitação | [espanso/espanso](https://github.com/espanso/espanso) |
| **Kando** | Menu circular (pie menu) cross-platform de alta performance | [kando-menu/kando](https://github.com/kando-menu/kando) |
| **WinApps** | Execução de aplicativos Windows (Microsoft 365) via contêiner KVM acelerado com FreeRDP | [winapps-org/winapps](https://github.com/winapps-org/winapps) |
| **Dockurr Windows** | Imagem Docker para virtualização Windows no Linux com suporte a KVM | [dockur/windows](https://github.com/dockur/windows) |
| **FreeRDP 3** | Implementação de código aberto de alta velocidade do protocolo RDP | [FreeRDP/FreeRDP](https://github.com/FreeRDP/FreeRDP) |
| **Sunshine Game Streamer** | Servidor de streaming self-hosted de baixa latência para Moonlight | [LizardByte/Sunshine](https://github.com/LizardByte/Sunshine) |
| **Moonlight Game Streaming** | Cliente de streaming de jogos de alto desempenho | [moonlight-stream/moonlight-qt](https://github.com/moonlight-stream/moonlight-qt) |
| **Moonlight Tizen** | Port do cliente Moonlight para TVs Samsung Tizen OS | [brightcraft/moonlight-tizen](https://github.com/brightcraft/moonlight-tizen) |
| **Apps2Samsung** | Instalador e gerenciador de pacotes Tizen para Smart TVs Samsung | [Apps2Samsung/Apps2Samsung](https://github.com/Apps2Samsung/Apps2Samsung) |
| **CopyQ** | Gerenciador avançado de área de transferência com histórico e scripts | [hluk/CopyQ](https://github.com/hluk/CopyQ) |
| **Rclone** | Utilitário definitivo para sincronização e montagem FUSE de nuvens | [rclone/rclone](https://github.com/rclone/rclone) |
| **PhotoGIMP** | Patch de customização do GIMP para interface similar ao Adobe Photoshop | [Diolinux/PhotoGIMP](https://github.com/Diolinux/PhotoGIMP) |
| **Kooha** | Gravador de tela moderno, elegante e nativo para Wayland | [SeaDve/Kooha](https://github.com/SeaDve/Kooha) |
| **LocalSend** | Compartilhamento local de arquivos cross-platform via Wi-Fi | [localsend/localsend](https://github.com/localsend/localsend) |
| **Jellyfin Desktop** | Cliente desktop para streaming do media center Jellyfin | [jellyfin/jellyfin-media-player](https://github.com/jellyfin/jellyfin-media-player) |
| **Libratbag & Piper** | Configuração de hardware e gravação de memória interna de mouses gaming (G502 X) | [libratbag/libratbag](https://github.com/libratbag/libratbag) |
| **Libwacom & Linux Wacom** | Drivers nativos e bibliotecas de identificação de mesas digitalizadoras Wacom | [linuxwacom/libwacom](https://github.com/linuxwacom/libwacom) |
| **OpenFortiVPN** | Cliente de código aberto para conexões SSL-VPN Fortinet com 2FA | [adrienverge/openfortivpn](https://github.com/adrienverge/openfortivpn) |
| **Remmina** | Cliente completo de Remote Desktop (RDP, VNC, SSH) para Linux | [FreeRDP/Remmina](https://github.com/FreeRDP/Remmina) |
| **OpenRGB** | Controle e sincronização universal de iluminação RGB de hardware | [CalcProgrammer1/OpenRGB](https://gitlab.com/CalcProgrammer1/OpenRGB) |
| **Flatseal** | Gerenciador gráfico de permissões para aplicativos Flatpak | [tchx84/Flatseal](https://github.com/tchx84/Flatseal) |
| **Tailscale** | Rede mesh VPN segura baseada no protocolo WireGuard | [tailscale/tailscale](https://github.com/tailscale/tailscale) |
| **Powerlevel10k** | Tema de alta performance para Zsh com suporte visual e git instantâneo | [romkatv/powerlevel10k](https://github.com/romkatv/powerlevel10k) |
| **COSMIC Applets da Comunidade** | Miniaplicativos para o painel e dock do COSMIC: Now Playing, Minimon, Clima e Drives | [cosmic-utils](https://github.com/cosmic-utils) & [DiegoMMR](https://github.com/DiegoMMR) |

---

## 📄 Licença & Isenção de Responsabilidade

Este projeto é disponibilizado sob a licença **MIT**. Todos os scripts foram projetados com foco em idempotência, integridade de dados e compatibilidade com o Pop!_OS 24.04 LTS sob o ecossistema COSMIC Desktop.
