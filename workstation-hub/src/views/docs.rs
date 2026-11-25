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

fn render_inline_md<'a>(text: &str) -> Element<'a, Message> {
    let mut spans: Vec<cosmic::iced::widget::text::Span<'a, String, Font>> = Vec::new();
    let mut rest = text;

    while !rest.is_empty() {
        // Find earliest inline marker: **bold**, `code`, or [label](url)
        let bold_idx = rest.find("**");
        let code_idx = rest.find('`');
        let link_idx = rest.find('[');

        let next_idx = [bold_idx, code_idx, link_idx]
            .into_iter()
            .flatten()
            .min();

        let Some(idx) = next_idx else {
            spans.push(span(rest.to_string()));
            break;
        };

        if idx > 0 {
            spans.push(span(rest[..idx].to_string()));
            rest = &rest[idx..];
        }

        if rest.starts_with("**") {
            if let Some(end) = rest[2..].find("**") {
                let inner = &rest[2..2 + end];
                spans.push(span(inner.to_string()).font(Font {
                    weight: Weight::Bold,
                    ..Font::DEFAULT
                }));
                rest = &rest[2 + end + 2..];
                continue;
            }
            spans.push(span("**".to_string()));
            rest = &rest[2..];
        } else if rest.starts_with('`') {
            if let Some(end) = rest[1..].find('`') {
                let inner = &rest[1..1 + end];
                spans.push(
                    span(inner.to_string())
                        .font(Font::MONOSPACE)
                        .color(Color::from_rgb(0.65, 0.85, 0.95)),
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
        .size(14.0)
        .into()
}

fn render_markdown<'a>(content: &'a str) -> Element<'a, Message> {
    let mut col = widget::column::with_capacity(64).spacing(6).width(Length::Fill);
    let mut in_code_block = false;
    let mut code_buf = String::new();

    for line in content.lines() {
        let trimmed = line.trim_end();
        if trimmed.trim_start().starts_with("```") {
            if in_code_block {
                let code_box = widget::container(
                    widget::text::monotext(code_buf.trim_end().to_string()).size(12.5),
                )
                .padding([8, 12])
                .width(Length::Fill);
                col = col.push(code_box);
                code_buf.clear();
                in_code_block = false;
            } else {
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
        if s.is_empty() {
            col = col.push(widget::space::vertical().height(Length::Fixed(4.0)));
        } else if s == "---" || s == "***" {
            col = col.push(widget::divider::horizontal::default());
        } else if let Some(h) = s.strip_prefix("# ") {
            col = col.push(widget::text::title2(h.trim().to_string()));
        } else if let Some(h) = s.strip_prefix("## ") {
            col = col.push(widget::text::title3(h.trim().to_string()));
        } else if let Some(h) = s.strip_prefix("### ") {
            col = col.push(widget::text::title4(h.trim().to_string()));
        } else if let Some(h) = s.strip_prefix("#### ") {
            col = col.push(widget::text::heading(h.trim().to_string()));
        } else if let Some(q) = s.strip_prefix("> ") {
            col = col.push(
                widget::container(
                    widget::text::body(format!("❝ {q}"))
                        .class(cosmic::theme::Text::Color(Color::from_rgb(0.75, 0.80, 0.90))),
                )
                .padding([4, 10]),
            );
        } else if let Some(item) = s.strip_prefix("- ").or_else(|| s.strip_prefix("* ")) {
            col = col.push(render_inline_md(&format!("  • {item}")));
        } else {
            col = col.push(render_inline_md(s));
        }
    }

    if in_code_block && !code_buf.is_empty() {
        col = col.push(
            widget::container(widget::text::monotext(code_buf).size(12.5))
                .padding([8, 12])
                .width(Length::Fill),
        );
    }

    widget::scrollable(col)
        .height(Length::Fill)
        .width(Length::Fill)
        .into()
}

pub fn view(app: &AppModel) -> Element<'_, Message> {
    let mut grouped: BTreeMap<String, Vec<(String, PathBuf)>> = BTreeMap::new();
    collect_md_files(&app.paths.popos_repo, "", &mut grouped);
    if app.paths.homelab_repo.exists() {
        collect_md_files(&app.paths.homelab_repo, "Homelab / ", &mut grouped);
    }

    let needle = app.docs_search.trim().to_ascii_lowercase();
    let mut tree_col = widget::column::with_capacity(24).spacing(10).width(Length::Fill);

    for (folder, mut files) in grouped {
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

    let left_pane = widget::column::with_capacity(2)
        .spacing(8)
        .width(Length::Fixed(300.0))
        .height(Length::Fill)
        .push(
            widget::text_input("Buscar documento (.md)...", &app.docs_search)
                .on_input(Message::DocsSearchChanged),
        )
        .push(widget::scrollable(tree_col).height(Length::Fill));

    let doc_title = app
        .selected_doc_path
        .as_ref()
        .and_then(|p| p.file_name())
        .and_then(|s| s.to_str())
        .unwrap_or("Selecione um documento à esquerda");

    let mut right_header = widget::row::with_capacity(3)
        .spacing(10)
        .align_y(Alignment::Center)
        .push(widget::text::title2(doc_title.to_string()))
        .push(widget::space::horizontal());

    if let Some(p) = &app.selected_doc_path {
        right_header = right_header
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
    } else {
        render_markdown(&app.selected_doc_content)
    };

    let right_pane = widget::column::with_capacity(3)
        .spacing(10)
        .width(Length::Fill)
        .height(Length::Fill)
        .push(right_header)
        .push(widget::divider::horizontal::default())
        .push(reader);

    widget::row::with_capacity(2)
        .spacing(16)
        .width(Length::Fill)
        .height(Length::Fill)
        .push(left_pane)
        .push(right_pane)
        .into()
}
