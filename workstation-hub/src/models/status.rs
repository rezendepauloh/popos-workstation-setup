use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct HubPaths {
    pub popos_repo: PathBuf,
    pub homelab_repo: PathBuf,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum HomelabNetworkMode {
    #[default]
    Local,
    Tailscale,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum HomelabAddressMode {
    #[default]
    Dns,
    Ip,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum SamsungTarget {
    #[default]
    Tv,
    Projector,
}

#[derive(Debug, Clone, Default)]
pub struct RemoteDevicesInfo {
    pub win_label: String,
    pub win_lan_host: String,
    pub win_ts_host: String,
    pub win_user: String,
    pub win_online: Option<bool>,
    pub android_label: String,
    pub android_lan_host: String,
    pub android_ts_host: String,
    pub android_port: String,
    pub tablet_label: String,
    pub tablet_lan_host: String,
    pub tablet_ts_host: String,
    pub tablet_port: String,
    pub tv_label: String,
    pub tv_ip: String,
    pub projector_label: String,
    pub projector_ip: String,
    pub ha_configured: bool,
    pub rustdesk_installed: bool,
    pub rustdesk_service_active: bool,
    pub rustdesk_id: String,
}

#[derive(Debug, Clone, Default)]
pub struct DockerContainerInfo {
    pub name: String,
    pub image: String,
    pub status: String,
    pub running: bool,
    pub compose_dir: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DockerUpdateState {
    UpToDate,
    UpdateAvailable { remote_digest: String },
    LocalOrUnverifiable,
    Error(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DockerImageUpdateInfo {
    pub container_name: String,
    pub image: String,
    pub local_version: String,
    pub local_digest: String,
    pub state: DockerUpdateState,
}

#[derive(Debug, Clone, Default)]
pub struct DockerSystemInfo {
    pub daemon_active: bool,
    pub containers: Vec<DockerContainerInfo>,
    pub df_lines: Vec<String>,
}

#[derive(Debug, Clone, Default)]
pub struct SystemHardwareInfo {
    pub cpu_load: String,
    pub ram_summary: String,
    pub cpu_temp: String,
    pub gpu_summary: String,
    pub disks: Vec<String>,
    pub rclone_status: Vec<String>,
    pub sunshine_active: bool,
    pub homelab_backup_summary: String,
}

#[derive(Debug, Clone, Default)]
pub struct NetworkHostStatus {
    pub label: String,
    pub host: String,
    pub network_type: String,
    pub online: bool,
    pub latency_ms: String,
}

#[derive(Debug, Clone, Default)]
pub struct TailscalePeerStatus {
    pub ip: String,
    pub hostname: String,
    pub os: String,
    pub status: String,
}

#[derive(Debug, Clone, Default)]
pub struct NetworkMonitorInfo {
    pub gateway_ip: String,
    pub local_interfaces: Vec<String>,
    pub hosts: Vec<NetworkHostStatus>,
    pub tailscale_peers: Vec<TailscalePeerStatus>,
    pub lan_neighbors: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum PanelSegment {
    Start,
    Center,
    End,
    #[default]
    Hidden,
}

#[derive(Debug, Clone, Default)]
pub struct PanelAppletInfo {
    pub id: String,
    pub name: String,
    pub comment: String,
    pub icon: String,
    pub segment: PanelSegment,
}

#[derive(Debug, Clone, Default)]
pub struct TrayItemInfo {
    pub bus_name: String,
    pub object_path: String,
    pub id: String,
    pub title: String,
    pub icon: String,
    pub status: String,
    pub systemd_unit: Option<String>,
}

#[derive(Debug, Clone, Default)]
pub struct ManagedIndicatorInfo {
    pub unit: String,
    pub label: String,
    pub icon: String,
    pub active: bool,
}

#[derive(Debug, Clone, Default)]
pub struct PanelAndTrayInfo {
    pub applets: Vec<PanelAppletInfo>,
    pub tray_items: Vec<TrayItemInfo>,
    pub managed_indicators: Vec<ManagedIndicatorInfo>,
}

#[derive(Debug, Clone, Default)]
pub struct SystemSnapshot {
    pub completed_flags: HashSet<String>,
    pub adb_devices: Vec<String>,
    pub docker_active: bool,
    pub docker_info: DockerSystemInfo,
    pub hardware_info: SystemHardwareInfo,
    pub network_info: NetworkMonitorInfo,
    pub panel_tray_info: PanelAndTrayInfo,
    pub winapps_running: bool,
    pub antigravity_version: String,
    pub homelab_online: Option<bool>,
    pub homelab_local_host: String,
    pub homelab_tailscale_host: String,
    pub homelab_domain: String,
    pub homelab_user: String,
    pub vpn_mpms_ip: Option<String>,
    pub tailscale_ip: Option<String>,
    pub remote_devices: RemoteDevicesInfo,
    pub local_android_backups: Vec<String>,
    pub log_files: Vec<PathBuf>,
    pub hub_executions: Vec<crate::services::log_service::HubExecutionRecord>,
}
