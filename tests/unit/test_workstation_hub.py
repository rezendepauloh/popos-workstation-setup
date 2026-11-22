# -*- coding: utf-8 -*-
"""
Testes Unitários & Coerência: Workstation & Homelab Hub (Rust / libcosmic).
Valida integridade estrutural, catálogo 1:1 com scripts/, util/ e umbrelos-scripts,
metadados desktop (.desktop / SVG / justfile) e executa 'cargo test --test core_tests' quando disponível.
"""

import glob
import os
import re
import shutil
import subprocess
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
HUB_DIR = os.path.join(ROOT_DIR, "workstation-hub")
SCRIPTS_DIR = os.path.join(ROOT_DIR, "scripts")
CATALOG_RS = os.path.join(HUB_DIR, "src", "models", "catalog.rs")


class TestWorkstationHub(unittest.TestCase):
    """Valida a estrutura, catálogo e integração do projeto Rust workstation-hub."""

    def test_01_project_manifest_justfile_and_desktop_assets_exist(self):
        """Cargo.toml, justfile, .desktop, metainfo e ícone SVG devem existir e estar consistentes."""
        required_files = [
            os.path.join(HUB_DIR, "Cargo.toml"),
            os.path.join(HUB_DIR, "justfile"),
            os.path.join(HUB_DIR, "src", "main.rs"),
            os.path.join(HUB_DIR, "src", "lib.rs"),
            os.path.join(HUB_DIR, "src", "app.rs"),
            os.path.join(HUB_DIR, "res", "br.dev.rezendepauloh.WorkstationHub.desktop"),
            os.path.join(HUB_DIR, "res", "br.dev.rezendepauloh.WorkstationHub.metainfo.xml"),
            os.path.join(
                HUB_DIR,
                "res",
                "icons",
                "hicolor",
                "scalable",
                "apps",
                "br.dev.rezendepauloh.WorkstationHub.svg",
            ),
        ]
        for path in required_files:
            self.assertTrue(os.path.isfile(path), f"Arquivo obrigatório ausente: {path}")

        with open(
            os.path.join(HUB_DIR, "res", "br.dev.rezendepauloh.WorkstationHub.desktop"),
            "r",
            encoding="utf-8",
        ) as f:
            desktop = f.read()
        self.assertIn("Name=Workstation & Homelab Hub", desktop)
        self.assertIn("Exec=workstation-hub", desktop)
        self.assertIn("Icon=br.dev.rezendepauloh.WorkstationHub", desktop)
        self.assertIn("StartupWMClass=br.dev.rezendepauloh.WorkstationHub", desktop)

        # Valida também que todos os scripts referenciados em HOMELAB_UTIL_ACTIONS existem quando o repo irmão está presente
        homelab_dir = os.path.abspath(os.path.join(ROOT_DIR, "..", "umbrelos-scripts"))
        if os.path.isdir(homelab_dir):
            with open(CATALOG_RS, "r", encoding="utf-8") as cf:
                catalog_src = cf.read()
            for rel_hl in re.findall(r'rel_path:\s*"(scripts/[^"]+\.sh)"', catalog_src):
                self.assertTrue(
                    os.path.isfile(os.path.join(homelab_dir, rel_hl)),
                    f"Script Homelab referenciado no catálogo não encontrado: {rel_hl}",
                )

        with open(
            os.path.join(
                HUB_DIR,
                "res",
                "icons",
                "hicolor",
                "scalable",
                "apps",
                "br.dev.rezendepauloh.WorkstationHub.svg",
            ),
            "r",
            encoding="utf-8",
        ) as f:
            svg = f.read()
        self.assertIn("<svg", svg)

    def test_02_rust_catalog_matches_all_28_modules_and_local_utils(self):
        """O catálogo SETUP_MODULES e LOCAL_UTIL_ACTIONS em catalog.rs deve corresponder aos scripts reais."""
        with open(CATALOG_RS, "r", encoding="utf-8") as f:
            catalog = f.read()

        actual_modules = sorted(
            os.path.basename(p)
            for p in glob.glob(os.path.join(SCRIPTS_DIR, "[0-9][0-9]_*.sh"))
            if os.path.basename(p) != "00_comum.sh"
        )
        self.assertEqual(len(actual_modules), 28)

        for mod in actual_modules:
            self.assertIn(f'"{mod}"', catalog, f"Módulo {mod} ausente em catalog.rs")
            with open(os.path.join(SCRIPTS_DIR, mod), "r", encoding="utf-8") as sf:
                scontent = sf.read()
            m = re.search(r'FLAG_NAME="([^"]+)"', scontent)
            self.assertIsNotNone(m, f"FLAG_NAME não encontrado em {mod}")
            self.assertIn(
                f'"{m.group(1)}"',
                catalog,
                f"FLAG_NAME {m.group(1)} ({mod}) ausente em catalog.rs",
            )

        for rel_util in (
            "util/android-backup/backup_android.sh",
            "util/android-backup/restore_android.sh",
            "util/docker-update/update_containers.sh",
            "util/update-antigravity/update_antigravity.sh",
            "setup_popos.sh",
        ):
            self.assertTrue(
                os.path.isfile(os.path.join(ROOT_DIR, rel_util)),
                f"Script local ausente: {rel_util}",
            )
            self.assertIn(
                f'"{rel_util}"',
                catalog,
                f"Utilitário {rel_util} ausente em catalog.rs",
            )

    def test_03_cosmic_menu_includes_workstation_hub(self):
        """15_cosmic_menu_dock.sh deve incluir o ID do Workstation Hub na App Library."""
        with open(
            os.path.join(SCRIPTS_DIR, "15_cosmic_menu_dock.sh"), "r", encoding="utf-8"
        ) as f:
            content = f.read()
        self.assertIn("br.dev.rezendepauloh.WorkstationHub", content)

    def test_04_rust_core_tests_pass_when_toolchain_cached(self):
        """Executa 'cargo test --test core_tests --offline' caso cargo e cache estejam disponíveis."""
        if not shutil.which("cargo") or not os.path.isfile(os.path.join(HUB_DIR, "Cargo.lock")):
            self.skipTest("Toolchain cargo ou Cargo.lock indisponível neste ambiente.")

        res = subprocess.run(
            ["cargo", "test", "--test", "core_tests", "--offline"],
            cwd=HUB_DIR,
            capture_output=True,
            text=True,
        )
        if res.returncode != 0 and "no matching package" in res.stderr:
            self.skipTest("Cache offline de crates ausente no sandbox.")
        self.assertEqual(
            res.returncode,
            0,
            f"Falha nos testes Rust:\nSTDOUT:\n{res.stdout}\nSTDERR:\n{res.stderr}",
        )

    def test_05_remote_device_scripts_exist_and_executable(self):
        """Todos os utilitários em util/remote-devices/ devem existir e possuir permissão +x."""
        remote_dir = os.path.join(ROOT_DIR, "util", "remote-devices")
        expected = [
            "win_remote.sh",
            "android_remote.sh",
            "samsung_tv_remote.py",
            "network_scan.sh",
            "ha_alexa_remote.sh",
        ]
        for fname in expected:
            fpath = os.path.join(remote_dir, fname)
            self.assertTrue(os.path.isfile(fpath), f"Script remoto ausente: {fpath}")
            self.assertTrue(os.access(fpath, os.X_OK), f"Script remoto sem +x: {fpath}")


if __name__ == "__main__":
    unittest.main()
