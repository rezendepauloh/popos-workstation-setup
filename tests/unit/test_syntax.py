# -*- coding: utf-8 -*-
"""
Testes Unitários: Validação de sintaxe (AST/Parser) de todos os scripts Bash e Python.
"""

import glob
import os
import py_compile
import subprocess
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SCRIPTS_DIR = os.path.join(ROOT_DIR, 'scripts')
DAEMONS_DIR = os.path.join(SCRIPTS_DIR, 'daemons')
UTIL_DIR = os.path.join(ROOT_DIR, 'util')


class TestSyntaxValidation(unittest.TestCase):
    """Garante que nenhum script Bash ou daemon Python possua erros de sintaxe."""

    def test_01_all_bash_scripts_syntax_valid(self):
        """Valida 'bash -n' em setup_popos_v2.sh, test_in_docker.sh, scripts/*.sh e util/*.sh."""
        bash_files = [
            os.path.join(ROOT_DIR, 'setup_popos_v2.sh'),
            os.path.join(ROOT_DIR, 'test_in_docker.sh'),
        ]
        bash_files.extend(sorted(glob.glob(os.path.join(SCRIPTS_DIR, '*.sh'))))
        bash_files.extend(sorted(glob.glob(os.path.join(UTIL_DIR, '*.sh'))))

        self.assertGreaterEqual(len(bash_files), 30, "Deveria encontrar pelo menos 30 scripts Bash.")

        for script in bash_files:
            with self.subTest(script=os.path.relpath(script, ROOT_DIR)):
                res = subprocess.run(
                    ['bash', '-n', script],
                    capture_output=True,
                    text=True
                )
                self.assertEqual(
                    res.returncode, 0,
                    f"Erro de sintaxe Bash em {script}:\n{res.stderr}"
                )

    def test_02_all_bash_scripts_have_shebang_and_permissions(self):
        """Verifica se todos os scripts em scripts/[0-9][0-9]_*.sh têm shebang #!/bin/bash e permissão +x."""
        module_scripts = sorted(glob.glob(os.path.join(SCRIPTS_DIR, '[0-9][0-9]_*.sh')))
        self.assertEqual(len(module_scripts), 29, "Devem existir exatamente 29 scripts numerados (00 a 28).")

        for script in module_scripts:
            rel = os.path.relpath(script, ROOT_DIR)
            with open(script, 'r', encoding='utf-8') as f:
                first_line = f.readline().strip()
            self.assertEqual(first_line, '#!/bin/bash', f"{rel} deve iniciar com #!/bin/bash")
            self.assertTrue(os.access(script, os.X_OK), f"{rel} deve possuir permissão de execução (+x)")

    def test_03_all_python_daemons_compile_cleanly(self):
        """Valida compilação AST de todos os daemons Python em scripts/daemons/*.py."""
        py_files = sorted(glob.glob(os.path.join(DAEMONS_DIR, '*.py')))
        self.assertGreaterEqual(len(py_files), 4, "Devem existir pelo menos 4 daemons/utilitários Python.")

        for py_file in py_files:
            rel = os.path.relpath(py_file, ROOT_DIR)
            with self.subTest(daemon=rel):
                try:
                    py_compile.compile(py_file, doraise=True)
                except py_compile.PyCompileError as e:
                    self.fail(f"Erro de sintaxe Python em {rel}: {e}")


if __name__ == '__main__':
    unittest.main()

