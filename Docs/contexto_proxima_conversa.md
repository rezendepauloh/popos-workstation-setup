# 📝 Contexto e Diretrizes: Alt Codes (Atalhos Alt + Teclado Numérico) no Pop!_OS (COSMIC Desktop / Wayland)

## 📌 1. Histórico e Conquistas Anteriores (Status: Concluído e Resolvido)
Na sessão anterior e nesta sessão, resolvemos de forma definitiva:
1. **Cedilha (`' + c = ç` e `' + C = Ç`)** no layout US-International com Dead Keys sob Wayland nativo.
2. **Aspas duplas (`Shift + '` 2x = `""`)** e **Aspas simples (`'` 2x = `''`)**, eliminando de vez o trema indesejado (`¨`) e o acento agudo isolado (`´`) nos navegadores e editores (Google Antigravity IDE, VS Code, Google Chrome e Brave) através do patch idempotente no compositor do Chromium (`scripts/patch_cedilla_electron.py`) e persistência automática via Hook do APT (`/etc/apt/apt.conf.d/99-patch-cedilla-electron`).
3. **Resolução de DNS Local Permanente (`192.168.0.8`) e Routing Domain (`~pk.local`)** configurado no Módulo 01 com failover para o `1.1.1.1` via `systemd-resolved` e `NetworkManager`.
4. **Alt Codes do Windows no Teclado Numérico (Status: Concluído e Ativo):** Implementado via daemon Python (`scripts/alt-numpad-daemon.py`) sob `evdev` + `uinput` gerenciado por `alt-numpad.service` (`systemctl --user`), funcionando de forma transparente em 100% das aplicações sob Wayland puro. Detalhes em [`Docs/issue_alt_codes_numpad_wayland.md`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/Docs/issue_alt_codes_numpad_wayland.md).
5. **Servidor Samba e Compartilhamento de Armazenamento (`/mnt/storage_700/samba`):** Configurado como o Módulo 25 (`scripts/25_samba_storage.sh`) com share `[Storage700]` espelhando a estrutura do UmbrelOS/Homelab, e o módulo de limpeza/hardening reordenado para a posição final 26 (`scripts/26_limpeza_otimizacao.sh`).
6. Documentação técnica atualizada em [`Docs/issue_chromium_electron_cedilha_wayland.md`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/Docs/issue_chromium_electron_cedilha_wayland.md), [`Docs/issue_alt_codes_numpad_wayland.md`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/Docs/issue_alt_codes_numpad_wayland.md) e no [`README.md`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/README.md).

---

## 🎯 2. Suporte a Alt Codes no Teclado Numérico (Estilo Windows) - [CONCLUÍDO]

### 📌 A Necessidade:
No Windows, os usuários de teclado mecânico ou teclados com numpad usam com frequência os clássicos **Alt Codes** mantendo pressionada a tecla <kbd>Alt</kbd> (ou <kbd>Alt Esquerdo</kbd>) enquanto digitam um código numérico no teclado numérico físico, gerando símbolos instantaneamente:
- <kbd>Alt</kbd> + <kbd>1</kbd><kbd>6</kbd><kbd>7</kbd> ➔ **`°`** *(Grau / Ordinal masculino)*
- <kbd>Alt</kbd> + <kbd>1</kbd><kbd>6</kbd><kbd>6</kbd> ➔ **`ª`** *(Ordinal feminino)*
- <kbd>Alt</kbd> + <kbd>0</kbd><kbd>1</kbd><kbd>6</kbd><kbd>7</kbd> ➔ **`§`** *(Parágrafo / Seção)*
- <kbd>Alt</kbd> + <kbd>0</kbd><kbd>1</kbd><kbd>7</kbd><kbd>6</kbd> ➔ **`°`**
- <kbd>Alt</kbd> + <kbd>0</kbd><kbd>1</kbd><kbd>5</kbd><kbd>3</kbd> ➔ **`™`**
- <kbd>Alt</kbd> + <kbd>0</kbd><kbd>1</kbd><kbd>6</kbd><kbd>9</kbd> ➔ **`©`**
- <kbd>Alt</kbd> + <kbd>0</kbd><kbd>1</kbd><kbd>7</kbd><kbd>4</kbd> ➔ **`®`**
- <kbd>Alt</kbd> + <kbd>0</kbd><kbd>1</kbd><kbd>5</kbd><kbd>1</kbd> ➔ **`—`** *(Travessão / Em-dash)*

---

## 🔍 3. Diagnóstico Técnico no Linux (COSMIC Desktop / Wayland)

### O comportamento padrão do Linux:
1. **Entrada Unicode Padrão no Linux (IBus / GTK / Wayland):**
   - O Linux nativamente usa o atalho <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>U</kbd>, seguido do código hexadecimal e <kbd>Enter</kbd> (ex: `Ctrl+Shift+U`, `b`, `0`, `Enter` para `°`).
   - Essa combinação é lenta e nada intuitiva para quem tem a memória muscular dos Alt Codes do Windows.
2. **Atalhos Nativos do US-International (AltGr):**
   - <kbd>AltGr</kbd> + <kbd>Shift</kbd> + <kbd>;</kbd> ➔ `°`
   - <kbd>AltGr</kbd> + <kbd>Shift</kbd> + <kbd>S</kbd> ➔ `§`
   - <kbd>AltGr</kbd> + <kbd>C</kbd> ➔ `©`
   - <kbd>AltGr</kbd> + <kbd>R</kbd> ➔ `®`
3. **Como viabilizar Alt Codes autênticos no Linux/Wayland:**
   - **Abordagem A (Espanso / Daemon de Teclado):** O `espanso` já está configurado no nosso setup para Wayland. Ele pode interceptar sequências ou atalhos com substituição imediata.
   - **Abordagem B (Daemon evdev / uinput de baixo nível em Python):** Um pequeno serviço de usuário em segundo plano que monitora o pressionamento de `KEY_LEFTALT` + sequência de teclas `KEY_KP1..KEY_KP9`, intercepta o evento e, ao soltar o `Alt`, injeta o caractere Unicode correspondente diretamente via `/dev/uinput` (como fizemos no `numlock-on`). Essa solução funciona em **100% dos aplicativos** sob Wayland, XWayland, jogos, terminais e editores!
   - **Abordagem C (Tabela Compose / XCompose):** Mapeamento de sequências compostas usando a tecla Compose ou Multi_key.

---

## 📂 4. Arquivos Relevantes do Projeto
- [`Docs/contexto_proxima_conversa.md`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/Docs/contexto_proxima_conversa.md)
- [`Docs/issue_chromium_electron_cedilha_wayland.md`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/Docs/issue_chromium_electron_cedilha_wayland.md)
- [`scripts/02_teclado_cedilha_numlock.sh`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/scripts/02_teclado_cedilha_numlock.sh)
- [`scripts/patch_cedilla_electron.py`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/scripts/patch_cedilla_electron.py)
- [`README.md`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/README.md)
