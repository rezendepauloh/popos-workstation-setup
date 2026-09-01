# [Bug / Feature Request]: Wacom Intuos Pro S (PTH-460) Bluetooth reconnection & HID stream detection on Linux (Pop!_OS 24.04 / COSMIC)

## 📌 Environment Information
- **OS:** Pop!_OS 24.04 LTS (Ubuntu 24.04 noble base)
- **Desktop Environment:** COSMIC Desktop (Wayland / cosmic-comp)
- **Kernel:** Linux 6.9.3-76060903-generic (x86_64)
- **OpenTabletDriver Version:** 0.6.7 (Debian package `opentabletdriver_0.6.7-1_x64.deb` with .NET 8 runtime)
- **Device:** Wacom Intuos Pro Small (Model: PTH-460)
  - **USB VID:PID:** `056a:0392`
  - **Bluetooth VID:PID:** `056a:0393`
  - **Bluetooth MAC:** `E0:9F:2A:20:BC:DD`

---

## 🔍 Description
When the Wacom Intuos Pro S (PTH-460) is connected via USB cable, OpenTabletDriver immediately detects the device (`Wacom PTH-460`), applies custom button bindings, pen pressure curve, and 180° rotation (Left-handed mode) perfectly.

However, when disconnecting the USB cable and turning on Bluetooth mode (pressing/holding the Touch Ring center button until the blue LED turns on), the device successfully pairs and connects to BlueZ (`bluetoothctl connect` succeeds with `Trusted: yes` and creates kernel input nodes `/dev/input/event25` [Pen], `event26` [Finger], `event27` [Pad]), but **OpenTabletDriver GUI and daemon fail to capture the stream or switch to Bluetooth mode seamlessly**.

---

## 📋 Steps to Reproduce
1. Connect Wacom Intuos Pro S via USB cable.
2. Open `otd-gui` -> Tablet is recognized as `Wacom PTH-460` and functions normally.
3. Unplug the USB cable.
4. Press/hold the Touch Ring button on the tablet to turn on Bluetooth.
5. In BlueZ / `bluetoothctl`, the tablet status changes to `Connected: yes` and `/proc/bus/input/devices` shows:
   ```text
   N: Name="Wacom Intuos Pro S Pen" (Handlers=mouse2 event25)
   N: Name="Wacom Intuos Pro S Finger" (Handlers=mouse3 event26)
   N: Name="Wacom Intuos Pro S Pad" (Handlers=event27 js0)
   ```
6. OpenTabletDriver GUI reports "No tablet detected" or fails to process pen/touch input from the Bluetooth stream.

---

## 🔬 System Diagnostics & Logs

### 1. Bluetoothctl Device Information:
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

### 2. Libwacom detection:
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

### 3. OpenTabletDriver Service Status:
```text
● opentabletdriver.service - OpenTabletDriver Daemon
   Loaded: loaded (~/.config/systemd/user/opentabletdriver.service)
   Active: active (running)
```

---

## 💡 Expected Behavior
OpenTabletDriver should automatically hook into the Bluetooth HID stream (`056a:0393`) when the USB cable (`056a:0392`) is unplugged and Bluetooth is connected, preserving user configurations (rotation 180°, pen pressure curves, and ExpressKeys bindings).
