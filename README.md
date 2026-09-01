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
    *   Layout configurado para `us+intl` (US Internacional tradicional com dead keys idêntico ao Windows).
    *   **Fix Oficial e Robusto do Cedilha & Aspas do Windows:** Configuração completa com `~/.XCompose`, correção da tabela de Compose do sistema (`/usr/share/X11/locale/en_US.UTF-8/Compose`), exportação de `XCOMPOSEFILE` e remoção de módulos legados (`GTK_IM_MODULE`/`QT_IM_MODULE`). Garante `' + c = ç` nativo, `'` duas vezes soltando `''` e `"` duas vezes soltando `""` (sem o trema `¨`).
    *   **NumLock Permanente:** Ativação automática do teclado numérico por padrão em toda nova sessão (`numlock-state` e `remember-numlock-state`).
*   **Janelas (Estilo Windows):** Ativa botões de Minimizar, Maximizar e Fechar na barra de título e minimização com clique do botão do meio.
*   **Mouse (Logitech G502 X):**
    *   Desativa a aceleração dinâmica de ponteiro (perfil plano linear `flat` 1:1).
    *   Grava macros físicas permanentes na memória EEPROM do hardware (`--commit`):
        *   **Botão 3:** Colar (<kbd>Ctrl</kbd>+<kbd>V</kbd>)
        *   **Botão 4:** Gatilho do Kando (<kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>F10</kbd>)
        *   **Botão 5:** Copiar (<kbd>Ctrl</kbd>+<kbd>C</kbd>)
        *   **Botões 6 e 7:** Rolagem horizontal (*Tilt Wheel* esquerda/direita).

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
*   **Manutenção de SSDs & Limpeza:** Ativação do TRIM semanal (`fstrim.timer`) para preservação dos NVMes, além de limpeza profunda do sistema com `apt autoremove/clean` e remoção de flatpaks órfãos.

### 6. Sincronização de Múltiplas Nuvens (Rclone VFS)
*   **Autenticação Automatizada & Fallback:** Leitura inteligente de variáveis do `.env`. Possui sistema de fallbacks com cópia automática de `rclone.conf` local ou abertura graciosa do assistente interativo `rclone config` se faltar algum remote.
*   **Serviços em Background (Systemd User):** Configuração com cache VFS sob demanda (`--vfs-cache-mode full`, retenção de 720h e limite de 50GB):
    *   `gdrive_pessoal` -> `~/GoogleDrive_Pessoal`
    *   `onedrive_pessoal` -> `~/OneDrive_Pessoal`
    *   `mega_pessoal` -> `~/MEGA_Pessoal`
*   **Validação de Montagem:** Função `verificar_gdrive_montado` que checa pontos FUSE e conteúdo antes de disparar etapas dependentes de backup.

### 7. Softwares de Workflow, Produtividade & Mídia
*   **VS Code:** Repositório oficial APT da Microsoft e instalação do pacote nativo `code`.
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
*   **Miniaplicativo de Controle de Mídia (COSMIC):** Download e compilação do `cosmic-applet-music-player` (com exibição da capa do álbum/fotinha, título/artista, botões MPRIS e controle por scroll), posicionado no **canto inferior esquerdo da Dock**.
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
│   ├── 10_cosmic_music_applet.sh       # Compilação e instalação do miniaplicativo de mídia
│   ├── 11_mouse_gaming.sh              # Logitech G502 X (DPIs, 1000Hz, macros on-board)
│   ├── 12_wacom_tablet.sh              # Suporte, drivers e pareamento da Wacom Intuos Pro
│   ├── 13_kando_restore.sh             # Sincronização de configurações do Kando
│   ├── 14_cosmic_restore.sh            # Restauração de temas COSMIC, App Library e Dock
│   ├── 15_ide_config_restore.sh        # Restauração de settings, atalhos e snippets das IDEs
│   ├── 16_zsh_p10k_setup.sh            # Zsh, Powerlevel10k, fontes MesloLGS NF e Ctrl+V
│   ├── 17_jogos_performance.sh         # Steam, Gamemode, MangoHud, Heroic e perfil Performance
│   ├── 18_flatpak_permissions.sh       # Overrides de discos e bandeja Wayland (CopyQ)
│   ├── 19_manutencao_ssds.sh           # Ativação do fstrim.timer para saúde dos SSDs
│   ├── 20_autostart_config.sh          # Entradas de autostart (CopyQ, Kando, Espanso, NumLock)
│   └── 21_limpeza_otimizacao.sh        # Limpeza de caches e runtimes não utilizados
├── setup_popos.sh                      # Script monolítico legado (preservado para segurança)
└── scripts_avulsos/                    # Scripts avulsos legados (preservados para segurança)
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
| `scripts/05_rclone_storage.sh` | Módulo de serviços systemd do Rclone para montagem FUSE das nuvens (GDrive, OneDrive, MEGA) e discos no COSMIC Files. |
| `scripts/06_softwares_workflow.sh` | Módulo de instalação do VS Code, Flatpaks principais, Jellyfin Server, Espanso e Kando com wrappers. |
| `scripts/07_powershell7.sh` | Módulo de instalação oficial do Microsoft PowerShell 7 (`pwsh`), repositórios Microsoft e perfil do usuário. |
| `scripts/08_antigravity_ide.sh` | Módulo de instalação completa e isolada do Google Antigravity IDE (`/opt/antigravity`, AppArmor e `.desktop`). |
| `scripts/09_onlyoffice_padrao.sh` | Módulo de associação do OnlyOffice como manipulador padrão de documentos office. |
| `scripts/10_cosmic_music_applet.sh` | Módulo de compilação e instalação do miniaplicativo de controle de mídia para a Dock. |
| `scripts/11_mouse_gaming.sh` | Módulo de gravação de polling rate 1000Hz, DPIs e macros na memória do mouse Logitech G502 X. |
| `scripts/12_wacom_tablet.sh` | Módulo de suporte, regras udev, drivers libwacom, OpenTabletDriver GUI e pareamento da Wacom Intuos Pro. |
| `scripts/13_kando_restore.sh` | Módulo de restauração de menus e atalho `Ctrl+Shift+F10` do Kando a partir do Google Drive. |
| `scripts/14_cosmic_restore.sh` | Módulo de restauração de temas, auto-tiling desligado, abas da App Library (*Jogos, Dev, Escritório, Mídia, Utilitários, Sistema*) e Dock. |
| `scripts/15_ide_config_restore.sh` | Módulo de sincronização de settings, atalhos (`Ctrl+V`, colar com botão direito) e snippets para VS Code e Antigravity. |
| `scripts/16_zsh_p10k_setup.sh` | Módulo de instalação e configuração do Zsh, Powerlevel10k, fontes MesloLGS NF, shell padrão e `Ctrl+V`. |
| `scripts/17_jogos_performance.sh` | Módulo de Steam, Gamemode, MangoHud, Heroic, `/mnt/nvme_01/Jogos` e perfil de Performance Máxima. |
| `scripts/18_flatpak_permissions.sh` | Módulo de overrides de filesystem (`/mnt/storage_*`) e liberação de bandeja (`StatusNotifierWatcher`). |
| `scripts/19_manutencao_ssds.sh` | Módulo de ativação do TRIM semanal (`fstrim.timer`) para os SSDs. |
| `scripts/20_autostart_config.sh` | Módulo de provisionamento de inicialização automática no login (CopyQ, Kando, Espanso, NumLock). |
| `scripts/21_limpeza_otimizacao.sh` | Módulo de limpeza de pacotes, autoremove e remoção de runtimes Flatpak não utilizados. |

---

## ⚙️ Guia de Execução

### 🚀 Modo Automatizado Completo (V2):
Executa todos os 21 módulos em sequência, pulando automaticamente o que já estiver concluído:
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

