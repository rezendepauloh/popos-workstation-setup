import importlib.util
import os
import py_compile
import sys
import types
import unittest


def _load_bt_audio_switcher_module():
    root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../'))
    script_path = os.path.join(root_dir, 'scripts', 'daemons', 'bt-audio-switcher.py')

    # Injeta stubs mínimos caso dbus / gi não estejam instalados no ambiente de teste
    injected = []
    if 'dbus' not in sys.modules:
        try:
            import dbus  # noqa: F401
        except ImportError:
            dbus_mod = types.ModuleType('dbus')
            dbus_ml = types.ModuleType('dbus.mainloop')
            dbus_glib = types.ModuleType('dbus.mainloop.glib')
            dbus_glib.DBusGMainLoop = object
            sys.modules['dbus'] = dbus_mod
            sys.modules['dbus.mainloop'] = dbus_ml
            sys.modules['dbus.mainloop.glib'] = dbus_glib
            injected.extend(['dbus', 'dbus.mainloop', 'dbus.mainloop.glib'])
    if 'gi' not in sys.modules:
        try:
            from gi.repository import GLib  # noqa: F401
        except ImportError:
            gi_mod = types.ModuleType('gi')
            gi_repo = types.ModuleType('gi.repository')
            gi_repo.GLib = types.SimpleNamespace()
            sys.modules['gi'] = gi_mod
            sys.modules['gi.repository'] = gi_repo
            injected.extend(['gi', 'gi.repository'])

    try:
        spec = importlib.util.spec_from_file_location('bt_audio_switcher', script_path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module
    finally:
        for name in injected:
            sys.modules.pop(name, None)


class TestBtAudioSwitcher(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = _load_bt_audio_switcher_module()

    def test_daemon_script_exists_and_syntax(self):
        root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../'))
        script_path = os.path.join(root_dir, 'scripts', 'daemons', 'bt-audio-switcher.py')
        self.assertTrue(os.path.isfile(script_path), "bt-audio-switcher.py deve existir")
        py_compile.compile(script_path, doraise=True)

    def test_systemd_service_file_exists(self):
        root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../'))
        service_path = os.path.join(root_dir, 'config', 'systemd', 'user', 'bt-audio-switcher.service')
        self.assertTrue(os.path.isfile(service_path), "bt-audio-switcher.service deve existir")
        with open(service_path, 'r', encoding='utf-8') as f:
            content = f.read()
        self.assertIn("bt-audio-switcher.py", content)
        self.assertIn("WantedBy=default.target", content)

    def test_extract_mac_from_bluez_path(self):
        mac = self.mod.extract_mac_from_bluez_path('/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF')
        self.assertEqual(mac, 'AA:BB:CC:DD:EE:FF')
        self.assertEqual(self.mod.extract_mac_from_bluez_path('/org/bluez/hci0'), '')

    def test_match_bluez_sink_with_dynamic_mac(self):
        sinks_underscore = [
            'alsa_output.pci-0000_00_1f.3.analog-stereo',
            'bluez_output.AA_BB_CC_DD_EE_FF.1',
        ]
        sinks_colon = [
            'alsa_output.pci-0000_00_1f.3.analog-stereo',
            'bluez_output.AA:BB:CC:DD:EE:FF.a2dp-sink',
        ]
        self.assertEqual(
            self.mod.match_bluez_sink(sinks_underscore, device_mac='AA:BB:CC:DD:EE:FF', device_name='QCY H3S'),
            'bluez_output.AA_BB_CC_DD_EE_FF.1',
        )
        self.assertEqual(
            self.mod.match_bluez_sink(sinks_colon, device_mac='AA:BB:CC:DD:EE:FF', device_name='QCY H3S'),
            'bluez_output.AA:BB:CC:DD:EE:FF.a2dp-sink',
        )

    def test_match_g733_and_fallback_sink(self):
        sinks = [
            'alsa_output.pci-0000_01_00.1.hdmi-stereo',
            'alsa_output.usb-Logitech_G733_Gaming_Headset-00.analog-stereo',
            'alsa_output.pci-0000_00_1f.3.analog-stereo',
        ]
        self.assertEqual(
            self.mod.match_g733_sink(sinks),
            'alsa_output.usb-Logitech_G733_Gaming_Headset-00.analog-stereo',
        )
        self.assertEqual(
            self.mod.select_fallback_sink(sinks),
            'alsa_output.pci-0000_00_1f.3.analog-stereo',
        )

    def test_parse_g733_adc_packet(self):
        # Online: voltage = 0x0FEE (4078 mV), status = 0x01
        pkt_on = bytes([0x11, 0xFF, 0x08, 0x0A, 0x0F, 0xEE, 0x01]) + bytes(13)
        self.assertIs(self.mod.parse_g733_adc_packet(pkt_on, 0x08), True)

        # Offline via zero voltage broadcast
        pkt_zero = bytes([0x11, 0xFF, 0x08, 0x00, 0x00, 0x00, 0x00]) + bytes(13)
        self.assertIs(self.mod.parse_g733_adc_packet(pkt_zero, 0x08), False)

        # Offline via HID++ 2.0 HW_ERROR (0xFF, feat_idx=0x08, sw=0x0A, err=0x05)
        pkt_err = bytes([0x11, 0xFF, 0xFF, 0x08, 0x0A, 0x05]) + bytes(14)
        self.assertIs(self.mod.parse_g733_adc_packet(pkt_err, 0x08), False)

        # Unrelated feature packet -> None
        pkt_other = bytes([0x11, 0xFF, 0x04, 0x00, 0x01, 0x02]) + bytes(14)
        self.assertIsNone(self.mod.parse_g733_adc_packet(pkt_other, 0x08))


if __name__ == '__main__':
    unittest.main()
