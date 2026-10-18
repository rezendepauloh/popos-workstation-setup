# ✅ [Relatório Técnico]: Suporte Nativo à Mesa Wacom Intuos Pro S (PTH-460) no Pop!_OS 24.04 (COSMIC / Wayland)

---

## 📌 Informações do Ambiente
- **Sistema Operacional:** Pop!_OS 24.04 LTS (x86_64)
- **Ambiente de Trabalho:** COSMIC Desktop Environment (COSMIC Epoch 1.10.0+ / Wayland)
- **Compositor:** `cosmic-comp` (Smithay / libinput)
- **Kernel Linux:** `7.1.x-generic`
- **Dispositivo:** Wacom Intuos Pro Small (Modelo: PTH-460)
  - **VID:PID via USB:** `056a:0392`
  - **VID:PID via Bluetooth:** `056a:0393`
  - **MAC Bluetooth:** `E0:9F:2A:20:BC:DD`

---

## 🔍 Histórico & Evolução

### 1. Limitações Iniciais do OpenTabletDriver (OTD)
* O OTD possuía um bug na biblioteca `HidSharp` no Linux onde conexões Bluetooth via `/dev/hidraw` falhavam com `DeviceIOException: No serial number`, limitando o funcionamento do driver apenas a conexões USB físicas.
* Além disso, o OTD criava um bloqueio modprobe (`install wacom /usr/bin/true`) que impedia o kernel Linux de carregar seu driver oficial `wacom.ko`.

### 2. A Virada com o COSMIC Epoch 1.10.0
* No release **COSMIC Epoch 1.10.0** (PR [#2220 do `cosmic-settings`](https://github.com/pop-os/cosmic-settings/pull/2220)), a System76 adicionou a primeira versão da página de configurações para mesas digitalizadoras (**Drawing Tablet**), permitindo mapear a área ativa da caneta para saídas específicas de vídeo (`map_to_output`) diretamente no `com.system76.CosmicComp`.

---

## 🛠️ Solução Nativa Definitiva (Kernel wacom.ko + COSMIC Wayland)

A mesa agora funciona **100% de forma nativa**, sem daemons em background, sem emuladores de terceiros e sem runtime .NET.

### 1. Desbloqueio do Kernel
* Removido o bloqueio do `wacom.ko` mascarando `/usr/lib/modprobe.d/99-opentabletdriver.conf` com `/etc/modprobe.d/99-opentabletdriver.conf -> /dev/null`.
* Carregamento do módulo `wacom` oficial, que reconhece nativamente os 3 nós de input:
  * `Wacom Intuos Pro S Pen` (Caneta com 8191 níveis de pressão, tilt X/Y e botões).
  * `Wacom Intuos Pro S Finger` (Touchpad multitoque nativo de até 10 dedos e gestos).
  * `Wacom Intuos Pro S Pad` (Botões físicos ExpressKeys e Touch Ring).

### 2. Regras de Permissão Udev
Instaladas em `/etc/udev/rules.d/99-wacom-native.rules`:
```udev
SUBSYSTEM=="input", ATTRS{idVendor}=="056a", TAG+="uaccess", MODE="0664", GROUP="input"
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="056a", TAG+="uaccess", MODE="0664", GROUP="input"
KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput", MODE="0660", GROUP="input"
```

### 3. Configuração de Modo Canhoto e Mapeamento de Monitor
Salva em `~/.config/cosmic/com.system76.CosmicComp/v1/input_devices`:
```rust
{
    "Wacom Intuos Pro S Pen": (
        state: Enabled,
        map_to_output: Some("DP-1"),
    ),
    "Wacom Intuos Pro S Finger": (
        state: Enabled,
        map_to_output: Some("DP-1"),
        left_handed: Some(true),
        rotation_angle: Some(180),
    ),
}
```
* **Caneta:** Proporção mapeada 1:1 para o monitor ultrawide `DP-1` com calibração e rastreamento estável.
* **Touch com os dedos:** Configurado para `left_handed: true` e `rotation_angle: 180`, alinhando os gestos de toque com a mesa virada para canhotos.

### 4. Mapeamento das ExpressKeys & Touch Ring (Daemon UInput Nativo)
Como o protocolo `zwp_tablet_pad_v2` do Wayland ainda não repassa atalhos arbitrários de ExpressKeys no COSMIC, um daemon leve em Python (`wacom-expresskeys-daemon.py`) roda sob o systemd do usuário (`wacom-expresskeys.service`), escutando `/dev/input/event*` (`Wacom Intuos Pro S Pad`) e injetando as teclas via `/dev/uinput`:

#### 🎮 Botões Físicos (ExpressKeys - Modo Canhoto 180°)
| Botão / ID | Ação Mapeada | Atalho Injetado | Finalidade |
| :--- | :--- | :--- | :--- |
| **Botão 1** (`BTN_0`) | **Desfazer** | <kbd>Ctrl</kbd> + <kbd>Z</kbd> | Voltar última alteração |
| **Botão 2** (`BTN_1`) | **Refazer** | <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>Z</kbd> | Reaplicar alteração |
| **Botão 3** (`BTN_2`) | **Pan / Hand Tool** | <kbd>Espaço</kbd> | Arrastar canvas / navegar pela tela |
| **Botão 4** (`BTN_3`) | **Salvar** | <kbd>Ctrl</kbd> + <kbd>S</kbd> | Salvar documento ou projeto |
| **Botão 5** (`BTN_4`) | **Copiar** | <kbd>Ctrl</kbd> + <kbd>C</kbd> | Copiar seleção para área de transferência |
| **Botão 6** (`BTN_5`) | **Colar** | <kbd>Ctrl</kbd> + <kbd>V</kbd> | Colar da área de transferência |

#### 🔄 Touch Ring (Anel de Toque)
| Controle / Eixo | Ação Mapeada | Atalho Injetado | Finalidade |
| :--- | :--- | :--- | :--- |
| **Giro Sentido Horário** | **Zoom In** | <kbd>Ctrl</kbd> + <kbd>+</kbd> | Aproximar zoom |
| **Giro Sentido Anti-Horário** | **Zoom Out** | <kbd>Ctrl</kbd> + <kbd>-</kbd> | Afastar zoom |
| **Botão Central** (`BTN_6`) | *(Livre / Reset)* | - | Uso auxiliar |

#### 🖊️ Botões da Caneta (Wacom Pro Pen 2)
| Botão | Ação Nativa |
| :--- | :--- |
| **Ponta da Caneta** (`BTN_TOUCH`) | Clique Esquerdo (`Left Click`) |
| **Botão Inferior** (`BTN_STYLUS`) | Clique Direito (`Right Click`) / Menu de contexto |
| **Botão Superior** (`BTN_STYLUS2`) | Clique do Meio (`Middle Click`) / Pan |

---

## 📦 Automação no Repositório
* Implementado no script oficial: [12_wacom_tablet.sh](scripts/12_wacom_tablet.sh).
* Daemon de atalhos: [wacom-expresskeys-daemon.py](scripts/wacom-expresskeys-daemon.py).
* Serviço systemd do usuário: [wacom-expresskeys.service](config/systemd/user/wacom-expresskeys.service).
* Execução idempotente compatível com o assistente central `setup_popos_v2.sh`.