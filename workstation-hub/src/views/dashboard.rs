use crate::app::{AppModel, Message, Page, TestTarget};
use crate::models::catalog::SETUP_MODULES;
use cosmic::iced::{Alignment, Length};
use cosmic::prelude::*;
use cosmic::widget::{self, settings};

pub fn view(app: &AppModel) -> Element<'_, Message> {
    let space_s = cosmic::theme::spacing().space_s;
    let space_m = cosmic::theme::spacing().space_m;

    let completed = SETUP_MODULES
        .iter()
        .filter(|m| app.snapshot.completed_flags.contains(m.flag_name))
        .count();
    let total = SETUP_MODULES.len();

    let active_host = app.active_homelab_host();
    let homelab_badge = match app.snapshot.homelab_online {
        None => "Verificando...".to_string(),
        Some(true) => format!("Online ({}@{active_host})", app.snapshot.homelab_user),
        Some(false) => format!("Offline ({}@{active_host})", app.snapshot.homelab_user),
    };

    let adb_badge = if app.snapshot.adb_devices.is_empty() {
        "Nenhum celular conectado".to_string()
    } else {
        format!("Conectado: {}", app.snapshot.adb_devices.join(", "))
    };

    let docker_badge = match (app.snapshot.docker_active, app.snapshot.winapps_running) {
        (true, true) => "Ativo (WinApps VM em execução)".to_string(),
        (true, false) => "Ativo (WinApps parado)".to_string(),
        (false, _) => "Daemon inativo / sob demanda".to_string(),
    };

    let status_section = settings::section()
        .title("Resumo do Ecossistema")
        .add(settings::item::builder("Módulos Pós-Formatação").control(
            widget::row::with_capacity(2)
                .spacing(space_s)
                .align_y(Alignment::Center)
                .push(widget::text::body(format!("{completed} / {total} concluídos")))
                .push(
                    widget::button::standard("Abrir Setup")
                        .on_press(Message::NavigateTo(Page::Setup)),
                ),
        ))
        .add(settings::item::builder("Homelab (umbrelOS SSH)").control(
            widget::row::with_capacity(2)
                .spacing(space_s)
                .align_y(Alignment::Center)
                .push(widget::text::body(homelab_badge))
                .push(
                    widget::button::standard("Abrir Homelab")
                        .on_press(Message::NavigateTo(Page::Homelab)),
                ),
        ))
        .add(
            settings::item::builder("Dispositivo Android (ADB)")
                .control(widget::text::body(adb_badge)),
        )
        .add(
            settings::item::builder("Docker & WinApps")
                .control(widget::text::body(docker_badge)),
        )
        .add(
            settings::item::builder("Google Antigravity IDE")
                .control(widget::text::body(app.snapshot.antigravity_version.clone())),
        );

    let quick_actions = settings::section()
        .title("Ações Rápidas")
        .add(
            settings::item::builder("Reparar IDEs (Antigravity & VS Code)")
                .description("Limpa locks residuais, caches Dawn/GPU e reaplica flags Wayland.")
                .control(
                    widget::button::suggested("Reparar IDEs")
                        .on_press(Message::RunLocalUtil("repair_ides".to_string())),
                ),
        )
        .add(
            settings::item::builder("Executar Suíte de Testes Pop!_OS")
                .description("Valida scripts Bash, daemons Python, segurança e módulos (tests/run_all.py).")
                .control(
                    widget::button::standard("Rodar Testes")
                        .on_press(Message::RunTestTarget(TestTarget::PoposFull)),
                ),
        )
        .add(
            settings::item::builder("Saúde & Hardware do Homelab")
                .description("Coleta CPU, temperatura, RAM, montagens, SMART dos 3 HDs e stacks via SSH.")
                .control(
                    widget::button::standard("Painel de Saúde")
                        .on_press(Message::RunHomelabAction("hl_dashboard".to_string())),
                ),
        )
        .add(
            settings::item::builder("Verificar Quedas no Homelab")
                .description("Audita erros EIO, containers reiniciando e falhas HTTP 502/503/504.")
                .control(
                    widget::button::standard("Verificar Quedas")
                        .on_press(Message::RunHomelabAction("hl_quedas".to_string())),
                ),
        )
        .add(
            settings::item::builder("Terminal SSH Direto (Homelab)")
                .description("Abre uma sessão SSH no cosmic-term para o servidor umbrelOS.")
                .control(
                    widget::button::standard("Abrir SSH")
                        .on_press(Message::OpenHomelabSshTerminal),
                ),
        );

    let repos_section = settings::section()
        .title("Repositórios Conectados")
        .add(
            settings::item::builder("popos-workstation-setup")
                .description(app.paths.popos_repo.to_string_lossy().to_string())
                .control(
                    widget::button::standard("Abrir Pasta")
                        .on_press(Message::OpenLocalFolder(app.paths.popos_repo.clone())),
                ),
        )
        .add(
            settings::item::builder("umbrelos-scripts (Homelab)")
                .description(app.paths.homelab_repo.to_string_lossy().to_string())
                .control(
                    widget::button::standard("Abrir Pasta")
                        .on_press(Message::OpenLocalFolder(app.paths.homelab_repo.clone())),
                ),
        );

    let header = widget::row::with_capacity(2)
        .spacing(space_s)
        .align_y(Alignment::Center)
        .push(widget::text::title2("Central da Workstation & Homelab").width(Length::Fill))
        .push(widget::button::standard(if app.is_probing {
            "Sondando..."
        } else {
            "Atualizar Painel"
        })
        .on_press(Message::RefreshSnapshot));

    let body = widget::column::with_capacity(4)
        .spacing(space_m)
        .push(header)
        .push(status_section)
        .push(quick_actions)
        .push(repos_section);

    widget::scrollable(body).height(Length::Fill).into()
}
