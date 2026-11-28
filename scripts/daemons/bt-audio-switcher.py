#!/usr/bin/env python3
"""
Daemon para Comutação Inteligente de Dispositivos de Áudio (QCY H3S Bluetooth & Logitech G733 USB).
- Monitora conexões Bluetooth no D-Bus (BlueZ) para o QCY H3S (ou BT_AUDIO_DEVICE_NAME).
- Monitora o estado real de energia (ligado/desligado) do headset sem fio Logitech G733 via HID++ 2.0
  (/dev/hidraw*, feature 0x1F20 ADC Measurement), já que o dongle USB mantém o sink ALSA sempre presente.
- Ao ligar/conectar um headset, define-o automaticamente como saída padrão e move os streams ativos.
- Ao desligar/desconectar, alterna para o outro headset (se estiver ligado) ou restaura as caixas de som.
"""

import glob
import os
import select
import subprocess
import sys
import dbus
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

TARGET_DEVICE_MAC = os.environ.get("MAC_QCY_H3S", "").strip()
TARGET_DEVICE_NAME = os.environ.get("BT_AUDIO_DEVICE_NAME", "QCY H3S").strip()
G733_SINK_TOKEN = os.environ.get("G733_SINK_TOKEN", "Logitech_G733").strip().lower()
FALLBACK_SINK = os.environ.get(
    "FALLBACK_AUDIO_SINK",
    "alsa_output.pci-0000_00_1f.3.analog-stereo",
).strip()

# HID++ 2.0 constantes para Logitech G733 Gaming Headset
LOGITECH_VID = 0x046D
G733_PIDS = (0x0AB5, 0x0AFE)
HIDPP_REPORT_SHORT = 0x10
HIDPP_REPORT_LONG = 0x11
HIDPP_DEVICE_INDEX = 0xFF
HIDPP_SW_ID = 0x0A
HIDPP_FEATURE_ADC = 0x1F20
HIDPP_ERROR_INDEX = 0xFF
G733_OFFLINE_DEBOUNCE_SEC = 2
G733_POLL_INTERVAL_SEC = 3


def extract_mac_from_bluez_path(path):
    """Extrai o endereço MAC de um object path BlueZ (ex: /org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF)."""
    if not path:
        return ""
    for part in str(path).split("/"):
        if part.startswith("dev_"):
            raw = part[4:].replace("_", ":").upper()
            if len(raw) == 17 and raw.count(":") == 5:
                return raw
    return ""


def match_bluez_sink(sinks, device_mac="", device_name=""):
    """Encontra o sink PipeWire/PulseAudio bluez correspondente ao MAC (com '_' ou ':') ou nome."""
    mac = (device_mac or TARGET_DEVICE_MAC or "").strip().lower()
    mac_underscore = mac.replace(":", "_") if mac else ""
    mac_colon = mac.replace("_", ":") if mac else ""
    name_token = (device_name or TARGET_DEVICE_NAME or "").strip().lower().replace(" ", "_")

    for s in sinks:
        s_low = s.lower()
        if "bluez" not in s_low:
            continue
        if mac_underscore and mac_underscore in s_low:
            return s
        if mac_colon and mac_colon in s_low:
            return s
        if name_token and name_token in s_low:
            return s
    return None


def match_g733_sink(sinks):
    """Encontra o sink PipeWire/PulseAudio correspondente ao Logitech G733."""
    for s in sinks:
        s_low = s.lower()
        if G733_SINK_TOKEN in s_low or "g733" in s_low:
            return s
    return None


def select_fallback_sink(sinks):
    """Seleciona o sink de fallback (caixas de som / áudio interno), evitando headsets USB/BT."""
    if FALLBACK_SINK in sinks:
        return FALLBACK_SINK
    for s in sinks:
        s_low = s.lower()
        if "analog" in s_low and "bluez" not in s_low and "g733" not in s_low and "headset" not in s_low:
            return s
    for s in sinks:
        s_low = s.lower()
        if "bluez" not in s_low and "g733" not in s_low:
            return s
    return None


def parse_g733_adc_packet(packet, adc_feature_index):
    """
    Interpreta resposta/evento HID++ 2.0 da feature 0x1F20 (ADC Measurement) do G733.
    Retorna:
      - True  se o headset está ligado/conectado (tensão > 0 mV)
      - False se o headset está desligado/offline (tensão == 0 ou erro HID++ 0xFF para adc_feature_index)
      - None  se o pacote não pertence à feature ADC (ignorar)
    """
    if not packet or len(packet) < 6:
        return None
    if packet[0] not in (HIDPP_REPORT_SHORT, HIDPP_REPORT_LONG):
        return None
    # Erro HID++ 2.0 (ex: 11 ff ff <feat_idx> <func|sw> 05 = HW_ERROR quando headset está desligado)
    if packet[2] == HIDPP_ERROR_INDEX and packet[3] == adc_feature_index:
        return False
    if packet[2] == adc_feature_index:
        voltage_mv = (packet[4] << 8) | packet[5]
        return voltage_mv > 0
    return None


def find_g733_hidraw_path():
    """Localiza dinamicamente o nó /dev/hidraw* pertencente ao dongle Logitech G733."""
    pid_hexes = {f"{pid:04X}" for pid in G733_PIDS}
    vid_hex = f"{LOGITECH_VID:04X}"
    for uevent_path in sorted(glob.glob("/sys/class/hidraw/hidraw*/device/uevent")):
        try:
            with open(uevent_path, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
        except OSError:
            continue
        hid_id = ""
        hid_name = ""
        for line in content.splitlines():
            if line.startswith("HID_ID="):
                hid_id = line.split("=", 1)[1].strip().upper()
            elif line.startswith("HID_NAME="):
                hid_name = line.split("=", 1)[1].strip()
        is_match = False
        # Formato típico: 0003:0000046D:00000AB5
        parts = hid_id.split(":")
        if len(parts) == 3 and parts[1].endswith(vid_hex) and any(parts[2].endswith(p) for p in pid_hexes):
            is_match = True
        elif "g733" in hid_name.lower():
            is_match = True

        if is_match:
            hidraw_name = os.path.basename(os.path.dirname(os.path.dirname(uevent_path)))
            dev_path = f"/dev/{hidraw_name}"
            if os.path.exists(dev_path):
                return dev_path
    return None


def list_sinks():
    try:
        res = subprocess.run(["pactl", "list", "sinks", "short"], capture_output=True, text=True, check=True)
        sinks = []
        for line in res.stdout.strip().splitlines():
            parts = line.split()
            if len(parts) >= 2:
                sinks.append(parts[1])
        return sinks
    except Exception:
        return []


def set_default_sink(sink_name):
    try:
        subprocess.run(["pactl", "set-default-sink", sink_name], check=True)
        # Move streams ativos para o novo sink
        res = subprocess.run(["pactl", "list", "sink-inputs", "short"], capture_output=True, text=True)
        for line in res.stdout.strip().splitlines():
            parts = line.split()
            if parts:
                stream_id = parts[0]
                subprocess.run(["pactl", "move-sink-input", stream_id, sink_name], stderr=subprocess.DEVNULL)
        return True
    except Exception as e:
        print(f"[bt-audio-switcher] Erro ao definir default sink para {sink_name}: {e}", file=sys.stderr, flush=True)
        return False


class AudioSwitcherDaemon:
    def __init__(self, bus):
        self.bus = bus
        self.bt_connected = False
        self.bt_mac = TARGET_DEVICE_MAC
        self.bt_retry_timer_id = None

        self.g733_connected = False
        self.g733_fd = None
        self.g733_watch_id = None
        self.g733_adc_feat_idx = None
        self.g733_offline_timer_id = None

    def is_target_bluez_device(self, path, dev_props=None):
        path_mac = extract_mac_from_bluez_path(path)
        if TARGET_DEVICE_MAC:
            if TARGET_DEVICE_MAC.lower() == path_mac.lower():
                return True, path_mac
            mac_path = TARGET_DEVICE_MAC.replace(":", "_").lower()
            if mac_path in str(path).lower():
                return True, path_mac or TARGET_DEVICE_MAC
        try:
            if dev_props is None:
                obj = self.bus.get_object("org.bluez", path)
                props_iface = dbus.Interface(obj, "org.freedesktop.DBus.Properties")
                dev_props = props_iface.GetAll("org.bluez.Device1")
            name = str(dev_props.get("Name", "") or dev_props.get("Alias", ""))
            addr = str(dev_props.get("Address", "") or path_mac)
            if TARGET_DEVICE_NAME and TARGET_DEVICE_NAME.lower() in name.lower():
                return True, addr
        except Exception:
            pass
        return False, ""

    def _cancel_bt_retry(self):
        if self.bt_retry_timer_id is not None:
            GLib.source_remove(self.bt_retry_timer_id)
            self.bt_retry_timer_id = None

    def _switch_to_fallback_or_other(self, exclude=""):
        sinks = list_sinks()
        if exclude != "bt" and self.bt_connected:
            bt_sink = match_bluez_sink(sinks, self.bt_mac, TARGET_DEVICE_NAME)
            if bt_sink:
                print(f"[bt-audio-switcher] Alternando saída para {TARGET_DEVICE_NAME}: {bt_sink}", flush=True)
                set_default_sink(bt_sink)
                return
        if exclude != "g733" and self.g733_connected:
            g733_sink = match_g733_sink(sinks)
            if g733_sink:
                print(f"[bt-audio-switcher] Alternando saída para Logitech G733: {g733_sink}", flush=True)
                set_default_sink(g733_sink)
                return
        fallback = select_fallback_sink(sinks)
        if fallback:
            set_default_sink(fallback)
            print(f"[bt-audio-switcher] Saída restaurada com sucesso para {fallback}", flush=True)
        else:
            print("[bt-audio-switcher] Nenhum sink de fallback encontrado.", file=sys.stderr, flush=True)

    # --- Bluetooth (QCY H3S) ---

    def on_bt_connected(self, device_mac=""):
        self.bt_connected = True
        if device_mac:
            self.bt_mac = device_mac
        self._cancel_bt_retry()
        print(
            f"[bt-audio-switcher] {TARGET_DEVICE_NAME} ({self.bt_mac or 'MAC dinâmico'}) conectado! "
            "Aguardando nó de áudio PipeWire...",
            flush=True,
        )
        attempts = {"count": 0}

        def _try_switch():
            if not self.bt_connected:
                self.bt_retry_timer_id = None
                return False
            sinks = list_sinks()
            sink = match_bluez_sink(sinks, self.bt_mac, TARGET_DEVICE_NAME)
            if sink:
                print(f"[bt-audio-switcher] Sink Bluetooth detectado: {sink}. Definindo como padrão...", flush=True)
                set_default_sink(sink)
                self.bt_retry_timer_id = None
                return False
            attempts["count"] += 1
            if attempts["count"] >= 24:  # 12 segundos
                print(f"[bt-audio-switcher] Timeout aguardando sink para {TARGET_DEVICE_NAME}.", flush=True)
                self.bt_retry_timer_id = None
                return False
            return True

        # Tenta imediatamente e depois a cada 500ms sem bloquear o loop GLib
        if _try_switch():
            self.bt_retry_timer_id = GLib.timeout_add(500, _try_switch)

    def on_bt_disconnected(self):
        self.bt_connected = False
        self._cancel_bt_retry()
        print(f"[bt-audio-switcher] {TARGET_DEVICE_NAME} desconectado! Restaurando saída...", flush=True)
        GLib.timeout_add(500, lambda: (self._switch_to_fallback_or_other(exclude="bt"), False)[1])

    def on_bluez_properties_changed(self, interface, changed_properties, invalidated_properties=None, path=None):
        if interface != "org.bluez.Device1":
            return
        if "Connected" not in changed_properties:
            return
        is_connected = bool(changed_properties["Connected"])
        is_target, mac = self.is_target_bluez_device(path)
        if not is_target:
            return
        if is_connected:
            self.on_bt_connected(mac)
        else:
            self.on_bt_disconnected()

    def check_initial_bt_state(self):
        try:
            manager = dbus.Interface(self.bus.get_object("org.bluez", "/"), "org.freedesktop.DBus.ObjectManager")
            objects = manager.GetManagedObjects()
            for path, interfaces in objects.items():
                if "org.bluez.Device1" in interfaces:
                    dev = interfaces["org.bluez.Device1"]
                    is_target, mac = self.is_target_bluez_device(path, dev)
                    if is_target:
                        if mac:
                            self.bt_mac = mac
                        if dev.get("Connected", False):
                            print(f"[bt-audio-switcher] Inicial: {TARGET_DEVICE_NAME} já está conectado.", flush=True)
                            self.on_bt_connected(mac)
                        else:
                            print(f"[bt-audio-switcher] Inicial: {TARGET_DEVICE_NAME} desconectado.", flush=True)
                        break
        except Exception as e:
            print(f"[bt-audio-switcher] Erro ao checar estado inicial Bluetooth: {e}", file=sys.stderr, flush=True)

    # --- Logitech G733 (HID++ 2.0 via /dev/hidraw*) ---

    def _close_g733_hidraw(self):
        if self.g733_watch_id is not None:
            GLib.source_remove(self.g733_watch_id)
            self.g733_watch_id = None
        if self.g733_fd is not None:
            try:
                os.close(self.g733_fd)
            except OSError:
                pass
            self.g733_fd = None
        self.g733_adc_feat_idx = None

    def _resolve_g733_adc_feature(self, fd):
        # Drena relatórios antigos
        while select.select([fd], [], [], 0.02)[0]:
            try:
                os.read(fd, 64)
            except OSError:
                break
        # HID++ 2.0 Root (0x00), func 0x00 (getFeature), sw_id=0x0A, feature=0x1F20
        req = bytes([HIDPP_REPORT_LONG, HIDPP_DEVICE_INDEX, 0x00, HIDPP_SW_ID, 0x1F, 0x20]) + bytes(14)
        os.write(fd, req)
        for _ in range(5):
            r, _, _ = select.select([fd], [], [], 0.5)
            if not r:
                break
            resp = os.read(fd, 64)
            if len(resp) >= 5 and resp[0] in (HIDPP_REPORT_SHORT, HIDPP_REPORT_LONG) and resp[2] == 0x00 and resp[3] == HIDPP_SW_ID:
                if resp[4] > 0:
                    return resp[4]
        return None

    def _open_g733_hidraw(self):
        if self.g733_fd is not None:
            return True
        dev_path = find_g733_hidraw_path()
        if not dev_path:
            return False
        try:
            fd = os.open(dev_path, os.O_RDWR | os.O_NONBLOCK)
        except OSError as e:
            print(f"[bt-audio-switcher] Sem permissão/erro ao abrir {dev_path} (G733): {e}", file=sys.stderr, flush=True)
            return False
        try:
            feat_idx = self._resolve_g733_adc_feature(fd)
        except OSError as e:
            os.close(fd)
            print(f"[bt-audio-switcher] Erro ao consultar HID++ do G733 em {dev_path}: {e}", file=sys.stderr, flush=True)
            return False
        if feat_idx is None:
            os.close(fd)
            return False
        self.g733_fd = fd
        self.g733_adc_feat_idx = feat_idx
        self.g733_watch_id = GLib.io_add_watch(
            self.g733_fd,
            GLib.IOCondition.IN | GLib.IOCondition.ERR | GLib.IOCondition.HUP,
            self._on_g733_hidraw_event,
        )
        print(
            f"[bt-audio-switcher] Logitech G733 monitorado em {dev_path} (HID++ 0x1F20 idx=0x{feat_idx:02x}).",
            flush=True,
        )
        return True

    def _cancel_g733_offline_timer(self):
        if self.g733_offline_timer_id is not None:
            GLib.source_remove(self.g733_offline_timer_id)
            self.g733_offline_timer_id = None

    def _handle_g733_state(self, is_online, initial=False):
        if is_online:
            self._cancel_g733_offline_timer()
            if not self.g733_connected:
                self.g733_connected = True
                sinks = list_sinks()
                sink = match_g733_sink(sinks)
                if sink:
                    prefix = "Inicial: " if initial else ""
                    print(
                        f"[bt-audio-switcher] {prefix}Logitech G733 ligado! Definindo sink padrão: {sink}",
                        flush=True,
                    )
                    set_default_sink(sink)
                else:
                    print("[bt-audio-switcher] Logitech G733 ligado, mas sink ALSA não encontrado.", file=sys.stderr, flush=True)
        else:
            if not self.g733_connected:
                return
            if self.g733_offline_timer_id is None:
                def _confirm_offline():
                    self.g733_offline_timer_id = None
                    if self.g733_connected:
                        self.g733_connected = False
                        print("[bt-audio-switcher] Logitech G733 desligado! Restaurando saída...", flush=True)
                        self._switch_to_fallback_or_other(exclude="g733")
                    return False

                self.g733_offline_timer_id = GLib.timeout_add_seconds(
                    G733_OFFLINE_DEBOUNCE_SEC,
                    _confirm_offline,
                )

    def _on_g733_hidraw_event(self, fd, condition):
        if condition & (GLib.IOCondition.ERR | GLib.IOCondition.HUP):
            print("[bt-audio-switcher] Dongle Logitech G733 desconectado (hidraw HUP/ERR).", flush=True)
            self._close_g733_hidraw()
            self._handle_g733_state(False)
            return False
        try:
            while True:
                packet = os.read(fd, 64)
                if not packet:
                    break
                state = parse_g733_adc_packet(packet, self.g733_adc_feat_idx)
                if state is not None:
                    self._handle_g733_state(state)
        except BlockingIOError:
            pass
        except OSError:
            self._close_g733_hidraw()
            self._handle_g733_state(False)
            return False
        return True

    def poll_g733_status(self, initial=False):
        if self.g733_fd is None:
            if not self._open_g733_hidraw():
                return True
        try:
            req = bytes([HIDPP_REPORT_LONG, HIDPP_DEVICE_INDEX, self.g733_adc_feat_idx, HIDPP_SW_ID]) + bytes(16)
            os.write(self.g733_fd, req)
            if initial:
                r, _, _ = select.select([self.g733_fd], [], [], 0.5)
                if r:
                    resp = os.read(self.g733_fd, 64)
                    state = parse_g733_adc_packet(resp, self.g733_adc_feat_idx)
                    if state is True:
                        self._handle_g733_state(True, initial=True)
                    else:
                        print("[bt-audio-switcher] Inicial: Logitech G733 desligado.", flush=True)
        except OSError:
            self._close_g733_hidraw()
            self._handle_g733_state(False)
        return True


def main():
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    daemon = AudioSwitcherDaemon(bus)

    bus.add_signal_receiver(
        daemon.on_bluez_properties_changed,
        signal_name="PropertiesChanged",
        dbus_interface="org.freedesktop.DBus.Properties",
        bus_name="org.bluez",
        path_keyword="path",
    )

    daemon.check_initial_bt_state()
    daemon.poll_g733_status(initial=True)
    GLib.timeout_add_seconds(G733_POLL_INTERVAL_SEC, daemon.poll_g733_status)

    print(
        f"[bt-audio-switcher] Monitorando conexões de áudio para {TARGET_DEVICE_NAME} e Logitech G733...",
        flush=True,
    )

    loop = GLib.MainLoop()
    try:
        loop.run()
    except KeyboardInterrupt:
        pass
    finally:
        daemon._close_g733_hidraw()


if __name__ == "__main__":
    main()
