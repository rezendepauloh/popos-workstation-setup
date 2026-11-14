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
# 1. Projetos Docker Compose
# ------------------------------------------------------------------------------
log_info "Buscando projetos Docker Compose ativos..."
mapfile -t COMPOSE_FILES < <(
    docker ps -a --format '{{.Label "com.docker.compose.project.config_files"}}' \
    | grep -v '^$' \
    | tr ',' '\n' \
    | sort -u
)

if [ ${#COMPOSE_FILES[@]} -eq 0 ]; then
    log_info "Nenhum projeto Docker Compose encontrado."
else
    for compose_file in "${COMPOSE_FILES[@]}"; do
        if [ ! -f "$compose_file" ]; then
            log_warn "Arquivo compose não encontrado: $compose_file (pulando)"
            continue
        fi
        project_dir="$(dirname "$compose_file")"
        log_info "Atualizando projeto Compose: $compose_file"
        if $DRY_RUN; then
            echo "  [dry-run] docker compose -f \"$compose_file\" pull --ignore-buildable"
            echo "  [dry-run] docker compose -f \"$compose_file\" up -d"
        else
            docker compose -f "$compose_file" pull --ignore-buildable || log_warn "Algumas imagens podem ser locais em $compose_file"
            docker compose -f "$compose_file" up -d
            log_ok "Projeto atualizado: $(basename "$project_dir")"
        fi
    done
fi

# ------------------------------------------------------------------------------
# 2. Containers Standalone (sem label com.docker.compose.project.config_files)
# ------------------------------------------------------------------------------
log_info "Buscando containers standalone..."
mapfile -t STANDALONE_CONTAINERS < <(
    docker ps -a --format '{{.Names}}|{{.Label "com.docker.compose.project.config_files"}}' \
    | awk -F'|' '$2 == "" {print $1}'
)

if [ ${#STANDALONE_CONTAINERS[@]} -eq 0 ]; then
    log_info "Nenhum container standalone encontrado."
else
    for cname in "${STANDALONE_CONTAINERS[@]}"; do
        image="$(docker inspect --format '{{.Config.Image}}' "$cname")"
        current_id="$(docker inspect --format '{{.Image}}' "$cname")"
        log_info "Verificando standalone '$cname' (imagem: $image)..."

        if $DRY_RUN; then
            echo "  [dry-run] docker pull \"$image\""
            continue
        fi

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

