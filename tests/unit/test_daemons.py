# -*- coding: utf-8 -*-
"""
Testes Unitários: Daemons Python e Patch Binário de Cedilha/Aspas
Testa a lógica de negócio do patch_cedilla_electron.py, alt-numpad-daemon.py e wacom-expresskeys-daemon.py
sem tocar em dispositivos /dev/input reais nem binários do sistema.
"""

import importlib.util
import os
import tempfile
import unittest
from unittest.mock import MagicMock, patch

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
DAEMONS_DIR = os.path.join(ROOT_DIR, 'scripts', 'daemons')


def load_module_from_path(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class TestDaemonsAndPatches(unittest.TestCase):
    """Valida a lógica dos utilitários em scripts/daemons/."""

    @classmethod
    def setUpClass(cls):
        cls.patcher = load_module_from_path(
            "patch_cedilla_electron",
            os.path.join(DAEMONS_DIR, "patch_cedilla_electron.py")
        )
        cls.alt_numpad = load_module_from_path(
            "alt_numpad_daemon",
            os.path.join(DAEMONS_DIR, "alt-numpad-daemon.py")
        )
        cls.wacom_daemon = load_module_from_path(
            "wacom_expresskeys_daemon",
            os.path.join(DAEMONS_DIR, "wacom-expresskeys-daemon.py")
        )

    def test_01_patch_cedilla_binary_and_idempotency(self):
        """Testa aplicação de bytes de cedilha/aspas em um binário mockado, criação de .orig e idempotência."""
        with tempfile.TemporaryDirectory() as tmpdir:
            fake_bin = os.path.join(tmpdir, "fake-electron-bin")
            # Constrói payload contendo todas as sequências originais que o Chromium usa
            original_payload = (
                b"HEADER_CHROMIUM_"
                + b"\x63\x00\x07\x01"                  # c -> ć
                + b"_MID_"
                + b"\x43\x00\x06\x01"                  # C -> Ć
                + b"_QUOTES_"
                + b"\x22\x00\xa8\x00\x27\x00\x44\x03"  # ¨ -> " (subtable)
                + b"\x08\x03\xa8\x00"                  # ¨ -> " (standalone)
                + b"\x27\x00\xb4\x00\x2c\x00\x1a\x20"  # '' -> '
                + b"_FOOTER"
            )
            with open(fake_bin, "wb") as f:
                f.write(original_payload)

            # 1ª Execução: deve aplicar o patch e criar backup .orig
            result1 = self.patcher.patch_binary(fake_bin)
            self.assertTrue(result1, "O primeiro patch deve retornar True.")
            self.assertTrue(os.path.exists(fake_bin + ".orig"), "Backup .orig deve ser criado.")

            with open(fake_bin, "rb") as f:
                patched_data = f.read()

            # Verifica que ć (07 01) virou ç (e7 00) e Ć (06 01) virou Ç (c7 00)
            self.assertIn(b"\x63\x00\xe7\x00", patched_data)
            self.assertIn(b"\x43\x00\xc7\x00", patched_data)
            self.assertNotIn(b"\x63\x00\x07\x01", patched_data)

            # 2ª Execução (Idempotência): deve reconhecer que já está aplicado e retornar True
            result2 = self.patcher.patch_binary(fake_bin)
            self.assertTrue(result2, "A segunda chamada idempotente deve retornar True.")

    def test_02_alt_numpad_decode_table_and_windows_codes(self):
        """Verifica se decode_alt_code resolve corretamente símbolos ABNT/Windows, setas e CP1252/CP850."""
        decode = self.alt_numpad.decode_alt_code
        # Símbolos clássicos PT-BR e jurídicos
        self.assertEqual(decode("167"), "º")
        self.assertEqual(decode("166"), "ª")
        self.assertEqual(decode("0167"), "§")
        self.assertEqual(decode("0176"), "°")
        self.assertEqual(decode("0151"), "—")
        # Setas mnemônicas e clássicas
        self.assertEqual(decode("88"), "⭡")
        self.assertEqual(decode("66"), "⭢")
        self.assertEqual(decode("22"), "⭣")
        self.assertEqual(decode("44"), "⭠")
        self.assertEqual(decode("24"), "↑")
        self.assertEqual(decode("26"), "→")
        # Fallback CP1252 (ex: Alt+065 = 'A') e CP850 (ex: Alt+65 = 'A')
        self.assertEqual(decode("065"), "A")
        self.assertEqual(decode("65"), "A")
        # Entrada inválida
        self.assertEqual(decode("abc"), "")

    def test_03_wacom_touch_ring_wheel_zoom_logic(self):
        """Testa cálculo de rotação horária (Zoom In) e anti-horária (Zoom Out) + wrap-around (71 <-> 0)."""
        with patch.object(self.wacom_daemon.WacomExpressKeysDaemon, 'send_pulse') as mock_pulse:
            daemon = self.wacom_daemon.WacomExpressKeysDaemon()
            ecodes = self.wacom_daemon.ecodes

            # Toque inicial na posição 10
            daemon.handle_wheel(10)
            mock_pulse.assert_not_called()

            # Avança no sentido horário (10 -> 12) => Zoom In (Ctrl + =)
            daemon.last_wheel_time = 0.0
            daemon.handle_wheel(12)
            mock_pulse.assert_called_once_with([ecodes.KEY_LEFTCTRL, ecodes.KEY_EQUAL])

            # Gira no sentido anti-horário com wrap-around (1 -> 70) => Zoom Out (Ctrl + -)
            mock_pulse.reset_mock()
            daemon.last_wheel_val = 1
            daemon.last_wheel_time = 0.0
            daemon.handle_wheel(70)
            mock_pulse.assert_called_once_with([ecodes.KEY_LEFTCTRL, ecodes.KEY_MINUS])


if __name__ == '__main__':
    unittest.main()

