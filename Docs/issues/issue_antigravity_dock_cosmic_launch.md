# 🐛 Issue: Inicialização do Antigravity IDE via Dock do COSMIC Desktop (`cosmic-app-list`)

> **Ambiente:** Pop!_OS 24.04 LTS (COSMIC Desktop Alpha/Beta)  
> **Compositor:** `cosmic-comp` (Wayland nativo)  
> **Componente Afetado:** COSMIC Dock (`cosmic-panel` / `com.system76.CosmicAppList`)  
> **Binário / Aplicação:** Google Antigravity IDE v1.107.0 (Electron v39.2.3)  
> **Data:** 06/11/2026  

---

## 📋 1. Descrição do Problema
O **Google Antigravity IDE** inicializa normalmente quando:
1. É executado via terminal CLI (`antigravity` ou `/opt/antigravity/antigravity-ide`).
2. É acionado via Busca do Sistema / Launcher (`Super` e digitando `antigravity`).
3. É aberto pela Biblioteca de Aplicativos (`CosmicAppLibrary`).

**Entretanto, ao clicar no ícone fixado na Dock do COSMIC (`cosmic-app-list`):**
- A janela principal não abre ou o clique é ignorado.
- Após múltiplos cliques consecutivos, o Electron exibe um diálogo de erro:
  > *"The window terminated unexpectedly (reason: 'launch-failed', code: '1002'). We are sorry for the inconvenience. You can reopen the window to continue where you left off."*

---

## 🔍 2. Diagnóstico Técnico e Achados

### 2.1. Arquitetura do App no Pop!_OS
- O binário original reside em `/opt/antigravity/antigravity-ide`.
- O pacote upstream instala em `/opt/antigravity/bin/antigravity-ide` um script CLI do Node (`ELECTRON_RUN_AS_NODE=1 "$ELECTRON" "$CLI" "$@"`). Quando chamado sem argumentos fora de uma sessão interativa, esse CLI não lança a interface gráfica padrão do VS Code/Antigravity, aguardando stdin (`To read from stdin, append '-'`).
- Foi criado um wrapper nativo em `~/.local/bin/antigravity` que executa `/opt/antigravity/antigravity-ide --ozone-platform=wayland "$@"`.
- Os arquivos `.desktop` foram mantidos em:
  - `~/.local/share/applications/antigravity.desktop`
  - `~/.local/share/applications/antigravity-ide.desktop`

### 2.2. A Dock do COSMIC (`cosmic-app-list`)
- O applet da Dock lê a lista de favoritos em `~/.config/cosmic/com.system76.CosmicAppList/v1/favorites`.
- O applet é compilado em Rust com base na crate `freedesktop-desktop-entry` e no protocolo de ativação Wayland (`xdg_activation` e `winit_wayland`).
- Diferente do Launcher (que faz busca textual direta no nome dos arquivos e campos `Exec`), o `cosmic-app-list` faz mapeamento estrito entre o `app_id` da janela Wayland (`StartupWMClass=antigravity-ide`), o token de ativação Wayland e o arquivo `.desktop`.
- Quando há mismatch de tokens, ausência de passagem de contexto de ativação ou tentativas de invocação paralela enquanto uma instância singleton do Electron já está em execução (como o agente em background), o Electron rejeita a criação da segunda janela e dispara o código de erro `launch-failed (code: 1002)`.

---

## 🛠️ 3. O que já foi implementado

1. **Dual Desktop Entries:**
   - Criação de `antigravity.desktop` e `antigravity-ide.desktop` com `StartupWMClass=antigravity-ide` e `StartupNotify=true`.
2. **Wrapper Wayland Dedicado:**
   - Script `~/.local/bin/antigravity` apontando diretamente para `/opt/antigravity/antigravity-ide` com `--ozone-platform=wayland`.
3. **Módulos Sincronizados:**
   - [`scripts/08_antigravity_ide.sh`](../../scripts/08_antigravity_ide.sh)
   - [`scripts/15_cosmic_menu_dock.sh`](../../scripts/15_cosmic_menu_dock.sh)
   - [`scripts/16_ide_config_restore.sh`](../../scripts/16_ide_config_restore.sh)
4. **Limpeza de Caches/Locks:**
   - Rotina `--repair-ides` pronta para remover `code.lock` e despejos de `Crashpad/pending`.

---

## 📌 4. Próximos Passos para Investigação Futura

1. **Protocolo `xdg_activation` no COSMIC:**
   - Inspecionar se o `cosmic-app-list` requer que o `.desktop` contenha parâmetros específicos de D-Bus ou chaves XDG (ex: `DBusActivatable=true` ou flags específicas de ativação Wayland).
2. **Remoção e Re-pin Manual na Dock:**
   - Testar desfixar o ícone da dock graficamente (clique com botão direito -> *Desafixar / Unpin*) e, com o Antigravity aberto via Launcher, clicar com o botão direito no ícone da janela ativa na Dock e selecionar *Fixar na Dock (Pin to Dock)*. Verificar qual string exata o COSMIC grava no arquivo `favorites`.
3. **Ambiente de Variáveis da Dock:**
   - O daemon `cosmic-app-list` é executado como processo filho do `cosmic-panel` ou escopo do systemd (`user@1000.service`), podendo não herdar variáveis como `PATH` atualizado ou tokens do DBus necessários para comunicação IPC do Electron.
4. **Single-Instance Lock do Electron / Antigravity:**
   - Investigar se passar a flag `--reuse-window` ou `--new-window` no `Exec` resolve a recusa do Electron em responder ao clique da dock quando já há um processo em execução.

