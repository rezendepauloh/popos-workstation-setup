# -*- coding: utf-8 -*-
"""
Testes Unitários: Biblioteca Comum (scripts/00_comum.sh)
Testa check_flag, set_flag, clear_flag e log_msg usando arquivos temporários isolados.
"""

import os
import subprocess
import tempfile
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
COMUM_SH = os.path.join(ROOT_DIR, 'scripts', '00_comum.sh')


class TestCommonLibrary(unittest.TestCase):
    """Testa funções de idempotência e logging do 00_comum.sh em sandbox temporário."""

    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.progress_file = os.path.join(self.tmp_dir.name, '.setup_progress_test.log')

    def tearDown(self):
        self.tmp_dir.cleanup()

    def _run_bash_snippet(self, snippet: str):
        cmd = f"""
        source "{COMUM_SH}"
        PROGRESS_LOG="{self.progress_file}"
        {snippet}
        """
        return subprocess.run(['bash', '-c', cmd], capture_output=True, text=True)

    def test_01_check_flag_returns_pending_when_empty(self):
        """check_flag deve retornar 1 (pendente) quando a flag ainda não foi registrada."""
        res = self._run_bash_snippet('check_flag "MOD_TEST_01"')
        self.assertEqual(res.returncode, 1)

    def test_02_set_flag_persists_and_check_flag_succeeds(self):
        """set_flag deve gravar a flag de forma idempotente e check_flag deve retornar 0."""
        res = self._run_bash_snippet('set_flag "MOD_TEST_02" && set_flag "MOD_TEST_02" && check_flag "MOD_TEST_02"')
        self.assertEqual(res.returncode, 0)
        with open(self.progress_file, 'r', encoding='utf-8') as f:
            lines = [line.strip() for line in f if line.strip()]
        self.assertEqual(lines, ["MOD_TEST_02"], "A flag não deve ser duplicada no arquivo de progresso.")

    def test_03_check_flag_with_force_clears_and_reruns(self):
        """check_flag com '--force' deve limpar a flag existente e retornar 1 (forçar execução)."""
        self._run_bash_snippet('set_flag "MOD_TEST_03"')
        res = self._run_bash_snippet('check_flag "MOD_TEST_03" "--force"')
        self.assertEqual(res.returncode, 1)
        with open(self.progress_file, 'r', encoding='utf-8') as f:
            content = f.read().strip()
        self.assertEqual(content, "", "O arquivo de progresso deveria ter removido a flag após --force.")

    def test_04_log_msg_formats_levels_correctly(self):
        """log_msg deve formatar corretamente mensagens INFO, SUCCESS, WARN, ERROR e HEADER."""
        res = self._run_bash_snippet('log_msg "INFO" "Mensagem de teste" && log_msg "HEADER" "Cabeçalho"')
        self.assertEqual(res.returncode, 0)
        self.assertIn("[INFO]", res.stdout)
        self.assertIn("Mensagem de teste", res.stdout)
        self.assertIn("=== Cabeçalho ===", res.stdout)


if __name__ == '__main__':
    unittest.main()

