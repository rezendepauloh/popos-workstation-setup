# -*- coding: utf-8 -*-
"""
Testes de Integração do Workflow: Espanso, Kando e CopyQ.
Valida que as configurações, binários, daemons e scripts de integração
(menus.json, copyq.conf, chamar_espanso_acao, config default.yml do Espanso)
estão íntegros e funcionando adequadamente no Pop!_OS COSMIC Wayland.
"""

import json
import os
import shutil
import subprocess
import unittest

REAL_HOME = os.path.expanduser("~")
KANDO_CONFIG_FILE = os.path.join(REAL_HOME, ".config", "kando", "menus.json")
ESPANSO_CONFIG_DIR = os.path.join(REAL_HOME, ".config", "espanso")
COPYQ_CONFIG_FILE = os.path.join(REAL_HOME, ".config", "copyq", "copyq.conf")
CHAMAR_ESPANSO_BIN = os.path.join(REAL_HOME, ".local", "bin", "chamar_espanso_acao")
KANDO_BIN = os.path.join(REAL_HOME, ".local", "bin", "kando")
EDF_BIN = os.path.join(REAL_HOME, ".local", "bin", "edf")


class TestWorkflowEspansoKandoCopyQ(unittest.TestCase):
    """Testa a integridade da pilha de automação de produtividade: Kando -> Espanso -> CopyQ."""

    def test_01_kando_menus_json_valid_and_has_clean_icons(self):
        """Garante que menus.json existe, é JSON válido e não contém ícones corrompidos ('?')."""
        if not os.path.exists(KANDO_CONFIG_FILE):
            self.skipTest(f"Arquivo {KANDO_CONFIG_FILE} ainda não criado no ambiente.")

        with open(KANDO_CONFIG_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)

        self.assertIn("menus", data)
        menu_paulo = data["menus"][0]

        # Garante atalho e que centered/useFixedPosition são false (COSMIC Wayland fix)
        self.assertFalse(menu_paulo.get("centered", False))
        self.assertFalse(menu_paulo.get("useFixedPosition", False))

        # Percorre a árvore e verifica que nenhum ícone possui valor '?' ou vazio
        def assert_valid_icons(node):
            name = node.get("name", "")
            icon = node.get("icon")
            if icon is not None:
                self.assertNotEqual(icon, "?", f"Nó '{name}' possui ícone inválido '?'")
            for child in node.get("children", []):
                assert_valid_icons(child)

        assert_valid_icons(menu_paulo.get("root", {}))

    def test_02_kando_cosmic_vertical_workspaces_mapping(self):
        """Verifica se os atalhos de workspace no Kando estão configurados para Up (Anterior, 0°) e Down (Próximo, 180°)."""
        if not os.path.exists(KANDO_CONFIG_FILE):
            self.skipTest(f"Arquivo {KANDO_CONFIG_FILE} ainda não criado.")

        with open(KANDO_CONFIG_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)

        nodes = {}
        def collect_nodes(node):
            if "name" in node:
                nodes[node["name"]] = node
            for child in node.get("children", []):
                collect_nodes(child)

        collect_nodes(data["menus"][0].get("root", {}))

        if "Espaço de Trabalho Anterior" in nodes:
            prev_ws = nodes["Espaço de Trabalho Anterior"]
            self.assertEqual(prev_ws.get("angle"), 0)
            actions = prev_ws.get("selectWorkflow", {}).get("actions", [])
            hotkeys = [a.get("hotkey") for a in actions if a.get("type") == "simulate-hotkey"]
            self.assertIn("MetaLeft+ControlLeft+ArrowUp", hotkeys)

        if "Próximo Espaço de Trabalho" in nodes:
            next_ws = nodes["Próximo Espaço de Trabalho"]
            self.assertEqual(next_ws.get("angle"), 180)
            actions = next_ws.get("selectWorkflow", {}).get("actions", [])
            hotkeys = [a.get("hotkey") for a in actions if a.get("type") == "simulate-hotkey"]
            self.assertIn("MetaLeft+ControlLeft+ArrowDown", hotkeys)

    def test_03_espanso_config_and_evdev_backend(self):
        """Valida que a configuração do Espanso para Wayland (linux.yml ou default.yml) está com backend EVDEV e layout US-Intl."""
        linux_yml = os.path.join(ESPANSO_CONFIG_DIR, "config", "linux.yml")
        default_yml = os.path.join(ESPANSO_CONFIG_DIR, "config", "default.yml")
        
        target_file = linux_yml if os.path.exists(linux_yml) else default_yml
        if not os.path.exists(target_file):
            self.skipTest("Arquivo de configuração do Espanso não encontrado.")

        with open(target_file, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("backend: EVDEV", content)
        self.assertIn("layout: \"us\"", content)
        self.assertIn("variant: \"intl\"", content)

    def test_04_chamar_espanso_acao_executable_and_actions(self):
        """Valida a existência e sintaxe Bash do assistente central chamar_espanso_acao."""
        if not os.path.exists(CHAMAR_ESPANSO_BIN):
            self.skipTest(f"Binário {CHAMAR_ESPANSO_BIN} não encontrado.")

        self.assertTrue(os.access(CHAMAR_ESPANSO_BIN, os.X_OK), "chamar_espanso_acao deve ser executável (+x)")

        # Validação de sintaxe bash com bash -n
        res = subprocess.run(["bash", "-n", CHAMAR_ESPANSO_BIN], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"Erro de sintaxe em {CHAMAR_ESPANSO_BIN}: {res.stderr}")

        with open(CHAMAR_ESPANSO_BIN, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("transporte_material)", content)
        self.assertIn("transporte_urbano)", content)
        self.assertIn("copyq", content)

    def test_05_copyq_configuration_present(self):
        """Valida que o CopyQ está configurado com monitoramento de clipboard e sem janelas invasivas."""
        if not os.path.exists(COPYQ_CONFIG_FILE):
            self.skipTest(f"Arquivo {COPYQ_CONFIG_FILE} não encontrado.")

        with open(COPYQ_CONFIG_FILE, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("check_clipboard=true", content)
        self.assertIn("copy_clipboard=true", content)


if __name__ == "__main__":
    unittest.main()
