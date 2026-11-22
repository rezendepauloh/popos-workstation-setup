# 🌐 Guia: Controle Remoto & Manutenção de Dispositivos na Rede (`util/remote-devices/`)

> Central de automação e controle remoto da rede local (LAN + Tailscale) diretamente do **Pop!_OS 24.04 LTS**, via terminal comum ou pela aba **Dispositivos (Rede)** do **Workstation & Homelab Hub**.

---

## 🔒 1. Configuração Segura (`.env`)

Todos os IPs, hostnames, MACs e tokens residem exclusivamente no arquivo local `.env` (protegido com `chmod 600` e ignorado pelo Git). Use a aba **Configurações → Editor `.env`** do Hub ou preencha a seção de dispositivos baseada em [`.env.example`](../../.env.example):

- `REMOTE_WIN_LAN_HOST` / `REMOTE_WIN_TS_HOST` / `REMOTE_WIN_USER` / `REMOTE_WIN_MAC`
- `REMOTE_ANDROID_LAN_HOST` / `REMOTE_ANDROID_TS_HOST` / `REMOTE_ANDROID_PORT` (padrão `5555`)
- `REMOTE_TV_IP` / `REMOTE_TV_MAC` / `REMOTE_PROJECTOR_IP` / `REMOTE_PROJECTOR_MAC`
- `HA_URL` / `HA_TOKEN` / `HA_ALEXA_NOTIFY_SERVICE`

---

## 💻 2. Windows 11 Remoto (`win_remote.sh`)

### Preparação única no Windows 11 (PowerShell como Administrador)
Execute o comando abaixo no Pop!_OS para gerar o snippet exato com a chave pública SSH desta máquina:

```bash
./util/remote-devices/win_remote.sh --setup-ssh-cmd
```

No **PowerShell Administrador** do Windows 11, certifique-se também de definir a rede como **Particular (Private)** e liberar as portas no Firewall (usando SIDs universais `*S-1-5-32-544` e `*S-1-5-18` para funcionar em Windows em Português):

```powershell
# Perfil de rede Particular + Firewall OpenSSH (porta 22)
Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private
New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -Profile Any -ErrorAction SilentlyContinue

# Habilitar RDP (porta 3389 — requer Windows 11 Pro/Enterprise; no Home use RustDesk ou Sunshine)
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Set-Service -Name TermService -StartupType Automatic
Start-Service TermService
New-NetFirewallRule -Name 'RDP-3389-TCP' -DisplayName 'RDP TCP 3389' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 3389 -Profile Any -ErrorAction SilentlyContinue
```

### Operações disponíveis (LAN ou Tailscale)
```bash
./util/remote-devices/win_remote.sh --mode lan --check          # Testa Ping, porta 22 e 3389
./util/remote-devices/win_remote.sh --mode lan --status         # OS, Uptime, RAM e espaço em disco
./util/remote-devices/win_remote.sh --mode lan --clean          # Limpa %TEMP%, Windows\Temp e Lixeira
./util/remote-devices/win_remote.sh --mode lan --winget-upgrade # Atualiza programas via winget
./util/remote-devices/win_remote.sh --mode lan --moonlight      # Abre tela remota via Moonlight/Sunshine (instala Flatpak se necessário)
./util/remote-devices/win_remote.sh --mode lan --rdp            # Abre tela remota RDP (xfreerdp3/remmina)
./util/remote-devices/win_remote.sh --wol                       # Envia Wake-on-LAN (via REMOTE_WIN_MAC)
```

---

## 📱 3. Android via Wi-Fi / Tailscale (`android_remote.sh`)

### Pré-requisitos
1. No celular, ative **Depuração sem fio** (ou conecte uma vez via USB e rode `adb tcpip 5555`).
2. Para espelhamento interativo de tela, o módulo `04_pacotes_base_dev.sh` instala o `scrcpy` oficial mais recente em `/opt/scrcpy` (`/usr/local/bin/scrcpy`). Para instalar manualmente (recomendado no Android 14+, pois o pacote `1.25` do APT é antigo):
   ```bash
   SCRCPY_URL=$(curl -fsSL https://api.github.com/repos/Genymobile/scrcpy/releases/latest | jq -r '.assets[] | select(.name | test("scrcpy-linux-x86_64-.*\\.tar\\.gz$")) | .browser_download_url')
   curl -fSL "$SCRCPY_URL" -o /tmp/scrcpy.tar.gz
   sudo rm -rf /opt/scrcpy && sudo mkdir -p /opt/scrcpy
   sudo tar -xzf /tmp/scrcpy.tar.gz -C /opt/scrcpy --strip-components=1
   sudo ln -sf /opt/scrcpy/scrcpy /usr/local/bin/scrcpy && rm -f /tmp/scrcpy.tar.gz
   ```

### Operações disponíveis
```bash
./util/remote-devices/android_remote.sh --mode lan --connect      # Conecta ADB Wi-Fi
./util/remote-devices/android_remote.sh --mode lan --status       # Modelo, bateria e df -h
./util/remote-devices/android_remote.sh --mode lan --clean-cache  # Executa pm trim-caches (sem root)
./util/remote-devices/android_remote.sh --mode lan --scrcpy       # Espelha e controla a tela via rede
```

---

## 📺 4. Smart TV & Projetor Samsung (`samsung_tv_remote.py`)

Comunicação local via API Tizen (`:8001` REST/WebSocket) e Wake-on-LAN UDP:

```bash
./util/remote-devices/samsung_tv_remote.py --target tv --status
./util/remote-devices/samsung_tv_remote.py --target tv --wol
./util/remote-devices/samsung_tv_remote.py --target tv --key KEY_VOLUP
./util/remote-devices/samsung_tv_remote.py --target projector --key KEY_POWER
```

> [!NOTE]
> Televisores e projetores Tizen aceitam controle remoto, status e Wake-on-LAN pela rede, mas não expõem API aberta para limpeza de cache de apps.

---

## 🔊 5. Alexa (via Home Assistant) & 🍏 Apple (iPhone/iPad)

- **Alexa (`ha_alexa_remote.sh`):** utiliza a API REST do **Home Assistant** rodando no Homelab (`HA_URL` + `HA_TOKEN`) para testar a API ou disparar avisos TTS/rotinas (`--notify "Mensagem"`).
- **iPhone & iPad:** por restrição de sandbox da Apple, não permitem SSH/RDP nem limpeza remota de cache via rede. Utilize `./util/remote-devices/network_scan.sh` para checar presença mDNS/ARP, **LocalSend** para envio de arquivos e conexão USB (`libimobiledevice`) caso deseje backups locais.
