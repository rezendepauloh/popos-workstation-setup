use crate::app::{AppModel, Message, SetupFilter};
use crate::models::catalog::{SETUP_MODULES, SetupCategory};
use crate::views::ui;
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

    let filter_row = ui::wrap_row(vec![
        filter_btn("Todos", SetupFilter::All, app.setup_filter),
        filter_btn("Pendentes", SetupFilter::Pending, app.setup_filter),
        filter_btn("Concluídos", SetupFilter::Completed, app.setup_filter),
        ui::btn_standard("Marcar Pendentes", Message::SelectPendingModules).into(),
        ui::btn_standard("Limpar Seleção", Message::ClearModuleSelection).into(),
    ]);

    let presets_row = ui::wrap_row(vec![
        preset_btn("Sistema", SetupCategory::SystemKernel),
        preset_btn("Dev & IDEs", SetupCategory::DevTools),
        preset_btn("Produtividade", SetupCategory::Productivity),
        preset_btn("COSMIC & Periféricos", SetupCategory::CosmicDesktop),
        preset_btn("Trabalho Remoto", SetupCategory::RemoteWork),
        preset_btn("Jogos & Mídia", SetupCategory::GamingMedia),
    ]);

    let selected_count = app.selected_modules.len();
    let batch_row = ui::wrap_row(vec![
        ui::btn_suggested(
            format!("Executar Selecionados ({selected_count})"),
            Message::RunSelectedModules,
        )
        .into(),
        ui::btn_standard("Rodar setup_popos.sh Completo", Message::RunFullSetup).into(),
        ui::btn_destructive("Limpar Todos Checkpoints", Message::ResetAllFlags).into(),
    ]);

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
        .push(ui::page_scroll(modules_section));

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
