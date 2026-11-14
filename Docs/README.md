# 📚 Documentação Técnica — Pop!_OS 24.04 LTS (COSMIC) Workstation Setup

> Bem-vindo à central unificada de engenharia, arquitetura, diagnósticos e manuais práticos da workstation **Pop!_OS 24.04 LTS**.  
> Este repositório de documentação centraliza todas as decisões técnicas, soluções para particularidades do **COSMIC Desktop (`cosmic-comp` / Wayland nativo)**, integrações de hardware, workflows de produtividade e relatórios de issues upstream.

---

## 🗂️ Estrutura e Mapa de Navegação

```text
Docs/
├── README.md                                         # Este índice central unificado
│
├── 📖 guias/                                         # Manuais operacionais e tutoriais práticos
│   ├── onedrive_winapps_mpms_guia.md                 # OneDrive corporativo nativo (SMB/GVFS) & indicador oficial
│   ├── otimizacao_debloat_winapps_vm.md              # Debloat do Windows 11 KVM (dockurr/windows) & AutoLogon
│   ├── como-parear-sunshine-moonlight-samsung-tv.md  # Streaming de jogos ultrawide para Smart TV Samsung Tizen
│   ├── nautilus_gerenciador_arquivos_padrao.md       # Definição do Nautilus como gerenciador padrão no COSMIC
│   ├── tema_escuro_botoes_vlc.md                     # Tema escuro e correção de botões no VLC via Qt Style Sheets
│   ├── como-fazer-backup-android.md                  # Backup automatizado de celular Android via ADB de alta velocidade
│   ├── como-atualizar-containers-docker.md           # Atualização automatizada de containers Docker (Compose & Standalone)
│   └── gravacao_de_tela_cosmic_kooha.md              # Gravação de tela nativa Wayland via Kooha e atalhos Kando
│
├── 🚨 issues/                                        # Diagnósticos aprofundados, bugs upstream & soluções
│   ├── issue_chromium_electron_cedilha_wayland.md    # Cedilha ('+c = ç) e aspas no Electron Wayland via patch binário
│   ├── issue_alt_codes_numpad_wayland.md             # Emulação de Alt Codes do Windows no Numpad (evdev/uinput)
│   ├── issue_cosmic_numlock_boot.md                  # NumLock permanente no boot e sincronização de LED físico
│   ├── issue_opentabletdriver_wacom_bluetooth.md     # Driver de kernel wacom.ko, Bluetooth e modo canhoto 180°
│   ├── issue_espanso_wayland_tray_cosmic.md          # Tray StatusNotifierItem nativo para Espanso no painel COSMIC
│   ├── issue_edf_espanso_kando_cosmic.md             # Formulários gráficos interativos (GTK3) com injeção de foco
│   ├── issue_antigravity_dock_cosmic_launch.md       # AppArmor unprivileged userns & inicialização da IDE Antigravity
│   ├── issue_cosmic_files_fuse_freeze.md             # Prevenção de travamentos FUSE no Rclone e mitigação no cosmic-files
│   └── issue_cursor_blurry_gtk4_wayland.md           # Resolução de cursor borrado em apps GTK4 sob Wayland fracionário
│
├── 📋 relatorios/                                    # Linha do tempo, auditorias de segurança e checkpoints
│   ├── auditoria_seguranca_workstation.md            # Dossiê completo de auditoria de segurança (SAST & Hardening)
│   └── contexto_proxima_conversa.md                  # Resumo do estado operacional, decisões e histórico recente
│
└── 🗺️ planejamento/                                 # Roadmaps técnicos e melhorias futuras
    └── melhorias_futuras_workstation.md              # Backlog de otimizações e novas funcionalidades
```

---

## 🚀 Acessos Rápidos por Categoria

### 1. 💼 Trabalho Remoto, Office & Produtividade
* **OneDrive Corporativo sem abrir VM:** [Guia de Integração do OneDrive MPMS](guias/onedrive_winapps_mpms_guia.md)
* **Debloat e Otimização do Windows 11 KVM:** [Manual de Debloat e AutoLogon do WinApps](guias/otimizacao_debloat_winapps_vm.md)
* **Nautilus como Gerenciador Padrão:** [Configuração de Handlers XDG e COSMIC](guias/nautilus_gerenciador_arquivos_padrao.md)

### 2. ⌨️ Teclado, Wayland & Ergonomia
* **Cedilha e Aspas nos Apps Electron (Antigravity/VS Code/Chrome):** [Diagnóstico & Patch Binário de ui::CharacterComposer](issues/issue_chromium_electron_cedilha_wayland.md)
* **Alt Codes Clássicos do Windows (º, ª, §, °, ™):** [Daemon Evdev/Uinput alt-numpad](issues/issue_alt_codes_numpad_wayland.md)
* **NumLock Ativo no Boot & Sincronização do Teclado:** [Configuração XKB e Helper Evdev](issues/issue_cosmic_numlock_boot.md)

### 3. 🎨 Hardware & Periféricos Especializados
* **Mesa Digitalizadora Wacom Intuos Pro S (Canhoto 180°):** [Driver Nativo do Kernel vs OpenTabletDriver](issues/issue_opentabletdriver_wacom_bluetooth.md)
* **Streaming Ultrawide para TV Samsung (Moonlight Tizen):** [Pareamento e Resoluções Sunshine](guias/como-parear-sunshine-moonlight-samsung-tv.md)
* **Backup Completo de Celular Android:** [Script ADB de Extração e Restauração](guias/como-fazer-backup-android.md)

### 4. ⚡ Automações & Daemons no COSMIC Desktop
* **Ícone na Bandeja do Painel COSMIC para Espanso:** [Daemon StatusNotifierItem em Python](issues/issue_espanso_wayland_tray_cosmic.md)
* **Formulários Dinâmicos de Snippets (EDF):** [Runner GTK3 com Injeção de Foco](issues/issue_edf_espanso_kando_cosmic.md)
* **Aceleração e Sandboxing do Google Antigravity:** [Perfil AppArmor e Flags Wayland](issues/issue_antigravity_dock_cosmic_launch.md)
* **Gravação de Vídeo e Áudio em Alta Performance:** [Workflow Kooha & Kando](guias/gravacao_de_tela_cosmic_kooha.md)
* **Interface Escura do VLC Media Player:** [Customização QSS Completa](guias/tema_escuro_botoes_vlc.md)
* **Atualização de Containers Docker:** [Script Automatizado (Compose & Standalone)](guias/como-atualizar-containers-docker.md)

---

## 🛡️ Diretrizes de Engenharia e Princípios Canônicos
Antes de realizar qualquer intervenção em código, criação de novos scripts ou alteração de configurações do sistema operacional, consulte obrigatoriamente:
👉 **[`AGENTS.md`](../AGENTS.md)** (Idempotência, execução de contexto `root` vs `$REAL_USER`, preservação de configurações e suíte de testes obrigatória).

