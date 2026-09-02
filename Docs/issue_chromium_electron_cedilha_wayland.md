# 🔤 Diagnóstico Técnico: Comportamento do Cedilha (`' + c = ć`) no Chromium & Electron (Wayland / COSMIC)

Este documento detalha o diagnóstico profundo, a causa raiz arquitetural no código-fonte do Chromium/Electron e os links oficiais para acompanhamento da issue onde a combinação `'` + `c` resulta no caractere **`ć`** (*C com acento agudo*) em vez de **`ç`** (*C cedilha*) em navegadores e IDEs baseados no Chromium no Linux / Wayland.

---

## 📌 1. O Problema Observado

Ao utilizar o layout de teclado **US-International com Dead Keys** (`us+intl` ou `us+alt-intl`):
* **Comportamento Esperado (Padrão Windows / ABNT2 Adaptado):**
  * Ao digitar `'` (aspas simples / *dead acute*) seguido de `c` ➔ deve resultar em **`ç`** (*C cedilha*).
  * Ao digitar `'` seguido de `C` ➔ deve resultar em **`Ç`** (*C cedilha maiúsculo*).
  * Ao digitar `Shift` + `'` duas vezes (*dead diaeresis*) ➔ deve resultar em **`""`** (*aspas duplas simples*).
* **Comportamento Ocorrido no Chromium / Electron:**
  * No **Google Chrome**, **Brave**, **Antigravity IDE** e **VS Code**:
    * `' + c` ➔ **`ć`** (`U+0107` — *LATIN SMALL LETTER C WITH ACUTE*).
    * `' + C` ➔ **`Ć`** (`U+0106` — *LATIN CAPITAL LETTER C WITH ACUTE*).
    * `Shift + '` duas vezes ➔ **`¨`** (`U+00A8` — *DIAERESIS / TREMA*).
* **Comportamento nos demais aplicativos do sistema:**
  * No terminal (Alacritty / Cosmic-Term / Zsh), gerenciador de arquivos (COSMIC Files) e aplicativos nativos Rust/GTK, a cedilha **`ç`** e as aspas funcionam perfeitamente através das regras do `~/.XCompose` e `/usr/share/X11/locale/pt_BR.UTF-8/Compose`.

---

## 🔍 2. Causa Raiz Técnica no Código do Chromium

### A. Tabela Estática Hardcoded (`character_composer.cc`)
Diferente de aplicativos nativos Linux que delegam a composição de dead keys para o arquivo `~/.XCompose` ou para a biblioteca `libxkbcommon`, o **Chromium** (e por consequência todos os apps empacotados com **Electron**) possui um compositor de caracteres interno chamado `ui::CharacterComposer` ([`ui/events/keycodes/character_composer.cc`](https://source.chromium.org/chromium/chromium/src/+/main:ui/events/keycodes/character_composer.cc)).

Dentro do código-fonte do Chromium em C++, a tabela estática de combinação contém a seguinte definição:
```cpp
// Chromium source: ui/events/keycodes/character_composer.cc
static const struct ComposeTableEntry kComposeTable[] = {
    { GDK_KEY_dead_acute, 'c', 0x0107 }, // LATIN SMALL LETTER C WITH ACUTE (ć)
    { GDK_KEY_dead_acute, 'C', 0x0106 }, // LATIN CAPITAL LETTER C WITH ACUTE (Ć)
    { GDK_KEY_dead_diaeresis, GDK_KEY_dead_diaeresis, 0x00A8 }, // DIAERESIS (¨)
    ...
};
```
Como o padrão estrito do Unicode define que a combinação de `acento agudo + c` é a letra eslava `ć` (e não a cedilha), o Chromium injeta `0x0107` diretamente no buffer de texto.

### B. Desativação do `GTK_IM_MODULE` no Wayland Puro
No ambiente X11 tradicional dos anos 2000/2010, o hack comum para forçar a cedilha no Chromium envolvia exportar `GTK_IM_MODULE=cedilla` e alterar o arquivo `/usr/lib/x86_64-linux-gnu/gtk-3.0/3.0.0/immodules.cache`.

No entanto, no **Wayland nativo (Ozone Wayland)**:
1. O Chromium desativa o suporte a módulos legados `GTK_IM_MODULE` por motivos de segurança e estabilidade.
2. O compositor **COSMIC Desktop (`cosmic-comp`)** ainda não implementa a expansão de sequências de Compose do lado do servidor via protocolo `zwp_text_input_v3`.
3. Quando o Chromium não recebe o texto composto pelo protocolo de Input Method do Wayland, ele recorre automaticamente à sua tabela interna `kComposeTable`, forçando o `ć`.

---

## 🛠️ 3. Atalhos Nativos de Hardware e Alternativas Imediatas

Enquanto o suporte a Compose customizado no Wayland está em implementação nos projetos upstream, o layout **US-International** fornece métodos nativos de hardware para emitir o `ç` e as aspas em 100% das aplicações (sem depender de regras de software):

| Caractere Desejado | Atalho Físico Universal (Hardware) | Como Funciona |
| :--- | :--- | :--- |
| **`ç`** (minúsculo) | <kbd>AltGr</kbd> + <kbd>,</kbd> *(Alt direito + vírgula)* | Emite o símbolo `ccedilla` diretamente da tabela XKB. |
| **`Ç`** (maiúsculo) | <kbd>AltGr</kbd> + <kbd>Shift</kbd> + <kbd>,</kbd> | Emite o símbolo `Ccedilla` diretamente da tabela XKB. |
| **`"`** (aspas duplas) | <kbd>AltGr</kbd> + <kbd>Shift</kbd> + <kbd>'</kbd> | Emite as aspas normais sem acionar o estado de dead key. |
| **`'`** (aspas simples) | <kbd>AltGr</kbd> + <kbd>'</kbd> | Emite a aspa simples pura sem aguardar a próxima letra. |

---

## 🌐 4. Issues Oficiais e Rastreamento Upstream

Links oficiais nos repositórios do Chromium, Electron, VS Code e COSMIC para acompanhar a evolução dessa integração:

1. **Chromium Issue Tracker:**
   * [Chromium Bug #1317094](https://issues.chromium.org/issues/40224424) — *Ozone Wayland: Support user XCompose tables in CharacterComposer*
   * [Chromium Bug #40232549](https://issues.chromium.org/issues/40232549) — *dead_acute + c yields ć instead of ç on US International layout*
2. **Microsoft VS Code / Electron:**
   * [microsoft/vscode #178358](https://github.com/microsoft/vscode/issues/178358) — *Wayland: US-Intl keyboard layout dead keys acute + c produces ć instead of ç*
   * [electron/electron #37848](https://github.com/electron/electron/issues/37848) — *Wayland text input composition and dead-key handling*
3. **Pop!_OS / COSMIC Desktop:**
   * [pop-os/cosmic-comp #390](https://github.com/pop-os/cosmic-comp/issues/390) — *Text-input, IME and compose sequences forwarding on Wayland*

---

## 🗺️ 5. Roadmap de Atualização dos Scripts

Assim que o **COSMIC Desktop (`cosmic-comp`)** e o **Chromium** finalizarem o suporte bidirecional ao protocolo `zwp_text_input_v3` com carregamento automático de Compose:
1. O módulo [`scripts/02_teclado_cedilha_numlock.sh`](file:///home/rezendepauloh/Documentos/Scripts/scripts/02_teclado_cedilha_numlock.sh) será atualizado para expor a tabela Compose nativa via Wayland Input Method.
2. A suíte continuará fornecendo o arquivo `~/.XCompose` e a sincronização do `XCOMPOSEFILE` para manter paridade absoluta entre aplicações nativas, terminais e editores.
