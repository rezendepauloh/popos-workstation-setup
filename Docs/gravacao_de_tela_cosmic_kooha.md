# Gravação de Tela no Pop!_OS COSMIC Desktop (Kooha)

Este documento detalha o funcionamento, configuração e atalhos da ferramenta de gravação de tela integrada à nossa workstation Pop!_OS 24.04 (COSMIC Desktop / Wayland).

---

## 1. Contexto: Gravação de Tela no COSMIC Desktop

No COSMIC Desktop em Wayland, o utilitário nativo de captura (`cosmic-screenshot`) é voltado exclusivamente para fotos estáticas (print screen). Para gravação contínua de tela e vídeo com qualidade e suporte aos protocolos modernos de Wayland (XDG Desktop Portal / PipeWire), utilizamos o **Kooha** (`io.github.seadve.Kooha`).

### Vantagens do Kooha:
- **Formato Nativo .MP4 (H.264):** Gera gravações diretamente em formato `.mp4` com compatibilidade universal (além de WebM, MKV e GIF).
- **Integração com XDG Desktop Portal:** Permite gravar a tela inteira, uma janela específica ou desenhar um retângulo de área livre no monitor.
- **Áudio Interno e Microfone:** Permite alternar facilmente a captura de som do sistema operacional (Desktop Audio) e do microfone.
- **Leveza:** Interface GTK4/Libadwaita limpa, rápida e sem necessidade de abrir softwares pesados como o OBS Studio.

---

## 2. Atalhos de Teclado Recomendados

| Ação | Atalho | Ferramenta |
| :--- | :--- | :--- |
| **Captura de Tela Estática (Print)** | <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>S</kbd> ou <kbd>Print Screen</kbd> | `cosmic-screenshot` |
| **Iniciar Gravador de Tela (Vídeo)** | <kbd>Ctrl</kbd> + <kbd>Print Screen</kbd> | `Kooha` |
| **Acesso Rápido via Mouse / Pie Menu** | <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>F10</kbd> ➔ *Utilitários* | `Kando` |

---

## 3. Como Vincular o Atalho no COSMIC Desktop

Para definir a combinação **<kbd>Ctrl</kbd> + <kbd>Print Screen</kbd>** (ou qualquer outra tecla de sua preferência):

1. Abra as **Configurações do Sistema (COSMIC Settings)**:
   - Pressione <kbd>Super</kbd> e digite `Configurações` (ou execute `cosmic-settings`).
2. Vá até a seção **Entrada (Input)** ➔ **Teclado (Keyboard)** ➔ **Atalhos de Teclado Personalizados (Custom Shortcuts)**.
3. Clique em **Adicionar Atalho (Add Shortcut)**:
   - **Nome:** `Gravar Tela (Kooha)`
   - **Comando:** `flatpak run io.github.seadve.Kooha`
   - **Combinação:** Pressione <kbd>Ctrl</kbd> + <kbd>Print Screen</kbd>.
4. Salve a configuração. O atalho responderá instantaneamente em qualquer tela ou aplicativo.

---

## 4. Configuração Padrão do Kooha (.MP4 e Áudio)

O script de automação (`06_softwares_workflow.sh` e `19_flatpak_permissions.sh`) já pré-configura:
1. **Formato MP4 por Padrão:** O perfil `profile-id` é mantido como `'mp4'` via GSettings.
2. **Permissões de Discos Secundários:** O Kooha possui permissão de leitura e escrita em `/mnt/storage_700` e `/mnt/storage_930`, permitindo salvar gravações longas diretamente em HDDs/SSDs secundários.

### Como Gravar Passo a Passo:
1. Pressione <kbd>Ctrl</kbd> + <kbd>Print Screen</kbd> ou abra o Kooha via Kando / Launcher.
2. Na janela do Kooha:
   - Escolha o modo de captura: **Tela Inteira (Monitor)** ou **Seleção de Área (Selection)**.
   - Ative/Desative os botões de **Alto-falante** (Som do sistema) e **Microfone**.
   - Verifique se a extensão selecionada na engrenagem/menu é **MP4**.
3. Clique no botão vermelho **Gravar (Record)**.
4. Para finalizar, clique no indicador de gravação na barra superior ou reabra o Kooha e clique em **Parar (Stop)**. O vídeo será salvo automaticamente na pasta `~/Vídeos` (ou no local escolhido).
