# 🐛 [Relatório Técnico]: Suporte à Mesa Wacom Intuos Pro S (PTH-460) no Pop!_OS 24.04 (COSMIC / Wayland)

---

## 📌 Informações do Ambiente
- **Sistema Operacional:** Pop!_OS 24.04 LTS (x86_64)
- **Ambiente de Trabalho:** COSMIC Desktop Environment (Wayland / `cosmic-comp`)
- **Kernel Linux:** `7.1.5-76070105-generic`
- **Dispositivo:** Wacom Intuos Pro Small (Modelo: PTH-460)
  - **VID:PID via USB:** `056a:0392`
  - **VID:PID via Bluetooth:** `056a:0393`
  - **MAC Bluetooth:** `E0:9F:2A:20:BC:DD`

---

## 🔍 Diagnóstico das Causas Raízes

### 1. Limitações do COSMIC Desktop (`cosmic-comp` / Smithay) no Modo Nativo
* O COSMIC Desktop é um ambiente de desktop moderno baseado no compositor Wayland em Rust (Smithay).
* Atualmente, o suporte a mesas digitalizadoras e personalização de orientação (Modo Canhoto / Rotação 180°) e o repasse do protocolo de botões físicos (`zwp_tablet_pad_v2`) ainda estão em desenvolvimento ativo pela System76.
* O compositor gerencia a geometria da tela e o mapeamento de coordenadas internamente, ignorando configurações do GNOME (`gsettings`) e matrizes de calibração do Udev (`LIBINPUT_CALIBRATION_MATRIX`) para touchpads/mesas.
* **Issues Oficiais da System76 para Acompanhamento:**
  * [pop-os/cosmic-settings #141: Feature request/brainstorming: Drawing tablet support (wacom)](https://github.com/pop-os/cosmic-settings/issues/141)
  * [pop-os/cosmic-comp #313: Support for Graphic & Display Drawing Tablets](https://github.com/pop-os/cosmic-comp/issues/313)

### 2. Comportamento do OpenTabletDriver no Wayland & Limitação do Bluetooth
* **Interface Gráfica (`otd-gui`):** Ao ser aberta no GTK/Wayland, inicializa no índice 0 (`Artist Mode` / X11), emitindo comandos IPC que resetam o modo de saída do daemon, limpando rotações e atalhos de botões.
* **Formatação Numérica Decimal (Locale):** Em sistemas com idioma Português (`pt_BR`), comandos numéricos enviados com ponto (`159.6`) eram parseados pelo runtime .NET sem casas decimais (`1596`), deslocando as coordenadas para dezenas de metros fora da tela visível. Resolvido com `LC_ALL=C`.
* **Identificador de Bluetooth:** A definição padrão continha apenas o Product ID USB `914` (`0x0392`). O Product ID Bluetooth `915` (`0x0393`) precisou ser adicionado à definição de hardware do OpenTabletDriver.
* **Bug da Biblioteca HidSharp no Bluetooth Linux:** No log de diagnóstico (`otd getdiagnostics`), o OpenTabletDriver falha ao abrir o endpoint Bluetooth com `DeviceIOException: No serial number` em `HidSharp.Platform.Linux.LinuxHidDevice.GetSerialNumber()`. Como dispositivos Bluetooth `/dev/hidraw` no Linux não expõem um descritor de serial idêntico ao USB, a biblioteca HidSharp interna descarta a mesa no modo sem fio, limitando o funcionamento do OpenTabletDriver estritamente ao modo USB.

---

## 🛠️ Solução Atual Implementada (Workaround Headless)

Para garantir estabilidade, orientação de canhoto (180°) e atalhos na caneta sem sofrer interferências da GUI:

1. **Daemon Headless (`otd-daemon`):**
   * Roda silenciosamente em segundo plano via serviço de usuário systemd e autostart (`~/.config/autostart/otd-daemon.desktop`).
   * A interface gráfica `OpenTabletDriver.UX.Gtk` foi desativada para evitar resets para `Artist Mode`.
2. **Modo Absoluto 180° com Proporção 1:1:**
   * Injeção de coordenadas absolutas via `/dev/uinput` com rotação de 180° calculada por software.
3. **Mapeamento Declarativo dos Botões Físicos (ExpressKeys) e Touch Ring:**
   * `AuxButton 0`: `Ctrl + Z` *(Desfazer)*
   * `AuxButton 1`: `Ctrl + Shift + Z` *(Refazer)*
   * `AuxButton 2`: `Espaço` *(Pan / Arrastar tela)*
   * `AuxButton 3`: `Ctrl + S` *(Salvar)*
   * `AuxButton 4`: `Ctrl + C` *(Copiar)*
   * `AuxButton 5`: `Ctrl + V` *(Colar)*
   * `Touch Ring`: Zoom In (`Ctrl + +`) / Zoom Out (`Ctrl + -`)
4. **Suporte Dual (USB + Bluetooth):**
   * Definições de hardware com PIDs `914` e `915` e regras Udev com `TAG+="uaccess"`.

---

## 🚀 Roadmap de Migração Futura (Driver 100% Nativo)

Assim que as issues da System76 ([cosmic-settings #141](https://github.com/pop-os/cosmic-settings/issues/141) e [cosmic-comp #313](https://github.com/pop-os/cosmic-comp/issues/313)) forem finalizadas e lançadas no Pop!_OS:

1. **Desinstalação do OpenTabletDriver:** Remover completamente o runtime .NET e daemons de terceiros.
2. **Ativação Pura do Kernel `wacom.ko` + `libinput`:**
   * Utilizar a interface gráfica nativa de Configurações do COSMIC para alternar Modo Canhoto (180°).
   * Mapear ExpressKeys e Touch Ring nativamente no desktop.
   * Usufruir do **Touch Multitoque nativo** de 1 a 4 dedos, caneta com pressão e inclinação em USB e Bluetooth.