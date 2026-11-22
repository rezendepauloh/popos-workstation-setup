#!/bin/bash
# ==============================================================================
# Utilitário: Controle & Manutenção Remota Windows 11 (SSH, RDP e Wake-on-LAN)
# ==============================================================================
# Uso:
#   ./win_remote.sh [--mode lan|tailscale] [--check|--status|--clean|--winget-upgrade|--rdp|--wol|--setup-ssh-cmd]
# ==============================================================================

set -eo pipefail

C_RESET='\033[0m'
C_CYAN='\033[1;36m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[1;31m'
C_BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"

if [ -f "$ENV_FILE" ] && [ ! -L "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

MODE="lan"
ACTION="--check"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            MODE="${2:-lan}"
            shift 2
            ;;
        --check|--status|--clean|--winget-upgrade|--rdp|--moonlight|--wol|--setup-ssh-cmd)
            ACTION="$1"
            shift
            ;;
        --help|-h)
            echo "Uso: $0 [--mode lan|tailscale] [--check|--status|--clean|--winget-upgrade|--rdp|--moonlight|--wol|--setup-ssh-cmd]"
            exit 0
            ;;
        *)
            echo -e "${C_RED}[ERRO] Argumento desconhecido: $1${C_RESET}" >&2
            exit 1
            ;;
    esac
done

TARGET_HOST="${REMOTE_WIN_LAN_HOST:-}"
if [ "$MODE" = "tailscale" ] && [ -n "${REMOTE_WIN_TS_HOST:-}" ]; then
    TARGET_HOST="$REMOTE_WIN_TS_HOST"
elif [ "$MODE" = "lan" ] && [ -n "$TARGET_HOST" ] && [ -n "${REMOTE_WIN_TS_HOST:-}" ]; then
    # Fallback automático para Tailscale caso o host/IP da LAN não responda na porta 22
    if ! timeout 1 bash -c "exec 3<>/dev/tcp/$TARGET_HOST/22" 2>/dev/null; then
        echo -e "${C_YELLOW}[INFO] LAN ($TARGET_HOST:22) sem resposta — usando fallback Tailscale ($REMOTE_WIN_TS_HOST)...${C_RESET}"
        TARGET_HOST="$REMOTE_WIN_TS_HOST"
    fi
fi
TARGET_USER="${REMOTE_WIN_USER:-}"
TARGET_MAC="${REMOTE_WIN_MAC:-}"

validate_token() {
    local val="$1"
    local name="$2"
    if [[ -z "$val" ]] || [[ ! "$val" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        echo -e "${C_RED}[ERRO] Variável '$name' ausente ou inválida no .env (Configure em Configurações -> .env).${C_RESET}" >&2
        exit 1
    fi
}

if [ "$ACTION" = "--setup-ssh-cmd" ]; then
    PUB_KEY=""
    for k in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub"; do
        if [ -f "$k" ]; then
            PUB_KEY=$(cat "$k")
            break
        fi
    done
    echo -e "${C_CYAN}${C_BOLD}=== HABILITAR OPENSSH SERVER NO WINDOWS 11 (POWERSHELL ADMIN) ===${C_RESET}"
    echo -e "${C_YELLOW}Execute os comandos abaixo no PowerShell como Administrador no Windows 11:${C_RESET}\n"
    cat << 'PS1'
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -ErrorAction SilentlyContinue
PS1
    if [ -n "$PUB_KEY" ]; then
        echo ""
        echo -e "${C_GREEN}# Para login SSH sem senha usando a chave deste Pop!_OS:${C_RESET}"
        echo "Add-Content -Path \"\$env:ProgramData\\ssh\\administrators_authorized_keys\" -Value \"$PUB_KEY\""
        echo "icacls \"\$env:ProgramData\\ssh\\administrators_authorized_keys\" /inheritance:r /grant \"*S-1-5-32-544:F\" /grant \"*S-1-5-18:F\""
    fi
    exit 0
fi

if [ "$ACTION" = "--wol" ]; then
    if [[ -z "$TARGET_MAC" ]] || [[ ! "$TARGET_MAC" =~ ^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$ ]]; then
        echo -e "${C_RED}[ERRO] REMOTE_WIN_MAC ausente ou inválido no .env (formato esperado AA:BB:CC:DD:EE:FF).${C_RESET}" >&2
        exit 1
    fi
    echo -e "${C_CYAN}[INFO] Enviando pacote Wake-on-LAN para $TARGET_MAC...${C_RESET}"
    python3 - "$TARGET_MAC" <<'PYEOF'
import socket, sys
mac = sys.argv[1].replace(":", "").replace("-", "")
payload = b"\xff" * 6 + bytes.fromhex(mac) * 16
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    s.sendto(payload, ("255.255.255.255", 9))
print("[OK] Pacote mágico Wake-on-LAN enviado!")
PYEOF
    exit 0
fi

validate_token "$TARGET_HOST" "REMOTE_WIN_LAN_HOST / REMOTE_WIN_TS_HOST"

if [ "$ACTION" = "--check" ]; then
    echo -e "${C_CYAN}${C_BOLD}=== DIAGNÓSTICO DE REDE: $TARGET_HOST ($MODE) ===${C_RESET}"
    if ping -c 1 -W 2 "$TARGET_HOST" >/dev/null 2>&1; then
        echo -e "${C_GREEN}[✔] Ping ICMP OK ($TARGET_HOST)${C_RESET}"
    else
        echo -e "${C_YELLOW}[!] Ping ICMP sem resposta (firewall do Windows pode bloquear ICMP)${C_RESET}"
    fi

    for port_info in "22:OpenSSH" "3389:RDP"; do
        p="${port_info%%:*}"
        name="${port_info#*:}"
        if timeout 2 bash -c "exec 3<>/dev/tcp/$TARGET_HOST/$p" 2>/dev/null; then
            echo -e "${C_GREEN}[✔] Porta $p ($name) ABERTA${C_RESET}"
        else
            echo -e "${C_RED}[✖] Porta $p ($name) FECHADA ou inacessível${C_RESET}"
        fi
    done

    if [ -n "$TARGET_USER" ] && [[ "$TARGET_USER" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        if ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "${TARGET_USER}@${TARGET_HOST}" "echo ok" >/dev/null 2>&1; then
            echo -e "${C_GREEN}[✔] SSH autenticado por chave com sucesso (${TARGET_USER}@${TARGET_HOST})${C_RESET}"
        else
            echo -e "${C_YELLOW}[!] SSH sem chave configurada ou OpenSSH inativo.${C_RESET}"
        fi
    fi
    exit 0
fi

validate_token "$TARGET_USER" "REMOTE_WIN_USER"

if [ "$ACTION" = "--moonlight" ]; then
    if command -v flatpak >/dev/null 2>&1; then
        if ! flatpak list --app 2>/dev/null | grep -q "com.moonlight_stream.Moonlight"; then
            echo -e "${C_CYAN}[INFO] Moonlight não encontrado. Instalando com.moonlight_stream.Moonlight via Flatpak...${C_RESET}"
            flatpak install -y flathub com.moonlight_stream.Moonlight
        fi
        echo -e "${C_CYAN}[INFO] Abrindo Moonlight (Sunshine Desktop)...${C_RESET}"
        exec flatpak run com.moonlight_stream.Moonlight
    elif command -v moonlight-qt >/dev/null 2>&1; then
        exec moonlight-qt
    else
        echo -e "${C_RED}[ERRO] Flatpak ou moonlight-qt não encontrado.${C_RESET}" >&2
        exit 1
    fi
fi

if [ "$ACTION" = "--rdp" ]; then
    echo -e "${C_CYAN}[INFO] Abrindo sessão RDP para ${TARGET_USER}@${TARGET_HOST}...${C_RESET}"
    if command -v xfreerdp3 >/dev/null 2>&1; then
        exec xfreerdp3 /v:"$TARGET_HOST" /u:"$TARGET_USER" /dynamic-resolution +clipboard /cert:ignore
    elif command -v xfreerdp >/dev/null 2>&1; then
        exec xfreerdp /v:"$TARGET_HOST" /u:"$TARGET_USER" /dynamic-resolution +clipboard /cert:ignore
    elif command -v remmina >/dev/null 2>&1; then
        exec remmina -c "rdp://${TARGET_USER}@${TARGET_HOST}"
    else
        echo -e "${C_RED}[ERRO] Nenhum cliente RDP (xfreerdp3/remmina) encontrado.${C_RESET}" >&2
        exit 1
    fi
fi

SSH_TARGET="${TARGET_USER}@${TARGET_HOST}"
SSH_OPTS=(-o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new)

if [ "$ACTION" = "--status" ]; then
    echo -e "${C_CYAN}${C_BOLD}=== STATUS REMOTO WINDOWS 11 ($SSH_TARGET) ===${C_RESET}"
    ssh "${SSH_OPTS[@]}" "$SSH_TARGET" 'powershell -NoProfile -Command "
        $os = Get-CimInstance Win32_OperatingSystem;
        $uptime = (Get-Date) - $os.LastBootUpTime;
        $ramTotal = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1);
        $ramFree = [math]::Round($os.FreePhysicalMemory / 1MB, 1);
        Write-Host \"Sistema: $($os.Caption) ($($os.Version))\";
        Write-Host \"Uptime: $($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m\";
        Write-Host \"RAM Livre: $ramFree GB / $ramTotal GB\";
        Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null -or $_.Free -ne $null } | ForEach-Object {
            $free = [math]::Round($_.Free / 1GB, 2);
            $used = [math]::Round($_.Used / 1GB, 2);
            Write-Host \"Disco $($_.Name): Livre $free GB | Usado $used GB\";
        }
    "'
elif [ "$ACTION" = "--clean" ]; then
    echo -e "${C_CYAN}${C_BOLD}=== LIMPEZA DE CACHE E TEMPORÁRIOS WINDOWS 11 ($SSH_TARGET) ===${C_RESET}"
    ssh "${SSH_OPTS[@]}" "$SSH_TARGET" 'powershell -NoProfile -Command "
        $before = [math]::Round((Get-PSDrive C).Free / 1GB, 2);
        Write-Host \"Espaço livre antes em C:: $before GB\";
        $paths = @($env:TEMP, \"C:\\Windows\\Temp\", \"$env:LOCALAPPDATA\\Temp\");
        foreach ($p in $paths) {
            if (Test-Path $p) {
                Get-ChildItem -Path $p -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue;
            }
        }
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue;
        $after = [math]::Round((Get-PSDrive C).Free / 1GB, 2);
        $diff = [math]::Round(($after - $before) * 1024, 1);
        Write-Host \"Espaço livre depois em C:: $after GB (Recuperado: $diff MB)\";
    "'
elif [ "$ACTION" = "--winget-upgrade" ]; then
    echo -e "${C_CYAN}${C_BOLD}=== ATUALIZANDO PACOTES VIA WINGET ($SSH_TARGET) ===${C_RESET}"
    ssh "${SSH_OPTS[@]}" "$SSH_TARGET" 'winget upgrade --all --accept-source-agreements --accept-package-agreements'
fi
