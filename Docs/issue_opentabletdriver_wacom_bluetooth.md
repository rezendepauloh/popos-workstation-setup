# [Relatório de Problema / Investigação]: Reconexão Bluetooth e Detecção do Fluxo HID da Wacom Intuos Pro S (PTH-460) no Linux (Pop!_OS 24.04 / COSMIC)

## 📌 Informações do Ambiente
- **Sistema Operacional:** Pop!_OS 24.04 LTS (Base Ubuntu 24.04 noble)
- **Ambiente de Trabalho:** COSMIC Desktop (Wayland / `cosmic-comp`)
- **Kernel Linux:** 6.9.3-76060903-generic (x86_64)
- **Versão do OpenTabletDriver:** 0.6.7 (Pacote Debian `opentabletdriver_0.6.7-1_x64.deb` com runtime .NET 8)
- **Dispositivo:** Wacom Intuos Pro Small (Modelo: PTH-460)
  - **VID:PID via USB:** `056a:0392`
  - **VID:PID via Bluetooth:** `056a:0393`
  - **MAC Bluetooth:** `E0:9F:2A:20:BC:DD`

---

## 🔍 Descrição do Problema
Quando a mesa digitalizadora Wacom Intuos Pro S (PTH-460) é conectada diretamente pelo cabo USB, o OpenTabletDriver a detecta imediatamente como `Wacom PTH-460`. Todas as funções funcionam perfeitamente: atalhos dos botões físicos (ExpressKeys), curva de pressão da caneta (Pro Pen 2) e rotação de 180° (Modo Canhoto).

No entanto, ao desconectar o cabo USB e ligar o modo Bluetooth (pressionando/segurando o botão central do Touch Ring até o LED azul piscar/acender), a mesa se conecta com sucesso ao Bluetooth do sistema operacional (`bluetoothctl connect` tem êxito com `Trusted: yes` e cria os nós de entrada no kernel `/dev/input/event25` [Pen], `event26` [Finger] e `event27` [Pad]), mas **o OpenTabletDriver (GUI e serviço em segundo plano) não captura o fluxo do dispositivo no modo sem fio nem faz a transição automática**.

---

## 📋 Passos para Reproduzir
1. Conectar a Wacom Intuos Pro S via cabo USB.
2. Abrir o aplicativo gráfico `otd-gui` -> A mesa é reconhecida perfeitamente como `Wacom PTH-460`.
3. Desconectar o cabo USB.
4. Ligar a mesa no modo Bluetooth segurando o botão central do Touch Ring.
5. No BlueZ / `bluetoothctl`, o dispositivo muda para `Connected: yes` e o `/proc/bus/input/devices` registra os 3 nós de entrada do kernel:
   ```text
   N: Name="Wacom Intuos Pro S Pen" (Handlers=mouse2 event25)
   N: Name="Wacom Intuos Pro S Finger" (Handlers=mouse3 event26)
   N: Name="Wacom Intuos Pro S Pad" (Handlers=event27 js0)
   ```
6. O OpenTabletDriver exibe "Nenhuma mesa detectada" e não processa os comandos de caneta/toque vindos da conexão Bluetooth.

---

## 🔬 Diagnósticos do Sistema e Logs

### 1. Informações do Dispositivo no Bluetoothctl:
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
	UUID: Human Interface Device... (00001124-0000-1000-8000-00805f9b34fb)
	UUID: PnP Information           (00001200-0000-1000-8000-00805f9b34fb)
	Modalias: usb:v056Ap0393d0000
```

### 2. Detecção Local via Libwacom (`libwacom-list-local-devices`):
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

### 3. Status do Serviço OpenTabletDriver:
```text
● opentabletdriver.service - OpenTabletDriver Daemon
   Loaded: loaded (~/.config/systemd/user/opentabletdriver.service)
   Active: active (running)
```

---

## 💡 Comportamento Esperado
O OpenTabletDriver deve interceptar automaticamente o fluxo HID Bluetooth (`056a:0393`) assim que o cabo USB (`056a:0392`) for desconectado e o Bluetooth estiver ativo, mantendo todas as preferências do usuário (rotação 180° para canhotos, sensibilidade de pressão e atalhos de botões).
