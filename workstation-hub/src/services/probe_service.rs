use crate::models::status::{
    DockerContainerInfo, DockerImageUpdateInfo, DockerSystemInfo, DockerUpdateState, HubPaths,
    NetworkHostStatus, NetworkMonitorInfo, RemoteDevicesInfo, SystemHardwareInfo, SystemSnapshot,
    TailscalePeerStatus,
};
use crate::services::env_service::read_env_map;
use crate::services::progress_service::read_completed_flags;
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;
use tokio::process::Command;

pub async fn collect_snapshot(paths: &HubPaths) -> SystemSnapshot {
    let completed_flags = read_completed_flags(&paths.popos_repo);
    let (homelab_local_host, homelab_tailscale_host, homelab_domain, homelab_user) =
        resolve_homelab_targets(&paths.homelab_repo);

    let (
        adb_devices,
        docker_res,
        docker_info,
        hardware_info,
        antigravity_version,
        homelab_online,
        vpn_mpms_ip,
        tailscale_ip,
        remote_devices,
    ) = tokio::join!(
        probe_adb_devices(),
        probe_docker_and_winapps(),
        probe_docker_info(),
        probe_hardware_info(),
        probe_antigravity_version(),
        probe_homelab_ssh(&homelab_local_host, &homelab_user),
        probe_vpn_mpms_ip(),
        probe_tailscale_ip(),
        probe_remote_devices(&paths.popos_repo),
    );

    let (network_info, panel_tray_info) = tokio::join!(
        probe_network_monitor(
            &paths.popos_repo,
            &homelab_local_host,
            &homelab_tailscale_host,
            &remote_devices,
        ),
        crate::services::panel_tray_service::probe_panel_and_tray(),
    );

    let local_android_backups = list_android_backups();
    let log_files = list_log_files(paths);
    let hub_executions = dirs::state_dir()
        .or_else(dirs::data_local_dir)
        .map(|d| crate::services::log_service::parse_hub_executions(&d.join("workstation-hub").join("logs")))
        .unwrap_or_default();

    SystemSnapshot {
        completed_flags,
        adb_devices,
        docker_active: docker_res.0,
        docker_info,
        hardware_info,
        network_info,
        panel_tray_info,
        winapps_running: docker_res.1,
        antigravity_version,
        homelab_online: Some(homelab_online),
        homelab_local_host,
        homelab_tailscale_host,
        homelab_domain,
        homelab_user,
        vpn_mpms_ip,
        tailscale_ip,
        remote_devices,
        local_android_backups,
        log_files,
        hub_executions,
    }
}

pub fn resolve_homelab_targets(homelab_repo: &Path) -> (String, String, String, String) {
    let cfg_path = homelab_repo.join("config.env");
    let map = read_env_map(&cfg_path);
    let local_host = map
        .get("SERVER_HOST")
        .or_else(|| map.get("STATIC_IP"))
        .filter(|s| !s.trim().is_empty())
        .cloned()
        .unwrap_or_else(|| "umbrel.local".to_string());
    let tailscale_host = map
        .get("TAILSCALE_HOSTNAME")
        .or_else(|| map.get("TAILSCALE_IP"))
        .filter(|s| !s.trim().is_empty())
        .cloned()
        .unwrap_or_default();
    let domain = map
        .get("HOMELAB_DOMAIN")
        .filter(|s| !s.trim().is_empty())
        .cloned()
        .unwrap_or_else(|| "pk.local".to_string());
    let user = map
        .get("SYSTEM_USER")
        .or_else(|| map.get("SERVER_USER"))
        .filter(|s| !s.trim().is_empty())
        .cloned()
        .unwrap_or_else(|| "umbrel".to_string());
    (local_host, tailscale_host, domain, user)
}

async fn probe_adb_devices() -> Vec<String> {
    let Ok(Ok(out)) = tokio::time::timeout(
        Duration::from_secs(2),
        Command::new("adb").arg("devices").output(),
    )
    .await
    else {
        return Vec::new();
    };
    if !out.status.success() {
        return Vec::new();
    }
    let text = String::from_utf8_lossy(&out.stdout);
    text.lines()
        .skip(1)
        .filter_map(|line| {
            let mut parts = line.split_whitespace();
            let id = parts.next()?;
            let state = parts.next()?;
            if state == "device" {
                Some(id.to_string())
            } else {
                None
            }
        })
        .collect()
}

async fn probe_docker_and_winapps() -> (bool, bool) {
    let Ok(Ok(out)) = tokio::time::timeout(
        Duration::from_secs(2),
        Command::new("docker")
            .args(["ps", "--format", "{{.Names}}"])
            .output(),
    )
    .await
    else {
        return (false, false);
    };
    if !out.status.success() {
        return (false, false);
    }
    let text = String::from_utf8_lossy(&out.stdout);
    let winapps = text.lines().any(|l| l.trim() == "winapps-windows");
    (true, winapps)
}

async fn probe_docker_info() -> DockerSystemInfo {
    let mut info = DockerSystemInfo::default();
    let Ok(Ok(ps_out)) = tokio::time::timeout(
        Duration::from_secs(2),
        Command::new("docker")
            .args([
                "ps",
                "-a",
                "--format",
                "{{.Names}}|{{.Image}}|{{.Status}}|{{.Label \"com.docker.compose.project.working_dir\"}}",
            ])
            .output(),
    )
    .await
    else {
        return info;
    };
    if !ps_out.status.success() {
        return info;
    }
    info.daemon_active = true;
    for line in String::from_utf8_lossy(&ps_out.stdout).lines() {
        let parts: Vec<&str> = line.splitn(4, '|').collect();
        if parts.len() < 3 {
            continue;
        }
        let status = parts[2].trim().to_string();
        let running = status.starts_with("Up ");
        info.containers.push(DockerContainerInfo {
            name: parts[0].trim().to_string(),
            image: parts[1].trim().to_string(),
            status,
            running,
            compose_dir: parts.get(3).map(|s| s.trim().to_string()).unwrap_or_default(),
        });
    }

    if let Ok(Ok(df_out)) = tokio::time::timeout(
        Duration::from_secs(2),
        Command::new("docker")
            .args([
                "system",
                "df",
                "--format",
                "{{.Type}}: {{.TotalCount}} total ({{.Active}} ativos) — {{.Size}} (recuperável: {{.Reclaimable}})",
            ])
            .output(),
    )
    .await
    {
        if df_out.status.success() {
            info.df_lines = String::from_utf8_lossy(&df_out.stdout)
                .lines()
                .map(|l| l.trim().to_string())
                .filter(|l| !l.is_empty())
                .collect();
        }
    }
    info
}

pub fn short_sha(s: &str) -> String {
    let trimmed = s.trim();
    if trimmed.is_empty() {
        return "desconhecido".to_string();
    }
    let stripped = trimmed.strip_prefix("sha256:").unwrap_or(trimmed);
    stripped.chars().take(12).collect()
}

pub fn parse_local_image_metadata(
    img_json: &str,
    fallback_img_id: &str,
) -> (String, HashSet<String>, String) {
    let Ok(val) = serde_json::from_str::<serde_json::Value>(img_json) else {
        return (String::new(), HashSet::new(), fallback_img_id.to_string());
    };
    let Some(img_data) = val.as_array().and_then(|arr| arr.first()) else {
        return (String::new(), HashSet::new(), fallback_img_id.to_string());
    };

    let labels = img_data
        .get("Config")
        .and_then(|c| c.get("Labels"))
        .and_then(|l| l.as_object());
    let oci_ver = labels
        .and_then(|m| {
            m.get("org.opencontainers.image.version")
                .or_else(|| m.get("version"))
        })
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim()
        .to_string();

    let mut local_digests = HashSet::new();
    let mut first_digest: Option<String> = None;
    if let Some(repo_digests) = img_data.get("RepoDigests").and_then(|r| r.as_array()) {
        for item in repo_digests {
            if let Some(s) = item.as_str() {
                if let Some((_, digest)) = s.split_once('@') {
                    let d = digest.trim().to_string();
                    if !d.is_empty() {
                        if first_digest.is_none() {
                            first_digest = Some(d.clone());
                        }
                        local_digests.insert(d);
                    }
                }
            }
        }
    }

    let primary_digest = first_digest.unwrap_or_else(|| fallback_img_id.to_string());
    (oci_ver, local_digests, primary_digest)
}

pub fn parse_imagetools_digest(text: &str) -> Option<String> {
    for line in text.lines() {
        if let Some(rest) = line.strip_prefix("Digest:") {
            let digest = rest.trim();
            if digest.starts_with("sha256:") {
                return Some(digest.to_string());
            }
        }
    }
    None
}

pub fn parse_remote_manifest_digest(manifest_json: &str, host_arch: &str) -> Option<String> {
    let val = serde_json::from_str::<serde_json::Value>(manifest_json).ok()?;
    if let Some(arr) = val.as_array() {
        for entry in arr {
            let desc = entry.get("Descriptor");
            let plat = desc.and_then(|d| d.get("platform"));
            let os = plat.and_then(|p| p.get("os")).and_then(|v| v.as_str());
            let arch = plat
                .and_then(|p| p.get("architecture"))
                .and_then(|v| v.as_str());
            if os == Some("linux") && arch == Some(host_arch) {
                if let Some(digest) = desc.and_then(|d| d.get("digest")).and_then(|v| v.as_str()) {
                    return Some(digest.to_string());
                }
            }
        }
        arr.first()
            .and_then(|e| e.get("Descriptor"))
            .and_then(|d| d.get("digest"))
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
    } else if val.is_object() {
        val.get("Descriptor")
            .and_then(|d| d.get("digest"))
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
    } else {
        None
    }
}

fn docker_host_arch() -> &'static str {
    match std::env::consts::ARCH {
        "x86_64" => "amd64",
        "aarch64" => "arm64",
        "arm" => "arm",
        _ => "amd64",
    }
}

async fn check_single_container_update(c: DockerContainerInfo) -> (String, DockerImageUpdateInfo) {
    let cname = c.name.clone();
    let image = c.image.clone();

    let inspect_c = tokio::time::timeout(
        Duration::from_secs(5),
        Command::new("docker").args(["inspect", &cname]).output(),
    )
    .await;

    let img_id = match inspect_c {
        Ok(Ok(out)) if out.status.success() => {
            let text = String::from_utf8_lossy(&out.stdout);
            serde_json::from_str::<serde_json::Value>(&text)
                .ok()
                .and_then(|v| {
                    v.as_array()
                        .and_then(|a| a.first())
                        .and_then(|o| o.get("Image"))
                        .and_then(|i| i.as_str())
                        .map(|s| s.to_string())
                })
                .unwrap_or_default()
        }
        _ => {
            return (
                cname.clone(),
                DockerImageUpdateInfo {
                    container_name: cname,
                    image,
                    local_version: String::new(),
                    local_digest: String::new(),
                    state: DockerUpdateState::Error("Falha ao inspecionar container".to_string()),
                },
            );
        }
    };

    let inspect_img = tokio::time::timeout(
        Duration::from_secs(5),
        Command::new("docker").args(["inspect", &img_id]).output(),
    )
    .await;

    let (local_version, local_digests, local_digest) = match inspect_img {
        Ok(Ok(out)) if out.status.success() => {
            let text = String::from_utf8_lossy(&out.stdout);
            parse_local_image_metadata(&text, &img_id)
        }
        _ => (String::new(), HashSet::new(), img_id),
    };

    let imagetools_out = tokio::time::timeout(
        Duration::from_secs(15),
        Command::new("docker")
            .args(["buildx", "imagetools", "inspect", &image])
            .output(),
    )
    .await;

    let mut remote_digest = match imagetools_out {
        Ok(Ok(out)) if out.status.success() => {
            let text = String::from_utf8_lossy(&out.stdout);
            parse_imagetools_digest(&text)
        }
        _ => None,
    };

    if remote_digest.is_none() {
        let manifest_out = tokio::time::timeout(
            Duration::from_secs(15),
            Command::new("docker")
                .args(["manifest", "inspect", "-v", &image])
                .output(),
        )
        .await;

        remote_digest = match manifest_out {
            Ok(Ok(out)) if out.status.success() => {
                let text = String::from_utf8_lossy(&out.stdout);
                parse_remote_manifest_digest(&text, docker_host_arch())
            }
            _ => None,
        };
    }

    let state = match remote_digest {
        None => DockerUpdateState::LocalOrUnverifiable,
        Some(rd) if local_digests.contains(&rd) => DockerUpdateState::UpToDate,
        Some(rd) => DockerUpdateState::UpdateAvailable { remote_digest: rd },
    };

    (
        cname.clone(),
        DockerImageUpdateInfo {
            container_name: cname,
            image,
            local_version,
            local_digest,
            state,
        },
    )
}

pub async fn check_docker_updates(
    containers: Vec<DockerContainerInfo>,
) -> HashMap<String, DockerImageUpdateInfo> {
    let futures_vec = containers.into_iter().map(check_single_container_update);
    let results = futures::future::join_all(futures_vec).await;
    results.into_iter().collect()
}

async fn probe_hardware_info() -> SystemHardwareInfo {
    let mut hw = SystemHardwareInfo::default();

    if let Ok(load) = fs::read_to_string("/proc/loadavg") {
        let parts: Vec<&str> = load.split_whitespace().take(3).collect();
        if !parts.is_empty() {
            hw.cpu_load = format!("Load avg: {}", parts.join(" / "));
        }
    }

    if let Ok(meminfo) = fs::read_to_string("/proc/meminfo") {
        let mut total_kb: u64 = 0;
        let mut avail_kb: u64 = 0;
        for line in meminfo.lines() {
            if let Some(rest) = line.strip_prefix("MemTotal:") {
                total_kb = rest.split_whitespace().next().and_then(|v| v.parse().ok()).unwrap_or(0);
            } else if let Some(rest) = line.strip_prefix("MemAvailable:") {
                avail_kb = rest.split_whitespace().next().and_then(|v| v.parse().ok()).unwrap_or(0);
            }
        }
        if total_kb > 0 {
            let used_kb = total_kb.saturating_sub(avail_kb);
            let total_gib = total_kb as f64 / 1048576.0;
            let used_gib = used_kb as f64 / 1048576.0;
            let avail_gib = avail_kb as f64 / 1048576.0;
            hw.ram_summary = format!("{used_gib:.1} GiB / {total_gib:.1} GiB (disp: {avail_gib:.1} GiB)");
        }
    }

    if let Ok(Ok(gpu_out)) = tokio::time::timeout(
        Duration::from_secs(2),
        Command::new("nvidia-smi")
            .args([
                "--query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total",
                "--format=csv,noheader,nounits",
            ])
            .output(),
    )
    .await
    {
        if gpu_out.status.success() {
            let line = String::from_utf8_lossy(&gpu_out.stdout).trim().to_string();
            let p: Vec<&str> = line.split(',').map(|s| s.trim()).collect();
            if p.len() >= 5 {
                hw.gpu_summary = format!(
                    "{} — {}°C | Uso: {}% | VRAM: {}/{} MiB",
                    p[0], p[1], p[2], p[3], p[4]
                );
            }
        }
    }
    if hw.gpu_summary.is_empty() {
        hw.gpu_summary = "Não detectada".to_string();
    }

    if let Ok(Ok(df_out)) = tokio::time::timeout(
        Duration::from_secs(2),
        Command::new("df")
            .args(["-h", "--output=target,used,size,avail,pcent", "/", "/mnt/storage_700", "/mnt/storage_930"])
            .output(),
    )
    .await
    {
        for line in String::from_utf8_lossy(&df_out.stdout).lines().skip(1) {
            let cols: Vec<&str> = line.split_whitespace().collect();
            if cols.len() >= 5 {
                hw.disks.push(format!(
                    "{} — {}/{} ({} livre, {} usado)",
                    cols[0], cols[1], cols[2], cols[3], cols[4]
                ));
            }
        }
    }

    let home_dir = dirs::home_dir().unwrap_or_else(|| PathBuf::from("/home"));
    for (label, rel) in [
        ("Google Drive (gdrive_pessoal)", "GoogleDrive_Pessoal"),
        ("OneDrive (onedrive_pessoal)", "OneDrive_Pessoal"),
        ("MEGA (mega_pessoal)", "Mega_Pessoal"),
    ] {
        let p = home_dir.join(rel);
        let mounted = p.exists()
            && fs::read_dir(&p).map(|mut d| d.next().is_some()).unwrap_or(false);
        hw.rclone_status.push(format!(
            "{label}: {}",
            if mounted { "Montado" } else { "Não montado / Vazio" }
        ));
    }

    if let Ok(Ok(sun_out)) = tokio::time::timeout(
        Duration::from_secs(2),
        Command::new("systemctl")
            .args(["--user", "is-active", "sunshine"])
            .output(),
    )
    .await
    {
        hw.sunshine_active = sun_out.status.success();
    }

    let hb_dir = Path::new("/mnt/storage_930/Backups_Homelab");
    if hb_dir.exists() {
        let count = fs::read_dir(hb_dir)
            .map(|rd| rd.filter_map(Result::ok).count())
            .unwrap_or(0);
        hw.homelab_backup_summary = format!("Pasta presente ({count} itens em Backups_Homelab)");
    } else {
        hw.homelab_backup_summary = "Pasta /mnt/storage_930/Backups_Homelab não encontrada".to_string();
    }

    hw
}

async fn probe_antigravity_version() -> String {
    let product_json = Path::new("/opt/antigravity/resources/app/product.json");
    if let Ok(content) = tokio::fs::read_to_string(product_json).await
        && let Ok(val) = serde_json::from_str::<serde_json::Value>(&content)
        && let Some(ver) = val
            .get("ideVersion")
            .or_else(|| val.get("version"))
            .and_then(|v| v.as_str())
    {
        return ver.to_string();
    }
    "não detectado".to_string()
}

async fn probe_homelab_ssh(host: &str, user: &str) -> bool {
    if host.is_empty() || user.is_empty() {
        return false;
    }
    let target = format!("{user}@{host}");
    let Ok(Ok(out)) = tokio::time::timeout(
        Duration::from_secs(2),
        Command::new("ssh")
            .args([
                "-o",
                "BatchMode=yes",
                "-o",
                "ConnectTimeout=2",
                "-o",
                "StrictHostKeyChecking=accept-new",
                &target,
                "exit",
                "0",
            ])
            .output(),
    )
    .await
    else {
        return false;
    };
    out.status.success()
}

fn list_android_backups() -> Vec<String> {
    let mut candidates = vec![
        PathBuf::from("/mnt/storage_930/Backups_Android"),
        PathBuf::from("/mnt/storage_700/Backups_Android"),
        PathBuf::from("/mnt/nvme_01/Backups_Android"),
    ];
    if let Some(home) = dirs::home_dir() {
        candidates.push(home.join("Backups_Android"));
    }

    for dir in candidates {
        if dir.is_dir()
            && let Ok(read_dir) = fs::read_dir(&dir)
        {
            let mut items: Vec<String> = read_dir
                .flatten()
                .filter_map(|entry| {
                    let name = entry.file_name().to_string_lossy().to_string();
                    if name.starts_with("android-backup-") && entry.path().is_dir() {
                        Some(name)
                    } else {
                        None
                    }
                })
                .collect();
            items.sort();
            items.reverse();
            return items;
        }
    }
    Vec::new()
}

async fn probe_remote_devices(popos_repo: &Path) -> RemoteDevicesInfo {
    let map = read_env_map(&popos_repo.join(".env"));
    let get = |k: &str, default: &str| {
        map.get(k)
            .filter(|v| !v.trim().is_empty())
            .cloned()
            .unwrap_or_else(|| default.to_string())
    };

    let win_lan = get("REMOTE_WIN_LAN_HOST", "");
    let win_online = if !win_lan.is_empty() && !win_lan.ends_with(".x") {
        let addr_rdp = format!("{win_lan}:3389");
        let addr_ssh = format!("{win_lan}:22");
        let rdp_ok = tokio::time::timeout(
            Duration::from_millis(600),
            tokio::net::TcpStream::connect(&addr_rdp),
        )
        .await
        .is_ok_and(|r| r.is_ok());
        let ssh_ok = if rdp_ok {
            true
        } else {
            tokio::time::timeout(
                Duration::from_millis(600),
                tokio::net::TcpStream::connect(&addr_ssh),
            )
            .await
            .is_ok_and(|r| r.is_ok())
        };
        Some(ssh_ok)
    } else {
        None
    };

    let rustdesk_installed = Path::new("/usr/bin/rustdesk").exists()
        || Command::new("which")
            .arg("rustdesk")
            .output()
            .await
            .is_ok_and(|o| o.status.success());

    let (rustdesk_service_active, rustdesk_id) = if rustdesk_installed {
        let active = Command::new("systemctl")
            .args(["is-active", "--quiet", "rustdesk"])
            .status()
            .await
            .is_ok_and(|s| s.success());
        let id = match tokio::time::timeout(
            Duration::from_secs(1),
            Command::new("rustdesk").arg("--get-id").output(),
        )
        .await
        {
            Ok(Ok(out)) if out.status.success() => {
                String::from_utf8_lossy(&out.stdout).trim().to_string()
            }
            _ => String::new(),
        };
        (active, id)
    } else {
        (false, String::new())
    };

    RemoteDevicesInfo {
        win_label: get("REMOTE_WIN_LABEL", "Windows 11 Remoto"),
        win_lan_host: win_lan,
        win_ts_host: get("REMOTE_WIN_TS_HOST", ""),
        win_user: get("REMOTE_WIN_USER", ""),
        win_online,
        android_label: get("REMOTE_ANDROID_LABEL", "Android (ADB Wi-Fi)"),
        android_lan_host: get("REMOTE_ANDROID_LAN_HOST", ""),
        android_ts_host: get("REMOTE_ANDROID_TS_HOST", ""),
        android_port: get("REMOTE_ANDROID_PORT", "5555"),
        tablet_label: get("REMOTE_TABLET_ANDROID_LABEL", "Tablet Android (ADB Wi-Fi)"),
        tablet_lan_host: get("REMOTE_TABLET_ANDROID_LAN_HOST", ""),
        tablet_ts_host: get("REMOTE_TABLET_ANDROID_TS_HOST", ""),
        tablet_port: get("REMOTE_TABLET_ANDROID_PORT", "5555"),
        tv_label: get("REMOTE_TV_LABEL", "Smart TV Samsung"),
        tv_ip: get("REMOTE_TV_IP", ""),
        projector_label: get("REMOTE_PROJECTOR_LABEL", "Projetor Samsung"),
        projector_ip: get("REMOTE_PROJECTOR_IP", ""),
        ha_configured: !get("HA_URL", "").is_empty() && !get("HA_TOKEN", "").is_empty(),
        rustdesk_installed,
        rustdesk_service_active,
        rustdesk_id,
    }
}

async fn probe_vpn_mpms_ip() -> Option<String> {
    let Ok(Ok(out)) = tokio::time::timeout(
        Duration::from_secs(1),
        Command::new("ip")
            .args(["-4", "-o", "addr", "show", "ppp0"])
            .output(),
    )
    .await
    else {
        return None;
    };
    if !out.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&out.stdout);
    text.split_whitespace()
        .skip_while(|&w| w != "inet")
        .nth(1)
        .map(|s| s.split('/').next().unwrap_or(s).to_string())
}

async fn probe_tailscale_ip() -> Option<String> {
    let Ok(Ok(status_out)) = tokio::time::timeout(
        Duration::from_secs(1),
        Command::new("tailscale").arg("status").output(),
    )
    .await
    else {
        return None;
    };
    let status_text = String::from_utf8_lossy(&status_out.stdout);
    if !status_out.status.success() || status_text.contains("Tailscale is stopped") {
        return None;
    }

    let Ok(Ok(out)) = tokio::time::timeout(
        Duration::from_secs(1),
        Command::new("tailscale").args(["ip", "-4"]).output(),
    )
    .await
    else {
        return None;
    };
    if !out.status.success() {
        return None;
    }
    let ip = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if ip.is_empty() { None } else { Some(ip) }
}

pub fn list_log_files(paths: &HubPaths) -> Vec<PathBuf> {
    let mut dirs_to_scan = vec![
        paths.popos_repo.join("Logs"),
        paths.homelab_repo.join("Logs"),
        paths.homelab_repo.join("temp"),
    ];
    if let Some(state) = dirs::state_dir().or_else(dirs::data_local_dir) {
        dirs_to_scan.push(state.join("workstation-hub").join("logs"));
    }

    let mut files: Vec<(std::time::SystemTime, PathBuf)> = Vec::new();
    for dir in dirs_to_scan {
        let Ok(entries) = fs::read_dir(&dir) else {
            continue;
        };
        for e in entries.flatten() {
            let p = e.path();
            if p.is_file() && p.extension().is_some_and(|ext| ext == "log") {
                let mtime = e
                    .metadata()
                    .and_then(|m| m.modified())
                    .unwrap_or(std::time::SystemTime::UNIX_EPOCH);
                files.push((mtime, p));
            }
        }
    }
    files.sort_by(|a, b| b.0.cmp(&a.0));
    files.into_iter().take(40).map(|(_, p)| p).collect()
}

fn extract_host_from_url(raw: &str) -> String {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return String::new();
    }
    let no_scheme = trimmed
        .strip_prefix("https://")
        .or_else(|| trimmed.strip_prefix("http://"))
        .unwrap_or(trimmed);
    let host_port = no_scheme.split('/').next().unwrap_or(no_scheme);
    host_port.split(':').next().unwrap_or(host_port).trim().to_string()
}

async fn ping_host(label: String, host: String, network_type: &'static str) -> NetworkHostStatus {
    if host.is_empty() {
        return NetworkHostStatus {
            label,
            host: "não configurado".to_string(),
            network_type: network_type.to_string(),
            online: false,
            latency_ms: "—".to_string(),
        };
    }

    let Ok(Ok(out)) = tokio::time::timeout(
        Duration::from_secs(2),
        Command::new("ping")
            .args(["-c", "1", "-W", "1", &host])
            .output(),
    )
    .await
    else {
        return NetworkHostStatus {
            label,
            host,
            network_type: network_type.to_string(),
            online: false,
            latency_ms: "Timeout".to_string(),
        };
    };

    if !out.status.success() {
        return NetworkHostStatus {
            label,
            host,
            network_type: network_type.to_string(),
            online: false,
            latency_ms: "Offline".to_string(),
        };
    }

    let stdout = String::from_utf8_lossy(&out.stdout);
    let latency_ms = stdout
        .split("time=")
        .nth(1)
        .and_then(|s| s.split_whitespace().next())
        .map(|v| format!("{v} ms"))
        .unwrap_or_else(|| "Online".to_string());

    NetworkHostStatus {
        label,
        host,
        network_type: network_type.to_string(),
        online: true,
        latency_ms,
    }
}

async fn probe_network_monitor(
    popos_repo: &Path,
    homelab_lan: &str,
    homelab_ts: &str,
    remote: &RemoteDevicesInfo,
) -> NetworkMonitorInfo {
    let mut info = NetworkMonitorInfo::default();

    let (gw_out, if_out, ts_out, neigh_out) = tokio::join!(
        tokio::time::timeout(
            Duration::from_secs(2),
            Command::new("ip").args(["route", "show", "default"]).output(),
        ),
        tokio::time::timeout(
            Duration::from_secs(2),
            Command::new("ip").args(["-br", "-4", "addr", "show"]).output(),
        ),
        tokio::time::timeout(
            Duration::from_secs(2),
            Command::new("tailscale").arg("status").output(),
        ),
        tokio::time::timeout(
            Duration::from_secs(2),
            Command::new("ip").args(["-4", "neigh", "show"]).output(),
        ),
    );

    if let Ok(Ok(out)) = gw_out
        && out.status.success()
    {
        let text = String::from_utf8_lossy(&out.stdout);
        info.gateway_ip = text
            .split_whitespace()
            .skip_while(|&w| w != "via")
            .nth(1)
            .unwrap_or("")
            .to_string();
    }

    if let Ok(Ok(out)) = if_out
        && out.status.success()
    {
        for line in String::from_utf8_lossy(&out.stdout).lines() {
            let cols: Vec<&str> = line.split_whitespace().collect();
            if cols.len() >= 3 {
                let iface = cols[0];
                if iface.starts_with("veth") || iface.starts_with("br-") || iface == "lo" {
                    continue;
                }
                info.local_interfaces
                    .push(format!("{iface} ({}) — {}", cols[1], cols[2..].join(", ")));
            }
        }
    }

    if let Ok(Ok(out)) = ts_out
        && out.status.success()
    {
        for line in String::from_utf8_lossy(&out.stdout).lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() || trimmed.starts_with('#') {
                continue;
            }
            let cols: Vec<&str> = trimmed.split_whitespace().collect();
            if cols.len() >= 4 && cols[0].contains('.') {
                let status = if cols.len() >= 5 {
                    cols[4..].join(" ")
                } else {
                    "local".to_string()
                };
                info.tailscale_peers.push(TailscalePeerStatus {
                    ip: cols[0].to_string(),
                    hostname: cols[1].to_string(),
                    os: cols[3].to_string(),
                    status,
                });
            }
        }
    }

    if let Ok(Ok(out)) = neigh_out
        && out.status.success()
    {
        for line in String::from_utf8_lossy(&out.stdout).lines() {
            let trimmed = line.trim();
            if trimmed.contains("FAILED") || trimmed.is_empty() {
                continue;
            }
            info.lan_neighbors.push(trimmed.to_string());
        }
    }

    let env_map = read_env_map(&popos_repo.join(".env"));
    let ha_host = env_map
        .get("HA_URL")
        .map(|s| extract_host_from_url(s))
        .unwrap_or_default();

    let mut targets: Vec<(String, String, &'static str)> = Vec::new();
    if !info.gateway_ip.is_empty() {
        targets.push((
            "Roteador / Gateway".to_string(),
            info.gateway_ip.clone(),
            "LAN",
        ));
    }
    targets.push((
        "umbrelOS Homelab (LAN)".to_string(),
        homelab_lan.to_string(),
        "LAN",
    ));
    targets.push((
        "umbrelOS Homelab (Tailscale)".to_string(),
        homelab_ts.to_string(),
        "Tailscale",
    ));
    targets.push(("Home Assistant".to_string(), ha_host, "LAN/DNS"));
    targets.push((
        format!("{} (LAN)", remote.win_label),
        remote.win_lan_host.clone(),
        "LAN",
    ));
    targets.push((
        format!("{} (Tailscale)", remote.win_label),
        remote.win_ts_host.clone(),
        "Tailscale",
    ));
    targets.push((
        format!("{} (LAN)", remote.android_label),
        remote.android_lan_host.clone(),
        "LAN",
    ));
    targets.push((
        format!("{} (Tailscale)", remote.android_label),
        remote.android_ts_host.clone(),
        "Tailscale",
    ));
    targets.push((
        format!("{} (LAN)", remote.tablet_label),
        remote.tablet_lan_host.clone(),
        "LAN",
    ));
    targets.push((
        format!("{} (Tailscale)", remote.tablet_label),
        remote.tablet_ts_host.clone(),
        "Tailscale",
    ));
    targets.push((remote.tv_label.clone(), remote.tv_ip.clone(), "LAN"));
    targets.push((
        remote.projector_label.clone(),
        remote.projector_ip.clone(),
        "LAN",
    ));
    targets.push(("Internet / DNS Cloudflare".to_string(), "1.1.1.1".to_string(), "WAN"));

    let mut futs = Vec::with_capacity(targets.len());
    for (label, host, net) in targets {
        futs.push(ping_host(label, host, net));
    }
    info.hosts = futures::future::join_all(futs).await;

    info
}
