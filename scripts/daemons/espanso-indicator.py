#!/usr/bin/env python3
"""
espanso-indicator.py
AppIndicator/StatusNotifierItem daemon for Espanso on Wayland/COSMIC Desktop.
Provides a native panel tray icon with quick actions:
- Search snippets
- Toggle Espanso (Enable/Disable)
- Open Config Folder
- Restart Espanso
- Exit Indicator
"""

import os
import subprocess
import signal
import gi

gi.require_version('Gtk', '3.0')
gi.require_version('AyatanaAppIndicator3', '0.1')
from gi.repository import Gtk, AyatanaAppIndicator3, GLib

APPINDICATOR_ID = 'espanso-indicator'
ICON_PATH = '/usr/share/pixmaps/espanso.png'

class EspansoIndicator:
    def __init__(self):
        self.is_enabled = True
        
        self.indicator = AyatanaAppIndicator3.Indicator.new(
            APPINDICATOR_ID,
            ICON_PATH if os.path.exists(ICON_PATH) else 'input-keyboard',
            AyatanaAppIndicator3.IndicatorCategory.APPLICATION_STATUS
        )
        self.indicator.set_status(AyatanaAppIndicator3.IndicatorStatus.ACTIVE)
        self.indicator.set_title("Espanso")
        
        self.build_menu()

    def build_menu(self):
        self.menu = Gtk.Menu()

        # Status item (Header)
        self.status_item = Gtk.MenuItem(label="● Espanso: Ativo")
        self.status_item.set_sensitive(False)
        self.menu.append(self.status_item)

        self.menu.append(Gtk.SeparatorMenuItem())

        # Search Bar
        item_search = Gtk.MenuItem(label="🔍 Buscar Snippets (Search)")
        item_search.connect('activate', self.on_search)
        self.menu.append(item_search)

        # Toggle Enable/Disable
        self.toggle_item = Gtk.MenuItem(label="⏸ Pausar Expansões")
        self.toggle_item.connect('activate', self.on_toggle)
        self.menu.append(self.toggle_item)

        self.menu.append(Gtk.SeparatorMenuItem())

        # Open config folder
        item_config = Gtk.MenuItem(label="📂 Abrir Configurações")
        item_config.connect('activate', self.on_open_config)
        self.menu.append(item_config)

        # Restart service
        item_restart = Gtk.MenuItem(label="🔄 Reiniciar Serviço")
        item_restart.connect('activate', self.on_restart)
        self.menu.append(item_restart)

        self.menu.append(Gtk.SeparatorMenuItem())

        # Exit Indicator
        item_quit = Gtk.MenuItem(label="❌ Fechar Indicador")
        item_quit.connect('activate', self.on_quit)
        self.menu.append(item_quit)

        self.menu.show_all()
        self.indicator.set_menu(self.menu)

    def on_search(self, _widget):
        try:
            subprocess.Popen(['espanso', 'cmd', 'search'])
        except Exception as e:
            print(f"[EspansoIndicator] Erro ao buscar: {e}")

    def on_toggle(self, _widget):
        try:
            subprocess.run(['espanso', 'cmd', 'toggle'], check=True)
            self.is_enabled = not self.is_enabled
            if self.is_enabled:
                self.status_item.set_label("● Espanso: Ativo")
                self.toggle_item.set_label("⏸ Pausar Expansões")
            else:
                self.status_item.set_label("○ Espanso: Pausado")
                self.toggle_item.set_label("▶ Retomar Expansões")
        except Exception as e:
            print(f"[EspansoIndicator] Erro no toggle: {e}")

    def on_open_config(self, _widget):
        config_path = os.path.expanduser('~/.config/espanso')
        try:
            subprocess.Popen(['xdg-open', config_path])
        except Exception as e:
            print(f"[EspansoIndicator] Erro ao abrir pasta: {e}")

    def on_restart(self, _widget):
        try:
            subprocess.run(['systemctl', '--user', 'restart', 'espanso.service'], check=True)
            self.is_enabled = True
            self.status_item.set_label("● Espanso: Ativo")
            self.toggle_item.set_label("⏸ Pausar Expansões")
        except Exception as e:
            print(f"[EspansoIndicator] Erro ao reiniciar: {e}")

    def on_quit(self, _widget):
        Gtk.main_quit()

def main():
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    signal.signal(signal.SIGTERM, signal.SIG_DFL)
    _app = EspansoIndicator()
    Gtk.main()

if __name__ == '__main__':
    main()
