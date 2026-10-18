#!/usr/bin/env python3
"""
wacom-expresskeys-daemon.py - Mapeador nativo de ExpressKeys e Touch Ring para Wacom Intuos Pro
no Pop!_OS (COSMIC Desktop / Wayland).

Escuta eventos do nó de entrada 'Wacom Intuos Pro S Pad' (USB ou Bluetooth) via evdev
e injeta as combinações de teclas configuradas via /dev/uinput.
Suporta hotplug/reconexão automática Bluetooth/USB.
"""

import sys
import os
import time
import glob
import signal
import select
import logging
import evdev
from evdev import ecodes, UInput

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%H:%M:%S'
)
logger = logging.getLogger("wacom-expresskeys")

# Mapeamento declarativo dos botões físicos (ExpressKeys)
# Wacom Intuos Pro S (Modo Canhoto 180°):
# Botão 1 (BTN_0): Desfazer (Ctrl + Z)
# Botão 2 (BTN_1): Refazer (Ctrl + Shift + Z)
# Botão 3 (BTN_2): Pan / Canvas Hand Tool (Espaço)
# Botão 4 (BTN_3): Salvar (Ctrl + S)
# Botão 5 (BTN_4): Copiar (Ctrl + C)
# Botão 6 (BTN_5): Colar (Ctrl + V)
# Botão 7 (BTN_6 / Centro do anel): Livre / Espaço (ou ação auxiliar)

BUTTON_SHORTCUTS = {
    ecodes.BTN_0: [ecodes.KEY_LEFTCTRL, ecodes.KEY_Z],
    ecodes.BTN_1: [ecodes.KEY_LEFTCTRL, ecodes.KEY_LEFTSHIFT, ecodes.KEY_Z],
    ecodes.BTN_2: [ecodes.KEY_SPACE],
    ecodes.BTN_3: [ecodes.KEY_LEFTCTRL, ecodes.KEY_S],
    ecodes.BTN_4: [ecodes.KEY_LEFTCTRL, ecodes.KEY_C],
    ecodes.BTN_5: [ecodes.KEY_LEFTCTRL, ecodes.KEY_V],
}

# Teclas necessárias no UInput Virtual Keyboard
CAPABILITIES = {
    ecodes.EV_KEY: [
        ecodes.KEY_LEFTCTRL,
        ecodes.KEY_LEFTSHIFT,
        ecodes.KEY_Z,
        ecodes.KEY_S,
        ecodes.KEY_C,
        ecodes.KEY_V,
        ecodes.KEY_SPACE,
        ecodes.KEY_EQUAL,
        ecodes.KEY_MINUS,
    ]
}

def find_wacom_pad_device():
    """Localiza o nó /dev/input/event* correspondente ao Pad da Wacom."""
    for path in glob.glob('/dev/input/event*'):
        try:
            dev = evdev.InputDevice(path)
            if "Wacom" in dev.name and "Pad" in dev.name:
                return dev
        except (OSError, PermissionError):
            continue
    return None

class WacomExpressKeysDaemon:
    def __init__(self):
        self.running = True
        self.uinput = None
        self.pad_dev = None
        self.last_wheel_val = None
        self.last_wheel_time = 0.0

        signal.signal(signal.SIGINT, self._handle_signal)
        signal.signal(signal.SIGTERM, self._handle_signal)

    def _handle_signal(self, signum, frame):
        logger.info(f"Sinal {signum} recebido. Encerrando daemon...")
        self.running = False

    def init_uinput(self):
        try:
            self.uinput = UInput(CAPABILITIES, name="Wacom-Virtual-ExpressKeys")
            logger.info("Dispositivo virtual UInput 'Wacom-Virtual-ExpressKeys' criado.")
        except Exception as e:
            logger.error(f"Erro ao criar UInput virtual: {e}")
            sys.exit(1)

    def emit_combo(self, keys, press=True):
        """Pressiona ou solta uma sequência de teclas simultâneas."""
        val = 1 if press else 0
        if press:
            for k in keys:
                self.uinput.write(ecodes.EV_KEY, k, 1)
        else:
            for k in reversed(keys):
                self.uinput.write(ecodes.EV_KEY, k, 0)
        self.uinput.syn()

    def send_pulse(self, keys, delay=0.02):
        """Emite pressionamento seguido de liberação de teclas."""
        self.emit_combo(keys, press=True)
        time.sleep(delay)
        self.emit_combo(keys, press=False)

    def handle_wheel(self, current_val):
        """Processa a rotação do Touch Ring (valores absolutos 0..71 ou -1 quando solto)."""
        now = time.time()
        if current_val < 0 or current_val > 71:
            self.last_wheel_val = None
            return

        if self.last_wheel_val is not None:
            # Throttle para não disparar centenas de zooms por segundo
            if (now - self.last_wheel_time) < 0.035:
                return

            diff = current_val - self.last_wheel_val
            # Ajuste de wrap-around (71 -> 0 ou 0 -> 71)
            if diff > 35:
                diff -= 72
            elif diff < -35:
                diff += 72

            if diff > 0:
                # Sentido horário -> Zoom In (Ctrl + +)
                logger.debug("Touch Ring: Zoom In")
                self.send_pulse([ecodes.KEY_LEFTCTRL, ecodes.KEY_EQUAL])
                self.last_wheel_time = now
            elif diff < 0:
                # Sentido anti-horário -> Zoom Out (Ctrl + -)
                logger.debug("Touch Ring: Zoom Out")
                self.send_pulse([ecodes.KEY_LEFTCTRL, ecodes.KEY_MINUS])
                self.last_wheel_time = now

        self.last_wheel_val = current_val

    def run(self):
        self.init_uinput()

        while self.running:
            self.pad_dev = find_wacom_pad_device()
            if not self.pad_dev:
                logger.info("Wacom Pad não detectado. Aguardando conexão Bluetooth/USB...")
                time.sleep(3)
                continue

            logger.info(f"Conectado ao dispositivo: {self.pad_dev.name} ({self.pad_dev.path})")
            try:
                # Grab para evitar que botões não tratados se comportem como cliques aleatórios
                try:
                    self.pad_dev.grab()
                except OSError:
                    pass

                while self.running:
                    r, _, _ = select.select([self.pad_dev.fd], [], [], 1.0)
                    if not r:
                        continue

                    for event in self.pad_dev.read():
                        if event.type == ecodes.EV_KEY:
                            if event.code in BUTTON_SHORTCUTS:
                                keys = BUTTON_SHORTCUTS[event.code]
                                if event.value == 1:
                                    logger.info(f"Botão {ecodes.BTN[event.code]} pressionado -> Ativando atalho")
                                    self.emit_combo(keys, press=True)
                                elif event.value == 0:
                                    logger.info(f"Botão {ecodes.BTN[event.code]} solto -> Liberando atalho")
                                    self.emit_combo(keys, press=False)

                        elif event.type == ecodes.EV_ABS and event.code == ecodes.ABS_WHEEL:
                            self.handle_wheel(event.value)

            except (OSError, evdev.device.DeviceDisconnectedError) as e:
                logger.warning(f"Dispositivo Wacom desconectado ou falha na leitura: {e}. Reconectando...")
                self.last_wheel_val = None
                time.sleep(2)

        if self.uinput:
            self.uinput.close()
        logger.info("Daemon encerrado com sucesso.")

if __name__ == "__main__":
    daemon = WacomExpressKeysDaemon()
    daemon.run()
