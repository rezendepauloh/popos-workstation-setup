# 🐞 Issue: Integração Espanso Dynamic Forms (EDF), Kando e Espanso no COSMIC Wayland

> **Status:** Analisado / Solução Híbrida Implementada  
> **Componentes Afetados:** `espanso-dynamic-forms` (v1.6.13), `kando` (v1.4.x), `espanso` (v2.4.1), `COSMIC Desktop` (`cosmic-comp` / Wayland nativo)

---

## 📌 Contexto & Problema Relatado
No ambiente Windows, o fluxo de automação do workflow é estruturado em:
1. O usuário aciona o **Kando Pie Menu** via atalho de mouse/teclado.
2. Seleciona uma ação do **Espanso** (ex: *Transporte de Material*, *Pedir Transporte*, *Atendimento STI*).
3. O Kando executa um script PowerShell (`chamar_*.ps1`) ou chama o executável do **Espanso Dynamic Forms (EDF)** (`EDF.exe --form-config <path.yml>`).
4. O EDF exibe um formulário visual moderno baseado em Vue/Vuetify (Electron).
5. Ao confirmar ("Preencher"), o EDF emite os campos preenchidos formatados para o stdout ou clipboard e o Espanso / script injeta na aplicação ativa.

No **Pop!_OS 24.04 (COSMIC Desktop / Wayland)**, identificamos dois comportamentos anômalos ao tentar replicar diretamente o binário Electron do EDF:
1. **Diferenças de Interface e Comportamento do EDF no Linux**: O binário Linux (`Espanso-Dynamic-Forms-Linux.deb` v1.6.13) roda sobre Electron 30 empacotado para X11/Wayland. Sob Wayland nativo no COSMIC, aplicações Electron de formulário modal de curta duração sofrem com falta de foco automático e com a dependência estrita do binário do Espanso estar no PATH do subprocesso de inicialização do Node (`Hi() -> espanso path`), gerando janelas com layout diferente do Windows ou travamentos em segundo plano caso executadas sem variáveis de ambiente gráficas (`WAYLAND_DISPLAY=wayland-1` / `DISPLAY=:1`).
2. **Kando chamando terminais vazios**: Originalmente, as entradas do Kando estavam mapeadas para comandos do Windows (`pwsh.exe` abrindo um terminal de console). No Linux, ao invocar terminais vazios sem passar o interpretador e parâmetros corretos, o terminal abria e fechava imediatamente sem injetar o texto.

---

## 🔍 Causa-Raiz Técnica

### 1. Electron & Wayland Socket Mismatch
No Pop!_OS 24.04 COSMIC, o socket do Wayland é instanciado em `/run/user/1000/wayland-1` (e não `wayland-0`). Quando processos são disparados a partir de daemons ou do Kando (que roda sob XWayland `DISPLAY=:1`), variáveis de ambiente como `WAYLAND_DISPLAY` podem não ser herdadas adequadamente pelo subprocesso do EDF se não forem explicitadas.

### 2. Tipos de Campos em Formulários YAML (`type: array`)
Vários formulários da STI (como `transporte_material.yml`, `transporte_urbano.yml` e `diaria_viagem.yml`) definem listas de itens (`type: array`), que no Windows o EDF renderiza como campos dinâmicos com botão "+" para adicionar múltiplos patrimônios ou passageiros.
Um simples leitor de texto de uma linha não atendia a essa estrutura, necessitando de suporte nativo a múltiplos itens e quebras de linha (`\n`).

---

## 🛠️ Solução Implementada

Para garantir **100% de confiabilidade, suporte offline e portabilidade entre Windows e Linux**, implementamos uma solução em 3 camadas:

### 1. Form Runner Nativo Multiplataforma (`form_runner.py`)
No repositório [`espanso-automacoes-sti`](espanso-automacoes-sti):
- Criamos o módulo `scripts/lib/form_runner.py` em Python (Tkinter com tema escuro Catppuccin Mocha / Zenity fallback).
- Suporta campos de texto comum, listas de opções suspensas (`combobox`), campos de data/hora e **áreas de texto multilinhas para arrays** (como itens patrimoniais do DMP e passageiros).
- Em `scripts/lib/utils.py`, a função `run_edf_form()` detecta o ambiente:
  - No **Windows**: usa `C:\Program Files\Espanso Dynamic Forms\EDF.exe` com a interface original.
  - No **Linux**: usa `form_runner.py` nativo (rápido, abre em menos de 50ms, sem overhead do Electron).

### 2. Assistente Centralizado do Kando (`chamar_espanso_acao`)
Criado em `~/.local/bin/chamar_espanso_acao` e gerenciado pelo script de provisionamento:
- Exporta as variáveis de display corretas (`DISPLAY=:1`, `WAYLAND_DISPLAY=wayland-1`, `XDG_RUNTIME_DIR`).
- Executa o script Python correspondente à ação selecionada no menu circular.
- Captura a saída pré-formatada em HTML / texto puro.
- Utiliza o **CopyQ** ou **wl-copy + kando-cosmic-helper** para enviar o conteúdo para o clipboard e simular a colagem (`Ctrl+V`) imediatamente no aplicativo onde o cursor estiver posicionado.
- Gera log em `/tmp/chamar_espanso_acao.log` para facilitar diagnóstico.

### 3. Provisionamento Automatizado Idempotente
As configurações foram integradas nos scripts do workstation setup:
- [`scripts/06_softwares_workflow.sh`](/scripts/06_softwares_workflow.sh): clona/atualiza o `espanso-automacoes-sti`, configura os módulos do Python e instala o binário do EDF v1.6.13 e o wrapper `chamar_espanso_acao`.
- [`scripts/13_kando_restore.sh`](/scripts/13_kando_restore.sh): higieniza os menus do Kando, ajusta as setas de espaço de trabalho do COSMIC para vertical (`0°` Up / `180°` Down) e liga cada botão do Espanso ao `chamar_espanso_acao`.

