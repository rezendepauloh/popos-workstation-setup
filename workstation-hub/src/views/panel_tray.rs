use crate::app::{AppModel, Message};
use crate::models::status::{PanelAppletInfo, PanelSegment};
use cosmic::iced::{Alignment, Length};
use cosmic::prelude::*;
use cosmic::widget::{self, icon, settings};
use std::path::Path;

fn render_real_icon(icon_spec: &str, size: u16) -> Element<'static, Message> {
    let trimmed = icon_spec.trim();
    if trimmed.is_empty() {
        return icon::from_name("application-x-executable-symbolic")
            .size(size)
            .into();
    }
    if Path::new(trimmed).is_absolute() && Path::new(trimmed).exists() {
        icon::icon(icon::from_path(std::path::PathBuf::from(trimmed)))
            .size(size)
            .into()
    } else {
        icon::from_name(trimmed.to_string()).size(size).into()
    }
}

fn applet_row(applet: &PanelAppletInfo) -> Element<'static, Message> {
    let visible = applet.segment != PanelSegment::Hidden;
    let id_for_toggle = applet.id.clone();

    let mut actions = widget::row::with_capacity(4)
        .spacing(6)
        .align_y(Alignment::Center);

    if visible {
        if applet.segment != PanelSegment::Start {
            actions = actions.push(
                widget::button::standard("Início")
                    .on_press(Message::SetPanelAppletSegment(
                        applet.id.clone(),
                        PanelSegment::Start,
                    )),
            );
        }
        if applet.segment != PanelSegment::Center {
            actions = actions.push(
                widget::button::standard("Centro")
                    .on_press(Message::SetPanelAppletSegment(
                        applet.id.clone(),
                        PanelSegment::Center,
                    )),
            );
        }
        if applet.segment != PanelSegment::End {
            actions = actions.push(
                widget::button::standard("Fim")
                    .on_press(Message::SetPanelAppletSegment(
                        applet.id.clone(),
                        PanelSegment::End,
                    )),
            );
        }
    }

    actions = actions.push(widget::toggler(visible).on_toggle(move |on| {
        let target = if on {
            PanelSegment::End
        } else {
            PanelSegment::Hidden
        };
        Message::SetPanelAppletSegment(id_for_toggle.clone(), target)
    }));

    let desc = if applet.comment.is_empty() {
        applet.id.clone()
    } else {
        applet.comment.clone()
    };

    settings::item_row(vec![
        render_real_icon(&applet.icon, 28),
        widget::column::with_capacity(2)
            .spacing(2)
            .width(Length::Fill)
            .push(widget::text::body(applet.name.clone()))
            .push(widget::text::caption(desc))
            .into(),
        actions.into(),
    ])
    .into()
}

pub fn view(app: &AppModel) -> Element<'_, Message> {
    let info = &app.snapshot.panel_tray_info;

    let header = widget::row::with_capacity(3)
        .spacing(12)
        .align_y(Alignment::Center)
        .push(widget::text::title2("Painel Superior & Bandeja (Tray)"))
        .push(widget::space::horizontal())
        .push(widget::button::standard("Atualizar Ícones").on_press(Message::RefreshSnapshot));

    // 1. Visual strip of active Tray Icons (with real colorful icons)
    let mut tray_strip = widget::row::with_capacity(12)
        .spacing(10)
        .padding([10, 14])
        .align_y(Alignment::Center);

    if info.tray_items.is_empty() {
        tray_strip = tray_strip.push(widget::text::caption(
            "Nenhum ícone ativo encontrado na bandeja StatusNotifierWatcher.",
        ));
    } else {
        for item in &info.tray_items {
            let tile = widget::column::with_capacity(2)
                .spacing(4)
                .align_x(Alignment::Center)
                .push(render_real_icon(&item.icon, 30))
                .push(widget::text::caption(item.title.clone()));

            tray_strip = tray_strip.push(
                widget::button::custom(tile)
                    .padding([8, 10])
                    .on_press(Message::ActivateTrayItem(
                        item.bus_name.clone(),
                        item.object_path.clone(),
                    )),
            );
        }
    }

    let strip_sec = settings::section()
        .title("Prévia Visual da Bandeja Ativa (Clique no ícone para abrir/ativar)")
        .add(widget::scrollable(tray_strip).direction(
            cosmic::iced::widget::scrollable::Direction::Horizontal(Default::default()),
        ));

    // 2. Managed Tray Indicators (Exibir / Ocultar ao vivo)
    let mut managed_sec =
        settings::section().title("Indicadores de Bandeja (Exibir / Ocultar)");
    for ind in &info.managed_indicators {
        let unit_toggle = ind.unit.clone();
        let unit_restart = ind.unit.clone();
        managed_sec = managed_sec.add(settings::item_row(vec![
            render_real_icon(&ind.icon, 28),
            widget::column::with_capacity(2)
                .spacing(2)
                .width(Length::Fill)
                .push(widget::text::body(ind.label.clone()))
                .push(widget::text::caption(format!(
                    "{} — {}",
                    ind.unit,
                    if ind.active { "Visível na bandeja" } else { "Oculto (parado)" }
                )))
                .into(),
            widget::row::with_capacity(2)
                .spacing(8)
                .align_y(Alignment::Center)
                .push(
                    widget::button::standard("Reiniciar")
                        .on_press(Message::RestartTrayIndicator(unit_restart)),
                )
                .push(widget::toggler(ind.active).on_toggle(move |show| {
                    Message::ToggleTrayIndicator(unit_toggle.clone(), show)
                }))
                .into(),
        ]));
    }

    // 3. All active D-Bus StatusNotifierItem apps
    let mut sni_sec = settings::section().title("Apps Ativos na Bandeja (StatusNotifierItem)");
    for item in &info.tray_items {
        let mut btns = widget::row::with_capacity(2)
            .spacing(6)
            .align_y(Alignment::Center)
            .push(
                widget::button::standard("Abrir / Ativar").on_press(Message::ActivateTrayItem(
                    item.bus_name.clone(),
                    item.object_path.clone(),
                )),
            );
        if let Some(unit) = &item.systemd_unit {
            btns = btns.push(
                widget::button::destructive("Ocultar").on_press(Message::ToggleTrayIndicator(
                    unit.clone(),
                    false,
                )),
            );
        }

        sni_sec = sni_sec.add(settings::item_row(vec![
            render_real_icon(&item.icon, 26),
            widget::column::with_capacity(2)
                .spacing(2)
                .width(Length::Fill)
                .push(widget::text::body(item.title.clone()))
                .push(widget::text::caption(format!(
                    "ID: {} | Status: {} | D-Bus: {}",
                    item.id, item.status, item.bus_name
                )))
                .into(),
            btns.into(),
        ]));
    }

    // 4. COSMIC Panel Applets grouped just like COSMIC Settings -> Painel -> Miniaplicativos
    let mut start_sec = settings::section().title("Painel COSMIC — Segmento Inicial");
    let mut center_sec = settings::section().title("Painel COSMIC — Segmento Central");
    let mut end_sec = settings::section().title("Painel COSMIC — Segmento Final");
    let mut hidden_sec = settings::section().title("Miniaplicativos Ocultos / Disponíveis");

    let mut has_start = false;
    let mut has_center = false;
    let mut has_end = false;
    let mut has_hidden = false;

    for applet in &info.applets {
        match applet.segment {
            PanelSegment::Start => {
                start_sec = start_sec.add(applet_row(applet));
                has_start = true;
            }
            PanelSegment::Center => {
                center_sec = center_sec.add(applet_row(applet));
                has_center = true;
            }
            PanelSegment::End => {
                end_sec = end_sec.add(applet_row(applet));
                has_end = true;
            }
            PanelSegment::Hidden => {
                hidden_sec = hidden_sec.add(applet_row(applet));
                has_hidden = true;
            }
        }
    }

    if !has_start {
        start_sec = start_sec.add(settings::item(
            "Vazio",
            widget::text::caption("Nenhum miniaplicativo neste segmento."),
        ));
    }
    if !has_center {
        center_sec = center_sec.add(settings::item(
            "Vazio",
            widget::text::caption("Nenhum miniaplicativo neste segmento."),
        ));
    }
    if !has_end {
        end_sec = end_sec.add(settings::item(
            "Vazio",
            widget::text::caption("Nenhum miniaplicativo neste segmento."),
        ));
    }
    if !has_hidden {
        hidden_sec = hidden_sec.add(settings::item(
            "Todos ativos",
            widget::text::caption("Todos os miniaplicativos detectados estão visíveis no painel."),
        ));
    }

    let content = widget::column::with_capacity(8)
        .spacing(16)
        .push(header)
        .push(strip_sec)
        .push(managed_sec)
        .push(sni_sec)
        .push(start_sec)
        .push(center_sec)
        .push(end_sec)
        .push(hidden_sec);

    widget::scrollable(content).into()
}
