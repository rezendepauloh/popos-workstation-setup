# 📝 Contexto e Diretrizes: Instalação e Configuração do Nextcloud Client no Pop!_OS (COSMIC Desktop / Wayland)

## 📌 1. Histórico e Conquistas Anteriores (Status: Concluído e Resolvido)
Nas sessões anteriores, resolvemos de forma definitiva e estruturada:
1. **Cedilha (`' + c = ç` e `' + C = Ç`)** no layout US-International com Dead Keys sob Wayland nativo.
2. **Aspas duplas (`Shift + '` 2x = `""`)** e **Aspas simples (`'` 2x = `''`)**, eliminando o trema (`¨`) e acento agudo isolado (`´`) nos navegadores e editores (Google Antigravity IDE, VS Code, Google Chrome e Brave) através do patch idempotente no compositor do Chromium (`scripts/patch_cedilla_electron.py`) e persistência via Hook do APT (`/etc/apt/apt.conf.d/99-patch-cedilla-electron`).
3. **Resolução de DNS Local Permanente (`192.168.0.8`) e Routing Domain (`~pk.local`)** configurado no Módulo 01 com failover para o `1.1.1.1` via `systemd-resolved` e `NetworkManager`.
4. **Alt Codes do Windows no Teclado Numérico (Status: Concluído e Ativo):** Implementado via daemon Python (`scripts/alt-numpad-daemon.py`) sob `evdev` + `uinput` gerenciado por `alt-numpad.service` (`systemctl --user`). Suporta ordinais (`º`, `ª`), parágrafo (`§`), grau (`°`), setas clássicas e triangulares (`⭡ ⭢ ⭣ ⭠` via <kbd>Alt</kbd>+`88`, `66`, `22`, `44`) e símbolos matemáticos. Sensibilidade de repetição perfeitamente calibrada (delay 300ms, rate 30ms).
5. **Servidor Samba e Compartilhamento de Armazenamento (`/mnt/storage_700/samba`):** Configurado no Módulo 25 (`scripts/25_samba_storage.sh`) com share `[Storage700]` espelhando a estrutura do UmbrelOS/Homelab, e o módulo de limpeza/hardening reordenado para a posição final 26 (`scripts/26_limpeza_otimizacao.sh`).
6. **Nextcloud Desktop Client (Status: Concluído e Integrado):**
   - Pacote oficial Flatpak (`com.nextcloud.desktopclient.nextcloud` via Flathub) adicionado no [`scripts/06_softwares_workflow.sh`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/scripts/06_softwares_workflow.sh) com pré-criação da pasta local de sync (`~/Nextcloud`).
   - Overrides de Flatpak configurados no [`scripts/19_flatpak_permissions.sh`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/scripts/19_flatpak_permissions.sh) concedendo acesso a `home`, `/mnt/storage_700`, `/mnt/storage_930` e barramentos de bandeja D-Bus (`org.kde.StatusNotifierWatcher` e `org.freedesktop.StatusNotifierWatcher`).
   - Autostart em segundo plano configurado no [`scripts/21_autostart_config.sh`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/scripts/21_autostart_config.sh) (`flatpak run com.nextcloud.desktopclient.nextcloud --background`).
   - Variáveis de ambiente `NEXTCLOUD_SERVER_URL` e `NEXTCLOUD_SYNC_DIR` documentadas no [`.env.example`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/.env.example).
7. **Atalhos do COSMIC (Padrão Windows & Produtividade):** Mapeamento persistente dos atalhos <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>S</kbd> (captura de tela interativa `cosmic-screenshot`) e <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>G</kbd> (fixar janelas no topo `ToggleSticky` / Always on Top / PiP) integrado no [`scripts/14_cosmic_theme_restore.sh`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/scripts/14_cosmic_theme_restore.sh) e sincronizado com o backup da nuvem (`~/GoogleDrive_Pessoal/Organização/Backup_COSMIC`).
8. **Backup e Restauração de Dispositivos Android via ADB ([`util/backup_android.sh`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/util/backup_android.sh) e [`util/restore_android.sh`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/util/restore_android.sh)):**
   - Cobertura expandida de diretórios: `Podcasts`, `VoiceRecorder`, `Sounds`, `Alarms`, `WhatsApp` legado, `WhatsApp Business`, `Telegram` (`/sdcard/Telegram` e `/sdcard/Android/media/org.telegram.messenger`).
   - Extração automática de instaladores `.apk` de todos os aplicativos instalados e reinstalação automatizada em lote no restore.
   - Reindexação profunda do `MediaScanner` pós-restauração para fotos, vídeos e músicas.
9. **Padronização de Aplicativos da Loja (Flatpaks Oficiais):**
   - **Calculadora GNOME** (`org.gnome.Calculator`) e **Flatseal** (`com.github.tchx84.Flatseal` - gerenciador gráfico de permissões) integrados nos scripts [`scripts/06_softwares_workflow.sh`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/scripts/06_softwares_workflow.sh), [`scripts/14_cosmic_theme_restore.sh`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/scripts/14_cosmic_theme_restore.sh) (janela flutuante) e [`scripts/15_cosmic_menu_dock.sh`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/scripts/15_cosmic_menu_dock.sh) (categoria Utilitários).
   - **Câmera Oficial do COSMIC** (`io.github.cosmic_utils.camera`) instalada e posicionada na categoria Mídia com regra de janela flutuante nativa.
10. **Web Apps do Microsoft 365 (Portal, Word, Excel, PowerPoint, Outlook):**
    - Configurados no [`scripts/23_trabalho_remoto_vpn_rdp.sh`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/scripts/23_trabalho_remoto_vpn_rdp.sh) como PWAs/janelas de aplicativo independentes via Chromium/Chrome.
    - Ícones oficiais SVG baixados da CDN da Microsoft e organizados na categoria **"Escritório & Trabalho Remoto"** do COSMIC App Library ([`scripts/15_cosmic_menu_dock.sh`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/scripts/15_cosmic_menu_dock.sh)), mantendo o OnlyOffice como editor local padrão.
11. **WinApps & Microsoft 365 (Word, Excel, PowerPoint, OneDrive MPMS Oficial):**
    - Módulo [`scripts/26_winapps_office.sh`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/scripts/26_winapps_office.sh) criado com stack Docker KVM acelerada (`dockurr/windows`), FreeRDP e helper de controle `winapps-vm`.
    - Script de limpeza e hardening renomeado de forma transparente para [`scripts/27_limpeza_otimizacao.sh`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/scripts/27_limpeza_otimizacao.sh) no orquestrador [`setup_popos_v2.sh`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/setup_popos_v2.sh).
    - Guia detalhado passo a passo de deploy e integração do OneDrive corporativo (Files On-Demand) com o Nautilus documentado em [`Docs/onedrive_winapps_mpms_guia.md`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/Docs/onedrive_winapps_mpms_guia.md).
12. Documentação técnica atualizada em [`Docs/issue_chromium_electron_cedilha_wayland.md`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/Docs/issue_chromium_electron_cedilha_wayland.md), [`Docs/issue_alt_codes_numpad_wayland.md`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/Docs/issue_alt_codes_numpad_wayland.md), [`Docs/onedrive_winapps_mpms_guia.md`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/Docs/onedrive_winapps_mpms_guia.md) e no [`README.md`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/README.md).

---

## 🎯 2. Próximos Objetivos & Validações

1. **Validação do Windows e Office 365 via WinApps:**
   - Subir o container Windows pela primeira vez com `winapps-vm start` e acompanhar em `http://127.0.0.1:8006`.
   - Efetuar login institucional no Portal Office / OneDrive MPMS com ativação de "Arquivos sob Demanda".
   - Executar o instalador do WinApps (`winapps-vm setup-apps`) para gerar os atalhos nativos no COSMIC Launcher.
2. **Mapeamento do Compartilhamento SMB do OneDrive no Nautilus:**
   - Conectar o marcador `OneDrive (MPMS)` apontando para `smb://127.0.0.1/OneDrive-MPMS` no Nautilus.

