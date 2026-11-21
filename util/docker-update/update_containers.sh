#!/bin/bash
set -e

# ==============================================================================
# Utilitário: Atualização de Todos os Containers Docker (Compose & Standalone)
# ==============================================================================
# Atualiza imagens e recria containers gerenciados via Docker Compose e
# containers standalone (como dozzle-agent), preservando configurações.
#
# Uso:
#   ./update_containers.sh           # Atualiza todos os containers e limpa imagens antigas
#   ./update_containers.sh --dry-run # Apenas verifica e exibe o que seria atualizado
# ==============================================================================

C_RESET="\033[0m"
C_BLUE="\033[1;34m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_RED="\033[1;31m"
C_CYAN="\033[1;36m"

DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
    esac
done

log_info()  { echo -e "${C_BLUE}[INFO]${C_RESET} $1"; }
log_ok()    { echo -e "${C_GREEN}[OK]${C_RESET} $1"; }
log_warn()  { echo -e "${C_YELLOW}[AVISO]${C_RESET} $1"; }
log_err()   { echo -e "${C_RED}[ERRO]${C_RESET} $1"; }

if ! command -v docker &>/dev/null; then
    log_err "Docker não encontrado no PATH."
    exit 1
fi

if ! docker info &>/dev/null; then
    log_err "Daemon do Docker não está acessível. Verifique permissões ou se o serviço está ativo."
    exit 1
fi

echo -e "${C_CYAN}================================================================${C_RESET}"
echo -e "${C_CYAN}   🐳 ATUALIZAÇÃO DE CONTAINERS DOCKER (COMPOSE & STANDALONE)   ${C_RESET}"
echo -e "${C_CYAN}================================================================${C_RESET}"
$DRY_RUN && log_warn "Modo --dry-run ativado: nenhuma alteração será aplicada."

# ------------------------------------------------------------------------------
# Helper Python para análise de versão/digest local vs remoto (--dry-run)
# ------------------------------------------------------------------------------
inspect_image_status() {
    local cname="$1"
    local image="$2"
    python3 - "$cname" "$image" <<'PYEOF'
import json, platform, subprocess, sys

cname, image = sys.argv[1], sys.argv[2]

def short_sha(s):
    if not s:
        return "desconhecido"
    s = s.replace("sha256:", "")
    return s[:12]

try:
    c_data = json.loads(subprocess.check_output(["docker", "inspect", cname], stderr=subprocess.DEVNULL))[0]
    img_id = c_data.get("Image", "")
    img_data = json.loads(subprocess.check_output(["docker", "inspect", img_id], stderr=subprocess.DEVNULL))[0]
except Exception:
    print(f"    • {cname} ({image}) -> [não foi possível inspecionar]")
    sys.exit(0)

labels = img_data.get("Config", {}).get("Labels") or {}
oci_ver = labels.get("org.opencontainers.image.version") or labels.get("version") or ""
repo_digests = img_data.get("RepoDigests") or []
local_digests = {d.split("@")[1] for d in repo_digests if "@" in d}
local_short = short_sha(next(iter(local_digests), img_id))
ver_info = f"v{oci_ver.lstrip('v')} | {local_short}" if oci_ver else local_short

arch_map = {"x86_64": "amd64", "aarch64": "arm64", "armv7l": "arm"}
host_arch = arch_map.get(platform.machine(), "amd64")

remote_digest = None
try:
    proc = subprocess.run(
        ["docker", "manifest", "inspect", "-v", image],
        capture_output=True, text=True, timeout=15
    )
    if proc.returncode == 0 and proc.stdout.strip():
        manifest = json.loads(proc.stdout)
        if isinstance(manifest, list):
            for entry in manifest:
                plat = (entry.get("Descriptor") or {}).get("platform") or {}
                if plat.get("os") == "linux" and plat.get("architecture") == host_arch:
                    remote_digest = (entry.get("Descriptor") or {}).get("digest")
                    break
            if not remote_digest and manifest:
                remote_digest = (manifest[0].get("Descriptor") or {}).get("digest")
        elif isinstance(manifest, dict):
            remote_digest = (manifest.get("Descriptor") or {}).get("digest")
except Exception:
    pass

if not remote_digest:
    status = "\033[1;33m⚠ Build local / não verificável remotamente\033[0m"
elif remote_digest in local_digests:
    status = "\033[1;32m✔ Atualizado\033[0m"
else:
    status = f"\033[1;36m⬆ Atualização disponível (remoto: {short_sha(remote_digest)})\033[0m"

print(f"    • {cname} | {image} | local: {ver_info} -> {status}")
PYEOF
}

# ------------------------------------------------------------------------------
# 1. Projetos Docker Compose
# ------------------------------------------------------------------------------
log_info "Buscando projetos Docker Compose ativos..."
mapfile -t COMPOSE_FILES < <(
    docker ps -a --format '{{.Label "com.docker.compose.project.config_files"}}' \
    | grep -v '^$' \
    | tr ',' '\n' \
    | sort -u
)

TOTAL_COMPOSE=${#COMPOSE_FILES[@]}
if [ "$TOTAL_COMPOSE" -eq 0 ]; then
    log_info "Nenhum projeto Docker Compose encontrado."
else
    idx=0
    for compose_file in "${COMPOSE_FILES[@]}"; do
        idx=$((idx + 1))
        if [ ! -f "$compose_file" ]; then
            log_warn "[$idx/$TOTAL_COMPOSE] Arquivo compose não encontrado: $compose_file (pulando)"
            continue
        fi
        project_dir="$(dirname "$compose_file")"
        project_name="$(basename "$project_dir")"

        if $DRY_RUN; then
            echo ""
            log_info "[$idx/$TOTAL_COMPOSE] Stack Compose: ${C_CYAN}$project_name${C_RESET} ($compose_file)"
            mapfile -t STACK_CONTAINERS < <(
                docker ps -a --format '{{.Names}}|{{.Config.Image}}|{{.Label "com.docker.compose.project.config_files"}}' 2>/dev/null \
                || docker ps -a --format '{{.Names}}|{{.Image}}|{{.Label "com.docker.compose.project.config_files"}}'
            )
            found_any=false
            for line in "${STACK_CONTAINERS[@]}"; do
                cname="${line%%|*}"
                rest="${line#*|}"
                cimg="${rest%%|*}"
                cfiles="${rest#*|}"
                if [[ ",$cfiles," == *",$compose_file,"* ]]; then
                    found_any=true
                    inspect_image_status "$cname" "$cimg"
                fi
            done
            if ! $found_any; then
                echo "    (nenhum container ativo encontrado para este compose)"
            fi
        else
            echo ""
            log_info "[$idx/$TOTAL_COMPOSE] Atualizando stack Compose: ${C_CYAN}$project_name${C_RESET} ($compose_file)"
            docker compose -f "$compose_file" pull --ignore-buildable || log_warn "Algumas imagens podem ser locais em $compose_file"
            docker compose -f "$compose_file" up -d
            log_ok "[$idx/$TOTAL_COMPOSE] Stack '$project_name' atualizada."
        fi
    done
fi

# ------------------------------------------------------------------------------
# 2. Containers Standalone (sem label com.docker.compose.project.config_files)
# ------------------------------------------------------------------------------
echo ""
log_info "Buscando containers standalone..."
mapfile -t STANDALONE_CONTAINERS < <(
    docker ps -a --format '{{.Names}}|{{.Label "com.docker.compose.project.config_files"}}' \
    | awk -F'|' '$2 == "" {print $1}'
)

TOTAL_STANDALONE=${#STANDALONE_CONTAINERS[@]}
if [ "$TOTAL_STANDALONE" -eq 0 ]; then
    log_info "Nenhum container standalone encontrado."
else
    s_idx=0
    for cname in "${STANDALONE_CONTAINERS[@]}"; do
        s_idx=$((s_idx + 1))
        image="$(docker inspect --format '{{.Config.Image}}' "$cname")"
        current_id="$(docker inspect --format '{{.Image}}' "$cname")"

        if $DRY_RUN; then
            log_info "[$s_idx/$TOTAL_STANDALONE] Standalone: ${C_CYAN}$cname${C_RESET}"
            inspect_image_status "$cname" "$image"
            continue
        fi

        echo ""
        log_info "[$s_idx/$TOTAL_STANDALONE] Atualizando standalone '${C_CYAN}$cname${C_RESET}' (imagem: $image)..."

        if ! docker pull "$image"; then
            log_warn "Não foi possível fazer pull de '$image' (pode ser imagem local). Pulando '$cname'."
            continue
        fi

        new_id="$(docker image inspect --format '{{.Id}}' "$image")"
        if [ "$current_id" = "$new_id" ]; then
            log_ok "'$cname' já está na versão mais recente."
        else
            log_warn "Nova versão encontrada para '$cname'. Recriando..."
            # Extrai parâmetros básicos via python3 para recriação segura
            recreate_cmd="$(python3 - "$cname" "$image" <<'PYEOF'
import json, subprocess, sys, shlex

cname, image = sys.argv[1], sys.argv[2]
data = json.loads(subprocess.check_output(["docker", "inspect", cname]))[0]
cfg = data.get("Config", {})
hcfg = data.get("HostConfig", {})

cmd = ["docker", "run", "-d", "--name", cname]

restart = (hcfg.get("RestartPolicy") or {}).get("Name")
if restart and restart != "no":
    cmd.extend(["--restart", restart])

net = hcfg.get("NetworkMode")
if net and net != "default":
    cmd.extend(["--network", net])

for port_spec, bindings in (hcfg.get("PortBindings") or {}).items():
    if bindings:
        for b in bindings:
            host_ip = b.get("HostIp") or ""
            host_port = b.get("HostPort") or ""
            mapping = f"{host_ip}:{host_port}:{port_spec}" if host_ip else f"{host_port}:{port_spec}"
            cmd.extend(["-p", mapping])

for bind in (hcfg.get("Binds") or []):
    cmd.extend(["-v", bind])

for env in (cfg.get("Env") or []):
    if not env.startswith("PATH="):
        cmd.extend(["-e", env])

cmd.append(image)
for c in (cfg.get("Cmd") or []):
    cmd.append(c)

print(" ".join(shlex.quote(x) for x in cmd))
PYEOF
)"
            docker stop "$cname" >/dev/null
            docker rm "$cname" >/dev/null
            eval "$recreate_cmd" >/dev/null
            log_ok "Container '$cname' atualizado e reiniciado."
        fi
    done
fi

# ------------------------------------------------------------------------------
# 3. Limpeza de imagens antigas (dangling)
# ------------------------------------------------------------------------------
if ! $DRY_RUN; then
    log_info "Removendo imagens antigas sem uso (dangling)..."
    docker image prune -f >/dev/null
    log_ok "Limpeza concluída."
fi

echo -e "${C_GREEN}✔ Atualização de containers Docker finalizada!${C_RESET}"

