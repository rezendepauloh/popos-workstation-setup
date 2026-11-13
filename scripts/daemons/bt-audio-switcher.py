#!/usr/bin/env python3
"""
Daemon para Comutação Inteligente de Dispositivos de Áudio (Bluetooth / QCY H3S).
Monitora conexões Bluetooth no D-Bus (BlueZ) e no PulseAudio/PipeWire.
Ao conectar o fone QCY H3S, define-o como saída de áudio padrão automaticamente.
Ao desconectar, restaura imediatamente para o sink padrão (caixas de som / áudio interno).
"""

import sys
import os
import subprocess
import time
import dbus
from dbus.mainloop.glib import DBusGMainLoop
import gi
from gi.repository import GLib

TARGET_DEVICE_MAC = os.environ.get("MAC_QCY_H3S", "").strip()
TARGET_DEVICE_NAME = os.environ.get("BT_AUDIO_DEVICE_NAME", "QCY H3S").strip()
FALLBACK_SINK = "alsa_output.pci-0000_00_1f.3.analog-stereo"

def is_target_bluez_device(bus, path, dev_props=None):
    if TARGET_DEVICE_MAC:
        mac_path = TARGET_DEVICE_MAC.replace(":", "_").lower()
        if mac_path in path.lower():
            return True
    try:
        if dev_props is None:
            obj = bus.get_object("org.bluez", path)
            props_iface = dbus.Interface(obj, "org.freedesktop.DBus.Properties")
            dev_props = props_iface.GetAll("org.bluez.Device1")
        name = str(dev_props.get("Name", "") or dev_props.get("Alias", ""))
        if TARGET_DEVICE_NAME and TARGET_DEVICE_NAME.lower() in name.lower():
            return True
    except Exception:
        pass
    return False

def get_current_default_sink():
    try:
        res = subprocess.run(["pactl", "get-default-sink"], capture_output=True, text=True, check=True)
        return res.stdout.strip()
    except Exception:
        return ""

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
        print(f"[bt-audio-switcher] Erro ao definir default sink para {sink_name}: {e}", file=sys.stderr)
        return False

def on_device_connected():
    print(f"[bt-audio-switcher] {TARGET_DEVICE_NAME} conectado! Aguardando nó de áudio PipeWire...", flush=True)
    # Tenta por até 10 segundos encontrar o sink bluetooth
    for _ in range(20):
        time.sleep(0.5)
        sinks = list_sinks()
        # Procura por sink bluez com o MAC ou nome correspondente
        mac_clean = TARGET_DEVICE_MAC.replace(":", "_") if TARGET_DEVICE_MAC else ""
        name_token = TARGET_DEVICE_NAME.lower().replace(" ", "_")
        for s in sinks:
            if "bluez" in s and ((mac_clean and mac_clean.lower() in s.lower()) or name_token in s.lower()):
                print(f"[bt-audio-switcher] Sink Bluetooth detectado: {s}. Definindo como padrão...", flush=True)
                set_default_sink(s)
                return
    print(f"[bt-audio-switcher] Timeout aguardando sink para {TARGET_DEVICE_NAME}.", flush=True)

def on_device_disconnected():
    print(f"[bt-audio-switcher] {TARGET_DEVICE_NAME} desconectado! Restaurando saída para caixas de som...", flush=True)
    time.sleep(0.5)
    sinks = list_sinks()
    if FALLBACK_SINK in sinks:
        set_default_sink(FALLBACK_SINK)
        print(f"[bt-audio-switcher] Saída restaurada com sucesso para {FALLBACK_SINK}", flush=True)
    else:
        # Pega o primeiro sink analógico ou não-hdmi se o fallback não existir
        for s in sinks:
            if "analog" in s:
                set_default_sink(s)
                print(f"[bt-audio-switcher] Fallback genérico restaurado: {s}", flush=True)
                break

def properties_changed(interface, changed_properties, invalidated_properties, path):
    if interface != "org.bluez.Device1":
        return
    if "Connected" in changed_properties:
        is_connected = bool(changed_properties["Connected"])
        bus = dbus.SystemBus()
        if is_target_bluez_device(bus, path):
            if is_connected:
                on_device_connected()
            else:
                on_device_disconnected()

def check_initial_state(bus):
    try:
        manager = dbus.Interface(bus.get_object('org.bluez', '/'), 'org.freedesktop.DBus.ObjectManager')
        objects = manager.GetManagedObjects()
        for path, interfaces in objects.items():
            if 'org.bluez.Device1' in interfaces:
                dev = interfaces['org.bluez.Device1']
                if is_target_bluez_device(bus, path, dev):
                    if dev.get('Connected', False):
                        print(f"[bt-audio-switcher] Inicial: {TARGET_DEVICE_NAME} já está conectado.", flush=True)
                        on_device_connected()
                    else:
                        print(f"[bt-audio-switcher] Inicial: {TARGET_DEVICE_NAME} desconectado.", flush=True)
                    break
    except Exception as e:
        print(f"[bt-audio-switcher] Erro ao checar estado inicial: {e}", file=sys.stderr)

def main():
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    
    bus.add_signal_receiver(
        properties_changed,
        signal_name="PropertiesChanged",
        dbus_interface="org.freedesktop.DBus.Properties",
        path_keyword="path"
    )

    check_initial_state(bus)
    print(f"[bt-audio-switcher] Monitorando conexões de áudio para {TARGET_DEVICE_NAME}...", flush=True)

    loop = GLib.MainLoop()
    try:
        loop.run()
    except KeyboardInterrupt:
        pass

if __name__ == "__main__":
    main()
