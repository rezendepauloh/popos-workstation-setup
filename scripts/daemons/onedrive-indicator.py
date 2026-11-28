#!/usr/bin/env python3
"""
onedrive-indicator.py
AppIndicator/StatusNotifierItem daemon for Microsoft OneDrive (MPMS) on Wayland/COSMIC Desktop.
Provides a native panel tray icon with quick actions:
- Status indicator (Connected / Disconnected / Syncing)
- Open Local Folder (~/OneDrive_MPMS) in Nautilus
- Sync OneDrive Files silently inside the Windows 11 VM (RemoteApp /background)
- Remount SMB Share
- Open OneDrive in Web Browser (Multi-tenant M365 SSO)
- Open Windows 11 VM in Remmina
- Open Windows 11 Web Console (:8006)
- Restart Windows Container
- Quit Indicator
"""

from datetime import datetime
import json
import os
import shutil
import signal
import socket
import subprocess
import threading
import time

try:
    import gi
    gi.require_version('Gtk', '3.0')
    gi.require_version('AyatanaAppIndicator3', '0.1')
    from gi.repository import Gtk, AyatanaAppIndicator3, GLib
    HAS_GTK = True
except (ImportError, ValueError):
    Gtk = None
    AyatanaAppIndicator3 = None
    GLib = None
    HAS_GTK = False

APPINDICATOR_ID = 'onedrive-indicator'
LOCAL_PATH = os.path.expanduser('~/OneDrive_MPMS')
SHARED_VM_DIR = os.path.expanduser('~/Compartilhado_VM')
SYNC_STATUS_FILE = os.path.join(SHARED_VM_DIR, 'onedrive_sync_status.json')
WINAPPS_CONF = os.path.expanduser('~/.config/winapps/winapps.conf')
WINAPPS_CONTAINER = 'winapps-windows'
SMB_HOST = '172.20.0.2'
SMB_PORT = 445
SYNC_TIMEOUT_SECONDS = 150
ONEDRIVE_WEB_URL = 'https://www.office.com/launch/onedrive?auth=2'
REMMINA_PROFILE = os.path.expanduser('~/.local/share/remmina/winapps_windows11.remmina')


def get_icon_name():
    """Retorna o nome ou caminho do ícone PNG colorido do OneDrive (evita tinting simbólico de SVG no COSMIC)."""
    hicolor_png = os.path.expanduser('~/.local/share/icons/hicolor/48x48/apps/onedrive.png')
    if os.path.exists(hicolor_png):
        return hicolor_png
    pixmap_icon = '/usr/share/pixmaps/onedrive.png'
    if os.path.exists(pixmap_icon):
        return pixmap_icon
    custom_icon = os.path.expanduser('~/.local/share/icons/hicolor/scalable/apps/onedrive.svg')
    if os.path.exists(custom_icon):
        return custom_icon
    return 'onedrive'


def parse_winapps_conf(conf_path=WINAPPS_CONF):
    """Lê pares CHAVE=VALOR de ~/.config/winapps/winapps.conf sem executar shell."""
    config = {}
    if not os.path.isfile(conf_path):
        return config
    try:
        with open(conf_path, 'r', encoding='utf-8') as f:
            for raw_line in f:
                line = raw_line.strip()
                if not line or line.startswith('#') or '=' not in line:
                    continue
                key, value = line.split('=', 1)
                key = key.strip()
                value = value.strip()
                if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
                    value = value[1:-1]
                config[key] = value
    except OSError:
        return {}
    return config


def read_sync_status(status_path=SYNC_STATUS_FILE):
    """Lê o arquivo JSON de status gerado por sync_onedrive.ps1 na pasta compartilhada."""
    if not os.path.isfile(status_path):
        return None
    try:
        with open(status_path, 'r', encoding='utf-8-sig') as f:
            data = json.load(f)
        if isinstance(data, dict):
            return data
    except (OSError, ValueError):
        return None
    return None


def format_sync_status_label(status_data):
    """Formata o rótulo de status exibido no topo do menu durante a sincronização."""
    if not isinstance(status_data, dict):
        return "⏳ OneDrive MPMS: Sincronizando..."
    state = status_data.get('state', '')
    up = int(status_data.get('files_to_upload', 0) or 0)
    down = int(status_data.get('files_to_download', 0) or 0)
    msg = (status_data.get('message') or '').strip()

    if state == 'starting':
        return "⏳ OneDrive MPMS: Iniciando OneDrive..."
    if state == 'syncing':
        if up > 0 or down > 0:
            return f"⏳ OneDrive MPMS: Sincronizando (↑{up} ↓{down})..."
        return "⏳ OneDrive MPMS: Sincronizando arquivos..."
    if state == 'completed':
        return "● OneDrive MPMS: Sincronizado"
    if state == 'error':
        return f"⚠️ OneDrive MPMS: {msg or 'Erro na sincronização'}"
    return "⏳ OneDrive MPMS: Sincronizando..."


def is_container_running(container=WINAPPS_CONTAINER):
    """Verifica se o container Docker do Windows (WinApps) está em execução."""
    try:
        res = subprocess.run(
            ['docker', 'inspect', '-f', '{{.State.Running}}', container],
            capture_output=True,
            text=True,
            timeout=5,
        )
        return res.returncode == 0 and res.stdout.strip().lower() == 'true'
    except Exception:
        return False


def send_notification(title, body, icon='onedrive'):
    """Envia notificação nativa de desktop via notify-send (se disponível)."""
    if not shutil.which('notify-send'):
        return
    try:
        subprocess.Popen(
            ['notify-send', '-a', 'OneDrive MPMS', '-i', icon, title, body],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        pass


def ensure_sync_scripts(shared_dir=SHARED_VM_DIR):
    """Garante que sync_onedrive.ps1 e sync_onedrive.vbs existam na pasta compartilhada."""
    os.makedirs(shared_dir, exist_ok=True)
    required = ('sync_onedrive.ps1', 'sync_onedrive.vbs')
    if all(os.path.isfile(os.path.join(shared_dir, name)) for name in required):
        return True

    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_winapps_dir = os.path.abspath(os.path.join(script_dir, '..', '..', 'util', 'winapps'))
    for name in required:
        dst = os.path.join(shared_dir, name)
        src = os.path.join(repo_winapps_dir, name)
        if not os.path.isfile(dst) and os.path.isfile(src):
            try:
                shutil.copy2(src, dst)
            except OSError:
                return False
    return all(os.path.isfile(os.path.join(shared_dir, name)) for name in required)


class OneDriveIndicator:
    def __init__(self):
        self.is_connected = False
        self.is_syncing = False
        self.last_sync_time = None
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

        # Sincronizar Arquivos do OneDrive dentro da VM (silencioso via RemoteApp)
        self.sync_files_item = Gtk.MenuItem(label="☁️ Sincronizar Arquivos do OneDrive")
        self.sync_files_item.connect('activate', self.on_sync_onedrive_files)
        self.menu.append(self.sync_files_item)

        # Remontar compartilhamento SMB no Nautilus
        item_sync = Gtk.MenuItem(label="🔄 Remontar Compartilhamento SMB")
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
        if self.is_syncing:
            return False
        if connected:
            if self.last_sync_time:
                self.status_item.set_label(f"● OneDrive MPMS: Conectado (Sync {self.last_sync_time})")
            else:
                self.status_item.set_label("● OneDrive MPMS: Conectado")
        else:
            self.status_item.set_label("○ OneDrive MPMS: Desconectado")
        return False

    def _set_sync_ui(self, syncing, status_label=None):
        self.is_syncing = syncing
        if status_label:
            self.status_item.set_label(status_label)
        if syncing:
            self.sync_files_item.set_label("⏳ Sincronizando OneDrive...")
            self.sync_files_item.set_sensitive(False)
        else:
            self.sync_files_item.set_label("☁️ Sincronizar Arquivos do OneDrive")
            self.sync_files_item.set_sensitive(True)
        return False

    def check_status_async(self):
        def worker():
            status = self.is_service_connected()
            GLib.idle_add(self.update_ui_status, status)

        threading.Thread(target=worker, daemon=True).start()

    def on_timer_check(self):
        if not self.is_syncing:
            self.check_status_async()
        return True  # Continua executando o timer

    def on_open_folder(self, _widget):
        try:
            subprocess.Popen(['xdg-open', LOCAL_PATH])
        except Exception as e:
            print(f"[OneDriveIndicator] Erro ao abrir pasta: {e}")

    def on_sync_onedrive_files(self, _widget):
        """Dispara sincronização silenciosa do OneDrive dentro da VM Windows via RemoteApp."""
        if self.is_syncing:
            return

        self._set_sync_ui(True, "⏳ OneDrive MPMS: Preparando sincronização...")

        def worker():
            rdp_proc = None
            try:
                if not is_container_running():
                    send_notification(
                        "OneDrive MPMS",
                        "Container Windows está parado. Inicie a VM antes de sincronizar.",
                    )
                    return

                if not shutil.which('xfreerdp3'):
                    send_notification(
                        "OneDrive MPMS",
                        "xfreerdp3 não encontrado no sistema.",
                    )
                    return

                conf = parse_winapps_conf()
                rdp_user = conf.get('RDP_USER', 'winapps')
                rdp_pass = conf.get('RDP_PASS', '')
                rdp_ip = conf.get('RDP_IP', '127.0.0.1')
                rdp_port = conf.get('RDP_PORT', '3389')

                if not rdp_pass:
                    send_notification(
                        "OneDrive MPMS",
                        "Credenciais RDP ausentes em ~/.config/winapps/winapps.conf.",
                    )
                    return

                if not ensure_sync_scripts():
                    send_notification(
                        "OneDrive MPMS",
                        "Scripts sync_onedrive.ps1/vbs não encontrados em ~/Compartilhado_VM.",
                    )
                    return

                # Remove status antigo para evitar leitura obsoleta
                try:
                    if os.path.exists(SYNC_STATUS_FILE):
                        os.remove(SYNC_STATUS_FILE)
                except OSError:
                    pass

                send_notification(
                    "OneDrive MPMS",
                    "Sincronizando arquivos em segundo plano na VM Windows...",
                )

                cmd = [
                    'xfreerdp3',
                    '/cert:ignore',
                    f'/u:{rdp_user}',
                    f'/p:{rdp_pass}',
                    r'/app:program:C:\Windows\System32\wscript.exe,cmd://B //Nologo \\host.lan\Data\sync_onedrive.vbs',
                    f'/v:{rdp_ip}:{rdp_port}',
                ]
                rdp_proc = subprocess.Popen(
                    cmd,
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )

                deadline = time.monotonic() + SYNC_TIMEOUT_SECONDS
                final_status = None

                while time.monotonic() < deadline:
                    status_data = read_sync_status()
                    if status_data:
                        label = format_sync_status_label(status_data)
                        GLib.idle_add(self.status_item.set_label, label)
                        state = status_data.get('state')
                        if state in ('completed', 'error'):
                            final_status = status_data
                            break

                    if rdp_proc.poll() is not None:
                        # FreeRDP encerrou antes; faz última leitura do status
                        final_status = read_sync_status()
                        break

                    time.sleep(2)

                # Encerra a conexão FreeRDP limpa assim que o script concluir
                if rdp_proc and rdp_proc.poll() is None:
                    try:
                        rdp_proc.terminate()
                        rdp_proc.wait(timeout=5)
                    except Exception:
                        try:
                            rdp_proc.kill()
                        except Exception:
                            pass

                if final_status and final_status.get('state') == 'completed':
                    # Garante montagem SMB atualizada no Nautilus
                    sync_script = os.path.expanduser('~/.local/bin/winapps-smb-sync.sh')
                    if os.path.exists(sync_script):
                        try:
                            subprocess.run([sync_script, '--once'], capture_output=True, timeout=20)
                        except Exception:
                            pass

                    self.last_sync_time = datetime.now().strftime('%H:%M')
                    msg = final_status.get('message') or 'Sincronização concluída!'
                    send_notification(
                        "OneDrive MPMS",
                        f"{msg} Arquivos atualizados em ~/OneDrive_MPMS.",
                    )
                elif final_status and final_status.get('state') == 'error':
                    err_msg = final_status.get('message') or 'Erro ao sincronizar OneDrive.'
                    send_notification("OneDrive MPMS — Erro", err_msg)
                else:
                    send_notification(
                        "OneDrive MPMS",
                        "Tempo limite de sincronização atingido. Verifique o OneDrive na VM se necessário.",
                    )
            except Exception as e:
                print(f"[OneDriveIndicator] Erro ao sincronizar arquivos: {e}")
                send_notification("OneDrive MPMS — Erro", f"Falha na sincronização: {e}")
            finally:
                if rdp_proc and rdp_proc.poll() is None:
                    try:
                        rdp_proc.terminate()
                    except Exception:
                        pass
                GLib.idle_add(self._set_sync_ui, False, None)
                GLib.timeout_add_seconds(1, self.check_status_async)

        threading.Thread(target=worker, daemon=True).start()

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
    if not HAS_GTK:
        raise RuntimeError("GTK3 e AyatanaAppIndicator3 são necessários para executar onedrive-indicator.py")
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    signal.signal(signal.SIGTERM, signal.SIG_DFL)
    _app = OneDriveIndicator()
    Gtk.main()


if __name__ == '__main__':
    main()
