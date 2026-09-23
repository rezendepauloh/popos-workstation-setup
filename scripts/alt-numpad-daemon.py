#!/usr/bin/env python3
"""
alt-numpad-daemon.py - Suporte nativo a Alt Codes do Windows no Pop!_OS (COSMIC Desktop / Wayland)
Intercepta Alt Esquerdo pressionado + dígitos no teclado numérico (KP0..KP9)
e injeta o caractere Unicode correspondente ao soltar o Alt.
"""

import sys
import os
import time
import glob
import signal
import select
import logging
import evdev
from evdev import ecodes

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%H:%M:%S'
)
logger = logging.getLogger("alt-numpad")

# Mapeamento de Keycodes do Teclado Numérico para dígitos
KP_MAP = {
    ecodes.KEY_KP0: '0',
    ecodes.KEY_KP1: '1',
    ecodes.KEY_KP2: '2',
    ecodes.KEY_KP3: '3',
    ecodes.KEY_KP4: '4',
    ecodes.KEY_KP5: '5',
    ecodes.KEY_KP6: '6',
    ecodes.KEY_KP7: '7',
    ecodes.KEY_KP8: '8',
    ecodes.KEY_KP9: '9',
}

# Keycodes hexadecimais para sequência Ctrl+Shift+U
HEX_KEY_MAP = {
    '0': ecodes.KEY_0,
    '1': ecodes.KEY_1,
    '2': ecodes.KEY_2,
    '3': ecodes.KEY_3,
    '4': ecodes.KEY_4,
    '5': ecodes.KEY_5,
    '6': ecodes.KEY_6,
    '7': ecodes.KEY_7,
    '8': ecodes.KEY_8,
    '9': ecodes.KEY_9,
    'a': ecodes.KEY_A,
    'b': ecodes.KEY_B,
    'c': ecodes.KEY_C,
    'd': ecodes.KEY_D,
    'e': ecodes.KEY_E,
    'f': ecodes.KEY_F,
}

# Tabela explícita para compatibilidade 1:1 com Windows Alt Codes e símbolos especiais
ALT_CODES_OVERRIDE = {
    # Caracteres de Língua Portuguesa e Normas
    "167": "º",     # Alt + 167 no Windows PT-BR (Ordinal masculino)
    "166": "ª",     # Alt + 166 no Windows PT-BR (Ordinal feminino)
    "0167": "§",    # Alt + 0167 (Símbolo de parágrafo/seção)
    "0176": "°",    # Alt + 0176 (Grau)
    "0186": "º",    # Alt + 0186 (Ordinal masculino)
    "0170": "ª",    # Alt + 0170 (Ordinal feminino)
    "0153": "™",    # Alt + 0153 (Trademark)
    "0169": "©",    # Alt + 0169 (Copyright)
    "0174": "®",    # Alt + 0174 (Registered)
    "0151": "—",    # Alt + 0151 (Em dash / Travessão)
    "0150": "–",    # Alt + 0150 (En dash)
    "0149": "•",    # Alt + 0149 (Bullet)
    "0171": "«",    # Alt + 0171
    "0187": "»",    # Alt + 0187
    "0128": "€",    # Alt + 0128 (Euro)
    "7": "•",       # Alt + 7 (Bullet CP437)

    # Setas Clássicas do Windows (CP437)
    "24": "↑",      # Alt + 24 (Seta para cima)
    "25": "↓",      # Alt + 25 (Seta para baixo)
    "26": "→",      # Alt + 26 (Seta para a direita)
    "27": "←",      # Alt + 27 (Seta para a esquerda)
    "16": "►",      # Alt + 16 (Triângulo para a direita)
    "17": "◄",      # Alt + 17 (Triângulo para a esquerda)
    "30": "▲",      # Alt + 30 (Triângulo para cima)
    "31": "▼",      # Alt + 31 (Triângulo para baixo)
    "18": "↕",      # Alt + 18 (Seta vertical dupla)
    "29": "↔",      # Alt + 29 (Seta horizontal dupla)

    # Setas com Ponta Triangular (⭡ ⭢ ⭣ ⭠ - Unicode U+2B60..2B63)
    # Suporta tanto o código decimal Unicode quanto atalhos mnemônicos intuitivos (Alt + 888, etc ou Alt + 8,2,4,6)
    "11105": "⭡",   # Alt + 11105 (Unicode U+2B61)
    "11106": "⭢",   # Alt + 11106 (Unicode U+2B62)
    "11107": "⭣",   # Alt + 11107 (Unicode U+2B63)
    "11104": "⭠",   # Alt + 11104 (Unicode U+2B60)

    # Atalhos Mnemônicos baseados nas direções do teclado numérico (8=Cima, 2=Baixo, 4=Esquerda, 6=Direita)
    "88": "⭡",      # Alt + 88  ➔ ⭡ (Cima)
    "66": "⭢",      # Alt + 66  ➔ ⭢ (Direita)
    "22": "⭣",      # Alt + 22  ➔ ⭣ (Baixo)
    "44": "⭠",      # Alt + 44  ➔ ⭠ (Esquerda)

    # E atalhos rápidos de 3 dígitos para setas finas
    "8593": "↑",    # Alt + 8593
    "8595": "↓",    # Alt + 8595
    "8594": "→",    # Alt + 8594
    "8592": "←",    # Alt + 8592
    "888": "↑",     # Alt + 888 ➔ ↑
    "222": "↓",     # Alt + 222 ➔ ↓
    "666": "→",     # Alt + 666 ➔ →
    "444": "←",     # Alt + 444 ➔ ←

    # Símbolos matemáticos e utilitários frequentes
    "241": "±",     # Alt + 241
    "246": "÷",     # Alt + 246
    "251": "√",     # Alt + 251
    "252": "ⁿ",     # Alt + 252
    "253": "²",     # Alt + 253
    "0178": "²",    # Alt + 0178
    "0179": "³",    # Alt + 0179
    "0185": "¹",    # Alt + 0185
    "0188": "¼",    # Alt + 0188
    "0189": "½",    # Alt + 0189
    "0190": "¾",    # Alt + 0190
    "0150": "–",    # Alt + 0150
}

def decode_alt_code(code_str: str) -> str:
    """Decodifica um código Alt numérico seguindo a lógica do Windows CP1252 / CP850."""
    if code_str in ALT_CODES_OVERRIDE:
        return ALT_CODES_OVERRIDE[code_str]

    try:
        code = int(code_str)
    except ValueError:
        return ""

    if code_str.startswith('0'):
        # Windows ANSI (Windows-1252)
        try:
            return bytes([code]).decode('cp1252')
        except Exception:
            try:
                return chr(code)
            except Exception:
                return ""
    else:
        # Windows OEM (CP850 / CP437)
        try:
            return bytes([code]).decode('cp850')
        except Exception:
            try:
                return bytes([code]).decode('cp437')
            except Exception:
                try:
                    return chr(code)
                except Exception:
                    return ""

class AltNumpadManager:
    def __init__(self):
        self.uinput = None
        self.devices = {}      # dev_path -> InputDevice
        self.alt_pressed = False
        self.numpad_buffer = []
        self.non_numpad_key_hit = False
        self.init_uinput()

    def init_uinput(self):
        """Cria dispositivo virtual uinput para repasse e injeção de caracteres."""
        self.uinput = evdev.UInput(name="Alt-Numpad-Virtual-Keyboard")
        logger.info("Dispositivo virtual UInput inicializado com sucesso.")

    def emit_key(self, keycode: int, value: int):
        self.uinput.write(ecodes.EV_KEY, keycode, value)
        self.uinput.syn()

    def inject_unicode_char(self, char: str):
        """Injeta um caractere Unicode via atalho universal Ctrl+Shift+U + hex + Enter."""
        if not char:
            return

        hex_str = format(ord(char), 'x').lower()
        logger.info(f"Injetando caractere '{char}' (U+{hex_str.upper()})...")

        # 1. Pressiona Ctrl + Shift + U
        self.emit_key(ecodes.KEY_LEFTCTRL, 1)
        self.emit_key(ecodes.KEY_LEFTSHIFT, 1)
        self.emit_key(ecodes.KEY_U, 1)
        time.sleep(0.015)
        self.emit_key(ecodes.KEY_U, 0)
        self.emit_key(ecodes.KEY_LEFTSHIFT, 0)
        self.emit_key(ecodes.KEY_LEFTCTRL, 0)
        time.sleep(0.015)

        # 2. Digita os dígitos hexadecimais
        for ch in hex_str:
            kc = HEX_KEY_MAP.get(ch)
            if kc:
                self.emit_key(kc, 1)
                time.sleep(0.005)
                self.emit_key(kc, 0)
                time.sleep(0.005)

        # 3. Pressiona Enter para confirmar o caractere Unicode
        self.emit_key(ecodes.KEY_ENTER, 1)
        time.sleep(0.005)
        self.emit_key(ecodes.KEY_ENTER, 0)
        self.uinput.syn()

    def scan_keyboards(self):
        """Detecta teclados físicos reais ignorando virtuais."""
        current_paths = set(self.devices.keys())
        found_paths = set()

        for path in glob.glob('/dev/input/event*'):
            if path in current_paths:
                found_paths.add(path)
                continue
            try:
                dev = evdev.InputDevice(path)
                # Ignora o próprio dispositivo uinput ou virtuais ou mouses
                if "Alt-Numpad" in dev.name or "Espanso" in dev.name or "libvirtualhid" in dev.name:
                    continue
                caps = dev.capabilities()
                # Não intercepta mouses (dispositivos com movimento relativo EV_REL)
                if ecodes.EV_REL in caps:
                    continue
                if ecodes.EV_KEY in caps:
                    keys = caps[ecodes.EV_KEY]
                    # Precisa conter LeftAlt e teclas do Numpad
                    if ecodes.KEY_LEFTALT in keys and ecodes.KEY_KP1 in keys:
                        dev.grab()
                        self.devices[path] = dev
                        found_paths.add(path)
                        logger.info(f"Teclado físico capturado: {dev.name} ({path})")
            except Exception as e:
                pass

        # Remove dispositivos desconectados
        for removed in (current_paths - found_paths):
            try:
                self.devices[removed].ungrab()
            except Exception:
                pass
            del self.devices[removed]
            logger.info(f"Dispositivo desconectado: {removed}")

    def handle_event(self, event):
        if event.type != ecodes.EV_KEY:
            # Repassa eventos de sincronização ou outros diretamente
            self.uinput.write(event.type, event.code, event.value)
            self.uinput.syn()
            return

        keycode = event.code
        value = event.value  # 0 = up, 1 = down, 2 = hold

        # 1. Pressionamento do Alt Esquerdo (KEY_LEFTALT)
        if keycode == ecodes.KEY_LEFTALT:
            if value == 1:
                self.alt_pressed = True
                self.numpad_buffer = []
                self.non_numpad_key_hit = False
                # Não repassa o Alt para o sistema ainda; aguarda ver se é um Alt Code
                return
            elif value == 0:
                was_alt_pressed = self.alt_pressed
                self.alt_pressed = False

                if self.numpad_buffer and not self.non_numpad_key_hit:
                    # Finalizou um Alt Code com sucesso!
                    code_str = "".join(self.numpad_buffer)
                    char = decode_alt_code(code_str)
                    logger.info(f"Alt Code detectado: Alt + {code_str} -> '{char}'")
                    self.numpad_buffer = []
                    if char:
                        self.inject_unicode_char(char)
                    return
                else:
                    # Foi um Alt comum solto (sem dígitos numpad)
                    self.numpad_buffer = []
                    if not self.non_numpad_key_hit:
                        # Emite clique rápido de Alt para foco de menu se desejado, ou limpa
                        self.emit_key(ecodes.KEY_LEFTALT, 1)
                        time.sleep(0.002)
                        self.emit_key(ecodes.KEY_LEFTALT, 0)
                    else:
                        # Apenas solta o Alt virtual que já havia sido repassado
                        self.emit_key(ecodes.KEY_LEFTALT, 0)
                    return
            elif value == 2:
                # Hold de Alt
                return

        # 2. Enquanto Alt Esquerdo estiver mantido pressionado
        if self.alt_pressed:
            if keycode in KP_MAP:
                if value == 1:  # Down no numpad
                    digit = KP_MAP[keycode]
                    self.numpad_buffer.append(digit)
                    logger.debug(f"Dígito capturado: {digit} (Buffer atual: {''.join(self.numpad_buffer)})")
                # Intercepta e não repassa dígitos do numpad para o sistema operacional!
                return
            else:
                # O usuário apertou uma tecla que NÃO é do numpad (ex: Alt+Tab, Alt+F4, Alt+letras)
                if not self.non_numpad_key_hit:
                    self.non_numpad_key_hit = True
                    self.numpad_buffer = []
                    # Envia o Alt que estava represado para a aplicação receber o atalho normalmente
                    self.emit_key(ecodes.KEY_LEFTALT, 1)
                # Repassa a tecla atual
                self.emit_key(keycode, value)
                return

        # 3. Demais teclas com Alt solto: Repasse transparente 1:1
        self.emit_key(keycode, value)

    def run(self):
        logger.info("Daemon Alt-Numpad iniciado e em execução.")
        last_scan = 0

        while True:
            now = time.time()
            if now - last_scan > 5.0 or not self.devices:
                self.scan_keyboards()
                last_scan = now

            if not self.devices:
                time.sleep(1.0)
                continue

            r, _, _ = select.select(list(self.devices.values()), [], [], 2.0)
            for dev in r:
                try:
                    for event in dev.read():
                        self.handle_event(event)
                except (OSError, evdev.device.DeviceError):
                    logger.warning(f"Erro ao ler dispositivo {dev.path}. Reescaneando...")
                    try:
                        dev.ungrab()
                    except Exception:
                        pass
                    if dev.path in self.devices:
                        del self.devices[dev.path]

    def cleanup(self):
        logger.info("Encerrando e liberando dispositivos...")
        for dev in list(self.devices.values()):
            try:
                dev.ungrab()
            except Exception:
                pass
        if self.uinput:
            try:
                self.uinput.close()
            except Exception:
                pass

def main():
    manager = AltNumpadManager()

    def sig_handler(sig, frame):
        manager.cleanup()
        sys.exit(0)

    signal.signal(signal.SIGINT, sig_handler)
    signal.signal(signal.SIGTERM, sig_handler)

    try:
        manager.run()
    except Exception as e:
        logger.exception(f"Erro inesperado no daemon: {e}")
        manager.cleanup()
        sys.exit(1)

if __name__ == "__main__":
    main()
