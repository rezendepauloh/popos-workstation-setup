# 🔢 Solução Definitiva: Alt Codes (Windows Numpad Codes) sob Wayland (COSMIC Desktop)

## 📌 1. Visão Geral e Contexto
No ecossistema Windows, a memória muscular de digitação depende intensamente do uso do **Alt Code** com o teclado numérico físico (Numpad): mantendo a tecla <kbd>Alt</kbd> (Esquerdo) pressionada enquanto se digita uma sequência numérica no teclado numérico e soltando o <kbd>Alt</kbd> para que o símbolo surja na tela.

No Linux/Wayland (especialmente no compositor COSMIC Desktop do Pop!_OS 24.04), esse mecanismo não existe nativamente:
1. O Linux tradicionalmente adota o atalho <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>U</kbd> seguido do código hexadecimal e <kbd>Enter</kbd>, o que é moroso e não reproduz a experiência física.
2. Em aplicações como Chromium, VS Code, Google Antigravity IDE, OnlyOffice e navegadores sob Wayland puro, interceptações puras de XCompose ou xkb não resolvem eventos de liberação de modificador (*Alt keyup*).

---

## 🛠️ 2. Arquitetura da Solução: `alt-numpad-daemon.py`

A solução implementada adota o modelo de mais baixo nível e máxima confiabilidade sob o Linux: **Kernel Event Device (`evdev`) + Dispositivo Virtual (`uinput`)**.

### Fluxo de Execução:
```text
[ Teclado Físico (CX 2.4G / Redragon Horus Pro) ]
                     │
                     ▼ (evdev grab)
          [ alt-numpad-daemon.py ]
                     │
       ┌─────────────┴─────────────┐
       ▼                           ▼
[ Alt pressionado? ]         [ Tecla Comum? ]
       │                           │
  Sim  │                           │
       ├─► Digita Numpad (KP0..9)  └─► Repasse 1:1 imediato
       │   - Suprime dígito na tela    para o UInput virtual
       │   - Acumula no buffer
       │
       └─► Solta Alt (KEY_UP)
           - Decodifica o código (CP850 / CP1252 / Unicode)
           - Emite atômico via UInput (Ctrl+Shift+U + hex + Enter)
                     │
                     ▼
[ Qualquer Aplicação: Google Antigravity, VS Code, Terminal, Navegadores ]
```

### Características Técnicas:
1. **Pass-through Transparente de Atalhos do Sistema:**
   - Se o usuário pressionar <kbd>Alt</kbd> e depois qualquer tecla diferente do numpad (como <kbd>Tab</kbd>, <kbd>F4</kbd>, <kbd>Enter</kbd> ou letras), o daemon detecta imediatamente que se trata de um atalho do sistema/aplicação, cancela a captura do numpad e repassa o <kbd>Alt</kbd> e as demais teclas sem nenhum delay percebido.
2. **Compatibilidade Ampla de Códigos (OEM e ANSI):**
   - **Com zero à esquerda (Windows ANSI / CP1252):**
     - <kbd>Alt</kbd> + `0167` ➔ **`§`** (Parágrafo / Seção)
     - <kbd>Alt</kbd> + `0176` ➔ **`°`** (Símbolo de Grau)
     - <kbd>Alt</kbd> + `0186` ➔ **`º`** (Ordinal Masculino)
     - <kbd>Alt</kbd> + `0170` ➔ **`ª`** (Ordinal Feminino)
     - <kbd>Alt</kbd> + `0153` ➔ **`™`** (Trademark)
     - <kbd>Alt</kbd> + `0169` ➔ **`©`** (Copyright)
     - <kbd>Alt</kbd> + `0174` ➔ **`®`** (Marca Registrada)
     - <kbd>Alt</kbd> + `0151` ➔ **`—`** (Travessão / Em-dash)
     - <kbd>Alt</kbd> + `0150` ➔ **`–`** (En-dash)
     - <kbd>Alt</kbd> + `0149` ➔ **`•`** (Bullet Point)
   - **Setas Clássicas e Símbolos de Interface (CP437):**
     - <kbd>Alt</kbd> + `24` ➔ **`↑`** *(Seta para cima)*
     - <kbd>Alt</kbd> + `25` ➔ **`↓`** *(Seta para baixo)*
     - <kbd>Alt</kbd> + `26` ➔ **`→`** *(Seta para a direita)*
     - <kbd>Alt</kbd> + `27` ➔ **`←`** *(Seta para a esquerda)*
     - <kbd>Alt</kbd> + `16` ➔ **`►`** *(Triângulo direita)*
     - <kbd>Alt</kbd> + `17` ➔ **`◄`** *(Triângulo esquerda)*
     - <kbd>Alt</kbd> + `30` ➔ **`▲`** *(Triângulo cima)*
     - <kbd>Alt</kbd> + `31` ➔ **`▼`** *(Triângulo baixo)*
   - **Setas Triangulares Modernas (`⭡ ⭢ ⭣ ⭠` - U+2B60..2B63):**
     - Atalhos mnemônicos diretos pelo teclado numérico (<kbd>8</kbd>=Cima, <kbd>6</kbd>=Direita, <kbd>2</kbd>=Baixo, <kbd>4</kbd>=Esquerda):
       - <kbd>Alt</kbd> + `88` ➔ **`⭡`**
       - <kbd>Alt</kbd> + `66` ➔ **`⭢`**
       - <kbd>Alt</kbd> + `22` ➔ **`⭣`**
       - <kbd>Alt</kbd> + `44` ➔ **`⭠`**
     - Também acessíveis pelos seus códigos decimais Unicode completos (`11105`, `11106`, `11107`, `11104`).
   - **Sem zero à esquerda (Windows OEM / CP850):**
     - <kbd>Alt</kbd> + `167` ➔ **`º`**
     - <kbd>Alt</kbd> + `166` ➔ **`ª`**
     - Qualquer código numérico padrão OEM / ASCII estendido.

---

## 📂 3. Arquivos e Estrutura do Sistema

| Arquivo | Finalidade |
| :--- | :--- |
| `scripts/alt-numpad-daemon.py` | Código-fonte do daemon de captura e injeção via evdev/uinput. |
| `~/.local/bin/alt-numpad-daemon.py` | Binário executável do usuário em produção. |
| `config/systemd/user/alt-numpad.service` | Modelo da unidade systemd de usuário. |
| `~/.config/systemd/user/alt-numpad.service` | Serviço systemd ativo no escopo do usuário. |
| `scripts/02_teclado_cedilha_numlock.sh` | Script de provisionamento idempotente que instala e ativa o serviço. |

---

## 🚀 4. Comandos de Gerenciamento & Verificação

### Verificar status do serviço:
```bash
systemctl --user status alt-numpad.service
```

### Visualizar logs em tempo real:
```bash
journalctl --user -u alt-numpad.service -f
```

### Reiniciar o serviço:
```bash
systemctl --user restart alt-numpad.service
```
