# -*- coding: utf-8 -*-
"""
Testes de Integração: Orquestrador (setup_popos.sh), Módulos e Configuração do Kando.
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
SETUP_SH = os.path.join(ROOT_DIR, 'setup_popos.sh')
SCRIPTS_DIR = os.path.join(ROOT_DIR, 'scripts')
DAEMONS_DIR = os.path.join(SCRIPTS_DIR, 'daemons')


class TestOrchestratorAndModules(unittest.TestCase):
    """Testa a integração do setup_popos.sh e regras críticas dos módulos."""

    def test_01_orchestrator_help_flag_runs_without_sudo(self):
        """'./setup_popos.sh --help' deve executar sem exigir sudo e exibir instruções de uso."""
        res = subprocess.run([SETUP_SH, '--help'], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)
        self.assertIn("Uso:", res.stdout)
        self.assertIn("--repair-ides", res.stdout)
        self.assertIn("--list", res.stdout)

    def test_02_orchestrator_list_flag_lists_all_modules(self):
        """'./setup_popos.sh --list' deve listar todos os módulos de 01 a 28."""
        res = subprocess.run([SETUP_SH, '--list'], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)
        for i in range(1, 29):
            prefix = f"{i:02d}_"
            self.assertIn(prefix, res.stdout, f"Módulo {prefix} deve aparecer na saída de --list")

    def test_03_orchestrator_modules_array_matches_scripts_directory(self):
        """Todos os scripts 01..28 em scripts/ devem estar declarados no array MODULES do setup_popos.sh."""
        with open(SETUP_SH, 'r', encoding='utf-8') as f:
            setup_content = f.read()

        match = re.search(r'MODULES=\(\s*(.*?)\s*\)', setup_content, re.DOTALL)
        self.assertIsNotNone(match, "Array MODULES=(...) não encontrado em setup_popos.sh")
        declared_modules = re.findall(r'"([^"]+\.sh)"', match.group(1))

        actual_files = sorted([
            os.path.basename(p)
            for p in glob.glob(os.path.join(SCRIPTS_DIR, '[0-9][0-9]_*.sh'))
            if os.path.basename(p) != '00_comum.sh'
        ])

        self.assertEqual(
            declared_modules,
            actual_files,
            "O array MODULES em setup_popos.sh deve corresponder 1:1 aos arquivos 01..28 em scripts/"
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
        self.assertIn('ForceAutoLogon', content)
        self.assertIn('UserAuthentication', content)
        self.assertIn('NoLockScreen', content)
        self.assertIn('fPromptForPassword', content)
        self.assertIn("{{.Action}}", content)
        self.assertNotIn("{{.Status}}", content)
        self.assertIn('onedrive-x86.desktop', content)
        self.assertIn('gio open smb://172.20.0.2/onedrive-mpms', content)
        self.assertIn('microsoft-onedrive.desktop', content)
        self.assertIn('winapps_windows11.remmina', content)
        self.assertIn('https://www.office.com/launch/onedrive?auth=2', content)

        autologon_bat = os.path.join(ROOT_DIR, 'util', 'winapps', 'setup_autologon.bat')
        self.assertTrue(os.path.isfile(autologon_bat), "util/winapps/setup_autologon.bat deve existir")
        with open(autologon_bat, 'r', encoding='utf-8') as f:
            bat_content = f.read()
        self.assertIn('AutoAdminLogon" /t REG_SZ /d "0"', bat_content)
        self.assertIn('delete "HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon" /v "ForceAutoLogon"', bat_content)
        self.assertIn('UserAuthentication" /t REG_DWORD /d 1', bat_content)
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

    def test_08_rclone_cloud_indicators_and_icons_configured(self):
        """Valida ícones dedicados, daemon unificado e serviços systemd dos indicadores Rclone."""
        for icon_name in ('google-drive.svg', 'onedrive-pessoal.svg', 'mega.svg'):
            svg_path = os.path.join(ROOT_DIR, 'config', 'icons', icon_name)
            self.assertTrue(os.path.isfile(svg_path), f"config/icons/{icon_name} deve existir")
            with open(svg_path, 'r', encoding='utf-8') as f:
                svg_content = f.read()
            self.assertIn('<svg', svg_content)

        indicator_script = os.path.join(DAEMONS_DIR, 'rclone-cloud-indicator.py')
        self.assertTrue(os.path.isfile(indicator_script), "scripts/daemons/rclone-cloud-indicator.py deve existir")
        self.assertTrue(os.access(indicator_script, os.X_OK), "rclone-cloud-indicator.py deve ter permissão +x")

        expected_services = {
            'gdrive-indicator.service': '--profile gdrive-pessoal',
            'onedrive-pessoal-indicator.service': '--profile onedrive-pessoal',
            'mega-indicator.service': '--profile mega-pessoal',
        }
        for svc_name, expected_flag in expected_services.items():
            svc_path = os.path.join(ROOT_DIR, 'config', 'systemd', 'user', svc_name)
            self.assertTrue(os.path.isfile(svc_path), f"config/systemd/user/{svc_name} deve existir")
            with open(svc_path, 'r', encoding='utf-8') as f:
                svc_content = f.read()
            self.assertIn('rclone-cloud-indicator.py', svc_content)
            self.assertIn(expected_flag, svc_content)
            self.assertIn('WantedBy=default.target', svc_content)

        rclone_script = os.path.join(SCRIPTS_DIR, '05_rclone_storage.sh')
        with open(rclone_script, 'r', encoding='utf-8') as f:
            rclone_content = f.read()
        self.assertIn('rclone-cloud-indicator.py', rclone_content)
        for svc_name in expected_services:
            self.assertIn(svc_name, rclone_content)
        for icon_base in ('google-drive', 'onedrive-pessoal', 'mega'):
            self.assertIn(icon_base, rclone_content)

    def test_09_smartcard_pkcs11_and_remmina_redirection_configured(self):
        """Valida suporte PC/SC, PKCS#11 (SafeNet/OpenSC/NSS) e redirecionamento Smartcard no Remmina."""
        mod23_path = os.path.join(SCRIPTS_DIR, '23_trabalho_remoto_vpn_rdp.sh')
        with open(mod23_path, 'r', encoding='utf-8') as f:
            content = f.read()

        for pkg in ('pcscd', 'pcsc-tools', 'libccid', 'opensc', 'opensc-pkcs11', 'libnss3-tools', 'p11-kit'):
            self.assertIn(pkg, content, f"Módulo 23 deve instalar o pacote {pkg}")

        self.assertIn('pcscd.socket', content)
        self.assertIn('p11-kit-proxy.so', content)
        self.assertIn('modutil', content)
        self.assertIn('sharesmartcard=1', content)
        self.assertNotIn('sharesmartcard=0', content)
        self.assertIn('libeTPkcs11.so', content)
        self.assertIn('safenet-etoken.module', content)

        mod19_path = os.path.join(SCRIPTS_DIR, '19_flatpak_permissions.sh')
        with open(mod19_path, 'r', encoding='utf-8') as f:
            mod19_content = f.read()
        self.assertIn('--socket=pcsc org.mozilla.firefox', mod19_content)


if __name__ == '__main__':
    unittest.main()

