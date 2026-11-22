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
    pub tv_label: String,
    pub tv_ip: String,
    pub projector_label: String,
    pub projector_ip: String,
    pub ha_configured: bool,
}

#[derive(Debug, Clone, Default)]
pub struct SystemSnapshot {
    pub completed_flags: HashSet<String>,
    pub adb_devices: Vec<String>,
    pub docker_active: bool,
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
