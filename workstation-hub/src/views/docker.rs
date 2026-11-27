use crate::app::{AppModel, Message};
use crate::views::ui;
use cosmic::iced::{Alignment, Length};
use cosmic::prelude::*;
use cosmic::widget::{self, settings};

pub fn view(app: &AppModel) -> Element<'_, Message> {
    let info = &app.snapshot.docker_info;
    let running_count = info.containers.iter().filter(|c| c.running).count();
    let total_count = info.containers.len();

    let daemon_label = if info.daemon_active {
        format!("Ativo ({running_count}/{total_count} em execução)")
    } else {
        "Inativo (socket parado ou inacessível)".to_string()
    };

    let header = widget::row::with_capacity(3)
        .spacing(12)
        .align_y(Alignment::Center)
        .push(widget::text::title2("Docker (Pop!_OS)"))
        .push(widget::space::horizontal())
        .push(widget::button::standard("Atualizar Scan").on_press(Message::RefreshSnapshot));

    let mut global_sec = settings::section().title("Análise de Disco & Manutenção Global");
    global_sec = global_sec.add(settings::item(
        "Status do Daemon Docker",
        widget::text::body(daemon_label),
    ));

    if info.df_lines.is_empty() {
        global_sec = global_sec.add(settings::item(
            "Uso de Disco (docker system df)",
            widget::text::caption("Sem dados (clique em Atualizar Scan ou inicie o Docker)"),
        ));
    } else {
        for line in &info.df_lines {
            global_sec = global_sec.add(settings::item(
                "Uso de Disco",
                widget::text::caption(line.clone()),
            ));
        }
    }

    let global_actions = ui::wrap_row(vec![
        ui::btn_standard(
            "Analisar Disco (df -v)",
            Message::RunDockerAction("df_verbose".to_string()),
        )
        .into(),
        ui::btn_standard(
            "Limpar Imagens Não Usadas",
            Message::RunDockerAction("prune_images".to_string()),
        )
        .into(),
        ui::btn_standard(
            "Limpar Build Cache",
            Message::RunDockerAction("prune_cache".to_string()),
        )
        .into(),
        ui::btn_destructive(
            "Limpeza Geral (Prune)",
            Message::RunDockerAction("prune_system".to_string()),
        )
        .into(),
    ]);

    let daemon_actions = ui::wrap_row(vec![
        ui::btn_suggested(
            "Atualizar Todas Imagens (Pull)",
            Message::RunDockerAction("pull_all".to_string()),
        )
        .into(),
        ui::btn_standard(
            "Iniciar Daemon",
            Message::RunDockerAction("start_daemon".to_string()),
        )
        .into(),
        ui::btn_standard(
            "Reiniciar Daemon",
            Message::RunDockerAction("restart_daemon".to_string()),
        )
        .into(),
    ]);

    global_sec = global_sec.add(
        widget::column::with_capacity(2)
            .spacing(8)
            .padding([8, 12])
            .push(global_actions)
            .push(daemon_actions),
    );

    let mut containers_sec = settings::section().title("Containers Detectados no Pop!_OS");
    if info.containers.is_empty() {
        containers_sec = containers_sec.add(settings::item(
            "Nenhum container encontrado",
            widget::text::caption("Verifique se o daemon Docker está ativo ou clique em Atualizar Scan."),
        ));
    } else {
        for c in &info.containers {
            let subtitle = if c.compose_dir.is_empty() {
                format!("Imagem: {} | Status: {}", c.image, c.status)
            } else {
                format!(
                    "Imagem: {} | Status: {}\nCompose: {}",
                    c.image, c.status, c.compose_dir
                )
            };

            let mut btns = widget::row::with_capacity(6).spacing(6);
            if c.running {
                btns = btns
                    .push(
                        widget::button::destructive("Parar").on_press(
                            Message::RunDockerContainerAction {
                                name: c.name.clone(),
                                compose_dir: c.compose_dir.clone(),
                                action: "stop".to_string(),
                            },
                        ),
                    )
                    .push(
                        widget::button::standard("Reiniciar").on_press(
                            Message::RunDockerContainerAction {
                                name: c.name.clone(),
                                compose_dir: c.compose_dir.clone(),
                                action: "restart".to_string(),
                            },
                        ),
                    );
            } else {
                btns = btns.push(
                    widget::button::suggested("Iniciar").on_press(
                        Message::RunDockerContainerAction {
                            name: c.name.clone(),
                            compose_dir: c.compose_dir.clone(),
                            action: "start".to_string(),
                        },
                    ),
                );
            }

            btns = btns.push(
                widget::button::standard("Logs").on_press(Message::RunDockerContainerAction {
                    name: c.name.clone(),
                    compose_dir: c.compose_dir.clone(),
                    action: "logs".to_string(),
                }),
            );

            if !c.compose_dir.is_empty() {
                btns = btns
                    .push(
                        widget::button::standard("Atualizar").on_press(
                            Message::RunDockerContainerAction {
                                name: c.name.clone(),
                                compose_dir: c.compose_dir.clone(),
                                action: "compose_update".to_string(),
                            },
                        ),
                    )
                    .push(
                        widget::button::standard("Reconstruir").on_press(
                            Message::RunDockerContainerAction {
                                name: c.name.clone(),
                                compose_dir: c.compose_dir.clone(),
                                action: "compose_rebuild".to_string(),
                            },
                        ),
                    );
            }

            containers_sec = containers_sec.add(settings::item_row(vec![
                widget::column::with_capacity(2)
                    .spacing(3)
                    .width(Length::Fill)
                    .push(widget::text::body(c.name.clone()))
                    .push(widget::text::caption(subtitle))
                    .into(),
                btns.into(),
            ]));
        }
    }

    let content = widget::column::with_capacity(3)
        .spacing(16)
        .push(header)
        .push(global_sec)
        .push(containers_sec);

    ui::page_scroll(content)
}
