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
        cls.rclone_indicator = load_module_from_path(
            "rclone_cloud_indicator",
            os.path.join(DAEMONS_DIR, "rclone-cloud-indicator.py")
        )
        cls.onedrive_indicator = load_module_from_path(
            "onedrive_indicator",
            os.path.join(DAEMONS_DIR, "onedrive-indicator.py")
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

    def test_04_rclone_indicator_profiles_and_formatting(self):
        """Valida os perfis do rclone-cloud-indicator.py e formatação de bytes."""
        profiles = self.rclone_indicator.CLOUD_PROFILES
        self.assertEqual(set(profiles.keys()), {'gdrive-pessoal', 'onedrive-pessoal', 'mega-pessoal'})
        self.assertEqual(profiles['gdrive-pessoal']['mount_service'], 'gdrive-pessoal.service')
        self.assertEqual(profiles['onedrive-pessoal']['mount_service'], 'onedrive-pessoal.service')
        self.assertEqual(profiles['mega-pessoal']['mount_service'], 'mega-pessoal.service')

        self.assertEqual(self.rclone_indicator.format_bytes(0), '0 B')
        self.assertEqual(self.rclone_indicator.format_bytes(512), '512 B')
        self.assertEqual(self.rclone_indicator.format_bytes(1024), '1.0 KB')
        self.assertEqual(self.rclone_indicator.format_bytes(1024 ** 3 * 2.5), '2.5 GB')

        args = self.rclone_indicator.parse_args(['--profile', 'mega-pessoal'])
        self.assertEqual(args.profile, 'mega-pessoal')

    def test_05_rclone_indicator_mountpoint_and_vfs_parsing(self):
        """Testa detecção de mountpoint em /proc/mounts simulado, df e logs VFS do rclone."""
        with tempfile.TemporaryDirectory() as tmpdir:
            mounted_dir = os.path.join(tmpdir, 'GoogleDrive_Pessoal')
            spaced_dir = os.path.join(tmpdir, 'My Cloud')
            unmounted_dir = os.path.join(tmpdir, 'Mega_Pessoal')
            os.makedirs(mounted_dir)
            os.makedirs(spaced_dir)
            os.makedirs(unmounted_dir)

            fake_mounts = os.path.join(tmpdir, 'mounts')
            with open(fake_mounts, 'w', encoding='utf-8') as f:
                f.write(f"gdrive_pessoal: {mounted_dir} fuse.rclone rw,nosuid,nodev 0 0\n")
                f.write(f"other: {spaced_dir.replace(' ', r'\040')} fuse.rclone rw 0 0\n")

            self.assertTrue(self.rclone_indicator.is_mountpoint_active(mounted_dir, mounts_file=fake_mounts))
            self.assertTrue(self.rclone_indicator.is_mountpoint_active(spaced_dir, mounts_file=fake_mounts))
            self.assertFalse(self.rclone_indicator.is_mountpoint_active(unmounted_dir, mounts_file=fake_mounts))

            # Testa parser de log VFS
            sample_line = "INFO  : Google drive root '': vfs cache: cleaned: objects 12 (was 14) in use 1, to upload 3, uploading 2, total size 45.2Mi (was 50Mi)"
            parsed = self.rclone_indicator.parse_vfs_journal_line(sample_line)
            self.assertEqual(parsed, {
                'objects': 12,
                'in_use': 1,
                'to_upload': 3,
                'uploading': 2,
                'total_size_str': '45.2Mi',
            })
            self.assertIsNone(self.rclone_indicator.parse_vfs_journal_line("unrelated log line"))

            # Testa get_vfs_cache_info com diretório local e journalctl mockado
            vfs_remote_dir = os.path.join(tmpdir, 'vfs', 'gdrive_pessoal')
            os.makedirs(vfs_remote_dir)
            with open(os.path.join(vfs_remote_dir, 'cached.bin'), 'wb') as f:
                f.write(b'x' * 2048)

            fake_journal = MagicMock(returncode=0, stdout=sample_line + "\n")
            with patch.object(self.rclone_indicator.subprocess, 'run', return_value=fake_journal):
                info = self.rclone_indicator.get_vfs_cache_info(
                    'gdrive_pessoal',
                    'gdrive-pessoal.service',
                    cache_base=os.path.join(tmpdir, 'vfs'),
                )
            self.assertEqual(info['cache_bytes'], 2048)
            self.assertEqual(info['cache_files'], 1)
            self.assertEqual(info['to_upload'], 3)
            self.assertEqual(info['uploading'], 2)

            # Testa get_mount_space_info com saída mockada do df
            fake_df = MagicMock(
                returncode=0,
                stdout="      1B-blocks         Used        Avail Use%\n53687091200 4294967296 49392123904   8%\n",
            )
            with patch.object(self.rclone_indicator.subprocess, 'run', return_value=fake_df):
                space = self.rclone_indicator.get_mount_space_info(mounted_dir)
            self.assertEqual(space, {
                'total': 53687091200,
                'used': 4294967296,
                'avail': 49392123904,
                'pcent': '8%',
            })

    def test_06_onedrive_indicator_sync_helpers_and_windows_scripts(self):
        """Valida parse_winapps_conf, leitura/formatação de status e scripts Windows do OneDrive MPMS."""
        mod = self.onedrive_indicator

        # Verifica presença dos scripts silenciosos do lado Windows
        winapps_util_dir = os.path.join(ROOT_DIR, 'util', 'winapps')
        self.assertTrue(os.path.isfile(os.path.join(winapps_util_dir, 'sync_onedrive.ps1')))
        self.assertTrue(os.path.isfile(os.path.join(winapps_util_dir, 'sync_onedrive.vbs')))

        with tempfile.TemporaryDirectory() as tmpdir:
            conf_file = os.path.join(tmpdir, 'winapps.conf')
            with open(conf_file, 'w', encoding='utf-8') as f:
                f.write('# comment\nRDP_USER="winapps"\nRDP_PASS=\'secret123\'\nRDP_IP=127.0.0.1\nRDP_PORT="3389"\n')

            parsed = mod.parse_winapps_conf(conf_file)
            self.assertEqual(parsed['RDP_USER'], 'winapps')
            self.assertEqual(parsed['RDP_PASS'], 'secret123')
            self.assertEqual(parsed['RDP_IP'], '127.0.0.1')
            self.assertEqual(parsed['RDP_PORT'], '3389')

            status_file = os.path.join(tmpdir, 'onedrive_sync_status.json')
            with open(status_file, 'w', encoding='utf-8-sig') as f:
                f.write('{"state":"syncing","message":"Sincronizando...","files_to_upload":2,"files_to_download":1}')

            status_data = mod.read_sync_status(status_file)
            self.assertEqual(status_data['state'], 'syncing')
            self.assertEqual(mod.format_sync_status_label(status_data), '⏳ OneDrive MPMS: Sincronizando (↑2 ↓1)...')
            self.assertEqual(
                mod.format_sync_status_label({'state': 'starting'}),
                '⏳ OneDrive MPMS: Iniciando OneDrive...',
            )
            self.assertEqual(
                mod.format_sync_status_label({'state': 'completed'}),
                '● OneDrive MPMS: Sincronizado',
            )
            self.assertIn(
                'Falha',
                mod.format_sync_status_label({'state': 'error', 'message': 'Falha X'}),
            )

            # Testa ensure_sync_scripts copiando do repositório para um diretório vazio
            shared_dir = os.path.join(tmpdir, 'Compartilhado_VM')
            self.assertTrue(mod.ensure_sync_scripts(shared_dir))
            self.assertTrue(os.path.isfile(os.path.join(shared_dir, 'sync_onedrive.ps1')))
            self.assertTrue(os.path.isfile(os.path.join(shared_dir, 'sync_onedrive.vbs')))


if __name__ == '__main__':
    unittest.main()

