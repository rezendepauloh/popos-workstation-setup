#!/usr/bin/env python3
"""
onedrive-indicator.py
AppIndicator/StatusNotifierItem daemon for Microsoft OneDrive (MPMS) on Wayland/COSMIC Desktop.
Provides a native panel tray icon with quick actions:
- Status indicator (Connected / Disconnected)
- Open Local Folder (~/OneDrive_MPMS) in Nautilus
- Remount / Sync SMB Share
- Open OneDrive in Web Browser (Multi-tenant M365 SSO)
- Open Windows 11 VM in Remmina
- Open Windows 11 Web Console (:8006)
- Restart Windows Container
- Quit Indicator
"""

import os
import signal
import socket
import subprocess
import threading
import gi

gi.require_version('Gtk', '3.0')
gi.require_version('AyatanaAppIndicator3', '0.1')
from gi.repository import Gtk, AyatanaAppIndicator3, GLib

APPINDICATOR_ID = 'onedrive-indicator'
LOCAL_PATH = os.path.expanduser('~/OneDrive_MPMS')
SMB_HOST = '172.20.0.2'
SMB_PORT = 445
ONEDRIVE_WEB_URL = 'https://www.office.com/launch/onedrive?auth=2'
REMMINA_PROFILE = os.path.expanduser('~/.local/share/remmina/winapps_windows11.remmina')


def get_icon_name():
    """Retorna o nome ou caminho do ícone do OneDrive."""
    custom_icon = os.path.expanduser('~/.local/share/icons/hicolor/scalable/apps/onedrive.svg')
    if os.path.exists(custom_icon):
        return custom_icon
    pixmap_icon = '/usr/share/pixmaps/onedrive.png'
    if os.path.exists(pixmap_icon):
        return pixmap_icon
    return 'onedrive'


class OneDriveIndicator:
    def __init__(self):
        self.is_connected = False
        icon_name = get_icon_name()

        self.indicator = AyatanaAppIndicator3.Indicator.new(
            APPINDICATOR_ID,
            icon_name,
            AyatanaAppIndicator3.IndicatorCategory.APPLICATION_STATUS
        )
        self.indicator.set_status(AyatanaAppIndicator3.IndicatorStatus.ACTIVE)
        self.indicator.set_title("OneDrive MPMS")

        self.build_menu()
        self.check_status_async()

        # Checar status a cada 15 segundos
        GLib.timeout_add_seconds(15, self.on_timer_check)

    def build_menu(self):
        self.menu = Gtk.Menu()

        # Item de Status (Cabeçalho informativo)
        self.status_item = Gtk.MenuItem(label="⏳ OneDrive MPMS: Verificando...")
        self.status_item.set_sensitive(False)
        self.menu.append(self.status_item)

        self.menu.append(Gtk.SeparatorMenuItem())

        # Abrir Pasta Local (~/OneDrive_MPMS)
        item_open = Gtk.MenuItem(label="📂 Abrir Pasta Local (~/OneDrive_MPMS)")
        item_open.connect('activate', self.on_open_folder)
        self.menu.append(item_open)

        # Sincronizar / Remontar SMB
        item_sync = Gtk.MenuItem(label="🔄 Remontar / Sincronizar Compartilhamento")
        item_sync.connect('activate', self.on_sync_smb)
        self.menu.append(item_sync)

        # Abrir no Navegador (Web)
        item_web = Gtk.MenuItem(label="🌐 Abrir OneDrive na Web (M365 Corporativo)")
        item_web.connect('activate', self.on_open_web)
        self.menu.append(item_web)

        self.menu.append(Gtk.SeparatorMenuItem())

        # Abrir Windows 11 no Remmina
        item_win = Gtk.MenuItem(label="🖥️ Abrir Windows 11 no Remmina")
        item_win.connect('activate', self.on_open_winapps)
        self.menu.append(item_win)

        # Abrir Console Web no Navegador (VNC :8006)
        item_web_console = Gtk.MenuItem(label="🖥️ Abrir Console Web da VM (:8006)")
        item_web_console.connect('activate', self.on_open_web_console)
        self.menu.append(item_web_console)

        # Reiniciar VM Container
        item_restart_vm = Gtk.MenuItem(label="⚙️ Reiniciar Container Windows")
        item_restart_vm.connect('activate', self.on_restart_vm)
        self.menu.append(item_restart_vm)

        self.menu.append(Gtk.SeparatorMenuItem())

        # Sair do Indicador
        item_quit = Gtk.MenuItem(label="❌ Fechar Indicador")
        item_quit.connect('activate', self.on_quit)
        self.menu.append(item_quit)

        self.menu.show_all()
        self.indicator.set_menu(self.menu)

    def is_service_connected(self):
        """Verifica se a pasta local possui arquivos ou se a porta SMB está aberta."""
        try:
            if os.path.exists(LOCAL_PATH) and len(os.listdir(LOCAL_PATH)) > 0:
                return True
        except Exception:
            pass

        try:
            with socket.create_connection((SMB_HOST, SMB_PORT), timeout=1.0):
                return True
        except Exception:
            return False

    def update_ui_status(self, connected):
        self.is_connected = connected
        if connected:
            self.status_item.set_label("● OneDrive MPMS: Conectado")
        else:
            self.status_item.set_label("○ OneDrive MPMS: Desconectado")
        return False

    def check_status_async(self):
        def worker():
            status = self.is_service_connected()
            GLib.idle_add(self.update_ui_status, status)

        threading.Thread(target=worker, daemon=True).start()

    def on_timer_check(self):
        self.check_status_async()
        return True  # Continua executando o timer

    def on_open_folder(self, _widget):
        try:
            subprocess.Popen(['xdg-open', LOCAL_PATH])
        except Exception as e:
            print(f"[OneDriveIndicator] Erro ao abrir pasta: {e}")

    def on_sync_smb(self, _widget):
        self.status_item.set_label("⏳ Remontando compartilhamento...")
        sync_script = os.path.expanduser('~/.local/bin/winapps-smb-sync.sh')

        def worker():
            if os.path.exists(sync_script):
                try:
                    subprocess.run([sync_script, '--once'], capture_output=True, timeout=30)
                except Exception as e:
                    print(f"[OneDriveIndicator] Erro no sync SMB: {e}")
            GLib.timeout_add_seconds(2, self.check_status_async)

        threading.Thread(target=worker, daemon=True).start()

    def on_open_web(self, _widget):
        try:
            subprocess.Popen(['xdg-open', ONEDRIVE_WEB_URL])
        except Exception as e:
            print(f"[OneDriveIndicator] Erro ao abrir navegador: {e}")

    def on_open_winapps(self, _widget):
        try:
            if os.path.exists(REMMINA_PROFILE):
                subprocess.Popen(['remmina', '-c', REMMINA_PROFILE])
            else:
                subprocess.Popen(['xdg-open', 'http://127.0.0.1:8006'])
        except Exception as e:
            print(f"[OneDriveIndicator] Erro ao abrir Remmina: {e}")

    def on_open_web_console(self, _widget):
        try:
            subprocess.Popen(['xdg-open', 'http://127.0.0.1:8006'])
        except Exception as e:
            print(f"[OneDriveIndicator] Erro ao abrir console web: {e}")

    def on_restart_vm(self, _widget):
        vm_bin = os.path.expanduser('~/.local/bin/winapps-vm')
        try:
            if os.path.exists(vm_bin):
                subprocess.Popen([vm_bin, 'restart'])
        except Exception as e:
            print(f"[OneDriveIndicator] Erro ao reiniciar VM: {e}")

    def on_quit(self, _widget):
        Gtk.main_quit()


def main():
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    signal.signal(signal.SIGTERM, signal.SIG_DFL)
    _app = OneDriveIndicator()
    Gtk.main()


if __name__ == '__main__':
    main()
