#!/usr/bin/env python3
"""
Testes Automatizados de Auditoria de Segurança (Hardening & SAST).
Garante que o repositório permaneça livre de credenciais hardcoded, injeções de
código em chamadas inline Python, exposições de portas de rede em 0.0.0.0,
regras udev world-writable (0666) e escalações de privilégio via sudoers.
"""

import os
import re
import unittest

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
SCRIPTS_DIR = os.path.join(BASE_DIR, "scripts")
DAEMONS_DIR = os.path.join(SCRIPTS_DIR, "daemons")
UTIL_DIR = os.path.join(BASE_DIR, "util")


class TestSecurityAudit(unittest.TestCase):
    """Validações estáticas de segurança e conformidade (DevSecOps)."""

    def _iter_code_files(self):
        """Itera sobre todos os arquivos de código e configuração versionados."""
        target_dirs = [SCRIPTS_DIR, UTIL_DIR, os.path.join(BASE_DIR, "Docs")]
        root_files = [
            os.path.join(BASE_DIR, "setup_popos.sh"),
            os.path.join(BASE_DIR, ".env.example"),
            os.path.join(BASE_DIR, "Dockerfile"),
            os.path.join(BASE_DIR, "README.md"),
        ]
        for fpath in root_files:
            if os.path.isfile(fpath):
                yield fpath

        for d in target_dirs:
            for root, _, files in os.walk(d):
                for fname in files:
                    if fname.endswith((".sh", ".py", ".ps1", ".bat", ".md", ".conf")):
                        yield os.path.join(root, fname)

    def test_01_no_hardcoded_credentials_or_personal_identifiers(self):
        """Garante ausência total de senhas, hashes 3DES, MACs pessoais e IDs internos."""
        forbidden_patterns = [
            "M!n0t@ur0",
            "1gm8OsVmtyC/GZ9btOJlzA==",
            "84:AC:60:05:50:19",
            "84_AC_60_05_50_19",
            "E0:9F:2A:20:BC:DD",
            "MPE-80703",
            "SUDO_PASSWORD",
        ]
        violations = []
        this_file = os.path.abspath(__file__)

        for fpath in self._iter_code_files():
            if os.path.abspath(fpath) == this_file:
                continue
            with open(fpath, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
            rel = os.path.relpath(fpath, BASE_DIR)
            for pat in forbidden_patterns:
                if pat in content:
                    violations.append(f"{rel}: contém padrão proibido '{pat}'")

        self.assertEqual(
            len(violations),
            0,
            "Dados sensíveis ou credenciais hardcoded detectados:\n" + "\n".join(violations),
        )

    def test_02_no_python_inline_string_interpolation_injection(self):
        """Impede injeção de código Python (RCE) via interpolação Bash '''$VAR'''."""
        violations = []
        for d in (SCRIPTS_DIR, UTIL_DIR):
            for root, _, files in os.walk(d):
                for fname in files:
                    if not fname.endswith(".sh"):
                        continue
                    fpath = os.path.join(root, fname)
                    rel = os.path.relpath(fpath, BASE_DIR)
                    with open(fpath, "r", encoding="utf-8") as f:
                        content = f.read()
                    if "'''$" in content or '"""$' in content:
                        violations.append(f"{rel}: interpolação insegura '''$VAR''' em bloco Python")
                    if "os.path.expanduser('~')" in content or 'os.path.expanduser("~")' in content:
                        violations.append(
                            f"{rel}: uso de os.path.expanduser('~') em script sudo (resolve para /root)"
                        )

        self.assertEqual(
            len(violations),
            0,
            "Padrões de injeção Python ou resolução incorreta de HOME detectados:\n"
            + "\n".join(violations),
        )

    def test_03_no_world_writable_udev_or_passwordless_samba_or_fuse_allow_other(self):
        """Verifica permissões de dispositivos udev, contas Samba e FUSE rclone."""
        with open(os.path.join(SCRIPTS_DIR, "02_teclado_cedilha_numlock.sh"), "r", encoding="utf-8") as f:
            s02 = f.read()
        self.assertNotIn('MODE="0666"', s02, "Regra udev de LEDs não deve usar MODE=0666.")

        with open(os.path.join(SCRIPTS_DIR, "22_openrgb_iluminacao.sh"), "r", encoding="utf-8") as f:
            s22 = f.read()
        self.assertNotIn('MODE="0666"', s22, "Regra udev OpenRGB não deve expor SMBus/USB com MODE=0666.")

        with open(os.path.join(SCRIPTS_DIR, "25_samba_storage.sh"), "r", encoding="utf-8") as f:
            s25 = f.read()
        self.assertNotIn(
            "smbpasswd -a -n",
            s25,
            "O módulo Samba jamais deve habilitar contas sem senha (smbpasswd -n).",
        )

        with open(os.path.join(SCRIPTS_DIR, "05_rclone_storage.sh"), "r", encoding="utf-8") as f:
            s05 = f.read()
        self.assertNotIn(
            "--allow-other",
            s05,
            "Montagens FUSE do Rclone não devem usar --allow-other.",
        )
        self.assertIn(
            "--rc-addr 127.0.0.1:5572",
            s05,
            "Rclone WebUI deve fazer bind estrito em 127.0.0.1:5572.",
        )

    def test_04_network_exposure_and_privilege_hardening(self):
        """Verifica isolamento loopback do WinApps, sudoers restrito da VPN e regras UFW."""
        with open(os.path.join(SCRIPTS_DIR, "26_winapps_office.sh"), "r", encoding="utf-8") as f:
            s26 = f.read()
        self.assertIn('"127.0.0.1:8006:8006"', s26)
        self.assertIn('"127.0.0.1:3389:3389/tcp"', s26)
        self.assertIn('"127.0.0.1:3389:3389/udp"', s26)
        self.assertNotIn('"8006:8006"', s26)
        self.assertNotIn('"3389:3389/tcp"', s26)

        with open(os.path.join(SCRIPTS_DIR, "23_trabalho_remoto_vpn_rdp.sh"), "r", encoding="utf-8") as f:
            s23 = f.read()
        self.assertIn("NOPASSWD: /usr/local/sbin/openfortivpn-mpms-helper", s23)
        self.assertNotIn("NOPASSWD: /usr/bin/openfortivpn", s23)
        self.assertNotIn('"-o" "$VPN_INPUT_OTP"', s23)

        with open(os.path.join(SCRIPTS_DIR, "28_limpeza_otimizacao.sh"), "r", encoding="utf-8") as f:
            s28 = f.read()
        self.assertNotIn("ufw allow from 192.168.0.0/24 comment", s28)
        self.assertIn("--exclude='.ssh/id_*'", s28)
        self.assertNotIn('BACKUP_DEST="/tmp/Backups_Workstation"', s28)

    def test_05_env_security_and_dockerignore_and_https(self):
        """Garante proteção contra symlink em .env, presença de .dockerignore e HTTPS."""
        with open(os.path.join(SCRIPTS_DIR, "00_comum.sh"), "r", encoding="utf-8") as f:
            s00 = f.read()
        self.assertIn('! -L "$BASE_DIR/.env"', s00)
        self.assertIn('chmod 600 "$BASE_DIR/.env"', s00)

        dockerignore_path = os.path.join(BASE_DIR, ".dockerignore")
        self.assertTrue(os.path.isfile(dockerignore_path), ".dockerignore deve existir na raiz.")
        with open(dockerignore_path, "r", encoding="utf-8") as f:
            di_content = f.read()
        for entry in (".env", "rclone.conf", "config/rclone/", "*.key", "Logs/"):
            self.assertIn(entry, di_content, f".dockerignore deve ignorar {entry}")

        with open(os.path.join(SCRIPTS_DIR, "06_softwares_workflow.sh"), "r", encoding="utf-8") as f:
            s06 = f.read()
        self.assertNotIn(
            "http://archive.ubuntu.com",
            s06,
            "Downloads de pacotes .deb devem utilizar exclusivamente HTTPS.",
        )


if __name__ == "__main__":
    unittest.main()

