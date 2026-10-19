# Espanso Wayland Tray Icon & Phantom Window Issue (COSMIC Desktop / StatusNotifierItem)

This report documents a UX issue on Wayland compositors (specifically System76 COSMIC Desktop / `cosmic-comp`), why it happens, and provides a lightweight workaround using a native `StatusNotifierItem` Python daemon.

---

## 1. Environment Details

- **OS:** Pop!_OS 24.04 LTS (Noble)
- **Desktop Environment:** COSMIC Epoch 1.10.0 (Alpha / Wayland compositor: `cosmic-comp`)
- **Espanso Version:** `espanso-debian-wayland-amd64` v2.4.1
- **Backend:** `EVDEV`

---

## 2. The Problem

### A. Phantom 1x1 Stray Window on Desktop
When `show_icon: true` is configured in `~/.config/espanso/config/default.yml`:
- Espanso spawns an internal `wxWidgets` `TaskBarIcon` window.
- In Linux, `wxWidgets` traditionally handles system tray integration using the X11 **XEmbed** protocol.
- Under Wayland compositors like COSMIC (`cosmic-comp`), the XEmbed protocol is not supported for panel docking.
- As a consequence, `cosmic-comp` interprets this tiny window as a regular floating top-level X11 window. A tiny 1x1 window with an active focus border (e.g. purple border) appears right in the middle of the desktop workspace.

### B. Missing Panel Status Indicator
- When `show_icon: false` is set to eliminate the phantom window, Espanso runs completely invisible in the background.
- However, Wayland desktop panels (COSMIC panel, KDE Plasma, GNOME with AppIndicator extension, Waybar) rely on **StatusNotifierItem (SNI / DBus)** or `org.kde.StatusNotifierItem` rather than XEmbed.
- Users have no visual indicator or click-to-toggle menu in their top bar/system tray.

---

## 3. Workaround Implementation

To give users a clean status icon in the Wayland panel without the phantom window, we combined two steps:

1. **Disable the built-in wxWidgets tray window:**
   In `~/.config/espanso/config/default.yml`:
   ```yaml
   backend: EVDEV
   show_icon: false
   show_notifications: true
   ```

2. **Run a lightweight DBus / Ayatana AppIndicator daemon (`espanso-indicator.py`):**
   A small script communicates with Espanso CLI (`espanso cmd ...`) and exposes a standard StatusNotifierItem icon on DBus.

### `espanso-indicator.py` Source
```python
#!/usr/bin/env python3
import os
import subprocess
import signal
import gi

gi.require_version('Gtk', '3.0')
gi.require_version('AyatanaAppIndicator3', '0.1')
from gi.repository import Gtk, AyatanaAppIndicator3

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

        self.status_item = Gtk.MenuItem(label="● Espanso: Active")
        self.status_item.set_sensitive(False)
        self.menu.append(self.status_item)

        self.menu.append(Gtk.SeparatorMenuItem())

        item_search = Gtk.MenuItem(label="🔍 Search Snippets")
        item_search.connect('activate', lambda _: subprocess.Popen(['espanso', 'cmd', 'search']))
        self.menu.append(item_search)

        self.toggle_item = Gtk.MenuItem(label="⏸ Pause Expansions")
        self.toggle_item.connect('activate', self.on_toggle)
        self.menu.append(self.toggle_item)

        self.menu.append(Gtk.SeparatorMenuItem())

        item_config = Gtk.MenuItem(label="📂 Open Config Folder")
        item_config.connect('activate', lambda _: subprocess.Popen(['xdg-open', os.path.expanduser('~/.config/espanso')]))
        self.menu.append(item_config)

        item_restart = Gtk.MenuItem(label="🔄 Restart Service")
        item_restart.connect('activate', self.on_restart)
        self.menu.append(item_restart)

        self.menu.append(Gtk.SeparatorMenuItem())

        item_quit = Gtk.MenuItem(label="❌ Quit Indicator")
        item_quit.connect('activate', lambda _: Gtk.main_quit())
        self.menu.append(item_quit)

        self.menu.show_all()
        self.indicator.set_menu(self.menu)

    def on_toggle(self, _widget):
        try:
            subprocess.run(['espanso', 'cmd', 'toggle'], check=True)
            self.is_enabled = not self.is_enabled
            if self.is_enabled:
                self.status_item.set_label("● Espanso: Active")
                self.toggle_item.set_label("⏸ Pause Expansions")
            else:
                self.status_item.set_label("○ Espanso: Paused")
                self.toggle_item.set_label("▶ Resume Expansions")
        except Exception as e:
            print(f"[EspansoIndicator] Toggle error: {e}")

    def on_restart(self, _widget):
        try:
            subprocess.run(['systemctl', '--user', 'restart', 'espanso.service'], check=True)
            self.is_enabled = True
            self.status_item.set_label("● Espanso: Active")
            self.toggle_item.set_label("⏸ Pause Expansions")
        except Exception as e:
            print(f"[EspansoIndicator] Restart error: {e}")

def main():
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    signal.signal(signal.SIGTERM, signal.SIG_DFL)
    _app = EspansoIndicator()
    Gtk.main()

if __name__ == '__main__':
    main()
```

### Systemd User Unit (`~/.config/systemd/user/espanso-indicator.service`)
```ini
[Unit]
Description=Espanso System Tray Indicator (Wayland / COSMIC)
After=espanso.service
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 %h/Documentos/DevProjects/Bash/popos-workstation-setup/scripts/espanso-indicator.py
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
```

---

## 4. Suggested Long-Term Solution for Espanso

Rather than relying on wxWidgets' X11/XEmbed `TaskBarIcon` on Linux:
- Consider implementing DBus **StatusNotifierItem (SNI)** via a pure Rust crate (such as `ksni` or `tray-icon`) when targetting `unix` under Wayland sessions.
- Automatically default to disabling the wxWidgets icon when `WAYLAND_DISPLAY` is detected.
