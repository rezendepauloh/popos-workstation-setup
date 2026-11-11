# -*- coding: utf-8 -*-
"""
Testes de Integração: Orquestrador (setup_popos_v2.sh), Módulos e Configuração do Kando.
Verifica a coerência entre a lista MODULES do orquestrador e os arquivos em scripts/,
flags informativas (--help, --list) e garante as regras de configuração do Kando (como centered: false).
"""

import glob
import json
import os
import re
import subprocess
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SETUP_SH = os.path.join(ROOT_DIR, 'setup_popos_v2.sh')
SCRIPTS_DIR = os.path.join(ROOT_DIR, 'scripts')
DAEMONS_DIR = os.path.join(SCRIPTS_DIR, 'daemons')


class TestOrchestratorAndModules(unittest.TestCase):
    """Testa a integração do setup_popos_v2.sh e regras críticas dos módulos."""

    def test_01_orchestrator_help_flag_runs_without_sudo(self):
        """'./setup_popos_v2.sh --help' deve executar sem exigir sudo e exibir instruções de uso."""
        res = subprocess.run([SETUP_SH, '--help'], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)
        self.assertIn("Uso:", res.stdout)
        self.assertIn("--repair-ides", res.stdout)
        self.assertIn("--list", res.stdout)

    def test_02_orchestrator_list_flag_lists_all_modules(self):
        """'./setup_popos_v2.sh --list' deve listar todos os módulos de 01 a 28."""
        res = subprocess.run([SETUP_SH, '--list'], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)
        for i in range(1, 29):
            prefix = f"{i:02d}_"
            self.assertIn(prefix, res.stdout, f"Módulo {prefix} deve aparecer na saída de --list")

    def test_03_orchestrator_modules_array_matches_scripts_directory(self):
        """Todos os scripts 01..28 em scripts/ devem estar declarados no array MODULES do setup_popos_v2.sh."""
        with open(SETUP_SH, 'r', encoding='utf-8') as f:
            setup_content = f.read()

        match = re.search(r'MODULES=\(\s*(.*?)\s*\)', setup_content, re.DOTALL)
        self.assertIsNotNone(match, "Array MODULES=(...) não encontrado em setup_popos_v2.sh")
        declared_modules = re.findall(r'"([^"]+\.sh)"', match.group(1))

        actual_files = sorted([
            os.path.basename(p)
            for p in glob.glob(os.path.join(SCRIPTS_DIR, '[0-9][0-9]_*.sh'))
            if os.path.basename(p) != '00_comum.sh'
        ])

        self.assertEqual(
            declared_modules,
            actual_files,
            "O array MODULES em setup_popos_v2.sh deve corresponder 1:1 aos arquivos 01..28 em scripts/"
        )

    def test_04_all_numbered_modules_source_00_comum_and_check_flag(self):
        """Todos os módulos 01..28 devem importar 00_comum.sh e implementar FLAG_NAME / check_flag / set_flag."""
        for script_path in sorted(glob.glob(os.path.join(SCRIPTS_DIR, '[0-9][0-9]_*.sh'))):
            base = os.path.basename(script_path)
            if base == '00_comum.sh':
                continue
            with self.subTest(module=base):
                with open(script_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                self.assertIn('00_comum.sh', content, f"{base} deve fazer source do 00_comum.sh")
                self.assertIn('FLAG_NAME=', content, f"{base} deve definir FLAG_NAME")
                self.assertIn('check_flag', content, f"{base} deve verificar idempotência com check_flag")
                self.assertIn('set_flag', content, f"{base} deve gravar conclusão com set_flag")

    def test_05_kando_restore_disables_centered_mode_for_cosmic_wayland(self):
        """Garante que 13_kando_restore.sh configure centered=false e useFixedPosition=false (PR #1535)."""
        kando_script = os.path.join(SCRIPTS_DIR, '13_kando_restore.sh')
        with open(kando_script, 'r', encoding='utf-8') as f:
            content = f.read()

        self.assertIn('.menus[0].centered = false', content)
        self.assertIn('.menus[0].useFixedPosition = false', content)
        self.assertNotIn('.menus[0].centered = true', content)

        # Testa a transformação jq em um JSON de backup simulado
        sample_backup = json.dumps({"menus": [{"name": "Menu Paulo", "shortcut": "Ctrl+Space", "centered": True}]})
        res = subprocess.run(
            ['jq', '.menus[0].shortcut = "Control+Shift+F10" | .menus[0].centered = false | .menus[0].useFixedPosition = false'],
            input=sample_backup,
            capture_output=True,
            text=True
        )
        self.assertEqual(res.returncode, 0)
        parsed = json.loads(res.stdout)
        self.assertEqual(parsed['menus'][0]['shortcut'], 'Control+Shift+F10')
        self.assertFalse(parsed['menus'][0]['centered'])
        self.assertFalse(parsed['menus'][0]['useFixedPosition'])

    def test_06_winapps_office_onedrive_and_autologon_configured(self):
        """Garante que o módulo 26 e util/winapps configurem AutoLogon e integração direta do OneDrive no Nautilus."""
        winapps_script = os.path.join(SCRIPTS_DIR, '26_winapps_office.sh')
        with open(winapps_script, 'r', encoding='utf-8') as f:
            content = f.read()

        self.assertIn('setup_autologon.bat', content)
        self.assertIn('AutoAdminLogon', content)
        self.assertIn('NoLockScreen', content)
        self.assertIn('fPromptForPassword', content)
        self.assertIn('onedrive-x86.desktop', content)
        self.assertIn('gio open smb://172.20.0.2/onedrive-mpms', content)
        self.assertIn('microsoft-onedrive.desktop', content)
        self.assertIn('winapps_windows11.remmina', content)
        self.assertIn('https://www.office.com/launch/onedrive?auth=2', content)

        autologon_bat = os.path.join(ROOT_DIR, 'util', 'winapps', 'setup_autologon.bat')
        self.assertTrue(os.path.isfile(autologon_bat), "util/winapps/setup_autologon.bat deve existir")
        with open(autologon_bat, 'r', encoding='utf-8') as f:
            bat_content = f.read()
        self.assertIn('AutoAdminLogon', bat_content)
        self.assertIn('NoLockScreen', bat_content)
        self.assertIn('fPromptForPassword', bat_content)

    def test_07_onedrive_indicator_and_icons_configured(self):
        """Valida que o ícone oficial do OneDrive, o daemon de bandeja e o serviço systemd estão configurados."""
        svg_file = os.path.join(ROOT_DIR, 'util', 'winapps', 'onedrive.svg')
        self.assertTrue(os.path.isfile(svg_file), "util/winapps/onedrive.svg deve existir")

        indicator_script = os.path.join(DAEMONS_DIR, 'onedrive-indicator.py')
        self.assertTrue(os.path.isfile(indicator_script), "scripts/daemons/onedrive-indicator.py deve existir")
        self.assertTrue(os.access(indicator_script, os.X_OK), "onedrive-indicator.py deve ter permissão +x")
        with open(indicator_script, 'r', encoding='utf-8') as f:
            ind_content = f.read()
        self.assertIn('https://www.office.com/launch/onedrive?auth=2', ind_content)
        self.assertIn('winapps_windows11.remmina', ind_content)

        service_file = os.path.join(ROOT_DIR, 'config', 'systemd', 'user', 'onedrive-indicator.service')
        self.assertTrue(os.path.isfile(service_file), "config/systemd/user/onedrive-indicator.service deve existir")

        # Verifica menção no módulo 26 e favoritos do COSMIC Dock
        winapps_script = os.path.join(SCRIPTS_DIR, '26_winapps_office.sh')
        with open(winapps_script, 'r', encoding='utf-8') as f:
            content = f.read()
        self.assertIn('onedrive-indicator.py', content)
        self.assertIn('onedrive-indicator.service', content)
        self.assertIn('Icon=onedrive', content)

        dock_script = os.path.join(SCRIPTS_DIR, '15_cosmic_menu_dock.sh')
        with open(dock_script, 'r', encoding='utf-8') as f:
            dock_content = f.read()
        self.assertIn('onedrive-x86', dock_content)


if __name__ == '__main__':
    unittest.main()

