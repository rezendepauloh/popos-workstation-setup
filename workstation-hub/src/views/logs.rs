use crate::app::{AppModel, ContextPage, Message, Page};
use crate::views::ui;
use crate::models::log_entry::{AnsiColor, LogLine, RunStatus};
use cosmic::app::context_drawer;
use cosmic::iced::{Alignment, Color, Length};
use cosmic::prelude::*;
use cosmic::widget::{self, settings};

pub fn view(app: &AppModel) -> Element<'_, Message> {
    let space_s = cosmic::theme::spacing().space_s;
    let space_m = cosmic::theme::spacing().space_m;

    let (exec_badge_text, exec_badge_color) = match &app.run_status {
        RunStatus::Idle => (
            "○ Ocioso (nenhuma tarefa em execução)".to_string(),
            Color::from_rgb(0.62, 0.65, 0.72),
        ),
        RunStatus::Running { label } => (
            format!("⏳ RODANDO AGORA: {label}"),
            Color::from_rgb(0.95, 0.80, 0.35),
        ),
        RunStatus::Succeeded { label, duration_ms } => (
            format!("✔ FINALIZADO (0): {label} ({:.1}s)", *duration_ms as f64 / 1000.0),
            Color::from_rgb(0.45, 0.88, 0.55),
        ),
        RunStatus::Failed {
            label,
            exit_code,
            duration_ms,
        } => (
            format!(
                "✖ FINALIZADO (código {exit_code}): {label} ({:.1}s)",
                *duration_ms as f64 / 1000.0
            ),
            Color::from_rgb(0.95, 0.45, 0.45),
        ),
    };

    let status_banner = widget::container(
        widget::text::body(exec_badge_text).class(cosmic::theme::Text::Color(exec_badge_color)),
    )
    .padding([6, 10])
    .width(Length::Fill);

    let hub_logs_dir = dirs::state_dir()
        .or_else(dirs::data_local_dir)
        .unwrap_or_else(|| app.paths.popos_repo.join("Logs"))
        .join("workstation-hub")
        .join("logs");

    let mut toolbar_btns = vec![
        ui::btn_standard("Logs Remotos Homelab", Message::FetchRemoteHomelabLogs).into(),
        ui::btn_standard("Copiar Saída", Message::CopyConsoleLogs).into(),
        ui::btn_standard("Limpar Console", Message::ClearConsoleLogs).into(),
        ui::btn_standard("Abrir Logs Hub", Message::OpenLocalFolder(hub_logs_dir)).into(),
        ui::btn_standard(
            "Abrir Pasta Logs/",
            Message::OpenLocalFolder(app.paths.popos_repo.join("Logs")),
        )
        .into(),
    ];

    if app.process_handle.is_some() {
        toolbar_btns.push(ui::btn_destructive("Encerrar Processo", Message::StopRunningProcess).into());
    }

    let toolbar = widget::column::with_capacity(2)
        .spacing(space_s)
        .push(widget::text::title2("Console em Tempo Real & Histórico de Logs"))
        .push(ui::wrap_row(toolbar_btns));

    let mut console_col = widget::column::with_capacity(app.log_lines.len().min(600))
        .spacing(2)
        .width(Length::Fill);

    let start_idx = app.log_lines.len().saturating_sub(600);
    for line in &app.log_lines[start_idx..] {
        console_col = console_col.push(render_log_line(line));
    }

    let console_box = widget::container(
        widget::scrollable(console_col)
            .height(Length::Fixed(app.console_height))
            .width(Length::Fill),
    )
    .padding(10)
    .width(Length::Fill);

    let console_resize = widget::row::with_capacity(2)
        .spacing(space_s)
        .align_y(Alignment::Center)
        .push(widget::text::caption(format!(
            "Altura Console: {}px",
            app.console_height as u32
        )))
        .push(
            widget::slider(180.0..=720.0, app.console_height, Message::ConsoleHeightChanged)
                .width(Length::Fixed(180.0)),
        );

    let stdin_bar = widget::row::with_capacity(2)
        .spacing(space_s)
        .align_y(Alignment::Center)
        .push(
            widget::text_input(
                "Entrada interativa PTY (ex: S, n, número da opção, OTP)...",
                &app.pty_input,
            )
            .on_input(Message::PtyInputChanged)
            .on_submit(|_| Message::SendPtyInput)
            .width(Length::Fill),
        )
        .push(widget::button::suggested("Enviar Entrada").on_press(Message::SendPtyInput));

    const PAGE_SIZE: usize = 6;
    let total_execs = app.snapshot.hub_executions.len();
    let total_pages = total_execs.max(1).div_ceil(PAGE_SIZE);
    let current_page = app.log_exec_page.min(total_pages.saturating_sub(1));
    let start_exec = current_page * PAGE_SIZE;
    let end_exec = (start_exec + PAGE_SIZE).min(total_execs);

    let mut execs_sec = settings::section().title(format!(
        "Execuções do Hub (workstation-hub.log · Página {}/{total_pages})",
        current_page + 1
    ));

    if total_execs == 0 {
        execs_sec = execs_sec.add(
            settings::item::builder("Nenhuma execução registrada ainda")
                .control(widget::text::caption("workstation-hub.log")),
        );
    } else {
        for idx in start_exec..end_exec {
            let rec = &app.snapshot.hub_executions[idx];
            execs_sec = execs_sec.add(
                settings::item::builder(&rec.label)
                    .description(&rec.timestamp)
                    .control(
                        widget::row::with_capacity(2)
                            .spacing(6)
                            .push(
                                widget::button::standard("Visualizar")
                                    .on_press(Message::OpenHubExecution(idx)),
                            )
                            .push(
                                widget::button::destructive("Apagar")
                                    .on_press(Message::DeleteHubExecution(idx)),
                            ),
                    ),
            );
        }
        let mut footer_row = widget::row::with_capacity(4)
            .spacing(space_s)
            .align_y(Alignment::Center);
        if total_pages > 1 {
            footer_row = footer_row
                .push(widget::button::standard("◀ Anterior").on_press(Message::LogExecPagePrev))
                .push(widget::text::caption(format!(
                    "Página {} de {total_pages} ({total_execs} execuções)",
                    current_page + 1
                )))
                .push(widget::button::standard("Próxima ▶").on_press(Message::LogExecPageNext));
        } else {
            footer_row = footer_row.push(widget::text::caption(format!(
                "{total_execs} execuções registradas"
            )));
        }
        footer_row = footer_row.push(
            widget::button::destructive("Apagar Tudo")
                .on_press(Message::ClearAllHubExecutions),
        );
        execs_sec = execs_sec.add(widget::container(footer_row).padding(4));
    }

    let mut logs_sec = settings::section().title("Arquivos de Log Salvos (Pop!_OS, Rust Hub & Homelab)");
    if app.snapshot.log_files.is_empty() {
        logs_sec = logs_sec.add(
            settings::item::builder("Nenhum arquivo .log encontrado")
                .control(widget::text::caption("Logs/")),
        );
    } else {
        for path in app.snapshot.log_files.iter().take(40) {
            let name = path
                .file_name()
                .and_then(|s| s.to_str())
                .unwrap_or("log");
            logs_sec = logs_sec.add(
                settings::item::builder(name)
                    .description(path.to_string_lossy().to_string())
                    .control(
                        widget::button::standard("Visualizar")
                            .on_press(Message::OpenLogFile(path.clone())),
                    ),
            );
        }
    }

    let mut root_col = widget::column::with_capacity(8)
        .spacing(space_m)
        .push(toolbar)
        .push(status_banner)
        .push(console_box)
        .push(console_resize)
        .push(stdin_bar)
        .push(execs_sec)
        .push(logs_sec);

    if let Some((path, content)) = &app.selected_log_preview {
        let preview_title = format!(
            "Prévia: {}",
            path.file_name().and_then(|s| s.to_str()).unwrap_or("")
        );
        let filter_q = app.log_preview_filter.trim().to_ascii_lowercase();
        let filtered_content = if filter_q.is_empty() {
            content.clone()
        } else {
            content
                .lines()
                .filter(|l| l.to_ascii_lowercase().contains(&filter_q))
                .collect::<Vec<_>>()
                .join("\n")
        };

        let preview_bar = widget::row::with_capacity(4)
            .spacing(space_s)
            .align_y(Alignment::Center)
            .push(
                widget::text_input("Filtrar prévia por execução ou texto...", &app.log_preview_filter)
                    .on_input(Message::LogPreviewFilterChanged)
                    .width(Length::Fill),
            )
            .push(widget::text::caption(format!(
                "{}px",
                app.log_preview_height as u32
            )))
            .push(
                widget::slider(
                    160.0..=720.0,
                    app.log_preview_height,
                    Message::LogPreviewHeightChanged,
                )
                .width(Length::Fixed(140.0)),
            )
            .push(widget::button::destructive("Fechar Prévia").on_press(Message::CloseLogPreview));

        let mut preview_col = widget::column::with_capacity(400)
            .spacing(2)
            .width(Length::Fill);
        for line in filtered_content.lines().take(500) {
            let styled = colorize_log_preview_line(line);
            preview_col = preview_col.push(render_owned_log_line(styled));
        }

        let preview_sec = settings::section()
            .title(preview_title)
            .add(widget::container(preview_bar).padding(4))
            .add(
                widget::container(
                    widget::scrollable(preview_col)
                        .height(Length::Fixed(app.log_preview_height))
                        .width(Length::Fill),
                )
                .padding(8),
            );
        root_col = root_col.push(preview_sec);
    }

    ui::page_scroll(root_col)
}

pub fn console_drawer(app: &AppModel) -> context_drawer::ContextDrawer<'_, Message> {
    let space_s = cosmic::theme::spacing().space_s;

    let (badge_text, badge_color, progress_val) = match &app.run_status {
        RunStatus::Idle => (
            "○ Ocioso (pronto)".to_string(),
            Color::from_rgb(0.62, 0.65, 0.72),
            0.0,
        ),
        RunStatus::Running { label } => (
            format!("⏳ {label}"),
            Color::from_rgb(0.95, 0.80, 0.35),
            app.console_progress.clamp(0.08, 0.95),
        ),
        RunStatus::Succeeded { label, duration_ms } => (
            format!("✔ {label} ({:.1}s)", *duration_ms as f64 / 1000.0),
            Color::from_rgb(0.45, 0.88, 0.55),
            1.0,
        ),
        RunStatus::Failed {
            label,
            exit_code,
            duration_ms,
        } => (
            format!(
                "✖ Falhou ({exit_code}): {label} ({:.1}s)",
                *duration_ms as f64 / 1000.0
            ),
            Color::from_rgb(0.95, 0.45, 0.45),
            1.0,
        ),
    };

    let mut status_row = widget::row::with_capacity(2)
        .spacing(space_s)
        .align_y(Alignment::Center)
        .push(
            widget::text::body(badge_text)
                .class(cosmic::theme::Text::Color(badge_color))
                .width(Length::Fill),
        );

    if app.process_handle.is_some() {
        status_row = status_row.push(
            widget::button::destructive("Parar").on_press(Message::StopRunningProcess),
        );
    }

    let header = widget::column::with_capacity(2)
        .spacing(6)
        .padding([4, 0])
        .push(status_row)
        .push(cosmic::iced::widget::progress_bar(0.0..=1.0, progress_val).girth(Length::Fixed(6.0)));

    let actions = ui::wrap_row(vec![
        ui::btn_standard("Copiar", Message::CopyConsoleLogs).into(),
        ui::btn_standard("Limpar", Message::ClearConsoleLogs).into(),
        ui::btn_standard("Aba Logs", Message::NavigateTo(Page::Logs)).into(),
    ]);

    let mut console_col = widget::column::with_capacity(app.log_lines.len().min(400).max(1))
        .spacing(2)
        .width(Length::Fill);

    if app.log_lines.is_empty() {
        console_col = console_col.push(widget::text::caption(
            "A saída dos comandos executados aparecerá aqui em tempo real.",
        ));
    } else {
        let start_idx = app.log_lines.len().saturating_sub(400);
        for line in &app.log_lines[start_idx..] {
            console_col = console_col.push(render_log_line(line));
        }
    }

    let footer = widget::row::with_capacity(2)
        .spacing(space_s)
        .align_y(Alignment::Center)
        .push(
            widget::text_input("Entrada PTY (S/n, OTP...)", &app.pty_input)
                .on_input(Message::PtyInputChanged)
                .on_submit(|_| Message::SendPtyInput)
                .width(Length::Fill),
        )
        .push(widget::button::suggested("Enviar").on_press(Message::SendPtyInput));

    let console_scroll = widget::scrollable(
        widget::container(console_col).padding([0, 14, 14, 0]),
    )
        .height(Length::Fixed(520.0))
        .width(Length::Fill)
        .direction(cosmic::iced::widget::scrollable::Direction::Both {
            vertical: Default::default(),
            horizontal: Default::default(),
        });

    context_drawer::context_drawer(
        console_scroll,
        Message::ToggleContextPage(ContextPage::Console),
    )
        .title("Console em Tempo Real")
        .actions(actions)
        .header(header)
        .footer(footer)
}

fn colorize_log_preview_line(line: &str) -> LogLine {
    if line.contains('\x1b') {
        return crate::services::ansi_parser::parse_ansi_line(line);
    }
    let trimmed = line.trim();
    let color = if trimmed.contains("[✔]")
        || trimmed.contains("[OK]")
        || trimmed.contains("[SUCCESS]")
        || trimmed.contains("✔ PASS")
        || trimmed.starts_with('✔')
    {
        AnsiColor::Green
    } else if trimmed.contains("[!]")
        || trimmed.contains("[ERROR]")
        || trimmed.contains("[ERRO]")
        || trimmed.contains("✖ FAIL")
        || trimmed.starts_with('✖')
        || trimmed.contains("Falhou")
    {
        AnsiColor::Red
    } else if trimmed.contains("[WARN]")
        || trimmed.contains("[AVISO]")
        || trimmed.contains('⚠')
        || trimmed.contains("⚡ SKIP")
    {
        AnsiColor::Yellow
    } else if trimmed.starts_with("▶ ")
        || trimmed.contains("[INFO]")
        || trimmed.starts_with("===")
        || trimmed.starts_with("i ")
    {
        AnsiColor::Cyan
    } else if trimmed.starts_with("---") || trimmed.contains("backup_") {
        AnsiColor::Blue
    } else {
        AnsiColor::Default
    };
    LogLine::plain(line, color, false)
}

fn render_owned_log_line(line: LogLine) -> Element<'static, Message> {
    if line.segments.len() == 1 {
        let seg = line.segments.into_iter().next().unwrap();
        let mut t = widget::text::monotext(seg.text).size(13.0);
        if let Some(c) = map_ansi_color(seg.color) {
            t = t.class(cosmic::theme::Text::Color(c));
        }
        return t.into();
    }

    let mut r = widget::row::with_capacity(line.segments.len()).spacing(0);
    for seg in line.segments {
        let mut t = widget::text::monotext(seg.text).size(13.0);
        if let Some(c) = map_ansi_color(seg.color) {
            t = t.class(cosmic::theme::Text::Color(c));
        }
        r = r.push(t);
    }
    r.into()
}

fn render_log_line(line: &LogLine) -> Element<'_, Message> {
    if line.segments.len() == 1 {
        let seg = &line.segments[0];
        let mut t = widget::text::monotext(&seg.text).size(13.0);
        if let Some(c) = map_ansi_color(seg.color) {
            t = t.class(cosmic::theme::Text::Color(c));
        }
        return t.into();
    }

    let mut r = widget::row::with_capacity(line.segments.len()).spacing(0);
    for seg in &line.segments {
        let mut t = widget::text::monotext(&seg.text).size(13.0);
        if let Some(c) = map_ansi_color(seg.color) {
            t = t.class(cosmic::theme::Text::Color(c));
        }
        r = r.push(t);
    }
    r.into()
}

fn map_ansi_color(color: AnsiColor) -> Option<Color> {
    match color {
        AnsiColor::Default => None,
        AnsiColor::Red => Some(Color::from_rgb(0.95, 0.45, 0.45)),
        AnsiColor::Green => Some(Color::from_rgb(0.45, 0.88, 0.55)),
        AnsiColor::Yellow => Some(Color::from_rgb(0.95, 0.80, 0.35)),
        AnsiColor::Blue => Some(Color::from_rgb(0.48, 0.70, 0.98)),
        AnsiColor::Magenta => Some(Color::from_rgb(0.85, 0.58, 0.95)),
        AnsiColor::Cyan => Some(Color::from_rgb(0.35, 0.85, 0.92)),
        AnsiColor::Muted => Some(Color::from_rgb(0.62, 0.65, 0.72)),
    }
}
