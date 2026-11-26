use crate::app::{AppModel, Message};
use cosmic::iced::font::{Font, Weight};
use cosmic::iced::widget::{rich_text, span};
use cosmic::iced::{Alignment, Color, Length};
use cosmic::prelude::*;
use cosmic::widget::{self, settings};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

fn collect_md_files(base: &Path, prefix: &str, out: &mut BTreeMap<String, Vec<(String, PathBuf)>>) {
    let readme = base.join("README.md");
    if readme.is_file() {
        out.entry(format!("{prefix}Raiz"))
            .or_default()
            .push(("README.md".to_string(), readme));
    }

    let docs_root = base.join("Docs");
    if !docs_root.is_dir() {
        return;
    }

    let mut stack = vec![docs_root.clone()];
    while let Some(dir) = stack.pop() {
        let Ok(entries) = fs::read_dir(&dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let p = entry.path();
            if p.is_dir() {
                stack.push(p);
            } else if p.extension().is_some_and(|e| e.eq_ignore_ascii_case("md")) {
                let rel_dir = p
                    .parent()
                    .and_then(|d| d.strip_prefix(base).ok())
                    .map(|d| d.to_string_lossy().to_string())
                    .unwrap_or_else(|| "Docs".to_string());
                let fname = p
                    .file_name()
                    .and_then(|s| s.to_str())
                    .unwrap_or("doc.md")
                    .to_string();
                out.entry(format!("{prefix}{rel_dir}"))
                    .or_default()
                    .push((fname, p));
            }
        }
    }
}

fn render_inline_md<'a>(text: &str, font_size: f32) -> Element<'a, Message> {
    render_inline_md_styled(text, font_size, false)
}

fn render_inline_md_styled<'a>(
    text: &str,
    font_size: f32,
    default_bold: bool,
) -> Element<'a, Message> {
    let mut spans: Vec<cosmic::iced::widget::text::Span<'a, String, Font>> = Vec::new();
    let mut rest = text;
    let base_font = if default_bold {
        Font {
            weight: Weight::Bold,
            ..Font::DEFAULT
        }
    } else {
        Font::DEFAULT
    };

    while !rest.is_empty() {
        // Find earliest inline marker: [![badge](img)](url), ![img](url), <kbd>, **bold**, `code`, or [label](url)
        let badge_idx = rest.find("[![");
        let img_idx = rest.find("![");
        let kbd_idx = rest.find("<kbd>");
        let bold_idx = rest.find("**");
        let code_idx = rest.find('`');
        let link_idx = rest.find('[');

        let next_idx = [badge_idx, img_idx, kbd_idx, bold_idx, code_idx, link_idx]
            .into_iter()
            .flatten()
            .min();

        let Some(idx) = next_idx else {
            spans.push(span(rest.to_string()).font(base_font));
            break;
        };

        if idx > 0 {
            spans.push(span(rest[..idx].to_string()).font(base_font));
            rest = &rest[idx..];
        }

        if rest.starts_with("[![") {
            if let Some(mid) = rest[3..].find("](") {
                let label = &rest[3..3 + mid];
                let after_mid = &rest[3 + mid + 2..];
                if let Some(end_img) = after_mid.find(")](") {
                    let after_img = &after_mid[end_img + 3..];
                    if let Some(end_url) = after_img.find(')') {
                        let url = &after_img[..end_url];
                        let pill_color = Color::from_rgb(0.45, 0.82, 0.98);
                        if url.starts_with("http://") || url.starts_with("https://") {
                            spans.push(
                                span(format!("[{label}]"))
                                    .color(pill_color)
                                    .font(Font {
                                        weight: Weight::Bold,
                                        ..Font::DEFAULT
                                    })
                                    .link(url.to_string()),
                            );
                        } else {
                            spans.push(
                                span(format!("[{label}]"))
                                    .color(pill_color)
                                    .font(Font {
                                        weight: Weight::Bold,
                                        ..Font::DEFAULT
                                    }),
                            );
                        }
                        rest = &after_img[end_url + 1..];
                        continue;
                    }
                }
            }
            spans.push(span("[![".to_string()));
            rest = &rest[3..];
        } else if rest.starts_with("![") {
            if let Some(close_br) = rest[2..].find("](") {
                let label = &rest[2..2 + close_br];
                let after_br = &rest[2 + close_br + 2..];
                if let Some(close_par) = after_br.find(')') {
                    spans.push(
                        span(format!("[{label}]"))
                            .color(Color::from_rgb(0.65, 0.78, 0.95)),
                    );
                    rest = &after_br[close_par + 1..];
                    continue;
                }
            }
            spans.push(span("![".to_string()));
            rest = &rest[2..];
        } else if rest.starts_with("<kbd>") {
            if let Some(end) = rest[5..].find("</kbd>") {
                let inner = &rest[5..5 + end];
                spans.push(
                    span(inner.to_string())
                        .font(Font::MONOSPACE)
                        .color(Color::from_rgb(0.95, 0.82, 0.45)),
                );
                rest = &rest[5 + end + 6..];
                continue;
            }
            spans.push(span("<kbd>".to_string()));
            rest = &rest[5..];
        } else if rest.starts_with("**") {
            if let Some(end) = rest[2..].find("**") {
                let inner = &rest[2..2 + end];
                let mut sub = inner;
                while !sub.is_empty() {
                    if let Some(c_start) = sub.find('`') {
                        if c_start > 0 {
                            spans.push(span(sub[..c_start].to_string()).font(Font {
                                weight: Weight::Bold,
                                ..Font::DEFAULT
                            }));
                        }
                        if let Some(c_end) = sub[c_start + 1..].find('`') {
                            let code_txt = &sub[c_start + 1..c_start + 1 + c_end];
                            spans.push(
                                span(format!(" {code_txt} "))
                                    .font(Font::MONOSPACE)
                                    .color(Color::from_rgb(0.65, 0.85, 0.95))
                                    .background(Color::from_rgb(0.16, 0.19, 0.25)),
                            );
                            sub = &sub[c_start + 1 + c_end + 1..];
                            continue;
                        }
                        spans.push(span(sub[c_start..].to_string()).font(Font {
                            weight: Weight::Bold,
                            ..Font::DEFAULT
                        }));
                        break;
                    } else {
                        spans.push(span(sub.to_string()).font(Font {
                            weight: Weight::Bold,
                            ..Font::DEFAULT
                        }));
                        break;
                    }
                }
                rest = &rest[2 + end + 2..];
                continue;
            }
            spans.push(span("**".to_string()));
            rest = &rest[2..];
        } else if rest.starts_with('`') {
            if let Some(end) = rest[1..].find('`') {
                let inner = &rest[1..1 + end];
                spans.push(
                    span(format!(" {inner} "))
                        .font(Font::MONOSPACE)
                        .color(Color::from_rgb(0.65, 0.85, 0.95))
                        .background(Color::from_rgb(0.16, 0.19, 0.25)),
                );
                rest = &rest[1 + end + 1..];
                continue;
            }
            spans.push(span("`".to_string()));
            rest = &rest[1..];
        } else if rest.starts_with('[') {
            if let Some(close_br) = rest[1..].find("](") {
                let label = &rest[1..1 + close_br];
                let after_br = &rest[1 + close_br + 2..];
                if let Some(close_par) = after_br.find(')') {
                    let url = &after_br[..close_par];
                    let link_color = Color::from_rgb(0.55, 0.78, 1.0);
                    if url.starts_with("http://") || url.starts_with("https://") {
                        spans.push(
                            span(label.to_string())
                                .color(link_color)
                                .underline(true)
                                .link(url.to_string()),
                        );
                    } else if url.ends_with(".md") || url.contains(".md#") {
                        spans.push(
                            span(label.to_string())
                                .color(link_color)
                                .underline(true)
                                .link(format!("doc://{url}")),
                        );
                    } else if url.starts_with('#') {
                        spans.push(
                            span(label.to_string())
                                .color(link_color)
                                .underline(true)
                                .link(format!("anchor://{url}")),
                        );
                    } else {
                        spans.push(span(label.to_string()).color(link_color));
                    }
                    rest = &after_br[close_par + 1..];
                    continue;
                }
            }
            spans.push(span("[".to_string()));
            rest = &rest[1..];
        }
    }

    rich_text(spans)
        .on_link_click(Message::LaunchUrl)
        .size(font_size)
        .line_height(1.45)
        .into()
}

fn is_table_separator(line: &str) -> bool {
    let trimmed = line.trim();
    trimmed.starts_with('|')
        && trimmed
            .chars()
            .all(|c| c == '|' || c == '-' || c == ':' || c == ' ')
}

fn render_table_row<'a>(
    line: &str,
    is_header: bool,
    row_idx: usize,
    font_size: f32,
) -> Element<'a, Message> {
    let cells: Vec<&str> = line
        .trim()
        .trim_matches('|')
        .split('|')
        .map(|s| s.trim())
        .collect();
    let mut row = widget::row::with_capacity(cells.len().max(1))
        .spacing(10)
        .width(Length::Fill);
    for cell in cells {
        let cell_el: Element<'a, Message> = if is_header {
            widget::text::heading(cell.to_string())
                .size(font_size)
                .into()
        } else {
            render_inline_md(cell, font_size)
        };
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
                background: Some(cosmic::iced::Background::Color(bg)),
                border: cosmic::iced::Border {
                    color: Color::from_rgb(0.22, 0.25, 0.32),
                    width: 1.0,
                    radius: 0.0.into(),
                },
                ..Default::default()
            }
        }))
        .into()
}

fn render_code_block<'a>(lang: &str, code: &str, font_size: f32) -> Element<'a, Message> {
    let trimmed_code = code.trim_end().to_string();
    let lang_label = if lang.is_empty() {
        "código".to_string()
    } else {
        lang.to_string()
    };

    let header = widget::row::with_capacity(3)
        .spacing(8)
        .align_y(Alignment::Center)
        .push(
            widget::text::caption(lang_label)
                .class(cosmic::theme::Text::Color(Color::from_rgb(0.60, 0.72, 0.90))),
        )
        .push(widget::space::horizontal())
        .push(widget::button::standard("Copiar").on_press(Message::CopyText(trimmed_code.clone())));

    let body = widget::text::monotext(trimmed_code).size((font_size - 1.5).max(10.5));

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

fn build_quote_card<'a>(qbuf: &mut Vec<String>, font_size: f32) -> Element<'a, Message> {
    let inner_md = qbuf.join("\n");
    qbuf.clear();
    let inner_el = render_markdown_column_owned(inner_md, font_size);
    let bar = widget::container(widget::space::vertical().height(Length::Fixed(24.0)))
        .width(Length::Fixed(3.0))
        .class(cosmic::theme::Container::Primary);
    let quote_row = widget::row::with_capacity(2)
        .spacing(10)
        .push(bar)
        .push(inner_el);
    widget::container(quote_row)
        .padding([8, 12])
        .width(Length::Fill)
        .class(cosmic::theme::Container::Card)
        .into()
}

fn render_markdown_column<'a>(content: &'a str, font_size: f32) -> Element<'a, Message> {
    let mut col = widget::column::with_capacity(64).spacing(10).width(Length::Fill);
    let mut in_code_block = false;
    let mut code_lang = String::new();
    let mut code_buf = String::new();
    let mut in_table = false;
    let mut table_row_idx = 0usize;
    let mut quote_buf: Vec<String> = Vec::new();

    for line in content.lines() {
        let trimmed = line.trim_end();
        if let Some(after_ticks) = trimmed.trim_start().strip_prefix("```") {
            if in_code_block {
                col = col.push(render_code_block(&code_lang, &code_buf, font_size));
                code_buf.clear();
                code_lang.clear();
                in_code_block = false;
            } else {
                code_lang = after_ticks.trim().to_string();
                in_code_block = true;
            }
            continue;
        }

        if in_code_block {
            code_buf.push_str(line);
            code_buf.push('\n');
            continue;
        }

        let s = trimmed.trim();
        if s == ">" || s.starts_with("> ") {
            let inner_line = s.strip_prefix("> ").unwrap_or("").to_string();
            quote_buf.push(inner_line);
            continue;
        } else if !quote_buf.is_empty() {
            col = col.push(build_quote_card(&mut quote_buf, font_size));
        }

        if s.starts_with('|') && s.ends_with('|') {
            if is_table_separator(s) {
                continue;
            }
            let is_header = !in_table || table_row_idx == 0;
            in_table = true;
            col = col.push(render_table_row(s, is_header, table_row_idx, font_size));
            table_row_idx += 1;
            continue;
        } else {
            in_table = false;
            table_row_idx = 0;
        }

        if s.is_empty() {
            col = col.push(widget::space::vertical().height(Length::Fixed(4.0)));
        } else if s == "---" || s == "***" {
            col = col.push(widget::divider::horizontal::default());
        } else if let Some(h) = s.strip_prefix("# ") {
            if h.contains('`') || h.contains("**") || h.contains('[') {
                col = col.push(render_inline_md_styled(h.trim(), font_size + 10.0, true));
            } else {
                col = col.push(widget::text::title2(h.trim().to_string()));
            }
        } else if let Some(h) = s.strip_prefix("## ") {
            if h.contains('`') || h.contains("**") || h.contains('[') {
                col = col.push(render_inline_md_styled(h.trim(), font_size + 6.0, true));
            } else {
                col = col.push(widget::text::title3(h.trim().to_string()));
            }
        } else if let Some(h) = s.strip_prefix("### ") {
            if h.contains('`') || h.contains("**") || h.contains('[') {
                col = col.push(render_inline_md_styled(h.trim(), font_size + 4.0, true));
            } else {
                col = col.push(widget::text::title4(h.trim().to_string()));
            }
        } else if let Some(h) = s.strip_prefix("#### ") {
            if h.contains('`') || h.contains("**") || h.contains('[') {
                col = col.push(render_inline_md_styled(h.trim(), font_size, true));
            } else {
                col = col.push(widget::text::heading(h.trim().to_string()));
            }
        } else if let Some(item) = s.strip_prefix("- ").or_else(|| s.strip_prefix("* ")) {
            if let Some(rest) = item.strip_prefix("[x] ").or_else(|| item.strip_prefix("[X] ")) {
                let row = widget::row::with_capacity(2)
                    .spacing(8)
                    .align_y(Alignment::Center)
                    .push(widget::checkbox(true))
                    .push(render_inline_md(rest, font_size));
                col = col.push(widget::container(row).padding([0, 6]));
            } else if let Some(rest) = item.strip_prefix("[ ] ") {
                let row = widget::row::with_capacity(2)
                    .spacing(8)
                    .align_y(Alignment::Center)
                    .push(widget::checkbox(false))
                    .push(render_inline_md(rest, font_size));
                col = col.push(widget::container(row).padding([0, 6]));
            } else {
                col = col.push(render_inline_md(&format!("  • {item}"), font_size));
            }
        } else {
            col = col.push(render_inline_md(s, font_size));
        }
    }

    if !quote_buf.is_empty() {
        col = col.push(build_quote_card(&mut quote_buf, font_size));
    }
    if in_code_block && !code_buf.is_empty() {
        col = col.push(render_code_block(&code_lang, &code_buf, font_size));
    }
    col.into()
}

fn render_markdown_column_owned<'a>(content: String, font_size: f32) -> Element<'a, Message> {
    let mut col = widget::column::with_capacity(16).spacing(8).width(Length::Fill);
    let mut in_code_block = false;
    let mut code_lang = String::new();
    let mut code_buf = String::new();

    for line in content.lines() {
        let trimmed = line.trim_end();
        if let Some(after_ticks) = trimmed.trim_start().strip_prefix("```") {
            if in_code_block {
                col = col.push(render_code_block(&code_lang, &code_buf, font_size));
                code_buf.clear();
                code_lang.clear();
                in_code_block = false;
            } else {
                code_lang = after_ticks.trim().to_string();
                in_code_block = true;
            }
            continue;
        }
        if in_code_block {
            code_buf.push_str(line);
            code_buf.push('\n');
            continue;
        }
        let s = trimmed.trim();
        if !s.is_empty() {
            col = col.push(render_inline_md(s, font_size));
        }
    }
    col.into()
}

fn render_markdown<'a>(content: &'a str, font_size: f32) -> Element<'a, Message> {
    let col = render_markdown_column(content, font_size);
    widget::scrollable(col)
        .id(widget::Id::new("docs_reader_scroll"))
        .height(Length::Fill)
        .width(Length::Fill)
        .into()
}

const DOC_CATEGORIES: &[&str] = &[
    "Todas as Categorias",
    "Raiz (README)",
    "Docs / Guias",
    "Docs / Issues",
    "Homelab (umbrelOS)",
];

pub fn view(app: &AppModel) -> Element<'_, Message> {
    let mut grouped: BTreeMap<String, Vec<(String, PathBuf)>> = BTreeMap::new();
    collect_md_files(&app.paths.popos_repo, "", &mut grouped);
    if app.paths.homelab_repo.exists() {
        collect_md_files(&app.paths.homelab_repo, "Homelab / ", &mut grouped);
    }

    let total_docs: usize = grouped.values().map(|v| v.len()).sum();
    let selected_cat_idx = app.docs_category_idx.min(DOC_CATEGORIES.len() - 1);

    let needle = app.docs_search.trim().to_ascii_lowercase();
    let mut tree_col = widget::column::with_capacity(24).spacing(10).width(Length::Fill);

    for (folder, mut files) in grouped {
        let cat_match = match selected_cat_idx {
            1 => folder == "Raiz",
            2 => folder.contains("guias"),
            3 => folder.contains("issues"),
            4 => folder.starts_with("Homelab"),
            _ => true,
        };
        if !cat_match {
            continue;
        }
        files.sort_by(|a, b| a.0.cmp(&b.0));
        let filtered: Vec<(String, PathBuf)> = files
            .into_iter()
            .filter(|(name, _)| {
                needle.is_empty()
                    || name.to_ascii_lowercase().contains(&needle)
                    || folder.to_ascii_lowercase().contains(&needle)
            })
            .collect();
        if filtered.is_empty() {
            continue;
        }

        let mut sec = settings::section().title(folder);
        for (name, path) in filtered {
            let is_selected = app.selected_doc_path.as_ref() == Some(&path);
            let btn = if is_selected {
                widget::button::suggested(name).on_press(Message::SelectDocFile(path))
            } else {
                widget::button::standard(name).on_press(Message::SelectDocFile(path))
            };
            sec = sec.add(widget::container(btn.width(Length::Fill)).padding([2, 4]));
        }
        tree_col = tree_col.push(sec);
    }

    let left_pane = widget::column::with_capacity(3)
        .spacing(8)
        .width(Length::Fixed(310.0))
        .height(Length::Fill)
        .push(
            widget::text_input("Buscar documento (.md)...", &app.docs_search)
                .on_input(Message::DocsSearchChanged),
        )
        .push(
            widget::dropdown(
                DOC_CATEGORIES,
                Some(selected_cat_idx),
                Message::DocsCategorySelected,
            )
            .width(Length::Fill),
        )
        .push(widget::scrollable(tree_col).height(Length::Fill));

    let doc_title = app
        .selected_doc_path
        .as_ref()
        .and_then(|p| p.file_name())
        .and_then(|s| s.to_str())
        .unwrap_or("Selecione um documento à esquerda");

    let mut right_header = widget::row::with_capacity(6)
        .spacing(8)
        .align_y(Alignment::Center)
        .push(widget::text::title2(doc_title.to_string()))
        .push(widget::space::horizontal())
        .push(widget::button::standard("A-").on_press(Message::DocsFontSizeDelta(-1.0)))
        .push(widget::text::caption(format!("{}px", app.docs_font_size as u32)))
        .push(widget::button::standard("A+").on_press(Message::DocsFontSizeDelta(1.0)));

    if let Some(p) = &app.selected_doc_path {
        let sel_btn = if app.docs_select_mode {
            widget::button::suggested("Modo Seleção").on_press(Message::ToggleDocsSelectMode)
        } else {
            widget::button::standard("Modo Seleção").on_press(Message::ToggleDocsSelectMode)
        };
        right_header = right_header
            .push(sel_btn)
            .push(widget::button::standard("Copiar").on_press(Message::CopyDocContent))
            .push(
                widget::button::standard("Abrir Externo")
                    .on_press(Message::OpenLocalFolder(p.clone())),
            );
    }

    let reader: Element<'_, Message> = if app.selected_doc_content.is_empty() {
        widget::text::caption(
            "Escolha qualquer arquivo .md na árvore à esquerda para ler a documentação formatada.",
        )
        .into()
    } else if app.docs_select_mode {
        cosmic::iced::widget::text_editor(&app.docs_editor_content)
            .on_action(Message::DocsEditorAction)
            .height(Length::Fill)
            .into()
    } else {
        render_markdown(&app.selected_doc_content, app.docs_font_size)
    };

    let right_pane = widget::column::with_capacity(3)
        .spacing(10)
        .width(Length::Fill)
        .height(Length::Fill)
        .push(right_header)
        .push(widget::divider::horizontal::default())
        .push(reader);

    let top_header = widget::row::with_capacity(2)
        .spacing(12)
        .align_y(Alignment::Center)
        .push(
            widget::column::with_capacity(2)
                .spacing(2)
                .width(Length::Fill)
                .push(widget::text::title2("Documentação Técnica & Manuais (Wiki)"))
                .push(widget::text::caption(
                    "Consulte guias de operação, decisões arquiteturais e manuais diretamente da pasta Docs/.",
                )),
        )
        .push(widget::text::body(format!("📚 {total_docs} documentos")));

    let body = widget::row::with_capacity(2)
        .spacing(16)
        .width(Length::Fill)
        .height(Length::Fill)
        .push(left_pane)
        .push(right_pane);

    widget::column::with_capacity(2)
        .spacing(12)
        .width(Length::Fill)
        .height(Length::Fill)
        .push(top_header)
        .push(body)
        .into()
}
