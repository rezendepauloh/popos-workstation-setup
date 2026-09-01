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
    *   Aplicação automática de overrides de permissão de sistema de arquivos para acesso aos discos `/mnt/storage_700`, `/mnt/storage_930` e `/mnt`.
    *   Associação do **OnlyOffice** como leitor padrão para documentos (`.docx`, `.xlsx`, `.pptx`).
*   **Jellyfin Media Server:** Instalação nativa via repositório oficial da equipe Jellyfin.
*   **Espanso (Wayland):** Download do pacote `.deb` oficial, bibliotecas de compatibilidade wxWidgets 3.0 para o Pop!_OS 24.04 (noble), instalação e registro de serviço nativo (`espanso service register && espanso start`).
*   **Kando:** Download dinâmico da última versão `.deb` diretamente da API do GitHub, com wrapper automático de compatibilidade para COSMIC Desktop / Wayland (forçando o backend XWayland).
*   **Autostart do Sistema:** Configuração de inicialização automática no login do usuário (`~/.config/autostart`) para **CopyQ**, **Kando**, **Espanso** e **NumLock**.

### 8. Restauração de Backups, Customizações e Dotfiles
*   **Kando:** Restaura configurações gerais (`config.json`) e menus (`menus.json` com o atalho `Control+Shift+F10` injetado via `jq`) a partir de `~/GoogleDrive_Pessoal/Organização/Kando/Casa`.
*   **COSMIC DE, Temas & Biblioteca de Apps:** Restaura configurações do painel COSMIC (`~/.config/cosmic`) e pontes visuais legadas (`gtk-3.0`, `gtk-4.0`, `qt5ct`, `qt6ct`) a partir de `~/GoogleDrive_Pessoal/Organização/Backup_COSMIC`, garantindo:
    *   Modo **auto-tiling desligado** por padrão.
    *   **NumLock ativado** por padrão no boot do compositor.
    *   Organização automática do **Menu / Biblioteca de Aplicativos** em pastas e categorias inteligentes (*Jogos, Desenvolvimento & Produtividade, Mídia & Criação, Utilitários, Sistema*) e favoritos fixados.
*   **IDEs (VS Code & Antigravity IDE):** Restaura de forma sincronizada os arquivos `settings.json`, `keybindings.json` (atalhos customizados) e pasta de `snippets/` a partir de `~/GoogleDrive_Pessoal/Organização/VSCode_Antigravity/` para os diretórios de configuração de ambos os editores (`~/.config/Code/User/` e `~/.config/Antigravity IDE/User/`).
*   **Terminal ZSH & Powerlevel10k:**
    *   Execução do instalador a partir de `~/GoogleDrive_Pessoal/Organização/Terminal ZSH Linux/install.sh`.
    *   Restauração dos dotfiles `~/.zshrc` e `~/.p10k.zsh`.
    *   Download automatizado das 4 variantes completas da fonte **MesloLGS NF** (*Regular, Bold, Italic, Bold Italic*) do repositório oficial do Powerlevel10k diretamente para `~/.local/share/fonts/`, com atualização de cache (`fc-cache -f`).
    *   Definição automática do **Zsh como shell padrão** do usuário (`chsh -s` / `usermod -s`).

### 9. Jogos & Performance
*   Instalação da **Steam** (pacote nativo APT), **Gamemode** (escalonador de prioridade de kernel) e **MangoHud**.
*   Instalação do **Heroic Games Launcher** (Flatpak) com override de permissão para o SSD de jogos (`/mnt/nvme_01`).
*   Criação prévia da pasta física `/mnt/nvme_01/Jogos` com posse e permissão `775`.
*   Configuração do perfil de **Performance Máxima** no Pop!_OS via `system76-power profile performance` (com fallback para `powerprofilesctl`).

---

## 📋 Estrutura de Logs e Idempotência

O script pode ser executado múltiplas vezes com segurança sem repetir etapas já concluídas. O controle é feito dentro da pasta local `./Logs/`:

| Arquivo | Finalidade | Formato / Exemplo |
| :--- | :--- | :--- |
| `Logs/.setup_estado.log` | Controle de idempotência (flags de etapas concluídas) | `IDE_CONFIG_RESTORE=1` |
| `Logs/.setup_execucao.log` | Histórico cronológico detalhado de execução e erros | `[2026-08-31 21:15:00] [INFO] Mensagem` |

---

## ⚙️ Guia de Execução

### No ambiente real (Pop!_OS 24.04):
1. Conceda permissão de execução ao script:
   ```bash
   chmod +x setup_popos.sh
   ```
2. Execute o script:
   ```bash
   ./setup_popos.sh
   ```

---

### 🧪 Testando em Ambiente Seguro (Docker no WSL / Ubuntu):

Para validar o script com segurança e sem alterar nada no seu sistema operacional hospedeiro, utilize a suíte de testes em container:

#### 🟢 Opção 1: Teste Automatizado com Relatório Completo (Recomendado)
O script `test_in_docker.sh` constrói a imagem Ubuntu 24.04, configura todos os mocks de hardware/desktop (gsettings, ratbagctl, rclone, flatpak, estrutura do Google Drive), executa o `setup_popos.sh` e valida todas as asserções:
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

