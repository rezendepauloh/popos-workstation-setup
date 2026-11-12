import unittest
import os
import sys

class TestBtAudioSwitcher(unittest.TestCase):
    def test_daemon_script_exists_and_syntax(self):
        root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../'))
        script_path = os.path.join(root_dir, 'scripts', 'daemons', 'bt-audio-switcher.py')
        self.assertTrue(os.path.isfile(script_path), "bt-audio-switcher.py deve existir")
        
        # Test compilation
        import py_compile
        py_compile.compile(script_path, doraise=True)

    def test_systemd_service_file_exists(self):
        root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../'))
        service_path = os.path.join(root_dir, 'config', 'systemd', 'user', 'bt-audio-switcher.service')
        self.assertTrue(os.path.isfile(service_path), "bt-audio-switcher.service deve existir")
        with open(service_path, 'r', encoding='utf-8') as f:
            content = f.read()
        self.assertIn("bt-audio-switcher.py", content)
        self.assertIn("WantedBy=default.target", content)

if __name__ == '__main__':
    unittest.main()
