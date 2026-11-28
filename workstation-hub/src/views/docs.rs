use crate::app::{AppModel, Message};
use crate::models::doc_entry::{
    AlertKind, DocEntryItem, DocSourceKind, MarkdownBlock, MarkdownInlineKind, MarkdownInlineSpan,
    MarkdownLinkResolution,
};
use crate::services::doc_service::{
    CATEGORY_ALL, SOURCE_ALL, filter_documents, parse_markdown, resolve_markdown_link,
};
use crate::views::ui;
use cosmic::iced::font::{Font, Style as FontStyle, Weight};
use cosmic::iced::widget::{rich_text, span};
use cosmic::iced::{Alignment, Background, Border, Color, Length};
use cosmic::prelude::*;
use cosmic::widget;
use std::path::Path;

fn rgb(c: [f32; 3]) -> Color {
    Color::from_rgb(c[0], c[1], c[2])
}

fn pill_badge<'a>(label: String, bg: [f32; 3], fg: [f32; 3]) -> Element<'a, Message> {
    widget::container(
        widget::text::caption(label)
            .size(10.5)
            .font(Font {
                weight: Weight::Bold,
                ..Font::DEFAULT
            })
            .class(cosmic::theme::Text::Color(rgb(fg))),
    )
    .padding([2, 6])
    .class(cosmic::theme::Container::custom(move |_| {
        cosmic::iced::widget::container::Style {
            background: Some(Background::Color(rgb(bg))),
            border: Border {
                color: Color::TRANSPARENT,
                width: 0.0,
                radius: 4.0.into(),
            },
            ..Default::default()
        }
    }))
    .into()
}

fn render_inlines<'a>(
    spans_in: &[MarkdownInlineSpan],
    font_size: f32,
    default_bold: bool,
) -> Element<'a, Message> {
    let base_font = if default_bold {
        Font {
            weight: Weight::Bold,
            ..Font::DEFAULT
        }
    } else {
        Font::DEFAULT
    };

    let mut out: Vec<cosmic::iced::widget::text::Span<'a, String, Font>> =
        Vec::with_capacity(spans_in.len().max(1));

    for sp in spans_in {
        match sp.kind {
            MarkdownInlineKind::Text => {
                out.push(span(sp.text.clone()).font(base_font));
            }
            MarkdownInlineKind::Bold => {
                out.push(span(sp.text.clone()).font(Font {
                    weight: Weight::Bold,
                    ..Font::DEFAULT
                }));
            }
            MarkdownInlineKind::Italic => {
                out.push(span(sp.text.clone()).font(Font {
                    style: FontStyle::Italic,
                    weight: if default_bold {
                        Weight::Bold
                    } else {
                        Weight::Normal
                    },
                    ..Font::DEFAULT
                }));
            }
            MarkdownInlineKind::Strikethrough => {
                out.push(
                    span(sp.text.clone())
                        .font(base_font)
                        .strikethrough(true)
                        .color(Color::from_rgb(0.58, 0.64, 0.72)),
                );
            }
            MarkdownInlineKind::Code => {
                out.push(
                    span(format!(" {} ", sp.text))
                        .font(Font::MONOSPACE)
                        .color(Color::from_rgb(0.65, 0.85, 0.95))
                        .background(Color::from_rgb(0.16, 0.19, 0.25)),
                );
            }
            MarkdownInlineKind::Kbd => {
                out.push(
                    span(format!(" {} ", sp.text))
                        .font(Font::MONOSPACE)
                        .color(Color::from_rgb(0.95, 0.82, 0.45))
                        .background(Color::from_rgb(0.18, 0.20, 0.26)),
                );
            }
            MarkdownInlineKind::Badge => {
                let pill_color = Color::from_rgb(0.45, 0.82, 0.98);
                let mut s = span(format!("[{}]", sp.text))
                    .color(pill_color)
                    .font(Font {
                        weight: Weight::Bold,
                        ..Font::DEFAULT
                    });
                if let Some(url) = &sp.target_url
                    && (url.starts_with("http://") || url.starts_with("https://"))
                {
                    s = s.link(url.clone());
                }
                out.push(s);
            }
            MarkdownInlineKind::Image => {
                let mut s =
                    span(format!("🖼️ [{}]", sp.text)).color(Color::from_rgb(0.65, 0.78, 0.95));
                if let Some(src) = &sp.target_url {
                    s = s.link(format!("doc://{src}"));
                }
                out.push(s);
            }
            MarkdownInlineKind::Link => {
                let link_color = Color::from_rgb(0.42, 0.76, 1.0);
                if let Some(url) = &sp.target_url {
                    if url.starts_with("http://") || url.starts_with("https://") {
                        out.push(
                            span(sp.text.clone())
                                .color(link_color)
                                .underline(true)
                                .link(url.clone()),
                        );
                    } else if url.starts_with('#') {
                        out.push(
                            span(sp.text.clone())
                                .color(link_color)
                                .underline(true)
                                .link(format!("anchor://{url}")),
                        );
                    } else {
                        out.push(
                            span(sp.text.clone())
                                .color(link_color)
                                .underline(true)
                                .link(format!("doc://{url}")),
                        );
                    }
                } else {
                    out.push(span(sp.text.clone()).color(link_color));
                }
            }
        }
    }

    rich_text(out)
        .on_link_click(Message::LaunchUrl)
        .size(font_size)
        .line_height(1.48)
        .into()
}

fn render_code_block<'a>(lang: &str, code: &str, font_size: f32) -> Element<'a, Message> {
    let lang_label = if lang.is_empty() {
        "código".to_string()
    } else {
        lang.to_string()
    };

    let header = widget::row::with_capacity(3)
        .spacing(8)
        .align_y(Alignment::Center)
        .push(
            widget::text::caption(lang_label.to_ascii_uppercase())
                .font(Font {
                    weight: Weight::Bold,
                    ..Font::DEFAULT
                })
                .class(cosmic::theme::Text::Color(Color::from_rgb(
                    0.58, 0.72, 0.92,
                ))),
        )
        .push(widget::space::horizontal())
        .push(
            widget::button::standard("📋 Copiar").on_press(Message::DocsCopyCodeBlock {
                lang: lang_label,
                code: code.to_string(),
            }),
        );

    let body = widget::text::monotext(code.to_string()).size((font_size - 1.5).max(10.5));

    let inner = widget::column::with_capacity(3)
        .spacing(6)
        .width(Length::Fill)
        .push(header)
        .push(widget::divider::horizontal::default())
        .push(body);

    widget::container(inner)
        .padding([8, 12])
        .width(Length::Fill)
        .class(cosmic::theme::Container::Card)
        .into()
}

fn render_table<'a>(
    headers: &[Vec<MarkdownInlineSpan>],
    rows: &[Vec<Vec<MarkdownInlineSpan>>],
    font_size: f32,
) -> Element<'a, Message> {
    let mut table_col = widget::column::with_capacity(rows.len() + 1)
        .spacing(0)
        .width(Length::Fill);

    table_col = table_col.push(render_table_row(headers, true, 0, font_size));
    for (idx, row) in rows.iter().enumerate() {
        table_col = table_col.push(render_table_row(row, false, idx + 1, font_size));
    }

    table_col.into()
}

fn render_table_row<'a>(
    cells: &[Vec<MarkdownInlineSpan>],
    is_header: bool,
    row_idx: usize,
    font_size: f32,
) -> Element<'a, Message> {
    let mut row = widget::row::with_capacity(cells.len().max(1))
        .spacing(8)
        .width(Length::Fill);

    for cell in cells {
        let cell_el = render_inlines(cell, font_size, is_header);
        row = row.push(
            widget::container(cell_el)
                .width(Length::FillPortion(1))
                .padding([6, 8]),
        );
    }

    let bg = if is_header {
        Color::from_rgb(0.14, 0.17, 0.24)
    } else if row_idx % 2 == 1 {
        Color::from_rgb(0.11, 0.12, 0.16)
    } else {
        Color::from_rgb(0.08, 0.09, 0.12)
    };

    widget::container(row)
        .width(Length::Fill)
        .class(cosmic::theme::Container::custom(move |_| {
            cosmic::iced::widget::container::Style {
                background: Some(Background::Color(bg)),
                border: Border {
                    color: Color::from_rgb(0.22, 0.25, 0.32),
                    width: 1.0,
                    radius: 0.0.into(),
                },
                ..Default::default()
            }
        }))
        .into()
}

fn render_blockquote<'a>(
    alert: Option<AlertKind>,
    lines: &[String],
    font_size: f32,
    source_root: Option<&Path>,
    current_doc: Option<&Path>,
) -> Element<'a, Message> {
    let inner_md = lines.join("\n");
    let inner_blocks = parse_markdown(&inner_md);

    let mut content_col = widget::column::with_capacity(inner_blocks.len() + 1)
        .spacing(6)
        .width(Length::Fill);

    let (accent, bg) = if let Some(kind) = alert {
        let accent_c = rgb(kind.accent_rgb());
        content_col = content_col.push(
            widget::text::heading(kind.label())
                .size(font_size)
                .class(cosmic::theme::Text::Color(accent_c)),
        );
        (accent_c, rgb(kind.bg_rgb()))
    } else {
        (
            Color::from_rgb(0.35, 0.65, 0.92),
            Color::from_rgb(0.10, 0.12, 0.17),
        )
    };

    for b in &inner_blocks {
        content_col = content_col.push(render_block(b, font_size, source_root, current_doc));
    }

    let bar = widget::container(widget::space::vertical().height(Length::Fixed(24.0)))
        .width(Length::Fixed(4.0))
        .class(cosmic::theme::Container::custom(move |_| {
            cosmic::iced::widget::container::Style {
                background: Some(Background::Color(accent)),
                border: Border {
                    color: Color::TRANSPARENT,
                    width: 0.0,
                    radius: 2.0.into(),
                },
                ..Default::default()
            }
        }));

    let row = widget::row::with_capacity(2)
        .spacing(12)
        .push(bar)
        .push(content_col);

    widget::container(row)
        .padding([10, 14])
        .width(Length::Fill)
        .class(cosmic::theme::Container::custom(move |_| {
            cosmic::iced::widget::container::Style {
                background: Some(Background::Color(bg)),
                border: Border {
                    color: accent.scale_alpha(0.35),
                    width: 1.0,
                    radius: 6.0.into(),
                },
                ..Default::default()
            }
        }))
        .into()
}

fn render_image_block<'a>(
    alt: &str,
    src: &str,
    source_root: Option<&Path>,
    current_doc: Option<&Path>,
) -> Element<'a, Message> {
    if let (Some(root), Some(cur)) = (source_root, current_doc)
        && let MarkdownLinkResolution::LocalImage(path) = resolve_markdown_link(root, cur, src)
    {
        let caption = if alt.is_empty() {
            path.file_name()
                .and_then(|s| s.to_str())
                .unwrap_or("Imagem")
                .to_string()
        } else {
            alt.to_string()
        };

        let header = widget::row::with_capacity(3)
            .spacing(8)
            .align_y(Alignment::Center)
            .push(widget::text::caption(format!("🖼️ {caption}")))
            .push(widget::space::horizontal())
            .push(
                widget::button::standard("Abrir Imagem")
                    .on_press(Message::DocsOpenMedia(path.clone())),
            );

        let img = widget::image(widget::image::Handle::from_path(path))
            .width(Length::Fill)
            .content_fit(cosmic::iced::ContentFit::ScaleDown);

        let inner = widget::column::with_capacity(2)
            .spacing(8)
            .width(Length::Fill)
            .push(header)
            .push(widget::container(img).max_height(460.0).width(Length::Fill));

        return widget::container(inner)
            .padding([10, 12])
            .width(Length::Fill)
            .class(cosmic::theme::Container::Card)
            .into();
    }

    let label = if alt.is_empty() { src } else { alt };
    widget::container(widget::text::caption(format!("🖼️ {label} ({src})")))
        .padding([8, 12])
        .width(Length::Fill)
        .class(cosmic::theme::Container::Card)
        .into()
}

fn render_attachment_card<'a>(
    label: &str,
    src: &str,
    source_root: Option<&Path>,
    current_doc: Option<&Path>,
) -> Element<'a, Message> {
    let resolved = source_root.zip(current_doc).and_then(|(root, cur)| {
        match resolve_markdown_link(root, cur, src) {
            MarkdownLinkResolution::LocalAttachment(p) | MarkdownLinkResolution::LocalImage(p) => {
                Some(p)
            }
            _ => None,
        }
    });

    let mut row = widget::row::with_capacity(3)
        .spacing(10)
        .align_y(Alignment::Center)
        .push(
            widget::column::with_capacity(2)
                .spacing(2)
                .width(Length::Fill)
                .push(widget::text::body(format!("📎 {label}")))
                .push(widget::text::caption(src.to_string())),
        );

    if let Some(path) = resolved {
        row = row.push(widget::button::suggested("Abrir Arquivo").on_press(Message::DocsOpenMedia(path)));
    }

    widget::container(row)
        .padding([10, 14])
        .width(Length::Fill)
        .class(cosmic::theme::Container::Card)
        .into()
}

fn render_block<'a>(
    block: &MarkdownBlock,
    font_size: f32,
    source_root: Option<&Path>,
    current_doc: Option<&Path>,
) -> Element<'a, Message> {
    match block {
        MarkdownBlock::Heading { level, inlines, .. } => {
            let delta = match level {
                1 => 10.0,
                2 => 6.0,
                3 => 3.5,
                _ => 1.0,
            };
            render_inlines(inlines, font_size + delta, true)
        }
        MarkdownBlock::Paragraph { inlines } => render_inlines(inlines, font_size, false),
        MarkdownBlock::CodeBlock { lang, code } => render_code_block(lang, code, font_size),
        MarkdownBlock::BlockQuote { alert, lines } => {
            render_blockquote(*alert, lines, font_size, source_root, current_doc)
        }
        MarkdownBlock::List { items } => {
            let mut list_col = widget::column::with_capacity(items.len())
                .spacing(5)
                .width(Length::Fill);
            for item in items {
                let left_pad = (item.indent_level as u16) * 18 + 6;
                let row = if let Some(checked) = item.checked {
                    widget::row::with_capacity(2)
                        .spacing(8)
                        .align_y(Alignment::Center)
                        .push(widget::checkbox(checked))
                        .push(render_inlines(&item.inlines, font_size, false))
                } else {
                    widget::row::with_capacity(2)
                        .spacing(8)
                        .align_y(Alignment::Start)
                        .push(
                            widget::text::body(item.marker.clone())
                                .size(font_size)
                                .class(cosmic::theme::Text::Color(Color::from_rgb(
                                    0.42, 0.76, 1.0,
                                ))),
                        )
                        .push(render_inlines(&item.inlines, font_size, false))
                };
                list_col = list_col.push(
                    widget::container(row)
                        .padding([0, 0, 0, left_pad])
                        .width(Length::Fill),
                );
            }
            list_col.into()
        }
        MarkdownBlock::Table { headers, rows } => render_table(headers, rows, font_size),
        MarkdownBlock::HorizontalRule => widget::divider::horizontal::default().into(),
        MarkdownBlock::Image { alt, src } => render_image_block(alt, src, source_root, current_doc),
        MarkdownBlock::AttachmentCard { label, src } => {
            render_attachment_card(label, src, source_root, current_doc)
        }
    }
}

fn render_doc_card<'a>(doc: &DocEntryItem, is_selected: bool) -> Element<'a, Message> {
    let (src_bg, src_fg) = doc.source_kind.badge_colors();
    let badges_row = widget::row::with_capacity(3)
        .spacing(6)
        .align_y(Alignment::Center)
        .push(pill_badge(
            doc.source_kind.badge_text().to_string(),
            src_bg,
            src_fg,
        ))
        .push(pill_badge(
            doc.badge_text.clone(),
            doc.badge_bg,
            doc.badge_fg,
        ))
        .push(widget::text::caption(doc.emoji.clone()).size(13.0));

    let mut card_col = widget::column::with_capacity(4)
        .spacing(4)
        .width(Length::Fill)
        .push(badges_row)
        .push(
            widget::text::body(doc.title.clone())
                .size(13.0)
                .font(Font {
                    weight: Weight::Semibold,
                    ..Font::DEFAULT
                })
                .wrapping(cosmic::iced::widget::text::Wrapping::WordOrGlyph),
        );

    if !doc.summary.is_empty() {
        card_col = card_col.push(
            widget::text::caption(doc.summary.clone())
                .size(11.2)
                .class(cosmic::theme::Text::Color(Color::from_rgb(
                    0.62, 0.68, 0.78,
                )))
                .wrapping(cosmic::iced::widget::text::Wrapping::WordOrGlyph),
        );
    }

    card_col = card_col.push(
        widget::text::monotext(doc.relative_path.clone())
            .size(10.5)
            .class(cosmic::theme::Text::Color(Color::from_rgb(
                0.35, 0.74, 0.96,
            ))),
    );

    let bg_normal = if is_selected {
        Color::from_rgb(0.09, 0.15, 0.30)
    } else {
        Color::from_rgb(0.07, 0.09, 0.14)
    };
    let bg_hover = if is_selected {
        Color::from_rgb(0.11, 0.19, 0.36)
    } else {
        Color::from_rgb(0.10, 0.13, 0.20)
    };
    let bg_pressed = if is_selected {
        Color::from_rgb(0.13, 0.22, 0.42)
    } else {
        Color::from_rgb(0.12, 0.16, 0.25)
    };
    let border_color = if is_selected {
        Color::from_rgb(0.22, 0.74, 0.97)
    } else {
        Color::from_rgb(0.15, 0.19, 0.27)
    };
    let border_hover = if is_selected {
        Color::from_rgb(0.35, 0.82, 1.0)
    } else {
        Color::from_rgb(0.25, 0.33, 0.46)
    };
    let border_width = if is_selected { 1.5 } else { 1.0 };

    let make_style = move |bg: Color, b_color: Color| cosmic::widget::button::Style {
        background: Some(Background::Color(bg)),
        border_radius: 8.0.into(),
        border_width,
        border_color: b_color,
        outline_width: 0.0,
        outline_color: Color::TRANSPARENT,
        icon_color: None,
        text_color: None,
        overlay: None,
        shadow_offset: cosmic::iced::Vector::ZERO,
    };

    widget::button::custom(card_col)
        .padding([10, 12])
        .width(Length::Fill)
        .class(cosmic::theme::Button::Custom {
            active: Box::new(move |_, _| make_style(bg_normal, border_color)),
            disabled: Box::new(move |_| make_style(bg_normal, border_color)),
            hovered: Box::new(move |_, _| make_style(bg_hover, border_hover)),
            pressed: Box::new(move |_, _| make_style(bg_pressed, border_hover)),
        })
        .on_press(Message::SelectDocFile(doc.full_path.clone()))
        .into()
}

pub fn view(app: &AppModel) -> Element<'_, Message> {
    let selected_source_idx = app
        .docs_source_idx
        .min(app.docs_sources.len().saturating_sub(1));
    let selected_source = app
        .docs_sources
        .get(selected_source_idx)
        .map(String::as_str)
        .unwrap_or(SOURCE_ALL);

    let selected_cat_idx = app
        .docs_category_idx
        .min(app.docs_categories.len().saturating_sub(1));
    let selected_cat = app
        .docs_categories
        .get(selected_cat_idx)
        .map(String::as_str)
        .unwrap_or(CATEGORY_ALL);

    let filtered = filter_documents(
        &app.docs_catalog,
        &app.docs_search,
        selected_source,
        selected_cat,
    );

    let total_docs = app.docs_catalog.len();
    let homelab_count = app
        .docs_catalog
        .iter()
        .filter(|d| d.source_kind == DocSourceKind::Homelab)
        .count();

    // Badge de status no cabeçalho superior
    let (status_text, status_bg, status_fg) = if let Some((msg, is_err)) = &app.docs_status_badge {
        if *is_err {
            (msg.clone(), [0.32, 0.16, 0.06], [0.98, 0.75, 0.14])
        } else {
            (msg.clone(), [0.05, 0.25, 0.19], [0.29, 0.87, 0.65])
        }
    } else if app.docs_search.trim().is_empty()
        && selected_source == SOURCE_ALL
        && selected_cat == CATEGORY_ALL
    {
        let suffix = if homelab_count > 0 {
            format!(" • {homelab_count} Homelab")
        } else {
            String::new()
        };
        (
            format!("📚 {total_docs} doc(s){suffix}"),
            [0.12, 0.16, 0.24],
            [0.49, 0.83, 0.99],
        )
    } else {
        (
            format!("🔎 {} de {total_docs} doc(s)", filtered.len()),
            [0.11, 0.22, 0.45],
            [0.58, 0.77, 0.99],
        )
    };

    // Coluna esquerda: Busca full-text + Origem + Categoria + Reindexar + Cards ricos
    let mut cards_col = widget::column::with_capacity(filtered.len().max(1))
        .spacing(8)
        .width(Length::Fill);

    if filtered.is_empty() {
        cards_col = cards_col.push(
            widget::container(widget::text::caption(
                "Nenhum documento corresponde aos filtros atuais.",
            ))
            .padding([12, 10]),
        );
    } else {
        for doc in &filtered {
            let is_selected = app.selected_doc_path.as_ref() == Some(&doc.full_path);
            cards_col = cards_col.push(render_doc_card(doc, is_selected));
        }
    }

    let cat_and_reload = widget::row::with_capacity(2)
        .spacing(6)
        .align_y(Alignment::Center)
        .push(
            widget::dropdown(
                &app.docs_categories,
                Some(selected_cat_idx),
                Message::DocsCategorySelected,
            )
            .width(Length::Fill),
        )
        .push(widget::button::standard("🔄").on_press(Message::DocsReloadCatalog));

    let left_pane = widget::column::with_capacity(4)
        .spacing(8)
        .width(Length::Fixed(340.0))
        .height(Length::Fill)
        .push(
            widget::text_input("Buscar por título ou conteúdo...", &app.docs_search)
                .on_input(Message::DocsSearchChanged),
        )
        .push(
            widget::dropdown(
                &app.docs_sources,
                Some(selected_source_idx),
                Message::DocsSourceSelected,
            )
            .width(Length::Fill),
        )
        .push(cat_and_reload)
        .push(
            widget::scrollable(widget::container(cards_col).padding([0, 12, 0, 0]))
                .height(Length::Fill),
        );

    // Coluna direita: Barra do leitor (histórico, metadados, zoom, ações) + conteúdo formatado
    let current_doc = app.current_doc_entry();
    let doc_title = current_doc
        .map(|d| format!("{} {}", d.emoji, d.title))
        .unwrap_or_else(|| "Selecione um documento à esquerda".to_string());
    let doc_meta = current_doc
        .map(|d| {
            if d.last_modified_display.is_empty() {
                format!("{}/{}", d.source_kind.display_prefix(), d.relative_path)
            } else {
                format!(
                    "{}/{}  •  Atualizado em {}",
                    d.source_kind.display_prefix(),
                    d.relative_path,
                    d.last_modified_display
                )
            }
        })
        .unwrap_or_else(|| "Docs/".to_string());

    let back_btn = if app.docs_back_history.is_empty() {
        widget::button::standard("◀")
    } else {
        widget::button::standard("◀").on_press(Message::DocsNavigateBack)
    };
    let fwd_btn = if app.docs_forward_history.is_empty() {
        widget::button::standard("▶")
    } else {
        widget::button::standard("▶").on_press(Message::DocsNavigateForward)
    };

    let zoom_pct = ((app.docs_font_size / 14.0) * 100.0).round() as u32;

    let mut actions: Vec<Element<'_, Message>> = vec![
        widget::button::standard("A-")
            .on_press(Message::DocsFontSizeDelta(-1.0))
            .into(),
        widget::button::standard(format!("{zoom_pct}%"))
            .on_press(Message::DocsFontSizeReset)
            .into(),
        widget::button::standard("A+")
            .on_press(Message::DocsFontSizeDelta(1.0))
            .into(),
    ];

    if let Some(p) = &app.selected_doc_path {
        actions.push(
            widget::button::suggested("📦 Exportar HTML")
                .on_press(Message::DocsExportHtml)
                .into(),
        );
        let sel_btn = if app.docs_select_mode {
            widget::button::suggested("Modo Seleção").on_press(Message::ToggleDocsSelectMode)
        } else {
            widget::button::standard("Modo Seleção").on_press(Message::ToggleDocsSelectMode)
        };
        actions.push(sel_btn.into());
        actions.push(
            widget::button::standard("📋 .md")
                .on_press(Message::CopyDocContent)
                .into(),
        );
        actions.push(
            widget::button::standard("📂 Pasta")
                .on_press(Message::DocsOpenCurrentFolder)
                .into(),
        );
        actions.push(
            widget::button::standard("Abrir Externo")
                .on_press(Message::OpenLocalFolder(p.clone()))
                .into(),
        );
    }

    let reader_top_row = widget::row::with_capacity(4)
        .spacing(8)
        .align_y(Alignment::Center)
        .push(back_btn)
        .push(fwd_btn)
        .push(
            widget::column::with_capacity(2)
                .spacing(2)
                .width(Length::Fill)
                .push(widget::text::title3(doc_title))
                .push(widget::text::monotext(doc_meta).size(11.0).class(
                    cosmic::theme::Text::Color(Color::from_rgb(0.58, 0.64, 0.74)),
                )),
        );

    let reader_actions_bar = ui::wrap_row(actions);

    let reader: Element<'_, Message> = if app.selected_doc_content.is_empty() {
        widget::container(widget::text::caption(
            "Escolha qualquer arquivo .md na árvore à esquerda para ler a documentação formatada.",
        ))
        .padding([16, 8])
        .into()
    } else if app.docs_select_mode {
        cosmic::iced::widget::text_editor(&app.docs_editor_content)
            .on_action(Message::DocsEditorAction)
            .height(Length::Fill)
            .into()
    } else {
        let source_root = current_doc.map(|d| d.source_root.as_path());
        let current_path = current_doc.map(|d| d.full_path.as_path());
        let mut col = widget::column::with_capacity(app.selected_doc_blocks.len().max(1))
            .spacing(10)
            .width(Length::Fill);
        for block in &app.selected_doc_blocks {
            col = col.push(render_block(
                block,
                app.docs_font_size,
                source_root,
                current_path,
            ));
        }
        widget::scrollable(
            widget::container(col)
                .padding([4, 16, 20, 4])
                .width(Length::Fill),
        )
        .id(widget::Id::new("docs_reader_scroll"))
        .height(Length::Fill)
        .width(Length::Fill)
        .into()
    };

    let right_pane = widget::column::with_capacity(4)
        .spacing(8)
        .width(Length::Fill)
        .height(Length::Fill)
        .push(reader_top_row)
        .push(reader_actions_bar)
        .push(widget::divider::horizontal::default())
        .push(reader);

    let sidebar_toggle_label = if app.docs_sidebar_open {
        "◀ Ocultar Lista"
    } else {
        "▶ Mostrar Lista"
    };

    let top_header = widget::row::with_capacity(3)
        .spacing(12)
        .align_y(Alignment::Center)
        .push(ui::btn_standard(
            sidebar_toggle_label,
            Message::ToggleDocsSidebar,
        ))
        .push(
            widget::column::with_capacity(2)
                .spacing(2)
                .width(Length::Fill)
                .push(widget::text::title2("Documentação Técnica & Manuais (Wiki)"))
                .push(widget::text::caption(
                    "Consulte guias do Pop!_OS e Homelab com busca full-text, histórico, alertas, imagens inline e exportação HTML offline.",
                )),
        )
        .push(pill_badge(status_text, status_bg, status_fg));

    let mut body = widget::row::with_capacity(2)
        .spacing(16)
        .width(Length::Fill)
        .height(Length::Fill);
    if app.docs_sidebar_open {
        body = body.push(left_pane);
    }
    body = body.push(right_pane);

    widget::column::with_capacity(2)
        .spacing(12)
        .width(Length::Fill)
        .height(Length::Fill)
        .push(top_header)
        .push(body)
        .into()
}
