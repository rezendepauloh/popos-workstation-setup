# Pop!_OS 24.04 LTS - Automated Workstation Provisioning & Setup

Script de automação, provisionamento idempotente e infraestrutura como código (IaC) para configuração completa do ambiente de trabalho, desenvolvimento, produtividade, mídia e jogos no **Pop!_OS 24.04 LTS** (com suporte de primeira classe ao **COSMIC Desktop Environment** e Wayland nativo).

---

## 🚀 Destaques & O que o Projeto Automatiza

### 1. Otimizações de Sistema, Kernel & I/O
*   **Swappiness Otimizado (`vm.swappiness=10`):** Aproveita a capacidade de 32 GB de RAM para máxima responsividade, minimizando acessos lentos de swap ao disco.
*   **File Watchers Elevados (`fs.inotify.max_user_watches=524288`):** Evita falhas de limites de monitoramento de arquivos em tempo real para o Antigravity IDE, VS Code, Git e grandes monorepos.
*   **DNS Local Permanente & Domínio de Roteamento (`~pk.local`):** Configuração persistente via drop-in do `systemd-resolved` (`/etc/systemd/resolved.conf.d/99-local-dns.conf`) e NetworkManager, com DNS primário local (`192.168.0.8`), fallback público seguro (`1.1.1.1`) e domínio de roteamento local (`~pk.local`) para desenvolvimento web e serviços locais sem conflito com mDNS.
*   **Memória ZRAM com Compressão Zstandard (`zstd`):** Swap ultra-rápido compactado na RAM com prioridade máxima.
*   **TRIM Semanal Automatizado (`fstrim.timer`):** Preservação contínua de vida útil e performance de leitura/escrita de todos os SSDs NVMe.

### 2. Periféricos, Entrada & Ergonomia
*   **Teclado Mecânico (Redragon Horus Pro):**
    *   Taxa de repetição ergonômica ajustada para 300ms de atraso e 30ms de intervalo (~33 caracteres/segundo).
    *   **Cedilha e Aspas do Windows no Wayland Nativo (`ui::CharacterComposer`):**
        *   Em Wayland nativo (`--ozone-platform=wayland`), motores Chromium/Electron utilizam tabelas estáticas de composição interna onde `' + c` resultava em `ć` (U+0107) e pressionar <kbd>"</kbd> (<kbd>Shift</kbd>+<kbd>'</kbd>) duas vezes gerava o trema `¨` (U+00A8).
        *   Utilitário nativo `/usr/local/bin/patch-cedilla-electron` ([scripts/patch_cedilla_electron.py](scripts/patch_cedilla_electron.py)) aplicando patch seguro por padrão de bytes diretamente nos binários de **Google Antigravity IDE**, **VS Code**, **Google Chrome** e **Brave**:
            *   <kbd>'</kbd> + <kbd>c</kbd> = **`ç`** e <kbd>'</kbd> + <kbd>C</kbd> = **`Ç`**
            *   <kbd>"</kbd> 2x = **`"`** (em vez de `¨`)
            *   <kbd>'</kbd> 2x = **`'`** (em vez de `´`)
        *   **APT Post-Invoke Hook** (`/etc/apt/apt.conf.d/99-patch-cedilla-electron`) garantindo reaplicação transparente a cada atualização do sistema. Documentação detalhada em [Docs/issue_chromium_electron_cedilha_wayland.md](Docs/issue_chromium_electron_cedilha_wayland.md).
    *   **NumLock Permanente & Sincronização do LED de Hardware:**
        *   Layout XKB do COSMIC configurado com `options: Some("numpad:mac")` garantindo que o teclado numérico sempre emita números.
        *   Persistência no `cosmic-greeter` para funcionamento já na tela de login e script `/usr/local/bin/numlock-on` (evdev/uinput) para acender o LED físico do hardware no boot. Documentação em [Docs/issue_cosmic_numlock_boot.md](Docs/issue_cosmic_numlock_boot.md).
    *   **Alt Codes do Windows no Teclado Numérico (Wayland Native):**
        *   Daemon de usuário [scripts/alt-numpad-daemon.py](scripts/alt-numpad-daemon.py) gerenciado pelo systemd (`alt-numpad.service`), emulando com perfeição os códigos clássicos do Windows sob Wayland:
            *   <kbd>Alt</kbd> + <kbd>1</kbd><kbd>6</kbd><kbd>7</kbd> = **`º`** | <kbd>Alt</kbd> + <kbd>1</kbd><kbd>6</kbd><kbd>6</kbd> = **`ª`**
            *   <kbd>Alt</kbd> + <kbd>0</kbd><kbd>1</kbd><kbd>6</kbd><kbd>7</kbd> = **`§`** | <kbd>Alt</kbd> + <kbd>0</kbd><kbd>1</kbd><kbd>7</kbd><kbd>6</kbd> = **`°`**
            *   <kbd>Alt</kbd> + <kbd>0</kbd><kbd>1</kbd><kbd>5</kbd><kbd>3</kbd> = **`™`** | <kbd>Alt</kbd> + <kbd>0</kbd><kbd>1</kbd><kbd>6</kbd><kbd>9</kbd> = **`©`** | <kbd>Alt</kbd> + <kbd>0</kbd><kbd>1</kbd><kbd>7</kbd><kbd>4</kbd> = **`®`**
            *   <kbd>Alt</kbd> + <kbd>0</kbd><kbd>1</kbd><kbd>5</kbd><kbd>1</kbd> = **`—`** | <kbd>Alt</kbd> + <kbd>0</kbd><kbd>1</kbd><kbd>4</kbd><kbd>9</kbd> = **`•`**
            *   <kbd>Alt</kbd> + <kbd>8</kbd><kbd>8</kbd> = **`⭡`** | <kbd>Alt</kbd> + <kbd>6</kbd><kbd>6</kbd> = **`⭢`** | <kbd>Alt</kbd> + <kbd>2</kbd><kbd>2</kbd> = **`⭣`** | <kbd>Alt</kbd> + <kbd>4</kbd><kbd>4</kbd> = **`⭠`**
            *   <kbd>Alt</kbd> + <kbd>2</kbd><kbd>4</kbd> = **`↑`** | <kbd>Alt</kbd> + <kbd>2</kbd><kbd>6</kbd> = **`→`** | <kbd>Alt</kbd> + <kbd>2</kbd><kbd>5</kbd> = **`↓`** | <kbd>Alt</kbd> + <kbd>2</kbd><kbd>7</kbd> = **`←`**
        *   Documentação detalhada em [Docs/issue_alt_codes_numpad_wayland.md](Docs/issue_alt_codes_numpad_wayland.md).
*   **Mouse Gamer (Logitech G502 X):**
    *   Curva de aceleração desativada (perfil plano linear `flat` 1:1) com polling rate de 1000Hz via [libratbag](https://github.com/libratbag/libratbag).
    *   Macros gravadas na EEPROM interna do mouse: Botão 3 = Colar (<kbd>Ctrl</kbd>+<kbd>V</kbd>), Botão 4 = Gatilho Kando (<kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>F10</kbd>), Botão 5 = Copiar (<kbd>Ctrl</kbd>+<kbd>C</kbd>), Botões 6 e 7 = Rolagem horizontal (*Tilt Wheel*).
*   **Mesa Digitalizadora (Wacom Intuos Pro S / PTH-460):**
    *   **Driver Oficial do Kernel (`wacom.ko`):** Módulo nativo desbloqueado, com regras udev de permissão de usuário (`/etc/udev/rules.d/99-wacom-native.rules`) e pareamento Bluetooth confiável no BlueZ.
    *   **Modo Canhoto 180° e Calibração de Proporção:** Configurado nativamente no compositor COSMIC (`~/.config/cosmic/com.system76.CosmicComp/v1/input_devices`) mapeando a Caneta e Touchpad para o monitor principal ultrawide (`DP-1`) com rotação de 180° para toques com os dedos.
    *   **ExpressKeys e Touch Ring:** Daemon leve em Python [scripts/wacom-expresskeys-daemon.py](scripts/wacom-expresskeys-daemon.py) gerenciado pelo systemd (`wacom-expresskeys.service`), injetando Desfazer (<kbd>Ctrl</kbd>+<kbd>Z</kbd>), Refazer (<kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>Z</kbd>), Pan (<kbd>Espaço</kbd>), Salvar (<kbd>Ctrl</kbd>+<kbd>S</kbd>), Copiar (<kbd>Ctrl</kbd>+<kbd>C</kbd>), Colar (<kbd>Ctrl</kbd>+<kbd>V</kbd>) e Zoom In/Out pelo anel. Documentação técnica em [Docs/issue_opentabletdriver_wacom_bluetooth.md](Docs/issue_opentabletdriver_wacom_bluetooth.md).

### 3. Produtividade, Automação & Workflows
*   **Espanso v2.4.1 (Wayland Edition):**
    *   Text expander moderno em Rust integrado com repositório privado de snippets [`espanso-automacoes-sti`](https://github.com/rezendepauloh/espanso-automacoes-sti) em `~/.config/espanso`.
    *   Execução estável via backend `EVDEV` com permissões `cap_dac_override`.
    *   Formulários gráficos interativos em Python/Tkinter e processamento de linguagem natural (spaCy).
    *   **Ícone Nativo na Bandeja do Painel COSMIC (StatusNotifierItem):** Daemon dedicado [scripts/espanso-indicator.py](scripts/espanso-indicator.py) gerenciado por serviço systemd (`espanso-indicator.service`), trazendo menu interativo (Buscar Snippets, Pausar/Retomar, Abrir Configurações e Reiniciar) e eliminando a micro-janela fantasma X11 de 1 pixel na tela. Documentação e relatório para upstream em [Docs/issue_espanso_wayland_tray_cosmic.md](Docs/issue_espanso_wayland_tray_cosmic.md).
*   **Kando v3.0.0 (Pie Menu):**
    *   Menu radial circular moderno com atalho global <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>F10</kbd> e acionamento no botão de gatilho do mouse G502 X.
    *   Wrapper de compatibilidade gráfica Wayland/X11 e conversão automática de atalhos e aplicativos do Windows para apps nativos Linux Pop!_OS e Flatpak.
*   **CopyQ:** Gerenciador avançado de área de transferência com histórico, abas e integração com o barramento `StatusNotifierWatcher` no painel superior.
*   **Google Antigravity IDE & VS Code:** Instalação oficial com aceleração gráfica Wayland nativa, perfil do AppArmor para sandboxing irrestrito, restauração sincronizada de dotfiles e configurações (`settings.json`, `keybindings.json`, `snippets`) a partir do Google Drive, e colar com botão direito no terminal integrado.
*   **Terminal Moderno (ZSH + Powerlevel10k):** Shell Zsh padrão, tema Powerlevel10k com fontes oficiais `MesloLGS NF` instaladas automaticamente, suporte a `Ctrl+V` nativo no prompt e `ESC` para limpar a linha.

### 4. Armazenamento, Nuvem & Rede Local
*   **Discos Físicos & Montagens Fixas (`/etc/fstab`):**
    *   SSD NVMe 01 (Sistema): `/`
    *   SSD NVMe 02 (Jogos): `/mnt/nvme_01`
    *   HD Storage 930: `/mnt/storage_930`
    *   HD Storage 700: `/mnt/storage_700` (com ancoragem automática da pasta `~/Downloads`)
*   **Nuvens Sincronizadas (Rclone VFS):**
    *   Google Drive Pessoal (`~/GoogleDrive_Pessoal`), OneDrive Pessoal (`~/OneDrive_Pessoal`) e MEGA Pessoal (`~/MEGA_Pessoal`) montados como serviços systemd com cache VFS sob demanda e proteção contra travamentos no gerenciador de arquivos.
*   **Servidor Samba Local (`/mnt/storage_700/samba`):**
    *   Compartilhamento local na rede (`192.168.0.0/24`) com o share `[Storage700]`, permissões idênticas às do ecossistema UmbrelOS/Homelab e portas liberadas no firewall UFW.
*   **Tailscale (Mesh VPN WireGuard):** VPN segura ponto a ponto entre dispositivos, com IP forwarding ativado e integração gráfica.
*   **Backup & Restauração de Dispositivos Android via ADB ([util/backup_android.sh](util/backup_android.sh) e [util/restore_android.sh](util/restore_android.sh)):**
    *   Extração em alta velocidade de fotos, documentos, mídias do WhatsApp/Telegram, geração de inventário e extração em lote dos `.apk` instalados, com restauração assistida e reindexação instantânea do MediaScanner. Documentação em [Docs/como-fazer-backup-android.md](Docs/como-fazer-backup-android.md).

### 5. Jogos, Streaming & Mídia
*   **Steam, Gamemode & MangoHud:** Aceleração máxima de jogos e monitoramento de desempenho.
*   **Sunshine Game Streamer (Host GameStream):** Servidor de streaming de jogos com permissões uinput/udev, aceleração por hardware e regras de firewall UFW configuradas.
*   **Streaming para Smart TV Samsung (Moonlight Tizen):** Alternância automática de resolução (Ultrawide 21:9 para 16:9 na TV) e guia completo de instalação via Apps2Samsung documentado em [Docs/como-parear-sunshine-moonlight-samsung-tv.md](Docs/como-parear-sunshine-moonlight-samsung-tv.md).
*   **VLC Media Player:** Perfil completo customizado com fix de tema escuro universal em Qt Style Sheets ([Docs/tema_escuro_botoes_vlc.md](Docs/tema_escuro_botoes_vlc.md)).
*   **GIMP com PhotoGIMP:** Interface gráfica e atalhos de teclado espelhados no Adobe Photoshop.
*   **Gravador de Tela Nativo (Kooha):** Gravação de tela em MP4/WebM com áudio interno e microfone via atalho <kbd>Ctrl</kbd> + <kbd>Print</kbd> e integração com o Kando ([Docs/gravacao_de_tela_cosmic_kooha.md](Docs/gravacao_de_tela_cosmic_kooha.md)).

### 6. Trabalho Remoto (MPMS) & WinApps
*   **VPN Aberta MPMS (openfortivpn):** Conexão SSL-VPN corporativa com autenticação de dois fatores (2FA/OTP), sem dependência do cliente proprietário pago EMS.
*   **Cliente RDP Remmina:** Perfil pré-configurado com áudio remoto e sincronização de área de transferência.
*   **Microsoft 365 Web Apps (PWAs):** Word, Excel, PowerPoint, Outlook e Portal configurados como aplicativos independentes com ícones SVG oficiais.
*   **WinApps (Ambiente Windows KVM/Docker):** Provisionamento de contêiner Windows com FreeRDP seamless e integração do OneDrive corporativo ao gerenciador de arquivos via SMB ([Docs/onedrive_winapps_mpms_guia.md](Docs/onedrive_winapps_mpms_guia.md)).

---

## 🏗️ Estrutura do Repositório & Módulos

```
.
├── setup_popos_v2.sh                   # Orquestrador Central Modular
├── scripts/                            # Módulos de Provisionamento Independentes
│   ├── 00_comum.sh                     # Biblioteca base (logs, checkpoints, usuário real)
│   ├── 01_otimizacao_sistema.sh        # Swappiness, inotify e DNS local (~pk.local)
│   ├── 02_teclado_cedilha_numlock.sh   # Layout US-Intl, Cedilha ('+c = ç) e NumLock
│   ├── 03_atualizacao_sistema.sh       # Atualização APT, Pop Recovery e firmware
│   ├── 04_pacotes_base_dev.sh          # Utilitários CLI, compiladores, NVM e Rust
│   ├── 05_rclone_storage.sh            # Montagens FUSE do Rclone (GDrive, OneDrive, MEGA)
│   ├── 06_softwares_workflow.sh        # Apps essenciais, Espanso v2.4.1 e Kando v3.0.0
│   ├── 07_powershell7.sh               # Microsoft PowerShell 7 (pwsh) oficial
│   ├── 08_antigravity_ide.sh           # Google Antigravity IDE (AppArmor, Wayland flags)
│   ├── 09_onlyoffice_padrao.sh         # OnlyOffice e Nautilus como aplicativos padrão
│   ├── 10_cosmic_applets_custom.sh      # Applets COSMIC (Now Playing, Minimon, Clima)
│   ├── 11_mouse_gaming.sh              # Logitech G502 X (DPIs, 1000Hz, macros físicas)
│   ├── 12_wacom_tablet.sh              # Driver nativo kernel wacom.ko, Modo Canhoto e UInput
│   ├── 13_kando_restore.sh             # Restauração e conversão de menus Kando v3
│   ├── 14_cosmic_theme_restore.sh      # Temas COSMIC/GTK/Qt, janelas flutuantes e fix VLC
│   ├── 15_cosmic_menu_dock.sh          # Categorias inteligentes da App Library e Dock
│   ├── 16_ide_config_restore.sh        # Sincronização de configurações VS Code e Antigravity
│   ├── 17_zsh_p10k_setup.sh            # Zsh, Oh-My-Zsh, Powerlevel10k e fontes Meslo
│   ├── 18_jogos_performance.sh         # Steam, Heroic Launcher e Sunshine Game Streamer
│   ├── 19_flatpak_permissions.sh       # Overrides de sistema de arquivos e D-Bus para Flatpaks
│   ├── 20_manutencao_ssds.sh           # Ativação do fstrim.timer semanal
│   ├── 21_autostart_config.sh          # Gerenciamento de autostart escalonado no login
│   ├── 22_openrgb_iluminacao.sh        # OpenRGB e regras udev para ASUS Aura
│   ├── 23_trabalho_remoto_vpn_rdp.sh   # VPN MPMS (openfortivpn 2FA), Remmina e PWAs Office
│   ├── 24_pdf_editors.sh               # Master PDF Editor e Okular
│   ├── 25_samba_storage.sh             # Servidor Samba local (/mnt/storage_700/samba)
│   ├── 26_winapps_office.sh            # WinApps (Windows KVM acelerado com FreeRDP)
│   ├── 27_limpeza_otimizacao.sh        # Limpeza, Docker socket, latência PipeWire e backups
│   ├── 28_tailscale.sh                 # Mesh VPN Tailscale (WireGuard)
│   ├── alt-numpad-daemon.py            # Daemon Python de Alt Codes do Windows (Wayland)
│   ├── espanso-indicator.py            # Tray Indicator nativo StatusNotifierItem para Espanso
│   ├── patch_cedilla_electron.py       # Patch cirúrgico de cedilha em binários Electron
│   └── wacom-expresskeys-daemon.py     # Daemon de atalhos e anel de zoom da Wacom (UInput)
├── util/                               # Utilitários de Manutenção e Hardware
│   ├── backup_android.sh               # Backup automatizado de celular Android via ADB
│   └── restore_android.sh              # Restauração assistida no celular formatado via ADB
└── Docs/                               # Relatórios Técnicos e Manuais Especializados
    ├── issue_espanso_wayland_tray_cosmic.md        # Relatório de Tray & Window no Wayland
    ├── issue_opentabletdriver_wacom_bluetooth.md   # Relatório de Driver Nativo Wacom
    ├── issue_chromium_electron_cedilha_wayland.md  # Relatório do Patch de Cedilha
    ├── issue_alt_codes_numpad_wayland.md           # Relatório de Alt Codes no Wayland
    ├── issue_cosmic_numlock_boot.md                # Relatório do NumLock no Greeter
    ├── issue_cosmic_files_fuse_freeze.md           # Diagnóstico de I/O e FUSE
    ├── como-parear-sunshine-moonlight-samsung-tv.md# Guia de streaming para Smart TV Samsung
    ├── como-fazer-backup-android.md                # Guia de backup e restore Android
    ├── gravacao_de_tela_cosmic_kooha.md            # Guia de gravação de tela
    ├── onedrive_winapps_mpms_guia.md               # Guia de deploy do WinApps
    ├── nautilus_gerenciador_arquivos_padrao.md     # Guia do Nautilus no COSMIC
    ├── tema_escuro_botoes_vlc.md                   # Guia de temas QSS para VLC
    └── melhorias_futuras_workstation.md            # Roadmap de otimizações de sistema
```

---

## ⚙️ Guia de Uso & Execução

### 🚀 Execução Completa Automatizada:
Executa todos os módulos de forma sequencial e idempotente, pulando automaticamente o que já estiver concluído:
```bash
sudo ./setup_popos_v2.sh
```

### 📋 Listar Todos os Módulos:
```bash
./setup_popos_v2.sh --list
```

### 🎯 Executar um Módulo Isolado:
```bash
# Pelo número ou nome via orquestrador:
sudo ./setup_popos_v2.sh 06
sudo ./setup_popos_v2.sh 12

# Ou chamando o script diretamente:
sudo ./scripts/06_softwares_workflow.sh
sudo ./scripts/12_wacom_tablet.sh
```

### 🔄 Forçar Reexecução (Limpar Checkpoints):
```bash
sudo ./setup_popos_v2.sh --force
```

### 🔧 Reparo Rápido de IDEs (Google Antigravity & VS Code):
Limpa travas residuais (`code.lock`), caches corrompidos de GPU/Dawn do Wayland e reaplica flags de estabilidade:
```bash
./setup_popos_v2.sh --repair-ides
```

---

## 🌟 Créditos & Projetos de Código Aberto

Este ecossistema de provisionamento é construído sobre projetos de código aberto e da comunidade Linux. Registramos nossos agradecimentos e referências aos autores originais:

| Software / Projeto | Descrição / Uso no Setup | Repositório / Link Oficial |
| :--- | :--- | :--- |
| **System76 COSMIC Desktop** | Ambiente de desktop de próxima geração em Rust (`cosmic-comp`, `cosmic-settings`, `cosmic-panel`, `cosmic-files`) | [pop-os/cosmic-epoch](https://github.com/pop-os/cosmic-epoch) |
| **Espanso** | Text expander em Rust focado em privacidade utilizado para automações de digitação | [espanso/espanso](https://github.com/espanso/espanso) |
| **Kando** | Menu circular (pie menu) cross-platform de alta performance | [kando-menu/kando](https://github.com/kando-menu/kando) |
| **Sunshine Game Streamer** | Servidor de streaming self-hosted de baixa latência para Moonlight | [LizardByte/Sunshine](https://github.com/LizardByte/Sunshine) |
| **Moonlight Game Streaming** | Cliente de streaming de jogos de alto desempenho | [moonlight-stream/moonlight-qt](https://github.com/moonlight-stream/moonlight-qt) |
| **Moonlight Tizen** | Port do cliente Moonlight para TVs Samsung Tizen OS | [brightcraft/moonlight-tizen](https://github.com/brightcraft/moonlight-tizen) |
| **Apps2Samsung** | Instalador e gerenciador de pacotes Tizen para Smart TVs Samsung | [Apps2Samsung/Apps2Samsung](https://github.com/Apps2Samsung/Apps2Samsung) |
| **CopyQ** | Gerenciador avançado de área de transferência com histórico e scripts | [hluk/CopyQ](https://github.com/hluk/CopyQ) |
| **Rclone** | Utilitário definitivo para sincronização e montagem FUSE de nuvens | [rclone/rclone](https://github.com/rclone/rclone) |
| **PhotoGIMP** | Patch de customização do GIMP para interface similar ao Adobe Photoshop | [Diolinux/PhotoGIMP](https://github.com/Diolinux/PhotoGIMP) |
| **Kooha** | Gravador de tela moderno, elegante e nativo para Wayland | [SeaDve/Kooha](https://github.com/SeaDve/Kooha) |
| **OnlyOffice Desktop Editors** | Suíte de escritório completa com compatibilidade com formatos MS Office | [ONLYOFFICE/DesktopEditors](https://github.com/ONLYOFFICE/DesktopEditors) |
| **LocalSend** | Compartilhamento local de arquivos cross-platform via Wi-Fi | [localsend/localsend](https://github.com/localsend/localsend) |
| **Jellyfin Desktop** | Cliente desktop para streaming do media center Jellyfin | [jellyfin/jellyfin-media-player](https://github.com/jellyfin/jellyfin-media-player) |
| **Libratbag & Piper** | Configuração de hardware e gravação de memória interna de mouses gaming (G502 X) | [libratbag/libratbag](https://github.com/libratbag/libratbag) |
| **Libwacom & Linux Wacom** | Drivers nativos e bibliotecas de identificação de mesas digitalizadoras Wacom | [linuxwacom/libwacom](https://github.com/linuxwacom/libwacom) |
| **WinApps** | Execução de aplicativos Windows (Microsoft 365) via contêiner KVM acelerado | [winapps-org/winapps](https://github.com/winapps-org/winapps) |
| **OpenFortiVPN** | Cliente de código aberto para conexões SSL-VPN Fortinet com 2FA | [adrienverge/openfortivpn](https://github.com/adrienverge/openfortivpn) |
| **Remmina** | Cliente completo de Remote Desktop (RDP, VNC, SSH) para Linux | [FreeRDP/Remmina](https://github.com/FreeRDP/Remmina) |
| **OpenRGB** | Controle e sincronização universal de iluminação RGB de hardware | [CalcProgrammer1/OpenRGB](https://gitlab.com/CalcProgrammer1/OpenRGB) |
| **Flatseal** | Gerenciador gráfico de permissões para aplicativos Flatpak | [tchx84/Flatseal](https://github.com/tchx84/Flatseal) |
| **Tailscale** | Rede mesh VPN segura baseada no protocolo WireGuard | [tailscale/tailscale](https://github.com/tailscale/tailscale) |
| **Powerlevel10k** | Tema de alta performance para Zsh com suporte visual e git instantâneo | [romkatv/powerlevel10k](https://github.com/romkatv/powerlevel10k) |
| **COSMIC Applets da Comunidade** | Miniaplicativos para o painel e dock do COSMIC: Now Playing, Minimon, Clima e Drives | [cosmic-utils](https://github.com/cosmic-utils) & [DiegoMMR](https://github.com/DiegoMMR) |

---

## 📄 Licença & Isenção de Responsabilidade

Este projeto é disponibilizado sob a licença **MIT**. Todos os scripts foram projetados com foco em idempotência, preservação de dados e compatibilidade nativa com o Pop!_OS 24.04 LTS e o ecossistema COSMIC Desktop.
