use crate::app::{AppModel, Message};
use crate::models::env_entry::EnvTarget;
use cosmic::iced::{Alignment, Length};
use cosmic::prelude::*;
use cosmic::widget::{self, settings};

pub fn view(app: &AppModel) -> Element<'_, Message> {
    let space_s = cosmic::theme::spacing().space_s;
    let space_m = cosmic::theme::spacing().space_m;

    let header = widget::row::with_capacity(2)
        .spacing(space_s)
        .align_y(Alignment::Center)
        .push(widget::text::title2("Configurações & Cofre .env Seguro").width(Length::Fill));

    let paths_section = settings::section()
        .title("Caminhos dos Repositórios")
        .add(
            settings::item::builder("popos-workstation-setup")
                .description("Diretório contendo setup_popos.sh, scripts/, util/ e tests/.")
                .control(
                    widget::text_input("Caminho do repositório Pop!_OS", &app.popos_path_input)
                        .on_input(Message::PoposPathInputChanged)
                        .width(Length::Fixed(420.0)),
                ),
        )
        .add(
            settings::item::builder("umbrelos-scripts (Homelab)")
                .description("Diretório contendo setup_umbrelos.sh, scripts/utils/ e config.env.")
                .control(
                    widget::text_input("Caminho do repositório Homelab", &app.homelab_path_input)
                        .on_input(Message::HomelabPathInputChanged)
                        .width(Length::Fixed(420.0)),
                ),
        )
        .add(
            settings::item::builder("Persistir Caminhos")
                .description("Salva em ~/.config/workstation-hub/paths.json com permissão 0600.")
                .control(
                    widget::button::suggested("Salvar Caminhos")
                        .on_press(Message::SaveRepoPaths),
                ),
        );

    let env_toolbar = widget::row::with_capacity(5)
        .spacing(space_s)
        .align_y(Alignment::Center)
        .push(target_btn(EnvTarget::Popos, app.env_target))
        .push(target_btn(EnvTarget::Homelab, app.env_target))
        .push(
            widget::text_input("Filtrar variável...", &app.env_search)
                .on_input(Message::EnvSearchChanged)
                .width(Length::Fill),
        )
        .push(widget::button::standard("Recarregar").on_press(Message::ReloadCurrentEnv))
        .push(widget::button::suggested("Salvar (chmod 0600)").on_press(Message::SaveCurrentEnv));

    let mut env_sec = settings::section().title(format!("Editor {}", app.env_target.label()));
    if let Some(msg) = &app.env_status_msg {
        env_sec = env_sec.add(
            settings::item::builder("Status do Arquivo")
                .control(widget::text::caption(msg.clone())),
        );
    }

    let query = app.env_search.trim().to_ascii_lowercase();
    for (idx, item) in app.env_entries.iter().enumerate() {
        if !query.is_empty()
            && !item.key.to_ascii_lowercase().contains(&query)
            && !item.section.to_ascii_lowercase().contains(&query)
            && !item.comment.to_ascii_lowercase().contains(&query)
        {
            continue;
        }

        let mut input = widget::text_input("Valor...", &item.value)
            .on_input(move |v| Message::EnvValueChanged(idx, v))
            .width(Length::Fixed(320.0));
        if item.is_secret && !item.revealed {
            input = input.password();
        }

        let mut ctrl = widget::row::with_capacity(2)
            .spacing(space_s)
            .align_y(Alignment::Center)
            .push(input);

        if item.is_secret {
            ctrl = ctrl.push(
                widget::button::standard(if item.revealed { "Ocultar" } else { "Revelar" })
                    .on_press(Message::ToggleEnvReveal(idx)),
            );
        }

        let desc = if item.comment.is_empty() {
            item.section.clone()
        } else {
            format!("{} · {}", item.section, item.comment)
        };

        env_sec = env_sec.add(
            settings::item::builder(&item.key)
                .description(desc)
                .control(ctrl),
        );
    }

    let col = widget::column::with_capacity(4)
        .spacing(space_m)
        .push(header)
        .push(paths_section)
        .push(env_toolbar)
        .push(env_sec);

    widget::scrollable(col).height(Length::Fill).into()
}

fn target_btn(target: EnvTarget, active: EnvTarget) -> Element<'static, Message> {
    if target == active {
        widget::button::suggested(target.label())
            .on_press(Message::SwitchEnvTarget(target))
            .into()
    } else {
        widget::button::standard(target.label())
            .on_press(Message::SwitchEnvTarget(target))
            .into()
    }
}
