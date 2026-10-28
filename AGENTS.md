# 🤖 AGENTS.md — Diretrizes para Agentes de IA & Engenharia Autônoma

> **Instruções operacionais, restrições arquiteturais e protocolo de trabalho para Antigravity, Claude Code, Gemini e assistentes de código que operam neste repositório.**  
> *Leia com atenção antes de realizar qualquer alteração em scripts, daemons ou documentação.*

---

## 🎯 1. Filosofia e Visão Geral do Sistema
O **Pop!_OS 24.04 LTS (COSMIC) Workstation Setup V2** é um ecossistema de Infraestrutura como Código (IaC) e automação pós-instalação idempotente para configurar uma estação de trabalho Linux de alta performance sob **COSMIC Desktop Environment (`cosmic-comp` / Wayland nativo)** em monitor Ultrawide (`3440x1440`, `DP-1`).

Pilares fundamentais:
1. **Idempotência Estrita**: Qualquer módulo deve poder ser executado múltiplas vezes (`--force`) sem duplicar linhas em arquivos de configuração (`.zshrc`, `/etc/fstab`, atalhos RON do COSMIC, JSONs do Kando/VS Code) e sem corromper o estado do sistema.
2. **Wayland & COSMIC Native First**: Priorize sempre soluções nativas para Wayland e `cosmic-comp` (protocolos Wayland, `evdev`/`uinput`, `StatusNotifierItem`, RON configs em `~/.config/cosmic/`), evitando gambiarras X11 a menos que estritamente documentadas.
3. **Execução Consciente de Contexto (`root` vs `$REAL_USER`)**: O orquestrador roda com `sudo`, mas arquivos na `$REAL_HOME` (`~/.config`, `~/.local`, serviços `systemctl --user`, `gsettings`, `flatpak`) **DEVEM** pertencer ao `$REAL_USER:$REAL_USER` (definido em `scripts/00_comum.sh`).

---

## 🏗️ 2. Arquitetura Modular e Organização de Diretórios

```text
.
├── setup_popos_v2.sh                   # Orquestrador central (--list, --force, --test, --repair-ides, <módulo>)
├── scripts/
│   ├── 00_comum.sh                     # Biblioteca compartilhada (cores, log_msg, check_flag, set_flag, REAL_USER/REAL_HOME)
│   ├── 01_otimizacao_sistema.sh        # Kernel sysctl (swappiness=10, inotify=524288) e DNS local (192.168.0.8 / ~pk.local)
│   ├── 02_teclado_cedilha_numlock.sh   # Layout US-Intl, patch binário Cedilha/Aspas Electron, Alt-Numpad e NumLock no boot
│   ├── 03_atualizacao_sistema.sh       # APT dist-upgrade, Pop Recovery e fwupd
│   ├── 04_pacotes_base_dev.sh          # CLI tools, build-essential, Python3, NVM/Node.js e Rust
│   ├── 05_rclone_storage.sh            # Montagens FUSE systemd para Google Drive, OneDrive e MEGA
│   ├── 06_softwares_workflow.sh        # Apps de produtividade, Flatpaks base, Espanso v2.4.1 (Wayland) e Kando v3.0.0
│   ├── 07_powershell7.sh               # PowerShell 7 (pwsh), Oh My Posh e módulos do Google Drive
│   ├── 08_antigravity_ide.sh           # Google Antigravity IDE, perfil AppArmor e flags nativas Wayland
│   ├── 09_onlyoffice_padrao.sh         # Associações XDG MIME para OnlyOffice e Nautilus
│   ├── 10_cosmic_applets_custom.sh     # Applets COSMIC (Now Playing, Minimon System Monitor, Weather)
│   ├── 11_mouse_gaming.sh              # Logitech G502 X via ratbagctl (1000Hz, flat profile, macros onboard)
│   ├── 12_wacom_tablet.sh              # Driver kernel wacom.ko, modo canhoto 180° no COSMIC e ExpressKeys daemon
│   ├── 13_kando_restore.sh             # Restauração do Kando Pie Menu (useFixedPosition: false, atalho COSMIC Ctrl+Shift+F10)
│   ├── 14_cosmic_theme_restore.sh      # Temas COSMIC/GTK/Qt, regras de janelas flutuantes (tiling_exception_custom) e VLC QSS
│   ├── 15_cosmic_menu_dock.sh          # Categorias da COSMIC App Library e itens fixados na Dock
│   ├── 16_ide_config_restore.sh        # Restauração de settings/keybindings e rotina --repair-ides (VS Code & Antigravity)
│   ├── 17_zsh_p10k_setup.sh            # Zsh, Oh-My-Zsh, Powerlevel10k e fontes MesloLGS NF
│   ├── 18_jogos_performance.sh         # Steam, Heroic, Gamemode, MangoHud e Sunshine Game Streamer (Moonlight Tizen)
│   ├── 19_flatpak_permissions.sh       # Overrides de filesystem (/mnt/storage_*) e D-Bus StatusNotifierWatcher
│   ├── 20_manutencao_ssds.sh           # Ativação do fstrim.timer semanal
│   ├── 21_autostart_config.sh          # Entradas ~/.config/autostart escalonadas
│   ├── 22_openrgb_iluminacao.sh        # OpenRGB e udev rules para ASUS Aura
│   ├── 23_trabalho_remoto_vpn_rdp.sh   # VPN MPMS (openfortivpn 2FA), Remmina RDP e PWAs do Microsoft 365
│   ├── 24_pdf_editors.sh               # Master PDF Editor 5 e Okular
│   ├── 25_samba_storage.sh             # Servidor Samba (/mnt/storage_700/samba - share [Storage700])
│   ├── 26_winapps_office.sh            # WinApps (Container KVM Windows + FreeRDP + SMB OneDrive MPMS)
│   ├── 27_tailscale.sh                 # Mesh VPN Tailscale (WireGuard)
│   ├── 28_limpeza_otimizacao.sh        # Limpeza final, Docker socket on-demand, PipeWire low-latency e backups
│   └── daemons/                        # Daemons em Python gerenciados por systemd / hooks APT
│       ├── alt-numpad-daemon.py        # Emulador de Alt Codes do Windows no Numpad via evdev/uinput
│       ├── espanso-indicator.py        # Ícone de bandeja StatusNotifierItem (AyatanaAppIndicator3) para Espanso
│       ├── patch_cedilla_electron.py   # Patch binário idempotente (ui::CharacterComposer) para ' + c = ç e aspas
│       └── wacom-expresskeys-daemon.py # Daemon evdev/uinput para ExpressKeys e Touch Ring da Wacom Intuos Pro S
├── tests/                              # Suíte de Testes Automatizados (Unitários & Integração)
│   ├── run_all.py                      # Executor unificado com relatório colorido ANSI (./setup_popos_v2.sh --test)
│   ├── unit/                           # Testes de sintaxe Bash/Python, 00_comum.sh e lógica dos daemons/patches
│   └── integration/                    # Testes do orquestrador CLI, coerência de módulos e transformações JSON/RON
├── test_in_docker.sh                   # Sandbox completo em container Docker com binários de hardware mockados
├── util/                               # Utilitários standalone (backup_android.sh e restore_android.sh via ADB)
└── Docs/                               # Documentação técnica profunda, guias e relatórios de issues upstream
```

---

## ⚠️ 3. Regras Críticas de Engenharia (NÃO VIOLE)

1. **Padrão de Cabeçalho e Idempotência em `scripts/XX_*.sh`**:
   - Todo módulo numerado **DEVE** iniciar com `#!/bin/bash`, `set -e`, carregar `source "$SCRIPT_DIR/00_comum.sh"`, definir um `FLAG_NAME` único, verificar `if check_flag "$FLAG_NAME" "$@"; then ... exit 0; fi` no início e chamar `set_flag "$FLAG_NAME"` no final.
   - Nota: Ao usar `source "$SCRIPT_DIR/00_comum.sh"`, lembre-se de que `00_comum.sh` redefine `SCRIPT_DIR` para a pasta `scripts/` e define `BASE_DIR` como a raiz do repositório.
2. **Sincronização do Orquestrador (`setup_popos_v2.sh`)**:
   - Se um novo módulo `XX_nome.sh` for adicionado, renomeado ou reordenado em `scripts/`, o array `MODULES=(...)` em `setup_popos_v2.sh` **DEVE** ser atualizado imediatamente (há um teste automatizado que falha caso divergirem).
3. **Peculiaridades de Software já Resolvidas (Não Reverta)**:
   - **Kando (`13_kando_restore.sh` & PR #1535)**: No COSMIC Wayland (com `kando-cosmic-helper` e `wp_pointer_warp_v1`), o menu **NÃO** deve usar modo centralizado fixo. Mantenha sempre `.menus[0].centered = false | .menus[0].useFixedPosition = false` para que o menu abra sob o cursor sem puxar o mouse para o centro da tela ultrawide.
   - **Cedilha no Electron/Chromium (`02_teclado_cedilha_numlock.sh` & `patch_cedilla_electron.py`)**: Sob Wayland nativo (`--ozone-platform=wayland`), o Chromium ignora `GTK_IM_MODULE=cedilla`. O patch binário em `ui::CharacterComposer` converte `' + c -> ç`, `' + C -> Ç`, `"" -> "` e `'' -> '` preservando cópia `.orig`.
   - **Wacom Intuos Pro S (`12_wacom_tablet.sh`)**: Usa exclusivamente o módulo nativo do kernel `wacom.ko` + configuração RON do COSMIC (Modo Canhoto 180°) + `wacom-expresskeys-daemon.py`. Nunca reinstale o OpenTabletDriver (conflita com Bluetooth/touch).

---

## 🔄 4. Ciclo Obrigatório de Toda Mudança (Checklist do Agente)

Antes de concluir qualquer resposta onde houve alteração de código ou configuração, o agente **DEVE obrigatoriamente** seguir este protocolo:

1. **Executar a Suíte de Testes Automatizados (Obrigatório)**:
   - Sempre rode `./setup_popos_v2.sh --test` (ou `python3 tests/run_all.py`).
   - Se criar um novo script, daemon ou regra de configuração importante, **adicione um teste correspondente** em `tests/unit/` ou `tests/integration/`.
   - **Nenhuma alteração deve ser entregue com testes falhando.**
2. **Validar Sintaxe e Permissões**:
   - Todo script `.sh` ou `.py` novo em `scripts/`, `scripts/daemons/` ou `util/` deve receber `chmod +x`.
3. **Manter a Documentação Sincronizada**:
   - 📖 **`README.md`**: Atualize a árvore de diretórios e a seção de destaques sempre que criar novos módulos, daemons ou flags.
   - 📋 **`Docs/`**: Quando investigar ou solucionar um bug complexo do COSMIC/Wayland/Hardware, documente a causa-raiz e a solução em `Docs/`.

---

## 🧪 5. Comandos Chave de Referência Rápida

```bash
# 1. Rodar a suíte rápida de testes automatizados (Unitários + Integração - ~0.4s)
./setup_popos_v2.sh --test
# ou diretamente:
python3 tests/run_all.py

# 2. Listar todos os módulos de provisionamento disponíveis
./setup_popos_v2.sh --list

# 3. Executar um módulo específico forçando reexecução (ignorando checkpoint)
sudo ./scripts/13_kando_restore.sh --force

# 4. Reparar locks e caches Wayland/GPU das IDEs (Antigravity & VS Code)
./setup_popos_v2.sh --repair-ides

# 5. Executar teste end-to-end completo em container Docker isolado (com mocks)
./test_in_docker.sh
```

