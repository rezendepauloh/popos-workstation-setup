use crate::app::{AppModel, Message};
use crate::models::catalog::{
    HOMELAB_SETUP_MODULES, HOMELAB_UTIL_ACTIONS, HOMELAB_WEB_SERVICES,
};
use crate::models::status::{HomelabAddressMode, HomelabNetworkMode};
use crate::views::ui;
use cosmic::iced::{Alignment, Length};
use cosmic::prelude::*;
use cosmic::widget::{self, settings};

pub fn view(app: &AppModel) -> Element<'_, Message> {
    let space_s = cosmic::theme::spacing().space_s;
    let space_m = cosmic::theme::spacing().space_m;

    let active_host = app.active_homelab_host();
    let conn_label = match app.snapshot.homelab_online {
        None => "Verificando SSH...".to_string(),
        Some(true) => format!("✔ Conectado ({}@{active_host})", app.snapshot.homelab_user),
        Some(false) => format!("✖ Sem resposta ({}@{active_host})", app.snapshot.homelab_user),
    };

    let header = widget::row::with_capacity(4)
        .spacing(space_s)
        .align_y(Alignment::Center)
        .push(widget::text::title2("Homelab umbrelOS").width(Length::Fill))
        .push(widget::text::body(conn_label))
        .push(widget::button::suggested("Abrir SSH").on_press(Message::OpenHomelabSshTerminal))
        .push(
            widget::button::standard("Pasta Scripts")
                .on_press(Message::OpenLocalFolder(app.paths.homelab_repo.clone())),
        );

    let net_row = ui::wrap_row(vec![
        widget::text::body("Rede:").into(),
        net_btn(
            "Local (LAN)",
            HomelabNetworkMode::Local,
            app.homelab_network_mode,
        ),
        net_btn(
            "Tailscale",
            HomelabNetworkMode::Tailscale,
            app.homelab_network_mode,
        ),
        widget::text::body("  Endereço Web:").into(),
        addr_btn(
            "DNS (*.pk.local)",
            HomelabAddressMode::Dns,
            app.homelab_address_mode,
        ),
        addr_btn(
            "IP (:porta)",
            HomelabAddressMode::Ip,
            app.homelab_address_mode,
        ),
    ]);

    let domain = if app.snapshot.homelab_domain.is_empty() {
        "pk.local"
    } else {
        app.snapshot.homelab_domain.as_str()
    };

    let web_buttons: Vec<Element<'_, Message>> = HOMELAB_WEB_SERVICES
        .iter()
        .map(|svc| {
            let url = match app.homelab_address_mode {
                HomelabAddressMode::Dns => format!("https://{}.{domain}", svc.subdomain),
                HomelabAddressMode::Ip => {
                    if svc.port == 80 {
                        format!("http://{active_host}")
                    } else {
                        format!("http://{active_host}:{}", svc.port)
                    }
                }
            };
            let label = match app.homelab_address_mode {
                HomelabAddressMode::Dns => format!("{} ({})", svc.name, svc.subdomain),
                HomelabAddressMode::Ip => {
                    if svc.port == 80 {
                        svc.name.to_string()
                    } else {
                        format!("{}:{}", svc.name, svc.port)
                    }
                }
            };
            ui::btn_standard(label, Message::LaunchUrl(url)).into()
        })
        .collect();
    let web_rows = ui::wrap_row(web_buttons);

    let web_section = settings::section()
        .title("Acessos Web Rápidos (22 Serviços)")
        .add(widget::container(net_row).padding(4))
        .add(widget::container(web_rows).padding(4));

    let restore_service_row = widget::row::with_capacity(2)
        .spacing(space_s)
        .align_y(Alignment::Center)
        .push(
            widget::text_input("immich, jellyfin, nextcloud, ha...", &app.homelab_service_input)
                .on_input(Message::HomelabServiceInputChanged)
                .width(Length::Fixed(240.0)),
        )
        .push(
            widget::button::suggested("Restaurar Serviço")
                .on_press(Message::RunHomelabRestoreService),
        );

    let quick_restore_sec = settings::section()
        .title("Restauração Direcionada")
        .add(
            settings::item::builder("Restaurar Serviço Específico")
                .description("Executa homelab_restaurar_servicos.sh --service <nome> via SSH.")
                .control(restore_service_row),
        );

    let mut col = widget::column::with_capacity(10)
        .spacing(space_m)
        .push(header)
        .push(web_section)
        .push(quick_restore_sec);

    let groups = [
        "Saúde & Diagnóstico",
        "Recuperação & Manutenção",
        "Stacks Docker",
        "Backups & Rollback",
    ];

    for group_name in groups {
        let mut sec = settings::section().title(group_name);
        for act in HOMELAB_UTIL_ACTIONS.iter().filter(|a| a.group == group_name) {
            let desc = if act.interactive {
                format!("{} (Interativo no Console PTY)", act.subtitle)
            } else {
                act.subtitle.to_string()
            };
            sec = sec.add(
                settings::item::builder(act.title)
                    .description(desc)
                    .control(
                        widget::button::standard("Executar")
                            .on_press(Message::RunHomelabAction(act.id.to_string())),
                    ),
            );
        }
        col = col.push(sec);
    }

    let setup_toggle = settings::section()
        .title("Provisionamento Base do Servidor (scripts/setup/)")
        .add(
            settings::item::builder("Exibir Módulos de Setup do umbrelOS (01..07)")
                .description("Módulos de instalação inicial do servidor (rodar apenas em manutenção/setup).")
                .control(
                    widget::toggler(app.show_homelab_setup)
                        .on_toggle(Message::ToggleHomelabSetupSection),
                ),
        );
    col = col.push(setup_toggle);

    if app.show_homelab_setup {
        let mut setup_sec = settings::section().title("Módulos Setup umbrelOS");
        for act in HOMELAB_SETUP_MODULES {
            setup_sec = setup_sec.add(
                settings::item::builder(act.title)
                    .description(act.subtitle)
                    .control(
                        widget::button::destructive("Executar Setup")
                            .on_press(Message::RunHomelabAction(act.id.to_string())),
                    ),
            );
        }
        col = col.push(setup_sec);
    }

    ui::page_scroll(col)
}

fn net_btn(
    label: &'static str,
    target: HomelabNetworkMode,
    active: HomelabNetworkMode,
) -> Element<'static, Message> {
    if target == active {
        widget::button::suggested(label)
            .on_press(Message::SetHomelabNetworkMode(target))
            .into()
    } else {
        widget::button::standard(label)
            .on_press(Message::SetHomelabNetworkMode(target))
            .into()
    }
}

fn addr_btn(
    label: &'static str,
    target: HomelabAddressMode,
    active: HomelabAddressMode,
) -> Element<'static, Message> {
    if target == active {
        widget::button::suggested(label)
            .on_press(Message::SetHomelabAddressMode(target))
            .into()
    } else {
        widget::button::standard(label)
            .on_press(Message::SetHomelabAddressMode(target))
            .into()
    }
}
