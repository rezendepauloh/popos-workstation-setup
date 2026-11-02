# 🐞 Issue: Integração Espanso Dynamic Forms (EDF), Kando e Espanso no COSMIC Wayland

> **Status:** Resolvido / Concluído com Sucesso  
> **Solução Adotada:** Motor nativo de formulários dinâmicos em Python/GTK3 ([scripts/daemons/form_runner.py](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/scripts/daemons/form_runner.py)) com restauração de foco e injeção de atalho via `kando-cosmic-helper`  
> **Componentes Afetados:** `espanso-dynamic-forms` (v1.6.13), `kando` (v1.4.x), `espanso` (v2.4.1), `COSMIC Desktop` (`cosmic-comp` / Wayland nativo)

---

## 📌 Contexto & Problema Relatado
No ambiente Windows, o fluxo de automação do workflow é estruturado em:
1. O usuário aciona o **Kando Pie Menu** via atalho de mouse/teclado.
2. Seleciona uma ação do **Espanso** (ex: *Transporte de Material*, *Pedir Transporte*, *Atendimento STI*).
3. O Kando executa um script PowerShell (`chamar_*.ps1`) ou chama o executável do **Espanso Dynamic Forms (EDF)** (`EDF.exe --form-config <path.yml>`).
4. O EDF exibe um formulário visual moderno baseado em Vue/Vuetify (Electron).
5. Ao confirmar ("Preencher"), o EDF emite os campos preenchidos formatados para o stdout ou clipboard e o Espanso / script injeta na aplicação ativa.

No **Pop!_OS 24.04 (COSMIC Desktop / Wayland)**, identificamos os seguintes comportamentos anômalos ao tentar replicar diretamente o binário Electron do EDF:
1. **Diferenças de Interface e Comportamento do EDF no Linux**: O binário Linux (`Espanso-Dynamic-Forms-Linux.deb` v1.6.13) roda sobre Electron 30 empacotado para X11/Wayland. Sob Wayland nativo no COSMIC, aplicações Electron de formulário modal sofrem com falta de foco automático e dependência estrita do binário do Espanso no PATH do subprocesso de inicialização do Node (`Hi() -> espanso path`), gerando janelas com layout diferente do Windows ou travamentos em segundo plano caso executadas sem variáveis gráficas explícitas (`WAYLAND_DISPLAY=wayland-1` / `DISPLAY=:1`).
2. **Kando chamando terminais vazios**: Originalmente, as entradas do Kando estavam mapeadas para comandos do Windows (`pwsh.exe` abrindo console Win32). No Linux, ao invocar terminais vazios sem passar o interpretador e parâmetros corretos, o terminal abria e fechava imediatamente sem injetar texto.
3. **Keycodes X11 vs Scancodes Linux (`";y"`)**: O `kando-cosmic-helper keys` opera com keycodes X11 (offset +8). Enviar keycodes de kernel Linux (29 para Ctrl e 47 para V) resultava literalmente na digitação dos caracteres `;` e `y`. Os keycodes X11 corretos são `37` (Control_L) e `55` (v).
4. **Perda de Foco de Janela no Compositor**: Ao fechar a janela modal do formulário, o compositor Wayland (`cosmic-comp`) demorava a restaurar o foco para a aplicação anterior, fazendo o atalho `Ctrl+V` ser emitido no vácuo.

---

## 🛠️ Solução Definitiva Implementada

Substituímos o binário pesado do Electron por uma solução 100% nativa em Python/GTK3, perfeitamente integrada ao ecossistema do repositório:

### 1. Form Runner Nativo em Python + GTK3 (`scripts/daemons/form_runner.py`)
- **Tecnologia:** Desenvolvido em Python com `PyGObject` (`Gtk.3.0` / `Gdk.3.0`), 100% nativo Wayland.
- **Visual Moderno:** Folha de estilos CSS completa inspirada no tema **Catppuccin Mocha / Pop!_OS Dark** com bordas arredondadas (`8px`), destaque visual nos campos em foco e botões modernos.
- **Eliminação de Bugs de Menus Suspensos:** Os comboboxes nativos do GTK3 abrem perfeitamente colados no campo correto, eliminando o bug do Tkinter no XWayland em que menus voavam para o canto superior esquerdo `(0, 0)`.
- **Motor de Regras Dinâmicas (`SHOW/HIDE`):** Parser completo das seções `uischema` do JSON Forms. Campos dependentes (como os itens de material no chamado "Olá") permanecem ocultos e só são exibidos quando a condição é atendida, recalculando o layout em tempo real.
- **Persistência Segura:** O script foi incorporado em [`scripts/daemons/form_runner.py`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/scripts/daemons/form_runner.py) e versionado no repositório [`espanso-automacoes-sti`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/espanso-automacoes-sti).

### 2. Despachante Inteligente com Restauração de Foco (`~/.local/bin/chamar_espanso_acao`)
- **Captura da Janela Chamadora:** Antes de abrir o formulário, salva a janela ativa atual via `kando-cosmic-helper focused`.
- **Restauração de Foco Automática:** Ao clicar em "Preencher", foca novamente a janela de destino via `kando-cosmic-helper focus <app_id> <title>`.
- **Injeção de Teclado Precisa:** Dispara `kando-cosmic-helper keys 37:down:30 55:down:30 55:up:30 37:up:30` (Control_L + V), com fallback para o módulo de kernel virtual `evdev.UInput`.
- **Área de Transferência Híbrida:** Atualiza simultaneamente o **CopyQ** (com suporte a `text/plain` e `text/html`) e o **Wayland clipboard (`wl-copy`)**.

---

## ✅ Conclusão e Testes
O fluxo completo `Kando -> Pie Menu -> Formulário GTK3 -> Preenchimento -> Injeção de Foco -> Ctrl+V` foi validado em tempo real no Pop!_OS 24.04 COSMIC Wayland, funcionando de maneira rápida, estável e com estética perfeitamente integrada ao sistema.
