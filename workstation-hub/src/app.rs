use crate::models::catalog::{
    HOMELAB_SETUP_MODULES, HOMELAB_UTIL_ACTIONS, LOCAL_UTIL_ACTIONS, SETUP_MODULES,
};
use crate::models::env_entry::{EnvTarget, EnvVarItem};
use crate::models::log_entry::{AnsiColor, LogLine, RunStatus};
use crate::models::status::{
    HomelabAddressMode, HomelabNetworkMode, HubPaths, SamsungTarget, SystemSnapshot,
};
use crate::services::env_service::{load_env_file, save_env_file};
use crate::services::input_validator::validate_identifier;
use crate::services::path_locator::{
    discover_paths, is_valid_homelab_repo, is_valid_popos_repo, save_paths,
};
use crate::services::probe_service::collect_snapshot;
use crate::services::progress_service::{clear_all_flags, clear_flag};
use crate::services::runner_service::{
    CommandSpec, RunnerEvent, RunningProcessHandle, build_cargo_test_command,
    build_remote_homelab_logs_command, build_script_command, build_setup_batch_command,
    build_tailscale_command, build_vpn_mpms_command, launch_in_cosmic_term, spawn_pty_command,
};
use crate::views;
use cosmic::app::context_drawer;
use cosmic::iced::{Alignment, Length, Subscription};
use cosmic::prelude::*;
use cosmic::widget::{self, about::About, icon, menu, nav_bar};
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::PathBuf;
use tokio::sync::mpsc::{UnboundedReceiver, UnboundedSender, unbounded_channel};

const APP_ICON: &[u8] =
    include_bytes!("../res/icons/hicolor/scalable/apps/br.dev.rezendepauloh.WorkstationHub.svg");
const REPOSITORY: &str = env!("CARGO_PKG_REPOSITORY");

static RUNNER_RX_SLOT: std::sync::OnceLock<
    tokio::sync::Mutex<Option<UnboundedReceiver<RunnerEvent>>>,
> = std::sync::OnceLock::new();

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Page {
    Dashboard,
    Setup,
    Utils,
    Homelab,
    RemoteDevices,
    Vpn,
    Tests,
    Logs,
    Settings,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SetupFilter {
    All,
    Pending,
    Completed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TestTarget {
    PoposFull,
    PoposDocker,
    HubRust,
    HomelabFull,
    HomelabUnit,
    HomelabIntegration,
}

#[derive(Copy, Clone, Debug, Default, Eq, PartialEq)]
pub enum ContextPage {
    #[default]
    About,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MenuAction {
    About,
    Refresh,
}

impl menu::action::MenuAction for MenuAction {
    type Message = Message;

    fn message(&self) -> Self::Message {
        match self {
            MenuAction::About => Message::ToggleContextPage(ContextPage::About),
            MenuAction::Refresh => Message::RefreshSnapshot,
        }
    }
}

#[derive(Debug, Clone)]
pub enum Message {
    RefreshSnapshot,
    SnapshotLoaded(SystemSnapshot),
    ToggleContextPage(ContextPage),
    LaunchUrl(String),

    // Setup Tab
    SetupSearchChanged(String),
    SetupFilterChanged(SetupFilter),
    ToggleSetupModule(String, bool),
    ToggleForceMode(bool),
    SelectPendingModules,
    ClearModuleSelection,
    SelectCategoryPreset(crate::models::catalog::SetupCategory),
    RunSelectedModules,
    RunSingleModule(String),
    RunFullSetup,
    ResetModuleFlag(String),
    ResetAllFlags,

    // Utils, Homelab & VPN
    RunLocalUtil(String),
    RunHomelabAction(String),
    HomelabServiceInputChanged(String),
    RunHomelabRestoreService,
    ToggleHomelabSetupSection(bool),
    SetHomelabNetworkMode(HomelabNetworkMode),
    SetHomelabAddressMode(HomelabAddressMode),
    OpenHomelabSshTerminal,
    OpenLocalFolder(PathBuf),
    RunTestTarget(TestTarget),
    VpnOtpChanged(String),
    VpnPassChanged(String),
    ConnectVpnMpms,
    RunTailscale(String),
    FetchRemoteHomelabLogs,
    SetRemoteNetworkMode(HomelabNetworkMode),
    SetSamsungTarget(SamsungTarget),
    RunRemoteAction(String),
    RunSamsungAction(String),
    AlexaTtsInputChanged(String),
    SendAlexaTts,

    // Logs & PTY Runner
    RunnerEventReceived(RunnerEvent),
    PtyInputChanged(String),
    SendPtyInput,
    StopRunningProcess,
    ClearConsoleLogs,
    OpenLogFile(PathBuf),
    OpenHubExecution(usize),
    LogExecPagePrev,
    LogExecPageNext,
    CloseLogPreview,
    LogPreviewFilterChanged(String),
    ConsoleHeightChanged(f32),
    LogPreviewHeightChanged(f32),
    CopyConsoleLogs,
    AutoProbeTick,

    // Settings & .env Editor
    PoposPathInputChanged(String),
    HomelabPathInputChanged(String),
    SaveRepoPaths,
    SwitchEnvTarget(EnvTarget),
    EnvSearchChanged(String),
    EnvValueChanged(usize, String),
    ToggleEnvReveal(usize),
    SaveCurrentEnv,
    ReloadCurrentEnv,

    // Navigation helper
    NavigateTo(Page),
}

pub struct AppModel {
    core: cosmic::Core,
    context_page: ContextPage,
    about: About,
    nav: nav_bar::Model,
    key_binds: HashMap<menu::KeyBind, MenuAction>,

    pub paths: HubPaths,
    pub snapshot: SystemSnapshot,
    pub is_probing: bool,
    pub banner_notice: Option<(String, bool)>,

    // Setup state
    pub setup_search: String,
    pub setup_filter: SetupFilter,
    pub selected_modules: HashSet<String>,
    pub force_mode: bool,

    // Homelab & VPN state
    pub homelab_service_input: String,
    pub show_homelab_setup: bool,
    pub homelab_network_mode: HomelabNetworkMode,
    pub homelab_address_mode: HomelabAddressMode,
    pub vpn_otp_input: String,
    pub vpn_pass_input: String,
    pub remote_network_mode: HomelabNetworkMode,
    pub samsung_target: SamsungTarget,
    pub alexa_tts_input: String,

    // Runner & Logs state
    pub run_status: RunStatus,
    pub log_lines: Vec<LogLine>,
    pub pty_input: String,
    pub process_handle: Option<RunningProcessHandle>,
    runner_tx: UnboundedSender<RunnerEvent>,
    pub selected_log_preview: Option<(PathBuf, String)>,
    pub log_preview_filter: String,
    pub log_exec_page: usize,
    pub console_height: f32,
    pub log_preview_height: f32,

    // Settings & .env state
    pub popos_path_input: String,
    pub homelab_path_input: String,
    pub env_target: EnvTarget,
    pub env_search: String,
    pub env_entries: Vec<EnvVarItem>,
    pub env_loaded_from_example: bool,
    pub env_status_msg: Option<String>,
}

impl cosmic::Application for AppModel {
    type Executor = cosmic::executor::Default;
    type Flags = ();
    type Message = Message;

    const APP_ID: &'static str = "br.dev.rezendepauloh.WorkstationHub";

    fn core(&self) -> &cosmic::Core {
        &self.core
    }

    fn core_mut(&mut self) -> &mut cosmic::Core {
        &mut self.core
    }

    fn init(
        core: cosmic::Core,
        _flags: Self::Flags,
    ) -> (Self, Task<cosmic::Action<Self::Message>>) {
        let mut nav = nav_bar::Model::default();
        nav.insert()
            .text("Visão Geral")
            .data::<Page>(Page::Dashboard)
            .icon(icon::from_name("go-home-symbolic"))
            .activate();
        nav.insert()
            .text("Pós-Formatação")
            .data::<Page>(Page::Setup)
            .icon(icon::from_name("system-software-install-symbolic"));
        nav.insert()
            .text("Utilitários")
            .data::<Page>(Page::Utils)
            .icon(icon::from_name("applications-utilities-symbolic"));
        nav.insert()
            .text("Homelab (umbrelOS)")
            .data::<Page>(Page::Homelab)
            .icon(icon::from_name("network-server-symbolic"));
        nav.insert()
            .text("Dispositivos (Rede)")
            .data::<Page>(Page::RemoteDevices)
            .icon(icon::from_name("computer-symbolic"));
        nav.insert()
            .text("VPN (MPMS & Tailscale)")
            .data::<Page>(Page::Vpn)
            .icon(icon::from_name("network-vpn-symbolic"));
        nav.insert()
            .text("Testes")
            .data::<Page>(Page::Tests)
            .icon(icon::from_name("applications-science-symbolic"));
        nav.insert()
            .text("Console & Logs")
            .data::<Page>(Page::Logs)
            .icon(icon::from_name("utilities-terminal-symbolic"));
        nav.insert()
            .text("Configurações")
            .data::<Page>(Page::Settings)
            .icon(icon::from_name("preferences-system-symbolic"));

        let about = About::default()
            .name("Workstation & Homelab Hub")
            .icon(widget::icon::from_svg_bytes(APP_ICON))
            .version(env!("CARGO_PKG_VERSION"))
            .links([("Repositório", REPOSITORY)])
            .license(env!("CARGO_PKG_LICENSE"));

        let paths = discover_paths();
        let (runner_tx, runner_rx) = unbounded_channel();
        let _ = RUNNER_RX_SLOT.set(tokio::sync::Mutex::new(Some(runner_rx)));

        let mut app = Self {
            core,
            context_page: ContextPage::default(),
            about,
            nav,
            key_binds: HashMap::new(),
            popos_path_input: paths.popos_repo.to_string_lossy().to_string(),
            homelab_path_input: paths.homelab_repo.to_string_lossy().to_string(),
            paths,
            snapshot: SystemSnapshot::default(),
            is_probing: true,
            banner_notice: None,
            setup_search: String::new(),
            setup_filter: SetupFilter::All,
            selected_modules: HashSet::new(),
            force_mode: false,
            homelab_service_input: String::new(),
            show_homelab_setup: false,
            homelab_network_mode: HomelabNetworkMode::Local,
            homelab_address_mode: HomelabAddressMode::Dns,
            vpn_otp_input: String::new(),
            vpn_pass_input: String::new(),
            remote_network_mode: HomelabNetworkMode::Local,
            samsung_target: SamsungTarget::Tv,
            alexa_tts_input: String::new(),
            run_status: RunStatus::Idle,
            log_lines: vec![LogLine::plain(
                "Hub pronto. Selecione uma ação para acompanhar a saída em tempo real.",
                AnsiColor::Muted,
                false,
            )],
            pty_input: String::new(),
            process_handle: None,
            runner_tx,
            selected_log_preview: None,
            log_preview_filter: String::new(),
            log_exec_page: 0,
            console_height: 340.0,
            log_preview_height: 260.0,
            env_target: EnvTarget::Popos,
            env_search: String::new(),
            env_entries: Vec::new(),
            env_loaded_from_example: false,
            env_status_msg: None,
        };

        app.load_env_for_target(EnvTarget::Popos);
        let title_task = app.update_title();
        let probe_task = app.spawn_probe_task();

        (app, Task::batch([title_task, probe_task]))
    }

    fn header_start(&self) -> Vec<Element<'_, Self::Message>> {
        let menu_bar = menu::bar(vec![menu::Tree::with_children(
            menu::root("Arquivo").apply(Element::from),
            menu::items(
                &self.key_binds,
                vec![
                    menu::Item::Button("Atualizar Status", None, MenuAction::Refresh),
                    menu::Item::Button("Sobre", None, MenuAction::About),
                ],
            ),
        )]);
        vec![menu_bar.into()]
    }

    fn nav_model(&self) -> Option<&nav_bar::Model> {
        Some(&self.nav)
    }

    fn on_nav_select(&mut self, id: nav_bar::Id) -> Task<cosmic::Action<Self::Message>> {
        self.nav.activate(id);
        let title_task = self.update_title();
        let probe_task = self.spawn_probe_task();
        Task::batch([title_task, probe_task])
    }

    fn context_drawer(&self) -> Option<context_drawer::ContextDrawer<'_, Self::Message>> {
        if !self.core.window.show_context {
            return None;
        }
        Some(match self.context_page {
            ContextPage::About => context_drawer::about(
                &self.about,
                |url| Message::LaunchUrl(url.to_string()),
                Message::ToggleContextPage(ContextPage::About),
            ),
        })
    }

    fn subscription(&self) -> Subscription<Self::Message> {
        let runner_sub = Subscription::run(|| {
            cosmic::iced::stream::channel(
                64,
                move |mut emitter: futures::channel::mpsc::Sender<Message>| async move {
                    use futures::SinkExt;
                    if let Some(slot) = RUNNER_RX_SLOT.get() {
                        let mut guard = slot.lock().await;
                        if let Some(mut rx) = guard.take() {
                            drop(guard);
                            while let Some(ev) = rx.recv().await {
                                if emitter.send(Message::RunnerEventReceived(ev)).await.is_err() {
                                    break;
                                }
                            }
                            return;
                        }
                    }
                    futures::future::pending::<()>().await;
                },
            )
        });

        let tick_sub = Subscription::run(|| {
            cosmic::iced::stream::channel(
                4,
                move |mut emitter: futures::channel::mpsc::Sender<Message>| async move {
                    use futures::SinkExt;
                    let mut interval = tokio::time::interval(std::time::Duration::from_secs(10));
                    loop {
                        interval.tick().await;
                        if emitter.send(Message::AutoProbeTick).await.is_err() {
                            break;
                        }
                    }
                },
            )
        });

        Subscription::batch([runner_sub, tick_sub])
    }

    fn update(&mut self, message: Self::Message) -> Task<cosmic::Action<Self::Message>> {
        match message {
            Message::RefreshSnapshot => {
                self.is_probing = true;
                return self.spawn_probe_task();
            }
            Message::SnapshotLoaded(snap) => {
                self.snapshot = snap;
                self.is_probing = false;
            }
            Message::ToggleContextPage(page) => {
                if self.context_page == page {
                    self.core.window.show_context = !self.core.window.show_context;
                } else {
                    self.context_page = page;
                    self.core.window.show_context = true;
                }
            }
            Message::LaunchUrl(url) => {
                if let Err(err) = open::that_detached(&url) {
                    self.banner_notice = Some((format!("Erro ao abrir URL: {err}"), true));
                }
            }
            Message::NavigateTo(page) => {
                self.activate_page(page);
                return self.update_title();
            }

            // Setup Tab
            Message::SetupSearchChanged(v) => self.setup_search = v,
            Message::SetupFilterChanged(f) => self.setup_filter = f,
            Message::ToggleSetupModule(id, checked) => {
                if checked {
                    self.selected_modules.insert(id);
                } else {
                    self.selected_modules.remove(&id);
                }
            }
            Message::ToggleForceMode(v) => self.force_mode = v,
            Message::SelectPendingModules => {
                self.selected_modules.clear();
                for m in SETUP_MODULES {
                    if !self.snapshot.completed_flags.contains(m.flag_name) {
                        self.selected_modules.insert(m.id.to_string());
                    }
                }
            }
            Message::ClearModuleSelection => self.selected_modules.clear(),
            Message::SelectCategoryPreset(cat) => {
                self.selected_modules.clear();
                for m in SETUP_MODULES {
                    if m.category == cat {
                        self.selected_modules.insert(m.id.to_string());
                    }
                }
            }
            Message::RunSelectedModules => {
                let mut files: Vec<String> = SETUP_MODULES
                    .iter()
                    .filter(|m| self.selected_modules.contains(m.id))
                    .map(|m| m.filename.to_string())
                    .collect();
                if files.is_empty() {
                    self.banner_notice = Some(("Selecione ao menos um módulo.".to_string(), true));
                } else {
                    files.sort();
                    let label = format!("Provisionamento em Lote ({} módulos)", files.len());
                    match build_setup_batch_command(
                        label,
                        &self.paths.popos_repo,
                        &files,
                        self.force_mode,
                    ) {
                        Ok(spec) => self.start_command(spec),
                        Err(e) => self.banner_notice = Some((e, true)),
                    }
                }
            }
            Message::RunSingleModule(id) => {
                if let Some(m) = SETUP_MODULES.iter().find(|m| m.id == id) {
                    let rel = format!("scripts/{}", m.filename);
                    let args: &[&str] = if self.force_mode { &["--force"] } else { &[] };
                    match build_script_command(
                        format!("Módulo {}: {}", m.id, m.title),
                        &self.paths.popos_repo,
                        &rel,
                        args,
                        m.requires_root,
                    ) {
                        Ok(spec) => self.start_command(spec),
                        Err(e) => self.banner_notice = Some((e, true)),
                    }
                }
            }
            Message::RunFullSetup => {
                let args: &[&str] = if self.force_mode { &["--force"] } else { &[] };
                match build_script_command(
                    "Provisionamento Completo (setup_popos.sh)",
                    &self.paths.popos_repo,
                    "setup_popos.sh",
                    args,
                    true,
                ) {
                    Ok(spec) => self.start_command(spec),
                    Err(e) => self.banner_notice = Some((e, true)),
                }
            }
            Message::ResetModuleFlag(flag) => {
                match clear_flag(&self.paths.popos_repo, &flag) {
                    Ok(()) => {
                        self.banner_notice = Some((format!("Checkpoint {flag} removido."), false));
                        return self.spawn_probe_task();
                    }
                    Err(e) => self.banner_notice = Some((e, true)),
                }
            }
            Message::ResetAllFlags => match clear_all_flags(&self.paths.popos_repo) {
                Ok(()) => {
                    self.banner_notice =
                        Some(("Todos os checkpoints de setup foram limpos.".to_string(), false));
                    return self.spawn_probe_task();
                }
                Err(e) => self.banner_notice = Some((e, true)),
            },

            // Utils & Homelab & Tests
            Message::RunLocalUtil(id) => {
                if let Some(act) = LOCAL_UTIL_ACTIONS.iter().find(|a| a.id == id) {
                    match build_script_command(
                        act.title,
                        &self.paths.popos_repo,
                        act.rel_path,
                        act.args,
                        act.requires_root,
                    ) {
                        Ok(spec) => self.start_command(spec),
                        Err(e) => self.banner_notice = Some((e, true)),
                    }
                }
            }
            Message::RunHomelabAction(id) => {
                let found = HOMELAB_UTIL_ACTIONS
                    .iter()
                    .chain(HOMELAB_SETUP_MODULES.iter())
                    .find(|a| a.id == id);
                if let Some(act) = found {
                    match build_script_command(
                        format!("Homelab: {}", act.title),
                        &self.paths.homelab_repo,
                        act.rel_path,
                        act.args,
                        act.requires_root,
                    ) {
                        Ok(spec) => self.start_command(spec),
                        Err(e) => self.banner_notice = Some((e, true)),
                    }
                }
            }
            Message::HomelabServiceInputChanged(v) => self.homelab_service_input = v,
            Message::RunHomelabRestoreService => {
                let svc = self.homelab_service_input.trim().to_string();
                if let Err(e) = validate_identifier(&svc) {
                    self.banner_notice = Some((e, true));
                } else {
                    match build_script_command(
                        format!("Homelab: Restaurar serviço {svc}"),
                        &self.paths.homelab_repo,
                        "scripts/utils/homelab_restaurar_servicos.sh",
                        &["--service", &svc],
                        false,
                    ) {
                        Ok(spec) => self.start_command(spec),
                        Err(e) => self.banner_notice = Some((e, true)),
                    }
                }
            }
            Message::ToggleHomelabSetupSection(v) => self.show_homelab_setup = v,
            Message::SetHomelabNetworkMode(mode) => self.homelab_network_mode = mode,
            Message::SetHomelabAddressMode(mode) => self.homelab_address_mode = mode,
            Message::OpenHomelabSshTerminal => {
                let target = format!(
                    "{}@{}",
                    self.snapshot.homelab_user,
                    self.active_homelab_host()
                );
                if let Err(e) =
                    launch_in_cosmic_term(&["ssh", &target], &self.paths.homelab_repo)
                {
                    self.banner_notice = Some((e, true));
                }
            }
            Message::VpnOtpChanged(v) => self.vpn_otp_input = v,
            Message::VpnPassChanged(v) => self.vpn_pass_input = v,
            Message::ConnectVpnMpms => {
                let otp = self.vpn_otp_input.trim().to_string();
                if otp.is_empty() {
                    self.banner_notice =
                        Some(("Informe o código Token / OTP 2FA.".to_string(), true));
                } else if let Err(e) = validate_identifier(&otp) {
                    self.banner_notice = Some((e, true));
                } else {
                    let pass = self.vpn_pass_input.clone();
                    let spec = build_vpn_mpms_command(&otp, &pass, &self.paths.popos_repo);
                    let mut term_args: Vec<&str> = Vec::with_capacity(1 + spec.args.len());
                    term_args.push(spec.program.as_str());
                    for a in &spec.args {
                        term_args.push(a.as_str());
                    }
                    if let Err(e) = launch_in_cosmic_term(&term_args, &spec.workdir) {
                        self.banner_notice = Some((e, true));
                    } else {
                        self.banner_notice = Some((
                            "VPN MPMS iniciada em uma janela dedicada do cosmic-term (console do Hub livre).".to_string(),
                            false,
                        ));
                    }
                    self.vpn_otp_input.clear();
                    self.vpn_pass_input.clear();
                }
            }
            Message::RunTailscale(action) => {
                let spec = build_tailscale_command(&action, &self.paths.popos_repo);
                self.start_command(spec);
            }
            Message::SetRemoteNetworkMode(m) => self.remote_network_mode = m,
            Message::SetSamsungTarget(t) => self.samsung_target = t,
            Message::AlexaTtsInputChanged(v) => self.alexa_tts_input = v,
            Message::SendAlexaTts => {
                let msg = self.alexa_tts_input.trim().to_string();
                if msg.is_empty() {
                    self.banner_notice = Some(("Digite uma mensagem para enviar à Alexa.".to_string(), true));
                } else {
                    match build_script_command(
                        "Alexa TTS (Home Assistant)",
                        &self.paths.popos_repo,
                        "util/remote-devices/ha_alexa_remote.sh",
                        &["--notify", &msg],
                        false,
                    ) {
                        Ok(spec) => {
                            self.alexa_tts_input.clear();
                            self.start_command(spec);
                        }
                        Err(e) => self.banner_notice = Some((e, true)),
                    }
                }
            }
            Message::RunRemoteAction(id) => {
                let mode = match self.remote_network_mode {
                    HomelabNetworkMode::Local => "lan",
                    HomelabNetworkMode::Tailscale => "tailscale",
                };
                let (label, rel, args): (&str, &str, Vec<&str>) = match id.as_str() {
                    "net_scan" => ("Escanear Rede (LAN + mDNS + Tailscale)", "util/remote-devices/network_scan.sh", vec![]),
                    "win_check" => ("Windows 11: Testar SSH/RDP", "util/remote-devices/win_remote.sh", vec!["--mode", mode, "--check"]),
                    "win_status" => ("Windows 11: Status & Disco", "util/remote-devices/win_remote.sh", vec!["--mode", mode, "--status"]),
                    "win_clean" => ("Windows 11: Limpar Cache & Temp", "util/remote-devices/win_remote.sh", vec!["--mode", mode, "--clean"]),
                    "win_winget" => ("Windows 11: Winget Upgrade", "util/remote-devices/win_remote.sh", vec!["--mode", mode, "--winget-upgrade"]),
                    "win_rdp" => ("Windows 11: Abrir RDP", "util/remote-devices/win_remote.sh", vec!["--mode", mode, "--rdp"]),
                    "win_wol" => ("Windows 11: Wake-on-LAN", "util/remote-devices/win_remote.sh", vec!["--mode", mode, "--wol"]),
                    "win_setup_ssh" => ("Windows 11: Comando Setup OpenSSH", "util/remote-devices/win_remote.sh", vec!["--setup-ssh-cmd"]),
                    "android_connect" => ("Android: Conectar ADB", "util/remote-devices/android_remote.sh", vec!["--mode", mode, "--connect"]),
                    "android_status" => ("Android: Status & Espaço", "util/remote-devices/android_remote.sh", vec!["--mode", mode, "--status"]),
                    "android_clean" => ("Android: Limpar Cache Apps", "util/remote-devices/android_remote.sh", vec!["--mode", mode, "--clean-cache"]),
                    "android_scrcpy" => ("Android: Espelhar Tela (scrcpy)", "util/remote-devices/android_remote.sh", vec!["--mode", mode, "--scrcpy"]),
                    "android_disconnect" => ("Android: Desconectar ADB", "util/remote-devices/android_remote.sh", vec!["--mode", mode, "--disconnect"]),
                    "ha_check" => ("Home Assistant: Testar API", "util/remote-devices/ha_alexa_remote.sh", vec!["--check"]),
                    _ => return Task::none(),
                };
                match build_script_command(label, &self.paths.popos_repo, rel, &args, false) {
                    Ok(spec) => self.start_command(spec),
                    Err(e) => self.banner_notice = Some((e, true)),
                }
            }
            Message::RunSamsungAction(action) => {
                let target = match self.samsung_target {
                    SamsungTarget::Tv => "tv",
                    SamsungTarget::Projector => "projector",
                };
                let args: Vec<&str> = match action.as_str() {
                    "status" => vec!["--target", target, "--status"],
                    "wol" => vec!["--target", target, "--wol"],
                    key => vec!["--target", target, "--key", key],
                };
                match build_script_command(
                    format!("Samsung ({target}): {action}"),
                    &self.paths.popos_repo,
                    "util/remote-devices/samsung_tv_remote.py",
                    &args,
                    false,
                ) {
                    Ok(spec) => self.start_command(spec),
                    Err(e) => self.banner_notice = Some((e, true)),
                }
            }
            Message::FetchRemoteHomelabLogs => {
                let host = self.active_homelab_host();
                let spec = build_remote_homelab_logs_command(
                    &self.snapshot.homelab_user,
                    &host,
                    &self.paths.homelab_repo,
                );
                self.start_command(spec);
            }
            Message::OpenLocalFolder(path) => {
                if let Err(e) = open::that_detached(&path) {
                    self.banner_notice = Some((format!("Erro ao abrir pasta: {e}"), true));
                }
            }
            Message::RunTestTarget(target) => {
                let spec_res = match target {
                    TestTarget::PoposFull => build_script_command(
                        "Testes Pop!_OS (tests/run_all.py)",
                        &self.paths.popos_repo,
                        "tests/run_all.py",
                        &[],
                        false,
                    ),
                    TestTarget::PoposDocker => build_script_command(
                        "Sandbox Docker Pop!_OS (tests/test_in_docker.sh)",
                        &self.paths.popos_repo,
                        "tests/test_in_docker.sh",
                        &[],
                        false,
                    ),
                    TestTarget::HubRust => Ok(build_cargo_test_command(
                        &self.paths.popos_repo.join("workstation-hub"),
                    )),
                    TestTarget::HomelabFull => build_script_command(
                        "Testes Homelab Completo (umbrelos-scripts)",
                        &self.paths.homelab_repo,
                        "tests/run_all.py",
                        &[],
                        false,
                    ),
                    TestTarget::HomelabUnit => build_script_command(
                        "Testes Homelab Unitários (--unit)",
                        &self.paths.homelab_repo,
                        "tests/run_all.py",
                        &["--unit"],
                        false,
                    ),
                    TestTarget::HomelabIntegration => build_script_command(
                        "Testes Homelab Integração Remota (--integration)",
                        &self.paths.homelab_repo,
                        "tests/run_all.py",
                        &["--integration"],
                        false,
                    ),
                };
                match spec_res {
                    Ok(spec) => self.start_command(spec),
                    Err(e) => self.banner_notice = Some((e, true)),
                }
            }

            // Runner & Logs
            Message::RunnerEventReceived(ev) => match ev {
                RunnerEvent::Started { label } => {
                    self.run_status = RunStatus::Running { label };
                }
                RunnerEvent::Line(line) => {
                    self.log_lines.push(line);
                    if self.log_lines.len() > 5000 {
                        let excess = self.log_lines.len() - 5000;
                        self.log_lines.drain(..excess);
                    }
                }
                RunnerEvent::Finished {
                    label,
                    exit_code,
                    duration_ms,
                } => {
                    self.process_handle = None;
                    self.persist_session_log(&label);
                    if exit_code == 0 {
                        self.run_status = RunStatus::Succeeded { label, duration_ms };
                    } else {
                        self.run_status = RunStatus::Failed {
                            label,
                            exit_code,
                            duration_ms,
                        };
                    }
                    return self.spawn_probe_task();
                }
                RunnerEvent::Error { label, message } => {
                    self.process_handle = None;
                    self.log_lines
                        .push(LogLine::plain(format!("✖ {message}"), AnsiColor::Red, true));
                    self.run_status = RunStatus::Failed {
                        label,
                        exit_code: 1,
                        duration_ms: 0,
                    };
                }
            },
            Message::PtyInputChanged(v) => self.pty_input = v,
            Message::SendPtyInput => {
                if let Some(handle) = &self.process_handle {
                    let payload = self.pty_input.clone();
                    if let Err(e) = handle.send_input(&payload) {
                        self.banner_notice = Some((e, true));
                    } else {
                        self.log_lines.push(LogLine::plain(
                            format!("➜ [stdin] {payload}"),
                            AnsiColor::Yellow,
                            false,
                        ));
                        self.pty_input.clear();
                    }
                }
            }
            Message::StopRunningProcess => {
                if let Some(handle) = &self.process_handle {
                    if let Err(e) = handle.terminate() {
                        self.banner_notice = Some((e, true));
                    } else {
                        self.log_lines.push(LogLine::plain(
                            "⚠ Solicitação de encerramento enviada ao processo.",
                            AnsiColor::Yellow,
                            true,
                        ));
                    }
                }
            }
            Message::ClearConsoleLogs => self.log_lines.clear(),
            Message::OpenLogFile(path) => match fs::read_to_string(&path) {
                Ok(content) => {
                    let tail: String = content
                        .lines()
                        .rev()
                        .take(400)
                        .collect::<Vec<_>>()
                        .into_iter()
                        .rev()
                        .collect::<Vec<_>>()
                        .join("\n");
                    self.selected_log_preview = Some((path, tail));
                }
                Err(e) => self.banner_notice = Some((format!("Erro ao ler log: {e}"), true)),
            },
            Message::OpenHubExecution(idx) => {
                if let Some(rec) = self.snapshot.hub_executions.get(idx) {
                    let title = PathBuf::from(format!("{} ({})", rec.label, rec.timestamp));
                    self.selected_log_preview = Some((title, rec.body.clone()));
                }
            }
            Message::LogExecPagePrev => {
                self.log_exec_page = self.log_exec_page.saturating_sub(1);
            }
            Message::LogExecPageNext => {
                let total = self.snapshot.hub_executions.len();
                let max_page = total.saturating_sub(1) / 6;
                if self.log_exec_page < max_page {
                    self.log_exec_page += 1;
                }
            }
            Message::CloseLogPreview => {
                self.selected_log_preview = None;
                self.log_preview_filter.clear();
            }
            Message::LogPreviewFilterChanged(v) => self.log_preview_filter = v,
            Message::ConsoleHeightChanged(h) => self.console_height = h,
            Message::LogPreviewHeightChanged(h) => self.log_preview_height = h,
            Message::AutoProbeTick => {
                if self.process_handle.is_none() && !self.is_probing {
                    return self.spawn_probe_task();
                }
            }
            Message::CopyConsoleLogs => {
                let full_text = self
                    .log_lines
                    .iter()
                    .map(LogLine::as_plain_text)
                    .collect::<Vec<_>>()
                    .join("\n");
                return cosmic::iced::clipboard::write(full_text);
            }

            // Settings & .env Editor
            Message::PoposPathInputChanged(v) => self.popos_path_input = v,
            Message::HomelabPathInputChanged(v) => self.homelab_path_input = v,
            Message::SaveRepoPaths => {
                let p = PathBuf::from(self.popos_path_input.trim());
                let h = PathBuf::from(self.homelab_path_input.trim());
                if !is_valid_popos_repo(&p) {
                    self.banner_notice = Some((
                        "Caminho do popos-workstation-setup inválido (setup_popos.sh não encontrado).".to_string(),
                        true,
                    ));
                } else {
                    if !is_valid_homelab_repo(&h) {
                        self.banner_notice = Some((
                            "Aviso: caminho do Homelab salvo, mas setup_umbrelos.sh não foi encontrado nele.".to_string(),
                            false,
                        ));
                    } else {
                        self.banner_notice = Some(("Caminhos dos repositórios salvos com segurança (0600).".to_string(), false));
                    }
                    let new_paths = HubPaths {
                        popos_repo: p,
                        homelab_repo: h,
                    };
                    if let Err(e) = save_paths(&new_paths) {
                        self.banner_notice = Some((e, true));
                    } else {
                        self.paths = new_paths;
                        self.load_env_for_target(self.env_target);
                        return self.spawn_probe_task();
                    }
                }
            }
            Message::SwitchEnvTarget(target) => {
                self.load_env_for_target(target);
            }
            Message::EnvSearchChanged(v) => self.env_search = v,
            Message::EnvValueChanged(idx, v) => {
                if let Some(item) = self.env_entries.get_mut(idx) {
                    item.value = v;
                }
            }
            Message::ToggleEnvReveal(idx) => {
                if let Some(item) = self.env_entries.get_mut(idx) {
                    item.revealed = !item.revealed;
                }
            }
            Message::SaveCurrentEnv => {
                let root = match self.env_target {
                    EnvTarget::Popos => &self.paths.popos_repo,
                    EnvTarget::Homelab => &self.paths.homelab_repo,
                };
                match save_env_file(root, self.env_target, &self.env_entries) {
                    Ok(saved_path) => {
                        self.env_loaded_from_example = false;
                        self.env_status_msg = Some(format!(
                            "Salvo em {} com permissão estrita 0600.",
                            saved_path.display()
                        ));
                        return self.spawn_probe_task();
                    }
                    Err(e) => self.env_status_msg = Some(format!("Erro ao salvar: {e}")),
                }
            }
            Message::ReloadCurrentEnv => {
                self.load_env_for_target(self.env_target);
            }
        }
        Task::none()
    }

    fn view(&self) -> Element<'_, Self::Message> {
        let space_s = cosmic::theme::spacing().space_s;
        let space_m = cosmic::theme::spacing().space_m;

        let active_page = *self.nav.active_data::<Page>().unwrap_or(&Page::Dashboard);
        let page_content: Element<'_, Message> = match active_page {
            Page::Dashboard => views::dashboard::view(self),
            Page::Setup => views::setup::view(self),
            Page::Utils => views::utils::view(self),
            Page::Homelab => views::homelab::view(self),
            Page::RemoteDevices => views::remote::view(self),
            Page::Vpn => views::vpn::view(self),
            Page::Tests => views::tests::view(self),
            Page::Logs => views::logs::view(self),
            Page::Settings => views::settings::view(self),
        };

        let mut root_col = widget::column::with_capacity(3).spacing(space_s);

        if let Some((msg, is_err)) = &self.banner_notice {
            let notice_label = if *is_err {
                format!("⚠ {msg}")
            } else {
                format!("✔ {msg}")
            };
            let banner = widget::container(widget::text::body(notice_label))
                .padding([8, 12])
                .width(Length::Fill);
            root_col = root_col.push(banner);
        }

        root_col = root_col.push(
            widget::container(page_content)
                .width(Length::Fill)
                .height(Length::Fill),
        );

        root_col = root_col.push(self.status_footer());

        widget::container(root_col)
            .padding(space_m)
            .width(Length::Fill)
            .height(Length::Fill)
            .into()
    }
}

impl AppModel {
    pub fn active_homelab_host(&self) -> String {
        match self.homelab_network_mode {
            HomelabNetworkMode::Local => {
                if self.snapshot.homelab_local_host.is_empty() {
                    "umbrel.local".to_string()
                } else {
                    self.snapshot.homelab_local_host.clone()
                }
            }
            HomelabNetworkMode::Tailscale => {
                if self.snapshot.homelab_tailscale_host.is_empty() {
                    self.snapshot.homelab_local_host.clone()
                } else {
                    self.snapshot.homelab_tailscale_host.clone()
                }
            }
        }
    }

    fn persist_session_log(&self, label: &str) {
        let Some(state_dir) = dirs::state_dir().or_else(dirs::data_local_dir) else {
            return;
        };
        let logs_dir = state_dir.join("workstation-hub").join("logs");
        let content = self
            .log_lines
            .iter()
            .map(LogLine::as_plain_text)
            .collect::<Vec<_>>()
            .join("\n");
        let _ = crate::services::log_service::append_rotated_log(&logs_dir, label, &content);
    }

    pub fn update_title(&mut self) -> Task<cosmic::Action<Message>> {
        let mut window_title = String::from("Workstation & Homelab Hub");
        if let Some(page) = self.nav.text(self.nav.active()) {
            window_title.push_str(" — ");
            window_title.push_str(page);
        }
        if let Some(id) = self.core.main_window_id() {
            self.set_window_title(window_title, id)
        } else {
            Task::none()
        }
    }

    fn activate_page(&mut self, target: Page) {
        let ids: Vec<_> = self.nav.iter().collect();
        for id in ids {
            if self.nav.data::<Page>(id) == Some(&target) {
                self.nav.activate(id);
                break;
            }
        }
    }

    fn spawn_probe_task(&self) -> Task<cosmic::Action<Message>> {
        let paths = self.paths.clone();
        Task::perform(
            async move { collect_snapshot(&paths).await },
            |snap| cosmic::Action::App(Message::SnapshotLoaded(snap)),
        )
    }

    fn start_command(&mut self, spec: CommandSpec) {
        if self.process_handle.is_some() {
            self.banner_notice = Some((
                "Já existe uma tarefa em execução. Aguarde ou cancele no Console.".to_string(),
                true,
            ));
            self.activate_page(Page::Logs);
            return;
        }
        self.banner_notice = None;
        self.log_lines.clear();
        let handle = spawn_pty_command(spec, self.runner_tx.clone());
        self.process_handle = Some(handle);
        self.activate_page(Page::Logs);
    }

    fn load_env_for_target(&mut self, target: EnvTarget) {
        self.env_target = target;
        let root = match target {
            EnvTarget::Popos => &self.paths.popos_repo,
            EnvTarget::Homelab => &self.paths.homelab_repo,
        };
        match load_env_file(root, target) {
            Ok(loaded) => {
                self.env_entries = loaded.entries;
                self.env_loaded_from_example = loaded.loaded_from_example;
                self.env_status_msg = Some(if loaded.loaded_from_example {
                    "Carregado a partir do modelo .example (ao salvar, criará o arquivo real com chmod 0600).".to_string()
                } else {
                    format!("Carregado de {}", loaded.path.display())
                });
            }
            Err(e) => {
                self.env_entries.clear();
                self.env_loaded_from_example = false;
                self.env_status_msg = Some(e);
            }
        }
    }

    fn status_footer(&self) -> Element<'_, Message> {
        let space_s = cosmic::theme::spacing().space_s;
        let status_text = match &self.run_status {
            RunStatus::Idle => "Status: Pronto".to_string(),
            RunStatus::Running { label } => format!("⏳ Em execução: {label}"),
            RunStatus::Succeeded { label, duration_ms } => {
                format!("✔ Concluído: {label} ({:.1}s)", *duration_ms as f64 / 1000.0)
            }
            RunStatus::Failed {
                label,
                exit_code,
                duration_ms,
            } => format!(
                "✖ Falhou ({exit_code}): {label} ({:.1}s)",
                *duration_ms as f64 / 1000.0
            ),
        };

        let mut bar = widget::row::with_capacity(4)
            .spacing(space_s)
            .align_y(Alignment::Center)
            .push(widget::text::caption(status_text).width(Length::Fill));

        if self.process_handle.is_some() {
            bar = bar.push(
                widget::button::destructive("Parar").on_press(Message::StopRunningProcess),
            );
        }

        bar = bar.push(
            widget::button::standard("Console").on_press(Message::NavigateTo(Page::Logs)),
        );
        bar = bar.push(
            widget::button::standard("Atualizar").on_press(Message::RefreshSnapshot),
        );

        widget::container(bar)
            .padding([8, 12])
            .width(Length::Fill)
            .into()
    }
}
