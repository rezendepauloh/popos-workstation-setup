# 📝 Contexto e Diretrizes: Solução Definitiva do Cedilha (' + c = ç) no Teclado US-International no Pop!_OS (COSMIC Wayland)

## 📌 Diagnóstico do Problema
- **Ambiente:** Pop!_OS 24.04 LTS rodando o novo ambiente de desktop **COSMIC (Wayland nativo)**.
- **Teclado:** Redragon mecânico layout Americano / Estados Unidos Internacional (`us+intl` com dead keys / teclas mortas).
- **Sintoma:**
  - Todos os acentos normais (`ã`, `é`, `ô`, `ü`) funcionam perfeitamente.
  - No entanto, ao pressionar `'` seguido de `c`, é produzido o caractere **`ć`** (c com acento agudo - caractere polonês/eslavo) em vez do **`ç`** (c-cedilha).
  - O problema ocorre principalmente em aplicações baseadas no motor Chromium / Electron:
    - **Google Antigravity IDE** (`/opt/antigravity`, base Electron)
    - **VS Code** (base Electron)
    - **Google Chrome** e **Brave Browser** (base Chromium)
  - Aplicações nativas GTK ou terminais às vezes usam mapeamentos diferentes dos navegadores Chromium e aplicativos Electron rodando sob Wayland puro (`--ozone-platform=wayland`).

---

## 🔍 Análise Técnica: Por que o `ć` acontece no Chromium/Electron sob Wayland?
1. **Diferença entre XWayland e Wayland Puro:**
   - Sob **X11 / XWayland**, o Chromium/Electron lê o arquivo clássico `~/.XCompose` e respeita o `GTK_IM_MODULE=cedilla` ou `xim`.
   - Sob **Wayland nativo** (`--ozone-platform=wayland`), o Chromium/Electron utiliza o protocolo de entrada do Wayland (`text-input-v3` ou `wayland-ime`). Nesse modo, muitas vezes o Chromium bypassa o XCompose clássico se a composição do compositor COSMIC estiver configurada com locale genérico (`en_US.UTF-8`), onde o padrão gramatical em inglês para `<dead_acute> <c>` é estritamente `ć` (U+0107).
2. **As soluções clássicas apontadas pelo Gemini:**
   - **`~/.XCompose`**: Já está presente no sistema com `<dead_acute> <c> : "ç" ccedilla`.
   - **`/etc/environment`**: Já possui `GTK_IM_MODULE=cedilla`.
   - Porém, para Chromium/Electron, certas flags de Ozone e variáveis de ambiente como `GTK_IM_MODULE=xim` vs `cedilla`, ou a flag `--enable-wayland-ime` vs `--ozone-platform-hint=auto`, determinam se o motor consulta o Compose ou a tabela nativa do XKB.
3. **Mapeamento em editores (`keyboard.dispatch`):**
   - O VS Code e o Antigravity IDE têm uma opção interna: `"keyboard.dispatch": "keyCode"`. Quando ativada com o motor de teclado correto, ela pode alterar a forma como eventos de teclas mortas são processados.
4. **Atalho Universal Alternativo:**
   - <kbd>AltGr</kbd> (Alt direito) + <kbd>,</kbd> (vírgula) = `ç`
   - <kbd>Shift</kbd> + <kbd>AltGr</kbd> + <kbd>,</kbd> = `Ç`

---

## 🔬 Diagnóstico e Causa Raiz Descoberta
1. **O mecanismo interno `ui::CharacterComposer` do Chromium:**
   - Sob **Wayland nativo** (`--ozone-platform=wayland`), o Chromium/Electron (utilizado pelo Antigravity IDE, VS Code, Google Chrome e Brave) **ignora completamente** o `~/.XCompose`, `GTK_IM_MODULE=cedilla` e as tabelas do `libxkbcommon`.
   - Ele utiliza um compositor interno próprio herdado do ChromeOS (`ui::CharacterComposer`), que possui uma **tabela estática hardcoded** onde a sequência `<dead_acute> + c` resulta estritamente em **`ć`** (U+0107) e `<dead_acute> + C` em **`Ć`** (U+0106).
   - Esse comportamento é um bug aberto histórico do Chromium ([Issue 40272818](https://issues.chromium.org/issues/40272818)).
   - A flag `"keyboard.dispatch": "keyCode"` no `settings.json` gerencia comandos de atalho internos do VS Code, mas o texto inserido em inputs e editores continua passando pela tabela do `CharacterComposer`.

---

## ✅ Solução Definitiva Implementada
1. **Patch Cirúrgico por Padrão de Bytes (`patch_cedilla_electron.py`):**
   - Utilitário idempotente em Python que localiza a assinatura estática da tabela no binário executável e substitui:
     - `c (0x0063) -> ć (0x0107)` [`63 00 07 01`] $\to$ [`63 00 e7 00`] (`ç`, U+00E7)
     - `C (0x0043) -> Ć (0x0106)` [`43 00 06 01`] $\to$ [`43 00 c7 00`] (`Ç`, U+00C7)
   - Cria backup original imutável (`.orig`) antes de qualquer alteração.
   - Instalado globalmente como `/usr/local/bin/patch-cedilla-electron`.

2. **Persistência Contra Atualizações (`/etc/apt/apt.conf.d/99-patch-cedilla-electron`):**
   - Criação de um Post-Invoke Hook no APT para que, após qualquer atualização (`apt upgrade`, `apt install google-chrome-stable`, `code`, etc.), o patch seja automaticamente reaplicado.

3. **Wayland Nativo Puro Unificado (`--ozone-platform=wayland`):**
   - Com a tabela corrigida nos binários, todos os navegadores e editores rodam em Wayland nativo puro (`~/.config/*-flags.conf`), garantindo máxima fluidez, aceleração de hardware e nitidez sem necessidade de recorrer ao XWayland.

4. **Automação Integrada aos Scripts do Repositório:**
   - [`scripts/patch_cedilla_electron.py`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/scripts/patch_cedilla_electron.py): Utilitário de patch versionado.
   - [`scripts/02_teclado_cedilha_numlock.sh`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/scripts/02_teclado_cedilha_numlock.sh): Instala o utilitário, configura o Hook APT e aplica o patch em todos os navegadores e IDEs.
   - [`scripts/08_antigravity_ide.sh`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/scripts/08_antigravity_ide.sh): Aplica o patch imediatamente após descompactar o Antigravity IDE.
   - [`scripts/16_ide_config_restore.sh`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/scripts/16_ide_config_restore.sh): Revalida o patch e as flags Wayland durante o reparo/restauração das IDEs.

---

## 📂 Arquivos Chave do Repositório
- [`scripts/patch_cedilla_electron.py`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/scripts/patch_cedilla_electron.py)
- [`scripts/02_teclado_cedilha_numlock.sh`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/scripts/02_teclado_cedilha_numlock.sh)
- [`scripts/08_antigravity_ide.sh`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/scripts/08_antigravity_ide.sh)
- [`scripts/16_ide_config_restore.sh`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/scripts/16_ide_config_restore.sh)
- [`README.md`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/README.md)
- `~/.XCompose`
- `~/.config/antigravity-flags.conf`
- `~/.config/code-flags.conf`
- `~/.config/chrome-flags.conf`
- `~/.config/brave-flags.conf`
