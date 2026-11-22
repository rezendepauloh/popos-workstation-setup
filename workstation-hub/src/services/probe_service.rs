use crate::models::status::{HubPaths, RemoteDevicesInfo, SystemSnapshot};
use crate::services::env_service::read_env_map;
use crate::services::progress_service::read_completed_flags;
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
        antigravity_version,
        homelab_online,
        vpn_mpms_ip,
        tailscale_ip,
        remote_devices,
    ) = tokio::join!(
        probe_adb_devices(),
        probe_docker_and_winapps(),
        probe_antigravity_version(),
        probe_homelab_ssh(&homelab_local_host, &homelab_user),
        probe_vpn_mpms_ip(),
        probe_tailscale_ip(),
        probe_remote_devices(&paths.popos_repo),
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
        tv_label: get("REMOTE_TV_LABEL", "Smart TV Samsung"),
        tv_ip: get("REMOTE_TV_IP", ""),
        projector_label: get("REMOTE_PROJECTOR_LABEL", "Projetor Samsung"),
        projector_ip: get("REMOTE_PROJECTOR_IP", ""),
        ha_configured: !get("HA_URL", "").is_empty() && !get("HA_TOKEN", "").is_empty(),
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
