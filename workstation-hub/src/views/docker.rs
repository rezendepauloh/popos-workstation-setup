use crate::app::{AppModel, Message};
use crate::models::status::DockerUpdateState;
use crate::services::probe_service::short_sha;
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

    if app.docker_updates_checking {
        global_sec = global_sec.add(settings::item(
            "Análise de Atualizações",
            widget::text::caption("Verificando digests remotos dos containers em paralelo..."),
        ));
    } else if !app.docker_update_results.is_empty() {
        let mut updates_avail = 0usize;
        let mut up_to_date = 0usize;
        let mut local_or_unverifiable = 0usize;
        let mut errors = 0usize;
        for res in app.docker_update_results.values() {
            match res.state {
                DockerUpdateState::UpdateAvailable { .. } => updates_avail += 1,
                DockerUpdateState::UpToDate => up_to_date += 1,
                DockerUpdateState::LocalOrUnverifiable => local_or_unverifiable += 1,
                DockerUpdateState::Error(_) => errors += 1,
            }
        }
        let checked_at = app
            .docker_updates_checked_at
            .as_deref()
            .unwrap_or("agora");
        let summary = if errors > 0 {
            format!(
                "Última análise ({checked_at}): {updates_avail} com atualização | {up_to_date} atualizados | {local_or_unverifiable} locais/não verificáveis | {errors} erro(s)"
            )
        } else {
            format!(
                "Última análise ({checked_at}): {updates_avail} com atualização | {up_to_date} atualizados | {local_or_unverifiable} locais/não verificáveis"
            )
        };
        global_sec = global_sec.add(settings::item(
            "Análise de Atualizações",
            widget::text::caption(summary),
        ));
    }

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

    let check_updates_btn = if app.docker_updates_checking {
        widget::button::standard("Analisando Atualizações...").into()
    } else {
        ui::btn_suggested("Analisar Atualizações", Message::CheckDockerUpdates).into()
    };

    let daemon_actions = ui::wrap_row(vec![
        check_updates_btn,
        ui::btn_standard(
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
            let mut subtitle = if c.compose_dir.is_empty() {
                format!("Imagem: {} | Status: {}", c.image, c.status)
            } else {
                format!(
                    "Imagem: {} | Status: {}\nCompose: {}",
                    c.image, c.status, c.compose_dir
                )
            };

            if let Some(upd) = app.docker_update_results.get(&c.name) {
                let local_info = if upd.local_version.is_empty() {
                    short_sha(&upd.local_digest)
                } else {
                    format!(
                        "v{} | {}",
                        upd.local_version.trim_start_matches('v'),
                        short_sha(&upd.local_digest)
                    )
                };
                let status_line = match &upd.state {
                    DockerUpdateState::UpToDate => {
                        format!("✔ Atualizado (local: {local_info})")
                    }
                    DockerUpdateState::UpdateAvailable { remote_digest } => {
                        format!(
                            "⬆ Atualização disponível (local: {local_info} → remoto: {})",
                            short_sha(remote_digest)
                        )
                    }
                    DockerUpdateState::LocalOrUnverifiable => {
                        format!("⚠ Build local / não verificável remotamente (local: {local_info})")
                    }
                    DockerUpdateState::Error(err) => {
                        format!("✖ Erro ao verificar atualização: {err}")
                    }
                };
                subtitle.push('\n');
                subtitle.push_str(&status_line);
            }

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
            } else {
                btns = btns.push(
                    widget::button::standard("Atualizar").on_press(
                        Message::RunDockerContainerAction {
                            name: c.name.clone(),
                            compose_dir: String::new(),
                            action: "standalone_update".to_string(),
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
