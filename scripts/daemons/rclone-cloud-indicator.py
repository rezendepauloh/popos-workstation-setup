#!/usr/bin/env python3
"""
rclone-cloud-indicator.py
AppIndicator/StatusNotifierItem daemon for Rclone cloud mounts on Wayland/COSMIC Desktop.
Supports parameterized profiles:
- gdrive-pessoal   (Google Drive -> ~/GoogleDrive_Pessoal)
- onedrive-pessoal (OneDrive Pessoal -> ~/OneDrive_Pessoal)
- mega-pessoal     (MEGA -> ~/Mega_Pessoal)

Provides a native panel tray icon with real-time status and quick actions:
- Mount & systemd service status (Connected / Disconnected)
- Cloud storage usage (df over FUSE mount) & VFS cache / pending uploads
- Open Local Folder in Nautilus
- Open Cloud Service in Web Browser
- Flush directory cache / sync (SIGHUP) & Remount / Restart systemd service
- Quit Indicator
"""

import argparse
import os
import re
import shutil
import signal
import subprocess
import sys
import threading

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


CLOUD_PROFILES = {
    'gdrive-pessoal': {
        'app_id': 'gdrive-indicator',
        'title': 'Google Drive',
        'short_name': 'Google Drive',
        'remote': 'gdrive_pessoal',
        'mount_service': 'gdrive-pessoal.service',
        'local_path': '~/GoogleDrive_Pessoal',
        'display_path': '~/GoogleDrive_Pessoal',
        'web_url': 'https://drive.google.com/',
        'icon_name': 'google-drive',
    },
    'onedrive-pessoal': {
        'app_id': 'onedrive-pessoal-indicator',
        'title': 'OneDrive Pessoal',
        'short_name': 'OneDrive Pessoal',
        'remote': 'onedrive_pessoal',
        'mount_service': 'onedrive-pessoal.service',
        'local_path': '~/OneDrive_Pessoal',
        'display_path': '~/OneDrive_Pessoal',
        'web_url': 'https://onedrive.live.com/',
        'icon_name': 'onedrive-pessoal',
    },
    'mega-pessoal': {
        'app_id': 'mega-indicator',
        'title': 'MEGA Pessoal',
        'short_name': 'MEGA',
        'remote': 'mega_pessoal',
        'mount_service': 'mega-pessoal.service',
        'local_path': '~/Mega_Pessoal',
        'display_path': '~/Mega_Pessoal',
        'web_url': 'https://mega.nz/fm',
        'icon_name': 'mega',
    },
}

_VFS_CLEANED_RE = re.compile(
    r'vfs cache:\s+cleaned:\s+objects\s+(\d+)\s+\(was\s+\d+\)\s+'
    r'in use\s+(\d+),\s+to upload\s+(\d+),\s+uploading\s+(\d+),\s+total size\s+([^\s(]+)'
)


def format_bytes(num_bytes):
    """Formata tamanho em bytes para unidade legível (B, KB, MB, GB, TB)."""
    try:
        value = float(num_bytes)
    except (TypeError, ValueError):
        return '0 B'
    if value < 0:
        value = 0.0
    units = ('B', 'KB', 'MB', 'GB', 'TB', 'PB')
    idx = 0
    while value >= 1024.0 and idx < len(units) - 1:
        value /= 1024.0
        idx += 1
    if idx == 0:
        return f"{int(value)} B"
    return f"{value:.1f} {units[idx]}"


def get_icon_name(icon_name):
    """Retorna o caminho completo do ícone PNG colorido (evita tinting simbólico de SVG no COSMIC)."""
    candidates = [
        os.path.expanduser(f'~/.local/share/icons/hicolor/48x48/apps/{icon_name}.png'),
        os.path.expanduser(f'~/.local/share/icons/hicolor/64x64/apps/{icon_name}.png'),
        f'/usr/share/pixmaps/{icon_name}.png',
        os.path.expanduser(f'~/.local/share/icons/hicolor/scalable/apps/{icon_name}.svg'),
        f'/usr/share/pixmaps/{icon_name}.svg',
    ]
    for path in candidates:
        if os.path.exists(path):
            return path
    return icon_name


def _unescape_mount_path(raw_path):
    """Decodifica escapes octais de /proc/mounts (ex: \\040 para espaço)."""
    return re.sub(r'\\([0-7]{3})', lambda m: chr(int(m.group(1), 8)), raw_path)


def is_mountpoint_active(local_path, mounts_file='/proc/mounts'):
    """Verifica em /proc/mounts se o diretório local está montado."""
    target = os.path.abspath(os.path.expanduser(local_path))
    target_real = os.path.realpath(target)
    try:
        with open(mounts_file, 'r', encoding='utf-8', errors='replace') as f:
            for line in f:
                parts = line.split()
                if len(parts) < 3:
                    continue
                mount_point = _unescape_mount_path(parts[1])
                if mount_point == target or mount_point == target_real:
                    return True
    except OSError:
        return False
    return False


def get_systemd_service_state(service_name):
    """Consulta o estado do serviço systemd --user (active, inactive, failed, etc.)."""
    try:
        res = subprocess.run(
            ['systemctl', '--user', 'is-active', service_name],
            capture_output=True,
            text=True,
            timeout=3,
        )
        state = res.stdout.strip()
        return state if state else 'unknown'
    except Exception:
        return 'unknown'


def get_mount_space_info(local_path):
    """Obtém uso e espaço disponível via df -B1 sobre a montagem FUSE."""
    target = os.path.abspath(os.path.expanduser(local_path))
    env = os.environ.copy()
    env['LC_ALL'] = 'C'
    try:
        res = subprocess.run(
            ['df', '-B1', '--output=size,used,avail,pcent', target],
            capture_output=True,
            text=True,
            env=env,
            timeout=3,
        )
        if res.returncode != 0:
            return None
        lines = [ln.strip() for ln in res.stdout.splitlines() if ln.strip()]
        if len(lines) < 2:
            return None
        cols = lines[-1].split()
        if len(cols) < 4:
            return None
        return {
            'total': int(cols[0]),
            'used': int(cols[1]),
            'avail': int(cols[2]),
            'pcent': cols[3],
        }
    except Exception:
        return None


def parse_vfs_journal_line(line):
    """Extrai métricas da linha de log periódica do cache VFS do rclone."""
    match = _VFS_CLEANED_RE.search(line or '')
    if not match:
        return None
    return {
        'objects': int(match.group(1)),
        'in_use': int(match.group(2)),
        'to_upload': int(match.group(3)),
        'uploading': int(match.group(4)),
        'total_size_str': match.group(5),
    }


def get_vfs_cache_info(remote_name, service_name, cache_base=None):
    """Coleta tamanho local do cache VFS e contadores de upload pendentes no journald."""
    if cache_base is None:
        cache_base = os.path.expanduser('~/.cache/rclone/vfs')
    vfs_dir = os.path.join(cache_base, remote_name)
    cache_bytes = 0
    cache_files = 0
    if os.path.isdir(vfs_dir):
        try:
            for root, _, files in os.walk(vfs_dir):
                for fname in files:
                    fpath = os.path.join(root, fname)
                    try:
                        cache_bytes += os.path.getsize(fpath)
                        cache_files += 1
                    except OSError:
                        pass
        except OSError:
            pass

    journal_info = None
    try:
        res = subprocess.run(
            ['journalctl', '--user', '-u', service_name, '-n', '15', '--no-pager', '-o', 'cat'],
            capture_output=True,
            text=True,
            timeout=2,
        )
        if res.returncode == 0:
            for line in reversed(res.stdout.splitlines()):
                parsed = parse_vfs_journal_line(line)
                if parsed is not None:
                    journal_info = parsed
                    break
    except Exception:
        pass

    return {
        'cache_bytes': cache_bytes,
        'cache_files': cache_files,
        'to_upload': journal_info['to_upload'] if journal_info else 0,
        'uploading': journal_info['uploading'] if journal_info else 0,
        'in_use': journal_info['in_use'] if journal_info else 0,
        'objects': journal_info['objects'] if journal_info else cache_files,
    }


class RcloneCloudIndicator:
    """Indicador StatusNotifierItem reutilizável para montagens Rclone no COSMIC."""

    def __init__(self, profile_key):
        if profile_key not in CLOUD_PROFILES:
            raise ValueError(f"Perfil desconhecido: {profile_key}")
        self.profile_key = profile_key
        self.profile = CLOUD_PROFILES[profile_key]
        self.local_path = os.path.expanduser(self.profile['local_path'])
        self.is_connected = False

        icon_name = get_icon_name(self.profile['icon_name'])
        self.indicator = AyatanaAppIndicator3.Indicator.new(
            self.profile['app_id'],
            icon_name,
            AyatanaAppIndicator3.IndicatorCategory.APPLICATION_STATUS,
        )
        self.indicator.set_status(AyatanaAppIndicator3.IndicatorStatus.ACTIVE)
        self.indicator.set_title(self.profile['title'])

        self.build_menu()
        self.check_status_async()
        GLib.timeout_add_seconds(15, self.on_timer_check)

    def build_menu(self):
        self.menu = Gtk.Menu()
        title = self.profile['title']
        short_name = self.profile['short_name']
        display_path = self.profile['display_path']

        self.status_item = Gtk.MenuItem(label=f"⏳ {title}: Verificando...")
        self.status_item.set_sensitive(False)
        self.menu.append(self.status_item)

        self.space_item = Gtk.MenuItem(label="💾 Espaço: Verificando...")
        self.space_item.set_sensitive(False)
        self.menu.append(self.space_item)

        self.vfs_item = Gtk.MenuItem(label="📦 Cache VFS: Verificando...")
        self.vfs_item.set_sensitive(False)
        self.menu.append(self.vfs_item)

        self.menu.append(Gtk.SeparatorMenuItem())

        item_open = Gtk.MenuItem(label=f"📂 Abrir Pasta Local ({display_path})")
        item_open.connect('activate', self.on_open_folder)
        self.menu.append(item_open)

        item_web = Gtk.MenuItem(label=f"🌐 Abrir {short_name} na Web")
        item_web.connect('activate', self.on_open_web)
        self.menu.append(item_web)

        self.menu.append(Gtk.SeparatorMenuItem())

        item_sync = Gtk.MenuItem(label="🔄 Sincronizar / Atualizar Cache (SIGHUP)")
        item_sync.connect('activate', self.on_sync_cache)
        self.menu.append(item_sync)

        item_remount = Gtk.MenuItem(label="♻️ Remontar / Reiniciar Serviço")
        item_remount.connect('activate', self.on_remount_service)
        self.menu.append(item_remount)

        item_refresh = Gtk.MenuItem(label="🧹 Verificar Status & Cache Agora")
        item_refresh.connect('activate', self.on_manual_refresh)
        self.menu.append(item_refresh)

        self.menu.append(Gtk.SeparatorMenuItem())

        item_quit = Gtk.MenuItem(label="❌ Fechar Indicador")
        item_quit.connect('activate', self.on_quit)
        self.menu.append(item_quit)

        self.menu.show_all()
        self.indicator.set_menu(self.menu)

    def collect_status(self):
        mounted = is_mountpoint_active(self.local_path)
        svc_state = get_systemd_service_state(self.profile['mount_service'])
        space_info = get_mount_space_info(self.local_path) if mounted else None
        vfs_info = get_vfs_cache_info(self.profile['remote'], self.profile['mount_service'])
        return {
            'mounted': mounted,
            'svc_state': svc_state,
            'space': space_info,
            'vfs': vfs_info,
        }

    def update_ui_status(self, status):
        title = self.profile['title']
        mounted = status['mounted']
        svc_state = status['svc_state']
        self.is_connected = mounted

        if mounted and svc_state == 'active':
            self.status_item.set_label(f"● {title}: Conectado (Montado)")
        elif mounted:
            self.status_item.set_label(f"◐ {title}: Montado (serviço: {svc_state})")
        elif svc_state == 'activating':
            self.status_item.set_label(f"⏳ {title}: Conectando...")
        else:
            self.status_item.set_label(f"○ {title}: Desconectado ({svc_state})")

        space = status.get('space')
        if mounted and space:
            used_fmt = format_bytes(space['used'])
            total_fmt = format_bytes(space['total'])
            avail_fmt = format_bytes(space['avail'])
            self.space_item.set_label(
                f"💾 Espaço: {used_fmt} / {total_fmt} ({space['pcent']}) — {avail_fmt} livre"
            )
        else:
            self.space_item.set_label("💾 Espaço: Indisponível")

        vfs = status.get('vfs') or {}
        cache_fmt = format_bytes(vfs.get('cache_bytes', 0))
        to_upload = vfs.get('to_upload', 0)
        uploading = vfs.get('uploading', 0)
        cache_files = vfs.get('cache_files', 0)
        if uploading > 0 or to_upload > 0:
            self.vfs_item.set_label(
                f"📦 Cache VFS: {cache_fmt} ({uploading} env. / {to_upload} pendente)"
            )
        else:
            self.vfs_item.set_label(
                f"📦 Cache VFS: {cache_fmt} ({cache_files} arq. — Sincronizado)"
            )
        return False

    def check_status_async(self):
        def worker():
            status = self.collect_status()
            GLib.idle_add(self.update_ui_status, status)

        threading.Thread(target=worker, daemon=True).start()

    def on_timer_check(self):
        self.check_status_async()
        return True

    def on_open_folder(self, _widget):
        try:
            nautilus_bin = shutil.which('nautilus')
            if nautilus_bin:
                subprocess.Popen([nautilus_bin, self.local_path])
            else:
                subprocess.Popen(['xdg-open', self.local_path])
        except Exception as e:
            print(f"[{self.profile['app_id']}] Erro ao abrir pasta: {e}")

    def on_open_web(self, _widget):
        try:
            subprocess.Popen(['xdg-open', self.profile['web_url']])
        except Exception as e:
            print(f"[{self.profile['app_id']}] Erro ao abrir navegador: {e}")

    def on_sync_cache(self, _widget):
        svc = self.profile['mount_service']
        self.status_item.set_label(f"⏳ {self.profile['title']}: Atualizando cache...")

        def worker():
            try:
                state = get_systemd_service_state(svc)
                if state == 'active':
                    subprocess.run(
                        ['systemctl', '--user', 'kill', '--signal=SIGHUP', svc],
                        capture_output=True,
                        timeout=10,
                    )
                else:
                    subprocess.run(
                        ['systemctl', '--user', 'start', svc],
                        capture_output=True,
                        timeout=20,
                    )
            except Exception as e:
                print(f"[{self.profile['app_id']}] Erro ao sincronizar cache: {e}")
            GLib.timeout_add_seconds(2, lambda: (self.check_status_async(), False)[1])

        threading.Thread(target=worker, daemon=True).start()

    def on_remount_service(self, _widget):
        svc = self.profile['mount_service']
        self.status_item.set_label(f"⏳ {self.profile['title']}: Remontando serviço...")

        def worker():
            try:
                subprocess.run(
                    ['systemctl', '--user', 'restart', svc],
                    capture_output=True,
                    timeout=25,
                )
            except Exception as e:
                print(f"[{self.profile['app_id']}] Erro ao remontar serviço: {e}")
            GLib.timeout_add_seconds(2, lambda: (self.check_status_async(), False)[1])

        threading.Thread(target=worker, daemon=True).start()

    def on_manual_refresh(self, _widget):
        self.status_item.set_label(f"⏳ {self.profile['title']}: Verificando...")
        self.check_status_async()

    def on_quit(self, _widget):
        Gtk.main_quit()


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description='Indicador de bandeja StatusNotifierItem para montagens Rclone no COSMIC/Wayland.'
    )
    parser.add_argument(
        '--profile',
        required=True,
        choices=sorted(CLOUD_PROFILES.keys()),
        help='Perfil de nuvem configurado no Rclone.',
    )
    return parser.parse_args(argv)


def main():
    args = parse_args()
    if not HAS_GTK:
        print(
            "[rclone-cloud-indicator] Erro: dependências GTK3 / AyatanaAppIndicator3 não disponíveis.",
            file=sys.stderr,
        )
        sys.exit(1)

    signal.signal(signal.SIGINT, signal.SIG_DFL)
    signal.signal(signal.SIGTERM, signal.SIG_DFL)
    _app = RcloneCloudIndicator(args.profile)
    Gtk.main()


if __name__ == '__main__':
    main()
