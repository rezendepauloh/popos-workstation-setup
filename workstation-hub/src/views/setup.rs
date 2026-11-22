use crate::app::{AppModel, Message, SetupFilter};
use crate::models::catalog::{SETUP_MODULES, SetupCategory};
use cosmic::iced::{Alignment, Length};
use cosmic::prelude::*;
use cosmic::widget::{self, settings};

pub fn view(app: &AppModel) -> Element<'_, Message> {
    let space_s = cosmic::theme::spacing().space_s;
    let space_m = cosmic::theme::spacing().space_m;

    let completed_count = SETUP_MODULES
        .iter()
        .filter(|m| app.snapshot.completed_flags.contains(m.flag_name))
        .count();

    let header = widget::row::with_capacity(2)
        .spacing(space_s)
        .align_y(Alignment::Center)
        .push(
            widget::text::title2(format!(
                "Pós-Formatação Pop!_OS ({completed_count}/{} concluídos)",
                SETUP_MODULES.len()
            ))
            .width(Length::Fill),
        )
        .push(
            widget::toggler(app.force_mode)
                .label("Forçar (--force)".to_string())
                .on_toggle(Message::ToggleForceMode),
        );

    let search_bar = widget::text_input("Buscar módulo por número, título ou descrição...", &app.setup_search)
        .on_input(Message::SetupSearchChanged)
        .width(Length::Fill);

    let filter_row = widget::row::with_capacity(8)
        .spacing(space_s)
        .align_y(Alignment::Center)
        .push(filter_btn("Todos", SetupFilter::All, app.setup_filter))
        .push(filter_btn("Pendentes", SetupFilter::Pending, app.setup_filter))
        .push(filter_btn("Concluídos", SetupFilter::Completed, app.setup_filter))
        .push(widget::button::standard("Marcar Pendentes").on_press(Message::SelectPendingModules))
        .push(widget::button::standard("Limpar Seleção").on_press(Message::ClearModuleSelection));

    let presets_row = widget::row::with_capacity(6)
        .spacing(space_s)
        .push(preset_btn("Sistema", SetupCategory::SystemKernel))
        .push(preset_btn("Dev & IDEs", SetupCategory::DevTools))
        .push(preset_btn("Produtividade", SetupCategory::Productivity))
        .push(preset_btn("COSMIC & Periféricos", SetupCategory::CosmicDesktop))
        .push(preset_btn("Trabalho Remoto", SetupCategory::RemoteWork))
        .push(preset_btn("Jogos & Mídia", SetupCategory::GamingMedia));

    let selected_count = app.selected_modules.len();
    let batch_row = widget::row::with_capacity(4)
        .spacing(space_s)
        .align_y(Alignment::Center)
        .push(
            widget::button::suggested(format!("Executar Selecionados ({selected_count})"))
                .on_press(Message::RunSelectedModules),
        )
        .push(
            widget::button::standard("Rodar setup_popos.sh Completo")
                .on_press(Message::RunFullSetup),
        )
        .push(
            widget::button::destructive("Limpar Todos Checkpoints")
                .on_press(Message::ResetAllFlags),
        );

    let query = app.setup_search.trim().to_ascii_lowercase();
    let mut modules_section = settings::section().title("Módulos 01 a 28 (scripts/)");
    let mut visible_count = 0usize;

    for m in SETUP_MODULES {
        let is_done = app.snapshot.completed_flags.contains(m.flag_name);
        match app.setup_filter {
            SetupFilter::Pending if is_done => continue,
            SetupFilter::Completed if !is_done => continue,
            _ => {}
        }
        if !query.is_empty()
            && !m.id.contains(&query)
            && !m.title.to_ascii_lowercase().contains(&query)
            && !m.description.to_ascii_lowercase().contains(&query)
            && !m.filename.to_ascii_lowercase().contains(&query)
        {
            continue;
        }
        visible_count += 1;

        let checked = app.selected_modules.contains(m.id);
        let status_tag = if is_done { "✔ Concluído" } else { "○ Pendente" };
        let title_str = format!("{} · {}  [{}]", m.id, m.title, status_tag);
        let desc_str = format!("{} · {}", m.category.label(), m.description);

        let mut controls = widget::row::with_capacity(3)
            .spacing(space_s)
            .align_y(Alignment::Center)
            .push(
                widget::checkbox(checked)
                    .on_toggle(|val| Message::ToggleSetupModule(m.id.to_string(), val)),
            );

        if is_done {
            controls = controls.push(
                widget::button::standard("Resetar Flag")
                    .on_press(Message::ResetModuleFlag(m.flag_name.to_string())),
            );
        }

        controls = controls.push(
            widget::button::suggested("Executar")
                .on_press(Message::RunSingleModule(m.id.to_string())),
        );

        modules_section = modules_section.add(
            settings::item::builder(title_str)
                .description(desc_str)
                .control(controls),
        );
    }

    if visible_count == 0 {
        modules_section = modules_section.add(
            settings::item::builder("Nenhum módulo encontrado")
                .description("Ajuste o filtro ou termo de busca acima.")
                .control(widget::text::caption("0 itens")),
        );
    }

    let content = widget::column::with_capacity(6)
        .spacing(space_m)
        .push(header)
        .push(search_bar)
        .push(filter_row)
        .push(presets_row)
        .push(batch_row)
        .push(widget::scrollable(modules_section).height(Length::Fill));

    content.into()
}

fn filter_btn(label: &'static str, target: SetupFilter, active: SetupFilter) -> Element<'static, Message> {
    if target == active {
        widget::button::suggested(label)
            .on_press(Message::SetupFilterChanged(target))
            .into()
    } else {
        widget::button::standard(label)
            .on_press(Message::SetupFilterChanged(target))
            .into()
    }
}

fn preset_btn(label: &'static str, cat: SetupCategory) -> Element<'static, Message> {
    widget::button::standard(label)
        .on_press(Message::SelectCategoryPreset(cat))
        .into()
}
