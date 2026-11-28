use crate::app::{AppModel, Message};
use crate::views::ui;
use cosmic::iced::Alignment;
use cosmic::prelude::*;
use cosmic::widget::{self, settings};

pub fn view(app: &AppModel) -> Element<'_, Message> {
    let info = &app.snapshot.winapps_info;

    let vm_label = if info.container_running {
        if info.container_status.is_empty() {
            "● Em execução (winapps-windows)".to_string()
        } else {
            format!("● Em execução — {}", info.container_status)
        }
    } else if !info.container_status.is_empty() {
        format!("○ Parado — {}", info.container_status)
    } else {
        "○ Container winapps-windows parado ou não encontrado".to_string()
    };

    let smb_label = if info.smb_mounted {
        format!("● Montado em ~/OneDrive_MPMS ({} itens na raiz)", info.smb_files_count)
    } else {
        "○ Desconectado / Pasta vazia (~/OneDrive_MPMS)".to_string()
    };

    let ports_label = format!(
        "RDP (:3389): {}   |   Console Web (:8006): {}",
        if info.rdp_port_open { "Online" } else { "Offline" },
        if info.vnc_web_open { "Online" } else { "Offline" },
    );

    let services_label = format!(
        "Indicador Painel: {}   |   Automount SMB: {}",
        if info.indicator_active { "Ativo" } else { "Parado" },
        if info.smb_service_active { "Ativo" } else { "Parado" },
    );

    let last_sync_label = if info.last_sync_state.is_empty() {
        "Nenhuma sincronização silenciosa registrada ainda".to_string()
    } else {
        let icon = match info.last_sync_state.as_str() {
            "completed" => "✔",
            "syncing" | "starting" => "⏳",
            "error" => "✖",
            _ => "•",
        };
        if info.last_sync_timestamp.is_empty() {
            format!("{icon} {}", info.last_sync_message)
        } else {
            format!(
                "{icon} {} ({})",
                info.last_sync_message,
                info.last_sync_timestamp.replace('T', " ")
            )
        }
    };

    let header = widget::row::with_capacity(3)
        .spacing(12)
        .align_y(Alignment::Center)
        .push(widget::text::title2("WinApps & OneDrive MPMS"))
        .push(widget::space::horizontal())
        .push(widget::button::standard("Atualizar Status").on_press(Message::RefreshSnapshot));

    // 1. Status em tempo real
    let mut status_sec = settings::section().title("Status da VM Windows 11 & Integração");
    status_sec = status_sec
        .add(settings::item("Container KVM (dockurr/windows)", widget::text::body(vm_label)))
        .add(settings::item("Compartilhamento OneDrive (SMB)", widget::text::body(smb_label)))
        .add(settings::item("Portas Locais (Loopback)", widget::text::caption(ports_label)))
        .add(settings::item("Serviços Systemd de Usuário", widget::text::caption(services_label)))
        .add(settings::item("Última Sincronização OneDrive", widget::text::caption(last_sync_label)));

    // 2. OneDrive MPMS (Sincronização & Arquivos)
    let mut onedrive_sec = settings::section().title("OneDrive Corporativo (MPMS) — Sincronização & Arquivos");
    let sync_btn: Element<'_, Message> = if info.container_running {
        ui::btn_suggested(
            "Sincronizar Arquivos do OneDrive (Silencioso)",
            Message::RunWinAppsAction("sync_onedrive".to_string()),
        )
        .into()
    } else {
        ui::btn_standard(
            "Sincronizar Arquivos do OneDrive (VM parada)",
            Message::RunWinAppsAction("sync_onedrive".to_string()),
        )
        .into()
    };

    let onedrive_actions = ui::wrap_row(vec![
        sync_btn,
        ui::btn_standard(
            "Abrir Pasta ~/OneDrive_MPMS",
            Message::RunWinAppsAction("open_onedrive_folder".to_string()),
        )
        .into(),
        ui::btn_standard(
            "Remontar SMB (fix-smb)",
            Message::RunWinAppsAction("fix_smb".to_string()),
        )
        .into(),
        ui::btn_standard(
            "Abrir OneDrive Web (M365)",
            Message::RunWinAppsAction("open_onedrive_web".to_string()),
        )
        .into(),
        ui::btn_standard(
            "Ver Log de Sincronização",
            Message::RunWinAppsAction("view_sync_log".to_string()),
        )
        .into(),
    ]);

    onedrive_sec = onedrive_sec.add(
        widget::column::with_capacity(2)
            .spacing(8)
            .padding([8, 12])
            .push(widget::text::caption(
                "Dispara o OneDrive.exe em segundo plano na VM via RemoteApp sem abrir janela visível, aguarda a estabilização dos arquivos e atualiza o compartilhamento SMB.",
            ))
            .push(onedrive_actions),
    );

    // 3. Controle da VM Windows 11
    let mut vm_sec = settings::section().title("Controle da VM Windows 11 & Acesso Visual");
    let mut vm_controls: Vec<Element<'_, Message>> = Vec::new();
    if info.container_running {
        vm_controls.push(
            ui::btn_standard(
                "Reiniciar VM",
                Message::RunWinAppsAction("restart_vm".to_string()),
            )
            .into(),
        );
        vm_controls.push(
            ui::btn_destructive(
                "Desligar VM",
                Message::RunWinAppsAction("stop_vm".to_string()),
            )
            .into(),
        );
    } else {
        vm_controls.push(
            ui::btn_suggested(
                "Iniciar VM Windows",
                Message::RunWinAppsAction("start_vm".to_string()),
            )
            .into(),
        );
    }
    vm_controls.push(
        ui::btn_standard(
            "Logs do Container",
            Message::RunWinAppsAction("logs_vm".to_string()),
        )
        .into(),
    );

    let vm_access = ui::wrap_row(vec![
        ui::btn_standard(
            "Abrir no Remmina (Console VNC)",
            Message::RunWinAppsAction("open_remmina_vnc".to_string()),
        )
        .into(),
        ui::btn_standard(
            "Abrir no Remmina (Sessão RDP)",
            Message::RunWinAppsAction("open_remmina_rdp".to_string()),
        )
        .into(),
        ui::btn_standard(
            "Abrir Console Web (:8006)",
            Message::RunWinAppsAction("open_web_console".to_string()),
        )
        .into(),
    ]);

    vm_sec = vm_sec.add(
        widget::column::with_capacity(2)
            .spacing(8)
            .padding([8, 12])
            .push(ui::wrap_row(vm_controls))
            .push(vm_access),
    );

    // 4. Manutenção, RemoteApps & Scripts Windows
    let scripts_hint = format!(
        "CLI winapps-vm: {}   |   Scripts sync_onedrive em ~/Compartilhado_VM: {}",
        if info.winapps_cli_installed { "Instalada" } else { "Ausente" },
        if info.sync_scripts_ready { "Prontos" } else { "Pendentes" },
    );

    let mut maint_sec = settings::section().title("Manutenção, RemoteApps & Scripts Windows");
    maint_sec = maint_sec.add(settings::item("Provisionamento Local", widget::text::caption(scripts_hint)));

    let maint_actions = ui::wrap_row(vec![
        ui::btn_standard(
            "Detectar Apps Office (setup-apps)",
            Message::RunWinAppsAction("setup_apps".to_string()),
        )
        .into(),
        ui::btn_standard(
            "Reparar AutoLogon (fix-autologon)",
            Message::RunWinAppsAction("fix_autologon".to_string()),
        )
        .into(),
        ui::btn_standard(
            "Reiniciar Indicador do Painel",
            Message::RunWinAppsAction("restart_indicator".to_string()),
        )
        .into(),
        ui::btn_standard(
            "Reiniciar Serviço SMB",
            Message::RunWinAppsAction("restart_smb_service".to_string()),
        )
        .into(),
        ui::btn_standard(
            "Atualizar Scripts & Indicador",
            Message::RunWinAppsAction("deploy_winapps_scripts".to_string()),
        )
        .into(),
        ui::btn_standard(
            "Abrir ~/Compartilhado_VM",
            Message::RunWinAppsAction("open_shared_folder".to_string()),
        )
        .into(),
        ui::btn_standard(
            "Abrir util/winapps",
            Message::OpenLocalFolder(app.paths.popos_repo.join("util").join("winapps")),
        )
        .into(),
    ]);

    maint_sec = maint_sec.add(
        widget::column::with_capacity(1)
            .spacing(8)
            .padding([8, 12])
            .push(maint_actions),
    );

    let content = widget::column::with_capacity(5)
        .spacing(16)
        .push(header)
        .push(status_sec)
        .push(onedrive_sec)
        .push(vm_sec)
        .push(maint_sec);

    ui::page_scroll(content)
}
