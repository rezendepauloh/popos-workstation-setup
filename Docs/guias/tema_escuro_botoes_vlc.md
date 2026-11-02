# Diagnóstico Técnico & Resolução: Botões Invisíveis no Footer do VLC em Tema Escuro (Pop!_OS 24.04 / COSMIC)

---

## 1. Descrição do Problema
No **Pop!_OS 24.04 LTS** com o **COSMIC Desktop (Wayland)** em modo escuro (`CosmicDark`), ao abrir o **VLC Media Player** (`/usr/bin/vlc`, baseado no toolkit Qt5 com backend `qt5ct`), a janela adota tons escuros no fundo (`#2b2e34` / `#40434a`).

Contudo, os botões de controle de mídia na barra inferior (Play, Pause, Stop, Próximo, Anterior, Tela Cheia, Volume, etc.) ficavam quase invisíveis contra o fundo da janela.

---

## 2. Diagnóstico de Engenharia Reversa

Ao inspecionar o plugin de interface gráfica do VLC (`/usr/lib/x86_64-linux-gnu/vlc/plugins/gui/libqt_plugin.so`), foram identificados dois fatores fundamentais:

1. **SVGs com Cores Estáticas (Hardcoded):**
   - Os ícones dos botões da barra de ferramentas (`:/toolbar/play.svg`, `pause.svg`, `stop.svg`, `previous.svg`, `next.svg`, `fullscreen.svg`, `volume-high.svg`, etc.) são compilados diretamente nos recursos do binário Qt (RCC) com atributos fixos:
     ```xml
     style="display:inline;fill:#747474;fill-opacity:1;fill-rule:evenodd;stroke:none;"
     ```
   - A cor `#747474` (um cinza médio com baixa luminosidade) não possui contraste suficiente contra a paleta de superfícies escuras do tema `CosmicDark`.

2. **Comportamento Transparente do `QToolButton`:**
   - No estilo padrão `qt5ct-style` e `Fusion`, os botões `QToolButton` da barra de ferramentas do VLC são renderizados com fundo totalmente transparente (`autoRaise = true`).
   - Sem uma área de delimitação (bounding box) ou contraste no contêiner do botão, os glifos em `#747474` parecem flutuar "apagados" no rodapé da janela.

---

## 3. Solução Adotada: Injeção de QSS Universal via `qt5ct`

Em vez de aplicar patches arriscados em binários compilados pelo APT (que seriam sobrescritos a cada atualização do pacote `vlc-plugin-qt`), a solução arquitetural mais robusta e nativa é utilizar o suporte a **Folhas de Estilo Qt (QSS)** da ponte `qt5ct`:

### Arquivo QSS: `~/.config/qt5ct/qss/vlc-dark-fix.qss`
```css
/* ==========================================================================
   VLC Media Player - Dark Mode Controls & Contrast Fix
   Aplica contraste nítido a todos os botões (nativos e customizados) e timeline.
   ========================================================================== */

/* 1. Botões do Controlador de Mídia (Play, Pause, Stop, Prev, Next, etc.) */
QToolButton {
    background-color: #585c66;
    color: #ffffff;
    border: 1px solid #7a7f8c;
    border-radius: 5px;
    margin: 2px 1px;
    padding: 3px;
    min-width: 22px;
    min-height: 22px;
}

QToolButton:hover {
    background-color: #6f7482;
    border: 1px solid #7b68ee;
}

QToolButton:pressed {
    background-color: #3b3e45;
    border: 1px solid #7b68ee;
}

/* 2. Barra de Progresso / Slider de Linha do Tempo e Volume */
QSlider::groove:horizontal {
    height: 6px;
    background: #484c55;
    border: 1px solid #5b5f6a;
    border-radius: 3px;
}

QSlider::sub-page:horizontal {
    background: #6c5ce7;
    border-radius: 3px;
}

QSlider::handle:horizontal {
    background: #ffffff;
    border: 1px solid #2b2e34;
    width: 14px;
    margin-top: -4px;
    margin-bottom: -4px;
    border-radius: 7px;
}

QSlider::handle:horizontal:hover {
    background: #ffffff;
    border: 2px solid #6c5ce7;
}

/* 3. Marcadores e Labels de Tempo */
QLabel {
    color: #f0f0f0;
}
```

### Por que essa solução é universal para TODOS os botões?
No VLC, qualquer botão inserido na barra de controle principal, na barra avançada ou em controladores de tela cheia (como avanço de quadros, gravação, loop A-B, equalizador, etc.) herda diretamente da classe **`QToolButton`**. Portanto, ao estilizar `QToolButton`, **100% dos botões adicionados ou reposicionados recebem o mesmo fundo contrastante, bordas e efeitos de hover/pressed**.

---

## 4. Persistência de Perfil e Layout Customizado dos Botões

### Onde o VLC salva a personalização dos botões?
As configurações de interface, tamanho de janelas e ordem exata dos botões nas barras ficam gravadas em:
* `~/.config/vlc/vlc-qt-interface.conf`
  - Chaves: `MainWindow/MainToolbar1`, `MainWindow/MainToolbar2`, `MainWindow/AdvToolbar`, `MainWindow/InputToolbar`, `MainWindow/FSCToolbar`.
* `~/.config/vlc/vlcrc` (opções gerais do VLC).

### Como salvar seu perfil no Google Drive:
Após personalizar os botões no VLC (*Ferramentas > Personalizar Interface*), execute o comando para persistir no Google Drive:
```bash
mkdir -p ~/GoogleDrive_Pessoal/Organização/Backup_COSMIC/vlc
cp -a ~/.config/vlc/* ~/GoogleDrive_Pessoal/Organização/Backup_COSMIC/vlc/
```

### Como o script restaura após uma formatação:
O módulo `scripts/14_cosmic_theme_restore.sh` sincroniza automaticamente os arquivos da pasta `Backup_COSMIC/vlc/` para `~/.config/vlc/`:
1. Restaura a disposição completa dos seus botões.
2. Injeta a diretiva `QtStyle=qt5ct-style`.
3. Garante a aplicação imediata do tema escuro com alto contraste.

Além disso, o utilitário de backup semanal `/usr/local/bin/backup-workstation` (configurado em `scripts/25_limpeza_otimizacao.sh`) inclui automaticamente a pasta `.config/vlc` nos arquivos compactados periódicos.

---

## 5. Resolução: Crash ao Abrir "Personalizar Interface..." e Estabilidade em Fullscreen

### Por que o VLC crasha ao clicar em "Personalizar Interface"?
O diálogo de personalização de botões do VLC (`ToolbarEditDialog` em `modules/gui/qt/dialogs/toolbar.cpp`) utiliza um mecanismo complexo de drag-and-drop (`PreviewWidget`, `DroppingController` e `WidgetListing`) herdado do Qt4/Qt5 inicial.

No protocolo **Wayland nativo** (`QT_QPA_PLATFORM=wayland`), o plugin Qt do Wayland (`libqwayland-generic-gpu.so`) lida com drag-and-drop de widgets internos de forma estrita quanto às janelas de superfície e coordenadas globais. Quando o VLC tenta instanciar os controladores arrastáveis de pré-visualização, ocorre uma quebra de evento no compositor Wayland, levando o processo a abortar imediatamente (`SIGSEGV` / terminação abrupta).

### Como resolvemos no sistema:
O setup cria um lançador em `~/.local/share/applications/vlc.desktop` e um wrapper em `~/.local/bin/vlc` com `QT_QPA_PLATFORM=xcb`. Assim, o VLC sempre é executado via **XWayland**:
1. O editor de interface abre perfeitamente sem nenhum crash.
2. A decodificação de vídeo opera estável sem os bugs de subsuperfície do Wayland.

### Correção de Janelas Sobrepostas e Painel no Meio da Tela em Fullscreen:
No ambiente XWayland sobre monitores Ultrawide / alta resolução com o compositor COSMIC, ocorriam dois problemas em modo Tela Cheia:
1. **Janelas do sistema ficando sobrepostas ao vídeo:** O VLC não ativava a propriedade X11 de foco exclusivo de vídeo. Corrigido ativando `video-on-top=1` no `~/.config/vlc/vlcrc`.
2. **Painel de controle flutuando no meio do monitor:** A geometria padrão de Fullscreen (`[FullScreen] wide=false`) calcula o controlador como uma janela flutuante estreita baseada em um ponto arbitrário `pos=@Point(1730 1375)`. Ajustado para `wide=true` em `~/.config/vlc/vlc-qt-interface.conf`, forçando o controlador a se ancorar como uma barra inferior contínua no rodapé da tela cheia.
3. **Loop de Opacidade no Terminal:** Desativada a transição suave de opacidade com `qt-fs-opacity=1.000000`, eliminando as mensagens repetitivas de `This plugin does not support setting window opacity`.

---

## 6. Validação e Testes

Para validar a aplicação:
```bash
# Executa a restauração do módulo 14:
sudo ./setup_popos_v2.sh 14 --force

# Abre o VLC com os botões estilizados:
vlc
```

---

## 7. Registro de Problema Pendente: Conflito Crítico Wayland/EGL (`wl_shm_pool`)

### Log do Erro Fatal:
```text
[000078cc38001fc0] egl_wl gl error: cannot create EGL window surface
[000078cc38001fc0] egl_wl gl error: cannot create EGL window surface
error marshalling arguments for (null) (signature wl_shm_pool): null value passed for arg 0
Error marshalling request: Argumento inválido
The Wayland connection experienced a fatal error: Argumento inválido
```

### Análise Técnica do Problema:
1. **Conflito de Inicialização do Módulo EGL (`egl_wl`):**
   - Mesmo com a interface gráfica Qt rodando via `xcb` (XWayland), o backend de vídeo do VLC (`vout`) tenta carregar plugins internos de superfície Wayland (`libegl_wl_plugin.so`).
   - Sob o driver proprietário da NVIDIA no compositor COSMIC, a chamada `eglCreateWindowSurface` falha repetidamente (`cannot create EGL window surface`).
2. **Crash Fatal de Protocolo Wayland:**
   - Ao falhar na criação da superfície EGL, o VLC tenta um fallback para memória compartilhada (`wl_shm`). No entanto, o ponteiro da pool é passado como nulo (`null value passed for arg 0`), disparando um erro fatal irrecuperável no protocolo IPC do Wayland que encerra o processo imediatamente (`Argumento inválido`).

### Estratégias Mapeadas para Retomada Futura:
1. **Desativação Forçada dos Plugins de Vídeo Wayland no VLC:**
   - Rodar o VLC desabilitando explicitamente os plugins de tela Wayland em tempo de execução via `--no-wayland` ou mascarando o plugin `libegl_wl_plugin.so` e `libwl_shell_plugin.so`.
2. **Avaliação da Versão Flatpak (`org.videolan.VLC`):**
   - A versão Flatpak utiliza runtimes isolados do GNOME/KDE com patches mais recentes para Wayland/XWayland e drivers NVIDIA, contornando incompatibilidades da compilação legada do VLC 3.0.x do APT.
3. **Alternativa Moderna com Tema Nativo Escuro (MPV + Celluloid / Clapper):**
   - Avaliar players modernos baseados em GTK4/Libadwaita ou Qt6 (como Celluloid ou Haruna) que possuem suporte de primeira classe a Wayland nativo e temas escuros sem necessidade de workarounds.

