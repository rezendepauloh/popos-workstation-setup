# 🐛 [Relatório de Problema & Investigação]: Suporte à Caneta e Reconexão Bluetooth da Wacom Intuos Pro S (PTH-460) no Pop!_OS 24.04 (COSMIC / Wayland)

---

## 📌 Informações do Ambiente
- **Sistema Operacional:** Pop!_OS 24.04 LTS (x86_64)
- **Ambiente de Trabalho:** COSMIC Desktop Environment (Wayland / `cosmic-comp`)
- **Kernel Linux:** `6.9.3-76060903-generic`
- **Versão do OpenTabletDriver:** 0.6.7 (com runtime .NET 8)
- **Dispositivo:** Wacom Intuos Pro Small (Modelo: PTH-460)
  - **VID:PID via USB:** `056a:0392`
  - **VID:PID via Bluetooth:** `056a:0393`
  - **MAC Bluetooth:** `E0:9F:2A:20:BC:DD`

---

## 🔍 Descrição do Problema

A caneta Pro Pen 2 da Wacom Intuos Pro S (PTH-460) apresenta falhas de detecção e rastreamento de entrada tanto no modo USB quanto no modo Bluetooth sob o ambiente Wayland (COSMIC Desktop):

1. **No Modo USB (`056a:0392`):**
   - A mesa é detectada pela GUI do OpenTabletDriver, porém o ponteiro da caneta não responde na tela do COSMIC Desktop Wayland.
   - **Causa Raiz Identificada:** O OpenTabletDriver configura por padrão o modo de saída como `OpenTabletDriver.Desktop.Output.LinuxArtistMode` (que é dependente do protocolo X11 / XTest). No Wayland (`cosmic-comp`), esses eventos X11 não são recebidos pelas aplicações nativas Wayland nem pelo compositor. O modo de saída obrigatório no Wayland é `OpenTabletDriver.Desktop.Output.LinuxVirtualTablet` (via `/dev/uinput`).

2. **No Modo Bluetooth (`056a:0393`):**
   - A mesa é pareada e conectada com sucesso via Bluetooth pelo BlueZ (`bluetoothctl connect E0:9F:2A:20:BC:DD`), gerando os nós de evento no kernel (`/dev/input/event*`).
   - No entanto, o daemon do OpenTabletDriver (`otd-daemon`) emite a seguinte mensagem de depuração e descarta o dispositivo:
     ```text
     [HidSharpDeviceRootHub:Debug] Changes: 1, Add: 1, Remove: 0
     [RootHub:Debug] Invoking DevicesChanged
     [DriverDaemon:Debug] No known tablets added, skipping detect
     ```
   - O OpenTabletDriver 0.6.7 não possui o Product ID Bluetooth `0x0393` registrado na tabela de configurações da `Wacom PTH-460` (onde consta apenas o PID USB `0x0392`).

3. **Conflito entre Drivers (OpenTabletDriver vs Driver Nativo do Kernel `wacom.ko`):**
   - O kernel Linux possui o módulo nativo `wacom.ko`, que possui suporte embutido para ambos os PIDs (`0392` e `0393`) via `libinput`.
   - Quando o `otd-daemon` está em execução em segundo plano, ele reivindica a interface HID dos dispositivos, interferindo no processamento nativo do `libinput` / `wacom`.

---

## 🔬 Diagnósticos do Sistema e Logs Relevantes

### 1. Detecção Bluetooth no BlueZ (`bluetoothctl info`):
```text
Device E0:9F:2A:20:BC:DD (public)
	Name: IntuosPro S
	Alias: IntuosPro S
	Class: 0x00002594 (9620)
	Icon: input-tablet
	Paired: yes
	Bonded: yes
	Trusted: yes
	Blocked: no
	Connected: yes
	Modalias: usb:v056Ap0393d0000
```

### 2. Nós de Entrada Gerados pelo Kernel no Bluetooth (`libwacom-list-local-devices`):
```yaml
devices:
- name: 'Wacom Intuos Pro S'
  bus: 'bluetooth'
  vid: '0x056a'
  pid: '0x0393'
  nodes: 
  - /dev/input/event27: 'Wacom Intuos Pro S Pad'
  - /dev/input/event26: 'Wacom Intuos Pro S Finger'
  - /dev/input/event25: 'Wacom Intuos Pro S Pen'
```

### 3. Log do `otd-daemon` ao Conectar no Bluetooth:
```json
{
  "Group": "DriverDaemon",
  "Message": "No known tablets added, skipping detect",
  "Level": 0
}
```

---

## 🛠️ Planos de Ação e Soluções

### Opção A: Ajustar OpenTabletDriver para Wayland & Adicionar PID Bluetooth
1. Alterar a configuração `OutputMode` no `~/.config/OpenTabletDriver/settings.json` para:
   ```json
   "OutputMode": {
     "Path": "OpenTabletDriver.Desktop.Output.LinuxVirtualTablet",
     "Settings": [],
     "Enable": true
   }
   ```
2. Adicionar uma definição de tablet personalizada (JSON) na pasta de configurações do OpenTabletDriver incluindo o PID `0x0393` para o modo sem fio.

### Opção B: Usar o Driver Oficial Nativo do Kernel Linux (`wacom.ko` + `libinput`)
1. Desativar o serviço em segundo plano do OpenTabletDriver:
   ```bash
   systemctl --user stop opentabletdriver.service
   systemctl --user disable opentabletdriver.service
   ```
2. Carregar o módulo nativo do kernel:
   ```bash
   sudo modprobe wacom
   ```
3. O `cosmic-comp` / `libinput` gerencia diretamente o rastreamento da caneta, pressão, botões físicos e rotação (modo canhoto) com suporte nativo de kernel para USB e Bluetooth sem depender de daemons externos.

---

## 📎 Arquivos Relacionados no Setup
* [`scripts/12_wacom_tablet.sh`](file:///home/rezendepauloh/Documentos/Scripts/scripts/12_wacom_tablet.sh)
