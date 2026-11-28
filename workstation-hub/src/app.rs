use crate::models::catalog::{
    HOMELAB_SETUP_MODULES, HOMELAB_UTIL_ACTIONS, LOCAL_UTIL_ACTIONS, SETUP_MODULES,
};
use crate::models::doc_entry::{DocEntryItem, MarkdownBlock, MarkdownLinkResolution};
use crate::models::env_entry::{EnvTarget, EnvVarItem};
use crate::models::log_entry::{AnsiColor, LogLine, RunStatus};
use crate::models::status::{
    HomelabAddressMode, HomelabNetworkMode, HubPaths, SamsungTarget, SystemSnapshot,
};
use crate::services::doc_service::{
    CATEGORY_ALL, SOURCE_ALL, available_categories, available_sources, discover_all_documents,
    export_standalone_html, parse_markdown, read_document_content, resolve_markdown_link,
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
    System,
    PanelTray,
    Docker,
    Homelab,
    RemoteDevices,
    Network,
    Vpn,
    Tests,
    Logs,
    Docs,
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
    Console,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MenuAction {
    Refresh,
    OpenProjectFolder,
    OpenLogsFolder,
    GoSettings,
    Quit,
    ToggleConsoleDrawer,
    GoDashboard,
    GoSystem,
    GoPanelTray,
    GoDocker,
    GoHomelab,
    GoNetwork,
    QuickBackupCosmic,
    QuickRepairIdes,
    QuickRestartRclone,
    QuickRunTests,
    OpenDocsFolder,
    About,
}

impl menu::action::MenuAction for MenuAction {
    type Message = Message;

    fn message(&self) -> Self::Message {
        match self {
            MenuAction::Refresh => Message::RefreshSnapshot,
            MenuAction::OpenProjectFolder => Message::MenuOpenProjectFolder,
            MenuAction::OpenLogsFolder => Message::MenuOpenLogsFolder,
            MenuAction::GoSettings => Message::NavigateTo(Page::Settings),
            MenuAction::Quit => Message::MenuQuit,
            MenuAction::ToggleConsoleDrawer => Message::ToggleContextPage(ContextPage::Console),
            MenuAction::GoDashboard => Message::NavigateTo(Page::Dashboard),
            MenuAction::GoSystem => Message::NavigateTo(Page::System),
            MenuAction::GoPanelTray => Message::NavigateTo(Page::PanelTray),
            MenuAction::GoDocker => Message::NavigateTo(Page::Docker),
            MenuAction::GoHomelab => Message::NavigateTo(Page::Homelab),
            MenuAction::GoNetwork => Message::NavigateTo(Page::Network),
            MenuAction::QuickBackupCosmic => Message::RunSystemAction("backup_cosmic_gdrive".to_string()),
            MenuAction::QuickRepairIdes => Message::RunSystemAction("repair_ides".to_string()),
            MenuAction::QuickRestartRclone => Message::RunSystemAction("rclone_restart".to_string()),
            MenuAction::QuickRunTests => Message::RunTestTarget(TestTarget::PoposFull),
            MenuAction::OpenDocsFolder => Message::NavigateTo(Page::Docs),
            MenuAction::About => Message::ToggleContextPage(ContextPage::About),
        }
    }
}

#[derive(Debug, Clone)]
pub enum Message {
    RefreshSnapshot,
    SnapshotLoaded(SystemSnapshot),
    ToggleContextPage(ContextPage),
    LaunchUrl(String),
    MenuOpenProjectFolder,
    MenuOpenLogsFolder,
    MenuOpenDocsFolder,
    MenuQuit,

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
    RustDeskTargetChanged(String),
    RustDeskConnect,
    RustDeskOpen,
    RustDeskToggleService,
    RunSamsungTargetAction(SamsungTarget, String),
    RunDockerAction(String),
    RunDockerContainerAction {
        name: String,
        compose_dir: String,
        action: String,
    },
    RunSystemAction(String),
    OpenRgbHexChanged(String),
    ApplyOpenRgbHex,
    OpenRgbSetColor(String),
    RunNetworkAction(String),
    SetPanelAppletSegment(String, crate::models::status::PanelSegment),
    ToggleTrayIndicator(String, bool),
    RestartTrayIndicator(String),
    ActivateTrayItem(String, String),
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
    DeleteHubExecution(usize),
    ClearAllHubExecutions,
    LogExecPagePrev,
    LogExecPageNext,
    DocsSearchChanged(String),
    DocsSourceSelected(usize),
    DocsCategorySelected(usize),
    DocsReloadCatalog,
    DocsNavigateBack,
    DocsNavigateForward,
    DocsFontSizeDelta(f32),
    DocsFontSizeReset,
    ToggleDocsSelectMode,
    ToggleDocsSidebar,
    DocsEditorAction(cosmic::iced::widget::text_editor::Action),
    SelectDocFile(PathBuf),
    CopyDocContent,
    DocsCopyCodeBlock { lang: String, code: String },
    DocsExportHtml,
    DocsOpenCurrentFolder,
    DocsOpenMedia(PathBuf),
    CopyText(String),
    CloseLogPreview,
    LogPreviewFilterChanged(String),
    ConsoleHeightChanged(f32),
    LogPreviewHeightChanged(f32),
    CopyConsoleLogs,
    AutoProbeTick,
    ConsoleProgressTick,

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
    pub rustdesk_target_id: String,
    pub samsung_target: SamsungTarget,
    pub alexa_tts_input: String,
    pub openrgb_hex_input: String,

    // Runner & Logs state
    pub run_status: RunStatus,
    pub log_lines: Vec<LogLine>,
    pub console_progress: f32,
    pub docs_catalog: Vec<DocEntryItem>,
    pub docs_sources: Vec<String>,
    pub docs_categories: Vec<String>,
    pub docs_search: String,
    pub docs_source_idx: usize,
    pub docs_category_idx: usize,
    pub docs_font_size: f32,
    pub docs_select_mode: bool,
    pub docs_sidebar_open: bool,
    pub docs_back_history: Vec<PathBuf>,
    pub docs_forward_history: Vec<PathBuf>,
    pub docs_status_badge: Option<(String, bool)>,
    pub docs_editor_content: cosmic::iced::widget::text_editor::Content,
    pub selected_doc_path: Option<PathBuf>,
    pub selected_doc_content: String,
    pub selected_doc_blocks: Vec<MarkdownBlock>,
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
            .text("Sistema")
            .data::<Page>(Page::System)
            .icon(icon::from_name("computer-symbolic"));
        nav.insert()
            .text("Painel & Tray")
            .data::<Page>(Page::PanelTray)
            .icon(icon::from_name("view-grid-symbolic"));
        nav.insert()
            .text("Docker (Pop!_OS)")
            .data::<Page>(Page::Docker)
            .icon(icon::from_name("utilities-system-monitor-symbolic"));
        nav.insert()
            .text("Homelab (umbrelOS)")
            .data::<Page>(Page::Homelab)
            .icon(icon::from_name("network-server-symbolic"));
        nav.insert()
            .text("Dispositivos (Rede)")
            .data::<Page>(Page::RemoteDevices)
            .icon(icon::from_name("computer-symbolic"));
        nav.insert()
            .text("Monitor de Rede")
            .data::<Page>(Page::Network)
            .icon(icon::from_name("network-wired-symbolic"));
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
            .text("Documentação (Wiki)")
            .data::<Page>(Page::Docs)
            .icon(icon::from_name("help-contents-symbolic"));
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
            rustdesk_target_id: String::new(),
            samsung_target: SamsungTarget::Tv,
            alexa_tts_input: String::new(),
            openrgb_hex_input: "7A5AF8".to_string(),
            run_status: RunStatus::Idle,
            log_lines: vec![LogLine::plain(
                "Hub pronto. Selecione uma ação para acompanhar a saída em tempo real.",
                AnsiColor::Muted,
                false,
            )],
            console_progress: 0.15,
            docs_catalog: Vec::new(),
            docs_sources: vec![SOURCE_ALL.to_string()],
            docs_categories: vec![CATEGORY_ALL.to_string()],
            docs_search: String::new(),
            docs_source_idx: 0,
            docs_category_idx: 0,
            docs_font_size: 14.0,
            docs_select_mode: false,
            docs_sidebar_open: true,
            docs_back_history: Vec::new(),
            docs_forward_history: Vec::new(),
            docs_status_badge: None,
            docs_editor_content: cosmic::iced::widget::text_editor::Content::new(),
            selected_doc_path: None,
            selected_doc_content: String::new(),
            selected_doc_blocks: Vec::new(),
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
        app.reload_docs_catalog();
        let title_task = app.update_title();
        let probe_task = app.spawn_probe_task();

        (app, Task::batch([title_task, probe_task]))
    }

    fn header_start(&self) -> Vec<Element<'_, Self::Message>> {
        let menu_bar = menu::bar(vec![
            menu::Tree::with_children(
                menu::root("Arquivo").apply(Element::from),
                menu::items(
                    &self.key_binds,
                    vec![
                        menu::Item::Button("Atualizar Painel", None, MenuAction::Refresh),
                        menu::Item::Button(
                            "Abrir Pasta do Projeto",
                            None,
                            MenuAction::OpenProjectFolder,
                        ),
                        menu::Item::Button("Abrir Pasta de Logs", None, MenuAction::OpenLogsFolder),
                        menu::Item::Button("Configurações & .env", None, MenuAction::GoSettings),
                        menu::Item::Divider,
                        menu::Item::Button("Sair", None, MenuAction::Quit),
                    ],
                ),
            ),
            menu::Tree::with_children(
                menu::root("Exibir").apply(Element::from),
                menu::items(
                    &self.key_binds,
                    vec![
                        menu::Item::Button(
                            "Alternar Console Lateral",
                            None,
                            MenuAction::ToggleConsoleDrawer,
                        ),
                        menu::Item::Divider,
                        menu::Item::Button("Visão Geral", None, MenuAction::GoDashboard),
                        menu::Item::Button("Sistema", None, MenuAction::GoSystem),
                        menu::Item::Button("Painel & Tray", None, MenuAction::GoPanelTray),
                        menu::Item::Button("Docker (Pop!_OS)", None, MenuAction::GoDocker),
                        menu::Item::Button("Homelab (umbrelOS)", None, MenuAction::GoHomelab),
                        menu::Item::Button("Monitor de Rede", None, MenuAction::GoNetwork),
                    ],
                ),
            ),
            menu::Tree::with_children(
                menu::root("Ações Rápidas").apply(Element::from),
                menu::items(
                    &self.key_binds,
                    vec![
                        menu::Item::Button(
                            "Backup COSMIC (.config -> Google Drive)",
                            None,
                            MenuAction::QuickBackupCosmic,
                        ),
                        menu::Item::Button(
                            "Reparar IDEs (Locks & GPU)",
                            None,
                            MenuAction::QuickRepairIdes,
                        ),
                        menu::Item::Button(
                            "Reiniciar Montagens Rclone",
                            None,
                            MenuAction::QuickRestartRclone,
                        ),
                        menu::Item::Divider,
                        menu::Item::Button(
                            "Rodar Testes (setup_popos.sh --test)",
                            None,
                            MenuAction::QuickRunTests,
                        ),
                    ],
                ),
            ),
            menu::Tree::with_children(
                menu::root("Ajuda").apply(Element::from),
                menu::items(
                    &self.key_binds,
                    vec![
                        menu::Item::Button("Documentação (Docs/)", None, MenuAction::OpenDocsFolder),
                        menu::Item::Divider,
                        menu::Item::Button("Sobre o Workstation Hub", None, MenuAction::About),
                    ],
                ),
            ),
        ]);
        let menu_bar = menu_bar.item_width(menu::ItemWidth::Uniform(310));
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
            ContextPage::Console => views::logs::console_drawer(self),
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

        let progress_sub = if self.process_handle.is_some() {
            Subscription::run(|| {
                cosmic::iced::stream::channel(
                    4,
                    move |mut emitter: futures::channel::mpsc::Sender<Message>| async move {
                        use futures::SinkExt;
                        let mut interval = tokio::time::interval(std::time::Duration::from_millis(350));
                        loop {
                            interval.tick().await;
                            if emitter.send(Message::ConsoleProgressTick).await.is_err() {
                                break;
                            }
                        }
                    },
                )
            })
        } else {
            Subscription::none()
        };

        Subscription::batch([runner_sub, tick_sub, progress_sub])
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
                if let Some(raw_href) = url.strip_prefix("doc://") {
                    if let Some(current_doc) = self.current_doc_entry().cloned() {
                        match resolve_markdown_link(
                            &current_doc.source_root,
                            &current_doc.full_path,
                            raw_href,
                        ) {
                            MarkdownLinkResolution::InternalDocument { path, .. } => {
                                return self.open_doc_by_path(path, true);
                            }
                            MarkdownLinkResolution::LocalImage(path)
                            | MarkdownLinkResolution::LocalAttachment(path) => {
                                if let Err(err) = open::that_detached(&path) {
                                    self.docs_status_badge =
                                        Some((format!("⚠️ Falha ao abrir: {err}"), true));
                                } else {
                                    let name = path
                                        .file_name()
                                        .and_then(|s| s.to_str())
                                        .unwrap_or("arquivo");
                                    self.docs_status_badge =
                                        Some((format!("📂 Aberto: {name}"), false));
                                }
                            }
                            MarkdownLinkResolution::ExternalHttpUrl(ext) => {
                                if let Err(err) = open::that_detached(&ext) {
                                    self.banner_notice =
                                        Some((format!("Erro ao abrir URL: {err}"), true));
                                }
                            }
                            MarkdownLinkResolution::Anchor(anchor) => {
                                return self.scroll_doc_to_anchor(&anchor);
                            }
                            MarkdownLinkResolution::Unsupported(target) => {
                                self.docs_status_badge =
                                    Some((format!("ℹ️ Referência externa: {target}"), false));
                            }
                        }
                    }
                } else if let Some(anchor) = url.strip_prefix("anchor://") {
                    return self.scroll_doc_to_anchor(anchor);
                } else if let Err(err) = open::that_detached(&url) {
                    self.banner_notice = Some((format!("Erro ao abrir URL: {err}"), true));
                }
            }
            Message::MenuOpenProjectFolder => {
                let _ = open::that_detached(&self.paths.popos_repo);
            }
            Message::MenuOpenLogsFolder => {
                if let Some(state_dir) = dirs::state_dir().or_else(dirs::data_local_dir) {
                    let logs_dir = state_dir.join("workstation-hub").join("logs");
                    let _ = fs::create_dir_all(&logs_dir);
                    let _ = open::that_detached(logs_dir);
                }
            }
            Message::MenuOpenDocsFolder => {
                let _ = open::that_detached(self.paths.popos_repo.join("Docs"));
            }
            Message::MenuQuit => {
                return cosmic::iced::exit();
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
            Message::RustDeskTargetChanged(val) => {
                self.rustdesk_target_id = val;
            }
            Message::RustDeskConnect => {
                let id = self.rustdesk_target_id.trim().to_string();
                if id.is_empty() {
                    self.banner_notice = Some(("Informe o ID remoto do RustDesk para conectar.".to_string(), true));
                } else {
                    match std::process::Command::new("rustdesk").arg("--connect").arg(&id).spawn() {
                        Ok(_) => {
                            self.banner_notice = Some((format!("Abrindo conexão RustDesk para {id}..."), false));
                        }
                        Err(e) => {
                            self.banner_notice = Some((format!("Falha ao abrir RustDesk: {e}"), true));
                        }
                    }
                }
            }
            Message::RustDeskOpen => {
                match std::process::Command::new("rustdesk").spawn() {
                    Ok(_) => {
                        self.banner_notice = Some(("RustDesk aberto.".to_string(), false));
                    }
                    Err(e) => {
                        self.banner_notice = Some((format!("Falha ao abrir RustDesk: {e}"), true));
                    }
                }
            }
            Message::RustDeskToggleService => {
                let spec = CommandSpec {
                    label: "RustDesk: Ativar & Reiniciar Serviço".to_string(),
                    program: "pkexec".to_string(),
                    args: vec![
                        "systemctl".to_string(),
                        "enable".to_string(),
                        "--now".to_string(),
                        "rustdesk.service".to_string(),
                    ],
                    workdir: self.paths.popos_repo.clone(),
                    cleanup_file: None,
                };
                self.start_command(spec);
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
                    "win_moonlight" => ("Windows 11: Abrir Moonlight", "util/remote-devices/win_remote.sh", vec!["--mode", mode, "--moonlight"]),
                    "win_rdp" => ("Windows 11: Abrir RDP", "util/remote-devices/win_remote.sh", vec!["--mode", mode, "--rdp"]),
                    "win_wol" => ("Windows 11: Wake-on-LAN", "util/remote-devices/win_remote.sh", vec!["--mode", mode, "--wol"]),
                    "win_setup_ssh" => ("Windows 11: Comando Setup OpenSSH", "util/remote-devices/win_remote.sh", vec!["--setup-ssh-cmd"]),
                    "android_connect" => ("Android: Conectar ADB", "util/remote-devices/android_remote.sh", vec!["--mode", mode, "--connect"]),
                    "android_status" => ("Android: Status & Espaço", "util/remote-devices/android_remote.sh", vec!["--mode", mode, "--status"]),
                    "android_clean" => ("Android: Limpar Cache Apps", "util/remote-devices/android_remote.sh", vec!["--mode", mode, "--clean-cache"]),
                    "android_scrcpy" => ("Android: Espelhar Tela (scrcpy)", "util/remote-devices/android_remote.sh", vec!["--mode", mode, "--scrcpy"]),
                    "android_disconnect" => ("Android: Desconectar ADB", "util/remote-devices/android_remote.sh", vec!["--mode", mode, "--disconnect"]),
                    "tablet_connect" => ("Tablet Android: Conectar ADB", "util/remote-devices/android_remote.sh", vec!["--device", "tablet", "--mode", mode, "--connect"]),
                    "tablet_status" => ("Tablet Android: Status & Espaço", "util/remote-devices/android_remote.sh", vec!["--device", "tablet", "--mode", mode, "--status"]),
                    "tablet_clean" => ("Tablet Android: Limpar Cache Apps", "util/remote-devices/android_remote.sh", vec!["--device", "tablet", "--mode", mode, "--clean-cache"]),
                    "tablet_scrcpy" => ("Tablet Android: Espelhar Tela (scrcpy)", "util/remote-devices/android_remote.sh", vec!["--device", "tablet", "--mode", mode, "--scrcpy"]),
                    "tablet_disconnect" => ("Tablet Android: Desconectar ADB", "util/remote-devices/android_remote.sh", vec!["--device", "tablet", "--mode", mode, "--disconnect"]),
                    "ha_check" => ("Home Assistant: Testar API", "util/remote-devices/ha_alexa_remote.sh", vec!["--check"]),
                    _ => return Task::none(),
                };
                match build_script_command(label, &self.paths.popos_repo, rel, &args, false) {
                    Ok(spec) => self.start_command(spec),
                    Err(e) => self.banner_notice = Some((e, true)),
                }
            }
            Message::RunSamsungTargetAction(target_dev, action) => {
                let target = match target_dev {
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
            Message::RunDockerAction(action) => {
                let (label, program, args): (&str, &str, Vec<String>) = match action.as_str() {
                    "df_verbose" => ("Docker: Análise de Disco (df -v)", "docker", vec!["system".into(), "df".into(), "-v".into()]),
                    "prune_images" => ("Docker: Limpar Imagens Não Usadas", "docker", vec!["image".into(), "prune".into(), "-a".into(), "-f".into()]),
                    "prune_cache" => ("Docker: Limpar Build Cache", "docker", vec!["builder".into(), "prune".into(), "-f".into()]),
                    "prune_system" => ("Docker: Limpeza Geral (Prune)", "docker", vec!["system".into(), "prune".into(), "-f".into()]),
                    "pull_all" => (
                        "Docker: Atualizar Todas Imagens (Pull)",
                        "bash",
                        vec![
                            "-lc".into(),
                            "docker images --format '{{.Repository}}:{{.Tag}}' | grep -v '<none>' | sort -u | xargs -r -n1 docker pull".into(),
                        ],
                    ),
                    "start_daemon" => ("Docker: Iniciar Daemon", "sudo", vec!["systemctl".into(), "start".into(), "docker".into()]),
                    "restart_daemon" => ("Docker: Reiniciar Daemon", "sudo", vec!["systemctl".into(), "restart".into(), "docker".into()]),
                    _ => return Task::none(),
                };
                self.start_command(CommandSpec {
                    label: label.to_string(),
                    program: program.to_string(),
                    args,
                    workdir: self.paths.popos_repo.clone(),
                    cleanup_file: None,
                });
            }
            Message::RunDockerContainerAction { name, compose_dir, action } => {
                let (label, program, args, workdir): (String, &str, Vec<String>, Option<PathBuf>) = match action.as_str() {
                    "start" => (format!("Docker: Iniciar {name}"), "docker", vec!["start".into(), name], None),
                    "stop" => (format!("Docker: Parar {name}"), "docker", vec!["stop".into(), name], None),
                    "restart" => (format!("Docker: Reiniciar {name}"), "docker", vec!["restart".into(), name], None),
                    "logs" => (format!("Docker: Logs {name}"), "docker", vec!["logs".into(), "--tail".into(), "150".into(), name], None),
                    "compose_update" if !compose_dir.is_empty() => (
                        format!("Docker Compose: Atualizar {name}"),
                        "bash",
                        vec!["-lc".into(), "docker compose pull && docker compose up -d".into()],
                        Some(PathBuf::from(compose_dir)),
                    ),
                    "compose_rebuild" if !compose_dir.is_empty() => (
                        format!("Docker Compose: Reconstruir {name}"),
                        "bash",
                        vec!["-lc".into(), "docker compose build --no-cache && docker compose up -d".into()],
                        Some(PathBuf::from(compose_dir)),
                    ),
                    _ => return Task::none(),
                };
                self.start_command(CommandSpec {
                    label,
                    program: program.to_string(),
                    args,
                    workdir: workdir.unwrap_or_else(|| self.paths.popos_repo.clone()),
                    cleanup_file: None,
                });
            }
            Message::RunSystemAction(action) => {
                let homelab_user = self.snapshot.homelab_user.clone();
                let homelab_host = self.active_homelab_host();
                let (label, program, args): (String, &str, Vec<String>) = match action.as_str() {
                    "sunshine_start" => ("Sunshine: Iniciar".into(), "systemctl", vec!["--user".into(), "start".into(), "sunshine".into()]),
                    "sunshine_stop" => ("Sunshine: Parar".into(), "systemctl", vec!["--user".into(), "stop".into(), "sunshine".into()]),
                    "sunshine_status" => ("Sunshine: Status".into(), "systemctl", vec!["--user".into(), "status".into(), "sunshine".into(), "--no-pager".into()]),
                    "openrgb_rainbow" => ("OpenRGB: Modo Rainbow".into(), "flatpak", vec!["run".into(), "org.openrgb.OpenRGB".into(), "--mode".into(), "rainbow".into()]),
                    "openrgb_off" => ("OpenRGB: Desligar Todos LEDs".into(), "flatpak", vec!["run".into(), "org.openrgb.OpenRGB".into(), "--mode".into(), "static".into(), "--color".into(), "000000".into()]),
                    "openrgb_list" => ("OpenRGB: Listar Dispositivos".into(), "flatpak", vec!["run".into(), "org.openrgb.OpenRGB".into(), "--list-devices".into()]),
                    "audio_restart" => ("Áudio: Reiniciar PipeWire".into(), "systemctl", vec!["--user".into(), "restart".into(), "pipewire".into(), "pipewire-pulse".into(), "wireplumber".into()]),
                    "audio_bt" => ("Áudio: Alternar para QCY H3S".into(), "bash", vec!["-lc".into(), "pactl list short sinks | awk '/bluez/{print $2}' | head -n1 | xargs -r pactl set-default-sink".into()]),
                    "audio_speakers" => ("Áudio: Alternar para Caixas de Som".into(), "bash", vec!["-lc".into(), "pactl list short sinks | awk '!/bluez/{print $2}' | head -n1 | xargs -r pactl set-default-sink".into()]),
                    "backup_cosmic_gdrive" => (
                        "Backup COSMIC (.config -> Google Drive)".into(),
                        "bash",
                        vec![
                            "-lc".into(),
                            "TS=$(date +%Y%m%d_%H%M%S) && ARC=/tmp/cosmic-config-$TS.tar.gz && tar -czf \"$ARC\" -C \"$HOME/.config\" cosmic && echo \"[INFO] Arquivo criado: $ARC\" && rclone copy \"$ARC\" gdrive_pessoal:Backups_PopOS/cosmic/ --progress && rm -f \"$ARC\" && echo \"[OK] Backup COSMIC enviado para gdrive_pessoal:Backups_PopOS/cosmic/\"".into(),
                        ],
                    ),
                    "sync_homelab_disk3" => (
                        "Homelab: Verificar Daemon & Sincronizar disk3".into(),
                        "bash",
                        vec![
                            "-lc".into(),
                            format!(
                                "echo '[INFO] Verificando serviços/timers de backup...' && systemctl --user list-timers --all | grep -iE 'homelab|backup|umbrel' || true; mkdir -p /mnt/storage_930/Backups_Homelab && rsync -avh --delete --progress {homelab_user}@{homelab_host}:/mnt/disk3/backups/ /mnt/storage_930/Backups_Homelab/ && echo '[OK] Sincronização concluída em /mnt/storage_930/Backups_Homelab/'"
                            ),
                        ],
                    ),
                    "rclone_restart" => ("Rclone: Reiniciar Montagens".into(), "bash", vec!["-lc".into(), "systemctl --user restart 'rclone-*' && echo '[OK] Serviços rclone reiniciados'".into()]),
                    "onedrive_sync" => ("OneDrive (MPMS): Forçar Sync".into(), "onedrive", vec!["--synchronize".into()],),
                    "repair_ides" => ("Reparar IDEs (Locks & GPU Cache)".into(), "bash", vec!["./setup_popos.sh".into(), "--repair-ides".into()]),
                    "restart_cosmic_panel" => ("COSMIC: Reiniciar Panel".into(), "bash", vec!["-lc".into(), "pkill -f cosmic-panel || true".into()]),
                    "power_suspend" => ("Energia: Suspender".into(), "systemctl", vec!["suspend".into()]),
                    "power_reboot" => ("Energia: Reiniciar PC".into(), "systemctl", vec!["reboot".into()]),
                    "power_off" => ("Energia: Desligar PC".into(), "systemctl", vec!["poweroff".into()]),
                    _ => return Task::none(),
                };
                self.start_command(CommandSpec {
                    label,
                    program: program.to_string(),
                    args,
                    workdir: self.paths.popos_repo.clone(),
                    cleanup_file: None,
                });
            }
            Message::OpenRgbHexChanged(v) => self.openrgb_hex_input = v,
            Message::ApplyOpenRgbHex => {
                let hex = self.openrgb_hex_input.trim().trim_start_matches('#').to_string();
                if hex.len() == 6 && hex.chars().all(|c| c.is_ascii_hexdigit()) {
                    self.start_command(CommandSpec {
                        label: format!("OpenRGB: Cor #{hex}"),
                        program: "flatpak".to_string(),
                        args: vec![
                            "run".into(),
                            "org.openrgb.OpenRGB".into(),
                            "--mode".into(),
                            "static".into(),
                            "--color".into(),
                            hex,
                        ],
                        workdir: self.paths.popos_repo.clone(),
                        cleanup_file: None,
                    });
                } else {
                    self.banner_notice = Some((
                        "Informe um código HEX válido de 6 dígitos (ex: 7A5AF8).".to_string(),
                        true,
                    ));
                }
            }
            Message::OpenRgbSetColor(hex) => {
                self.openrgb_hex_input = hex.clone();
                self.start_command(CommandSpec {
                    label: format!("OpenRGB: Cor #{hex}"),
                    program: "flatpak".to_string(),
                    args: vec![
                        "run".into(),
                        "org.openrgb.OpenRGB".into(),
                        "--mode".into(),
                        "static".into(),
                        "--color".into(),
                        hex,
                    ],
                    workdir: self.paths.popos_repo.clone(),
                    cleanup_file: None,
                });
            }
            Message::RunNetworkAction(action) => {
                let (label, program, args): (&str, &str, Vec<String>) = match action.as_str() {
                    "lan_sweep" => (
                        "Rede: Varredura LAN (Ping Sweep)",
                        "bash",
                        vec![
                            "-lc".into(),
                            "SUBNET=$(ip -4 route show scope link | awk '{print $1}' | head -n1); echo \"[INFO] Varrendo sub-rede $SUBNET...\"; if command -v nmap >/dev/null; then nmap -sn \"$SUBNET\"; else PREFIX=${SUBNET%.*}; for i in $(seq 1 254); do (ping -c1 -W1 \"${PREFIX}.$i\" >/dev/null 2>&1 && echo \"Ativo: ${PREFIX}.$i\") & done; wait; fi".into(),
                        ],
                    ),
                    "dns_check" => (
                        "Rede: Teste DNS & Internet",
                        "bash",
                        vec![
                            "-lc".into(),
                            "echo '=== Gateway ==='; ping -c 2 \"$(ip route show default | awk '/via/{print $3; exit}')\"; echo '=== Cloudflare 1.1.1.1 ==='; ping -c 2 1.1.1.1; echo '=== Resolução DNS ==='; resolvectl query google.com || nslookup google.com".into(),
                        ],
                    ),
                    "listening_ports" => (
                        "Rede: Portas Locais Abertas (ss -tulnp)",
                        "ss",
                        vec!["-tulnp".into()],
                    ),
                    "tailscale_status" => (
                        "Tailscale: Status Completo",
                        "tailscale",
                        vec!["status".into()],
                    ),
                    _ => return Task::none(),
                };
                self.start_command(CommandSpec {
                    label: label.to_string(),
                    program: program.to_string(),
                    args,
                    workdir: self.paths.popos_repo.clone(),
                    cleanup_file: None,
                });
            }
            Message::SetPanelAppletSegment(id, seg) => {
                match crate::services::panel_tray_service::set_applet_segment(&id, seg) {
                    Ok(()) => {
                        self.banner_notice = Some((
                            format!("Painel COSMIC atualizado ({id})"),
                            false,
                        ));
                        let paths = self.paths.clone();
                        return Task::perform(
                            async move {
                                crate::services::probe_service::collect_snapshot(&paths).await
                            },
                            Message::SnapshotLoaded,
                        )
                        .map(cosmic::Action::App);
                    }
                    Err(e) => self.banner_notice = Some((e, true)),
                }
            }
            Message::ToggleTrayIndicator(unit, show) => {
                let verb = if show { "start" } else { "stop" };
                let label = format!(
                    "Bandeja: {} {unit}",
                    if show { "Exibir" } else { "Ocultar" }
                );
                self.start_command(CommandSpec {
                    label,
                    program: "systemctl".to_string(),
                    args: vec!["--user".into(), verb.into(), unit],
                    workdir: self.paths.popos_repo.clone(),
                    cleanup_file: None,
                });
            }
            Message::RestartTrayIndicator(unit) => {
                self.start_command(CommandSpec {
                    label: format!("Bandeja: Reiniciar {unit}"),
                    program: "systemctl".to_string(),
                    args: vec!["--user".into(), "restart".into(), unit],
                    workdir: self.paths.popos_repo.clone(),
                    cleanup_file: None,
                });
            }
            Message::ActivateTrayItem(bus, path) => {
                self.start_command(CommandSpec {
                    label: format!("Bandeja: Ativar {bus}"),
                    program: "gdbus".to_string(),
                    args: vec![
                        "call".into(),
                        "--session".into(),
                        "--dest".into(),
                        bus,
                        "--object-path".into(),
                        path,
                        "--method".into(),
                        "org.kde.StatusNotifierItem.Activate".into(),
                        "0".into(),
                        "0".into(),
                    ],
                    workdir: self.paths.popos_repo.clone(),
                    cleanup_file: None,
                });
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
            Message::DeleteHubExecution(idx) => {
                if let Some(rec) = self.snapshot.hub_executions.get(idx).cloned()
                    && let Some(state_dir) = dirs::state_dir().or_else(dirs::data_local_dir)
                {
                    let logs_dir = state_dir.join("workstation-hub").join("logs");
                    match crate::services::log_service::delete_hub_execution(
                        &logs_dir,
                        &rec.timestamp,
                        &rec.label,
                    ) {
                        Ok(()) => {
                            self.snapshot.hub_executions.remove(idx);
                            self.selected_log_preview = None;
                        }
                        Err(e) => self.banner_notice = Some((e, true)),
                    }
                }
            }
            Message::ClearAllHubExecutions => {
                if let Some(state_dir) = dirs::state_dir().or_else(dirs::data_local_dir) {
                    let logs_dir = state_dir.join("workstation-hub").join("logs");
                    match crate::services::log_service::clear_hub_executions(&logs_dir) {
                        Ok(()) => {
                            self.snapshot.hub_executions.clear();
                            self.log_exec_page = 0;
                            self.selected_log_preview = None;
                            self.banner_notice = Some((
                                "Histórico de execuções do Hub apagado.".to_string(),
                                false,
                            ));
                        }
                        Err(e) => self.banner_notice = Some((e, true)),
                    }
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
            Message::DocsSearchChanged(v) => {
                self.docs_search = v;
                self.docs_status_badge = None;
            }
            Message::DocsSourceSelected(idx) => {
                self.docs_source_idx = idx;
                let source = self
                    .docs_sources
                    .get(idx)
                    .map(String::as_str)
                    .unwrap_or(SOURCE_ALL);
                self.docs_categories = available_categories(&self.docs_catalog, source);
                self.docs_category_idx = 0;
                self.docs_status_badge = None;
            }
            Message::DocsCategorySelected(idx) => {
                self.docs_category_idx = idx;
                self.docs_status_badge = None;
            }
            Message::DocsReloadCatalog => {
                self.reload_docs_catalog();
                self.docs_status_badge = Some((
                    format!("🔄 {} doc(s) reindexado(s)", self.docs_catalog.len()),
                    false,
                ));
            }
            Message::DocsNavigateBack => {
                if let Some(prev_path) = self.docs_back_history.pop() {
                    if let Some(cur) = self.selected_doc_path.clone() {
                        self.docs_forward_history.push(cur);
                    }
                    return self.open_doc_by_path(prev_path, false);
                }
            }
            Message::DocsNavigateForward => {
                if let Some(next_path) = self.docs_forward_history.pop() {
                    if let Some(cur) = self.selected_doc_path.clone() {
                        self.docs_back_history.push(cur);
                    }
                    return self.open_doc_by_path(next_path, false);
                }
            }
            Message::DocsFontSizeDelta(delta) => {
                self.docs_font_size = (self.docs_font_size + delta).clamp(11.0, 22.0);
            }
            Message::DocsFontSizeReset => {
                self.docs_font_size = 14.0;
            }
            Message::ToggleDocsSelectMode => {
                self.docs_select_mode = !self.docs_select_mode;
            }
            Message::ToggleDocsSidebar => {
                self.docs_sidebar_open = !self.docs_sidebar_open;
            }
            Message::DocsEditorAction(action) => {
                // Allow cursor movement, selection, and scrolling only (read-only)
                if !action.is_edit() {
                    self.docs_editor_content.perform(action);
                }
            }
            Message::SelectDocFile(path) => {
                return self.open_doc_by_path(path, true);
            }
            Message::CopyDocContent => {
                if !self.selected_doc_content.is_empty() {
                    let fname = self
                        .current_doc_entry()
                        .map(|d| d.file_name.clone())
                        .unwrap_or_else(|| "documento.md".to_string());
                    self.docs_status_badge = Some((format!("📋 {fname} copiado!"), false));
                    return cosmic::iced::clipboard::write(self.selected_doc_content.clone());
                }
            }
            Message::DocsCopyCodeBlock { lang, code } => {
                if !code.is_empty() {
                    let label = if lang.is_empty() { "código" } else { &lang };
                    self.docs_status_badge =
                        Some((format!("📋 Bloco {label} copiado!"), false));
                    return cosmic::iced::clipboard::write(code);
                }
            }
            Message::DocsExportHtml => {
                if let Some(doc) = self.current_doc_entry().cloned() {
                    let html = export_standalone_html(&doc, &self.selected_doc_content);
                    let downloads_dir = dirs::download_dir()
                        .or_else(dirs::home_dir)
                        .unwrap_or_else(|| PathBuf::from("/tmp"));
                    let _ = fs::create_dir_all(&downloads_dir);
                    let stem = doc
                        .file_name
                        .strip_suffix(".md")
                        .unwrap_or(&doc.file_name);
                    let out_path = downloads_dir.join(format!("{stem}_offline.html"));
                    match fs::write(&out_path, html) {
                        Ok(()) => {
                            let fname = out_path
                                .file_name()
                                .and_then(|s| s.to_str())
                                .unwrap_or("offline.html");
                            self.docs_status_badge =
                                Some((format!("📦 Exportado: {fname}"), false));
                            self.banner_notice = Some((
                                format!("HTML offline exportado em {}", out_path.display()),
                                false,
                            ));
                        }
                        Err(e) => {
                            self.docs_status_badge =
                                Some(("⚠️ Falha ao exportar HTML".to_string(), true));
                            self.banner_notice =
                                Some((format!("Erro ao exportar HTML: {e}"), true));
                        }
                    }
                }
            }
            Message::DocsOpenCurrentFolder => {
                let target_dir = self
                    .selected_doc_path
                    .as_ref()
                    .and_then(|p| p.parent())
                    .map(PathBuf::from)
                    .unwrap_or_else(|| self.paths.popos_repo.join("Docs"));
                if let Err(err) = open::that_detached(&target_dir) {
                    self.docs_status_badge =
                        Some((format!("⚠️ Falha ao abrir pasta: {err}"), true));
                }
            }
            Message::DocsOpenMedia(path) => {
                if let Err(err) = open::that_detached(&path) {
                    self.docs_status_badge =
                        Some((format!("⚠️ Falha ao abrir mídia: {err}"), true));
                } else {
                    let name = path
                        .file_name()
                        .and_then(|s| s.to_str())
                        .unwrap_or("mídia");
                    self.docs_status_badge = Some((format!("📂 Aberto: {name}"), false));
                }
            }
            Message::CopyText(txt) => {
                if !txt.is_empty() {
                    return cosmic::iced::clipboard::write(txt);
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
            Message::ConsoleProgressTick => {
                if self.process_handle.is_some() {
                    self.console_progress += 0.06;
                    if self.console_progress > 0.94 {
                        self.console_progress = 0.12;
                    }
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
                        self.reload_docs_catalog();
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
            Page::System => views::system::view(self),
            Page::PanelTray => views::panel_tray::view(self),
            Page::Docker => views::docker::view(self),
            Page::Homelab => views::homelab::view(self),
            Page::RemoteDevices => views::remote::view(self),
            Page::Network => views::network::view(self),
            Page::Vpn => views::vpn::view(self),
            Page::Tests => views::tests::view(self),
            Page::Logs => views::logs::view(self),
            Page::Docs => views::docs::view(self),
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
            self.context_page = ContextPage::Console;
            self.core.window.show_context = true;
            return;
        }
        self.banner_notice = None;
        self.log_lines.clear();
        self.console_progress = 0.15;
        let handle = spawn_pty_command(spec, self.runner_tx.clone());
        self.process_handle = Some(handle);
        self.context_page = ContextPage::Console;
        self.core.window.show_context = true;
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

    pub fn current_doc_entry(&self) -> Option<&DocEntryItem> {
        let path = self.selected_doc_path.as_ref()?;
        self.docs_catalog.iter().find(|d| &d.full_path == path)
    }

    fn reload_docs_catalog(&mut self) {
        let prev_path = self.selected_doc_path.clone();
        self.docs_catalog =
            discover_all_documents(&self.paths.popos_repo, &self.paths.homelab_repo);
        self.docs_sources = available_sources(&self.docs_catalog);
        if self.docs_source_idx >= self.docs_sources.len() {
            self.docs_source_idx = 0;
        }
        let selected_source = self
            .docs_sources
            .get(self.docs_source_idx)
            .map(String::as_str)
            .unwrap_or(SOURCE_ALL);
        self.docs_categories = available_categories(&self.docs_catalog, selected_source);
        if self.docs_category_idx >= self.docs_categories.len() {
            self.docs_category_idx = 0;
        }
        if self.docs_catalog.is_empty() {
            self.selected_doc_path = None;
            self.selected_doc_content.clear();
            self.selected_doc_blocks.clear();
            self.docs_editor_content = cosmic::iced::widget::text_editor::Content::new();
            return;
        }
        let target = prev_path
            .and_then(|p| self.docs_catalog.iter().find(|d| d.full_path == p))
            .or_else(|| {
                self.docs_catalog
                    .iter()
                    .find(|d| d.relative_path.eq_ignore_ascii_case("Docs/README.md"))
            })
            .or_else(|| self.docs_catalog.first())
            .map(|d| d.full_path.clone());

        if let Some(path) = target {
            let _ = self.open_doc_by_path(path, false);
        }
    }

    fn open_doc_by_path(
        &mut self,
        path: PathBuf,
        record_history: bool,
    ) -> Task<cosmic::Action<Message>> {
        let Some(entry) = self
            .docs_catalog
            .iter()
            .find(|d| d.full_path == path)
            .cloned()
        else {
            self.docs_status_badge =
                Some(("⚠️ Documento não encontrado no catálogo".to_string(), true));
            return Task::none();
        };

        match read_document_content(&entry.source_root, &entry.full_path) {
            Ok(content) => {
                if record_history
                    && let Some(prev) = self.selected_doc_path.clone()
                    && prev != entry.full_path
                {
                    self.docs_back_history.push(prev);
                    self.docs_forward_history.clear();
                }
                self.docs_editor_content =
                    cosmic::iced::widget::text_editor::Content::with_text(&content);
                self.selected_doc_blocks = parse_markdown(&content);
                self.selected_doc_path = Some(entry.full_path);
                self.selected_doc_content = content;
                self.docs_status_badge = None;
                cosmic::iced::widget::scrollable::snap_to(
                    widget::Id::new("docs_reader_scroll"),
                    cosmic::iced::widget::scrollable::RelativeOffset {
                        x: Some(0.0),
                        y: Some(0.0),
                    },
                )
            }
            Err(e) => {
                self.docs_status_badge = Some((format!("⚠️ Falha ao ler: {e}"), true));
                Task::none()
            }
        }
    }

    fn scroll_doc_to_anchor(&self, anchor: &str) -> Task<cosmic::Action<Message>> {
        let slug = anchor
            .trim_start_matches('#')
            .to_ascii_lowercase()
            .replace('-', " ");
        let lines: Vec<&str> = self.selected_doc_content.lines().collect();
        let total = lines.len().max(1) as f32;
        if let Some((idx, _)) = lines.iter().enumerate().find(|(_, l)| {
            let t = l.trim_start();
            t.starts_with('#')
                && t.trim_start_matches('#')
                    .to_ascii_lowercase()
                    .chars()
                    .filter(|c| c.is_alphanumeric() || c.is_whitespace())
                    .collect::<String>()
                    .contains(&slug)
        }) {
            let ratio = (idx as f32 / total).clamp(0.0, 1.0);
            return cosmic::iced::widget::scrollable::snap_to(
                widget::Id::new("docs_reader_scroll"),
                cosmic::iced::widget::scrollable::RelativeOffset {
                    x: Some(0.0),
                    y: Some(ratio),
                },
            );
        }
        Task::none()
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

        let mut bar = widget::row::with_capacity(6)
            .spacing(space_s)
            .align_y(Alignment::Center)
            .push(widget::text::caption(status_text).width(Length::Fill));

        if self.process_handle.is_some() {
            bar = bar
                .push(
                    cosmic::iced::widget::progress_bar(0.0..=1.0, self.console_progress)
                        .length(Length::Fixed(120.0))
                        .girth(Length::Fixed(6.0)),
                )
                .push(
                    widget::button::destructive("Parar").on_press(Message::StopRunningProcess),
                );
        }

        bar = bar.push(
            widget::button::standard("Console")
                .on_press(Message::ToggleContextPage(ContextPage::Console)),
        );
        bar = bar.push(
            widget::button::standard("Histórico").on_press(Message::NavigateTo(Page::Logs)),
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
