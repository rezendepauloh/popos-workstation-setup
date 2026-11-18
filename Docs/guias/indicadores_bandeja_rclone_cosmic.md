# ☁️ Indicadores Nativos de Bandeja para Nuvens Rclone (COSMIC / Wayland)

Este guia documenta a arquitetura e operação dos indicadores de bandeja **StatusNotifierItem** (`AyatanaAppIndicator3`) integrados ao painel superior do **Pop!_OS 24.04 (COSMIC)** para as montagens Rclone pessoais (**Google Drive**, **OneDrive Pessoal** e **MEGA**).

---

## 🏗️ Arquitetura

Seguindo o padrão estabelecido por [`scripts/daemons/onedrive-indicator.py`](../../scripts/daemons/onedrive-indicator.py) (dedicado ao OneDrive MPMS corporativo), os três serviços pessoais compartilham um único daemon parametrizado:

- **Daemon:** [`scripts/daemons/rclone-cloud-indicator.py`](../../scripts/daemons/rclone-cloud-indicator.py) (instalado em `~/.local/bin/rclone-cloud-indicator.py`)
- **Provisionamento:** [`scripts/05_rclone_storage.sh`](../../scripts/05_rclone_storage.sh)

| Nuvem | Perfil (`--profile`) | Unidade Indicador (`systemd --user`) | Serviço Rclone | Ponto de Montagem | Ícone Dedicado |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Google Drive** | `gdrive-pessoal` | `gdrive-indicator.service` | `gdrive-pessoal.service` | `~/GoogleDrive_Pessoal` | `google-drive.svg` |
| **OneDrive Pessoal** | `onedrive-pessoal` | `onedrive-pessoal-indicator.service` | `onedrive-pessoal.service` | `~/OneDrive_Pessoal` | `onedrive-pessoal.svg` |
| **MEGA** | `mega-pessoal` | `mega-indicator.service` | `mega-pessoal.service` | `~/Mega_Pessoal` | `mega.svg` |

> [!NOTE]
> O ícone do **OneDrive Pessoal** (`onedrive-pessoal.svg`) utiliza a nuvem oficial da Microsoft com um emblema verde pessoal no canto inferior direito para diferenciá-lo visualmente do **OneDrive MPMS** (`onedrive.svg`) na barra superior do COSMIC.

---

## 📊 Status em Tempo Real & Ações Rápidas

A cada **15 segundos** (em thread em segundo plano, sem travar a UI GTK/Wayland), cada indicador coleta:
1. **Estado da Montagem & Systemd:** verifica `/proc/mounts` e `systemctl --user is-active <serviço>`.
2. **Espaço em Nuvem:** consulta `df -B1` sobre a montagem FUSE (espaço usado, total, percentual e disponível).
3. **Cache VFS & Fila de Upload:** soma os arquivos em `~/.cache/rclone/vfs/<remote>` e lê as entradas periódicas `vfs cache: cleaned:` via `journalctl --user`.

### Ações do Menu
- **📂 Abrir Pasta Local:** abre a pasta montada diretamente no **Nautilus** (com fallback `xdg-open`).
- **🌐 Abrir na Web:** abre a interface Web oficial da respectiva nuvem no navegador padrão.
- **🔄 Sincronizar / Atualizar Cache (SIGHUP):** envia `systemctl --user kill --signal=SIGHUP <serviço>`, forçando o `rclone mount` a descartar o cache de diretórios e buscar alterações remotas imediatamente sem desmontar arquivos abertos. Se o serviço estiver parado, inicia-o.
- **♻️ Remontar / Reiniciar Serviço:** executa `systemctl --user restart <serviço>` e atualiza o status em seguida.
- **🧹 Verificar Status & Cache Agora:** dispara uma checagem imediata sob demanda.
- **❌ Fechar Indicador:** encerra a instância do indicador na bandeja.

---

## 🛠️ Gerenciamento Manual

```bash
# Verificar status dos indicadores e montagens
systemctl --user status gdrive-indicator.service onedrive-pessoal-indicator.service mega-indicator.service

# Reiniciar um indicador específico
systemctl --user restart gdrive-indicator.service

# Reprovisionar ícones, daemon e serviços via módulo 05
sudo ./scripts/05_rclone_storage.sh --force
```
