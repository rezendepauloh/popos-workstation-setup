use crate::models::doc_entry::{
    AlertKind, DocEntryItem, DocSourceKind, MarkdownBlock, MarkdownInlineKind, MarkdownInlineSpan,
    MarkdownLinkResolution, MarkdownListItem,
};
use chrono::{DateTime, Local};
use std::collections::BTreeSet;
use std::fs;
use std::path::{Component, Path, PathBuf};

pub const SOURCE_ALL: &str = "Todas as Origens";
pub const CATEGORY_ALL: &str = "Todas as Categorias";

const ALLOWED_IMAGE_EXTS: &[&str] = &["png", "jpg", "jpeg", "gif", "webp", "bmp"];
const ALLOWED_ATTACHMENT_EXTS: &[&str] = &[
    "pdf", "mp4", "mkv", "webm", "mov", "docx", "xlsx", "pptx", "csv", "txt", "sh", "py", "ps1",
    "rs", "toml", "json", "yaml", "yml", "conf", "service", "svg",
];

/// Verifica de forma fail-closed se `candidate` existe, não é symlink (nem atravessa symlinks dentro
/// de `allowed_root`), está contido estritamente dentro de `allowed_root` e possui extensão permitida.
pub fn is_safe_contained_path(
    allowed_root: &Path,
    candidate: &Path,
    allowed_exts: Option<&[&str]>,
) -> Option<PathBuf> {
    let canon_root = fs::canonicalize(allowed_root).ok()?;
    if !canon_root.is_dir() {
        return None;
    }

    // Rejeita symlinks no alvo final
    let meta = fs::symlink_metadata(candidate).ok()?;
    if meta.file_type().is_symlink() || !meta.is_file() {
        return None;
    }

    let canon_candidate = fs::canonicalize(candidate).ok()?;
    if !canon_candidate.starts_with(&canon_root) {
        return None;
    }

    // Rejeita qualquer diretório intermediário que seja symlink dentro da raiz
    let mut probe = PathBuf::new();
    for comp in candidate.components() {
        probe.push(comp);
        if probe.starts_with(allowed_root)
            && probe != allowed_root
            && let Ok(m) = fs::symlink_metadata(&probe)
            && m.file_type().is_symlink()
        {
            return None;
        }
    }

    if let Some(exts) = allowed_exts {
        let ext = canon_candidate
            .extension()
            .and_then(|e| e.to_str())
            .map(|e| e.to_ascii_lowercase())?;
        if !exts.iter().any(|allowed| *allowed == ext) {
            return None;
        }
    }

    Some(canon_candidate)
}

pub fn is_safe_doc_path(allowed_root: &Path, candidate: &Path) -> Option<PathBuf> {
    is_safe_contained_path(allowed_root, candidate, Some(&["md"]))
}

pub fn is_safe_image_path(allowed_root: &Path, candidate: &Path) -> Option<PathBuf> {
    is_safe_contained_path(allowed_root, candidate, Some(ALLOWED_IMAGE_EXTS))
}

pub fn is_safe_attachment_path(allowed_root: &Path, candidate: &Path) -> Option<PathBuf> {
    is_safe_contained_path(allowed_root, candidate, Some(ALLOWED_ATTACHMENT_EXTS))
}

pub fn read_document_content(allowed_root: &Path, full_path: &Path) -> Result<String, String> {
    let safe_path = is_safe_doc_path(allowed_root, full_path)
        .ok_or_else(|| "Caminho de documento inválido ou fora da raiz permitida.".to_string())?;
    fs::read_to_string(&safe_path).map_err(|e| format!("Falha ao ler arquivo: {e}"))
}

/// Descobre todos os documentos Markdown (`.md`) dos repositórios Pop!_OS e Homelab.
pub fn discover_all_documents(popos_repo: &Path, homelab_repo: &Path) -> Vec<DocEntryItem> {
    let mut docs = Vec::new();
    if popos_repo.is_dir() {
        collect_repo_docs(popos_repo, DocSourceKind::PoposWorkstation, &mut docs);
    }
    if homelab_repo.is_dir() && homelab_repo != popos_repo {
        collect_repo_docs(homelab_repo, DocSourceKind::Homelab, &mut docs);
    }

    docs.sort_by(|a, b| {
        a.source_kind
            .sort_order()
            .cmp(&b.source_kind.sort_order())
            .then_with(|| a.category_sort_order.cmp(&b.category_sort_order))
            .then_with(|| b.is_index_readme.cmp(&a.is_index_readme))
            .then_with(|| {
                a.title
                    .to_ascii_lowercase()
                    .cmp(&b.title.to_ascii_lowercase())
            })
            .then_with(|| a.relative_path.cmp(&b.relative_path))
    });
    docs
}

fn collect_repo_docs(root: &Path, source_kind: DocSourceKind, out: &mut Vec<DocEntryItem>) {
    let Ok(canon_root) = fs::canonicalize(root) else {
        return;
    };

    // Documentos na raiz do repositório (README.md, AGENTS.md)
    for top_file in ["README.md", "AGENTS.md"] {
        let candidate = root.join(top_file);
        if let Some(safe_path) = is_safe_doc_path(&canon_root, &candidate)
            && let Some(item) = build_doc_entry(&canon_root, &safe_path, source_kind)
        {
            out.push(item);
        }
    }

    // Subdiretório Docs/ recursivamente (sem seguir symlinks)
    let docs_dir = root.join("Docs");
    if let Ok(meta) = fs::symlink_metadata(&docs_dir)
        && !meta.file_type().is_symlink()
        && meta.is_dir()
    {
        let mut stack = vec![docs_dir];
        while let Some(dir) = stack.pop() {
            let Ok(entries) = fs::read_dir(&dir) else {
                continue;
            };
            for entry in entries.flatten() {
                let p = entry.path();
                let Ok(m) = fs::symlink_metadata(&p) else {
                    continue;
                };
                if m.file_type().is_symlink() {
                    continue;
                }
                if m.is_dir() {
                    let name = p.file_name().and_then(|s| s.to_str()).unwrap_or("");
                    if name.starts_with('.') || name == "target" || name == "node_modules" {
                        continue;
                    }
                    stack.push(p);
                } else if p.extension().is_some_and(|e| e.eq_ignore_ascii_case("md"))
                    && let Some(safe_path) = is_safe_doc_path(&canon_root, &p)
                    && let Some(item) = build_doc_entry(&canon_root, &safe_path, source_kind)
                {
                    out.push(item);
                }
            }
        }
    }
}

fn build_doc_entry(
    canon_root: &Path,
    safe_path: &Path,
    source_kind: DocSourceKind,
) -> Option<DocEntryItem> {
    let content = fs::read_to_string(safe_path).ok()?;
    let rel_path = safe_path
        .strip_prefix(canon_root)
        .ok()?
        .to_string_lossy()
        .replace('\\', "/");
    let file_name = safe_path
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("doc.md")
        .to_string();

    let category_key = extract_category_key(&rel_path);
    let (category_label, badge_text, badge_bg, badge_fg, category_sort_order, default_emoji) =
        category_metadata(&category_key);

    let (emoji, title) = extract_document_title(&content, &file_name, default_emoji);
    let summary = extract_document_summary(&content);
    let last_modified_display = fs::metadata(safe_path)
        .and_then(|m| m.modified())
        .ok()
        .map(|st| {
            let dt: DateTime<Local> = st.into();
            dt.format("%d/%m/%Y %H:%M").to_string()
        })
        .unwrap_or_default();

    let is_index_readme = file_name.eq_ignore_ascii_case("README.md");

    // Pré-computa blob de busca em minúsculas para pesquisa instantânea (título + caminho + conteúdo)
    let search_blob = format!(
        "{}\n{}\n{}\n{}\n{}\n{}",
        title, file_name, rel_path, category_label, summary, content
    )
    .to_ascii_lowercase();

    Some(DocEntryItem {
        title,
        emoji,
        file_name,
        relative_path: rel_path,
        full_path: safe_path.to_path_buf(),
        source_root: canon_root.to_path_buf(),
        source_kind,
        category_key,
        category_label: category_label.to_string(),
        badge_text: badge_text.to_string(),
        badge_bg,
        badge_fg,
        summary,
        last_modified_display,
        category_sort_order,
        is_index_readme,
        search_blob,
    })
}

fn extract_category_key(rel_path: &str) -> String {
    let lower = rel_path.to_ascii_lowercase();
    if !lower.contains('/') {
        return "raiz".to_string();
    }
    let parts: Vec<&str> = lower.split('/').collect();
    if parts.first() == Some(&"docs") {
        if parts.len() == 2 {
            return "indice".to_string();
        }
        return parts[1].to_string();
    }
    parts[0].to_string()
}

fn category_metadata(
    key: &str,
) -> (&'static str, &'static str, [f32; 3], [f32; 3], u8, &'static str) {
    match key {
        "raiz" => (
            "Raiz do Repositório",
            "RAIZ",
            [0.12, 0.23, 0.37],
            [0.49, 0.83, 0.99],
            0,
            "📘",
        ),
        "indice" => (
            "Índice Docs/",
            "ÍNDICE",
            [0.12, 0.23, 0.37],
            [0.49, 0.83, 0.99],
            1,
            "📚",
        ),
        "guias" => (
            "Guias & Manuais",
            "GUIA",
            [0.05, 0.25, 0.19],
            [0.29, 0.87, 0.65],
            2,
            "📖",
        ),
        "arquitetura" => (
            "Arquitetura",
            "ARQ",
            [0.19, 0.12, 0.34],
            [0.77, 0.71, 0.99],
            3,
            "🏛️",
        ),
        "issues" => (
            "Issues & Diagnósticos",
            "ISSUE",
            [0.32, 0.16, 0.06],
            [0.98, 0.75, 0.14],
            4,
            "🚨",
        ),
        "relatorios" => (
            "Relatórios & Auditorias",
            "RELATÓRIO",
            [0.28, 0.10, 0.16],
            [0.99, 0.64, 0.69],
            5,
            "📋",
        ),
        "planejamento" => (
            "Planejamento & Roadmap",
            "ROADMAP",
            [0.09, 0.20, 0.34],
            [0.58, 0.77, 0.99],
            6,
            "🗺️",
        ),
        _ => (
            "Documentação Geral",
            "DOC",
            [0.15, 0.18, 0.24],
            [0.72, 0.78, 0.86],
            9,
            "📄",
        ),
    }
}

pub fn available_sources(docs: &[DocEntryItem]) -> Vec<String> {
    let mut sources = vec![SOURCE_ALL.to_string()];
    if docs
        .iter()
        .any(|d| d.source_kind == DocSourceKind::PoposWorkstation)
    {
        sources.push(DocSourceKind::PoposWorkstation.label().to_string());
    }
    if docs.iter().any(|d| d.source_kind == DocSourceKind::Homelab) {
        sources.push(DocSourceKind::Homelab.label().to_string());
    }
    sources
}

pub fn available_categories(docs: &[DocEntryItem], selected_source: &str) -> Vec<String> {
    let mut seen: BTreeSet<(u8, String)> = BTreeSet::new();
    for doc in docs {
        if selected_source != SOURCE_ALL && doc.source_kind.label() != selected_source {
            continue;
        }
        seen.insert((doc.category_sort_order, doc.category_label.clone()));
    }
    let mut out = vec![CATEGORY_ALL.to_string()];
    for (_, label) in seen {
        out.push(label);
    }
    out
}

pub fn filter_documents<'a>(
    docs: &'a [DocEntryItem],
    search: &str,
    selected_source: &str,
    selected_category: &str,
) -> Vec<&'a DocEntryItem> {
    let needle = search.trim().to_ascii_lowercase();
    let terms: Vec<&str> = needle.split_whitespace().collect();

    docs.iter()
        .filter(|doc| {
            if selected_source != SOURCE_ALL && doc.source_kind.label() != selected_source {
                return false;
            }
            if selected_category != CATEGORY_ALL && doc.category_label != selected_category {
                return false;
            }
            if terms.is_empty() {
                return true;
            }
            terms.iter().all(|t| doc.search_blob.contains(t))
        })
        .collect()
}

fn extract_document_title(content: &str, file_name: &str, fallback_emoji: &str) -> (String, String) {
    for line in content.lines() {
        let trimmed = line.trim();
        if let Some(heading) = trimmed.strip_prefix("# ") {
            let clean = strip_inline_formatting(heading.trim());
            if !clean.is_empty() {
                return split_leading_emoji(&clean, fallback_emoji);
            }
        }
    }
    let stem = file_name.strip_suffix(".md").unwrap_or(file_name);
    (fallback_emoji.to_string(), humanize_identifier(stem))
}

fn split_leading_emoji(heading: &str, fallback_emoji: &str) -> (String, String) {
    let trimmed = heading.trim();
    if let Some((first_token, rest)) = trimmed.split_once(char::is_whitespace) {
        let has_non_ascii_symbol = first_token.chars().any(|c| !c.is_ascii_alphanumeric() && !c.is_ascii_punctuation());
        if has_non_ascii_symbol && first_token.chars().count() <= 4 && !rest.trim().is_empty() {
            return (first_token.to_string(), rest.trim().to_string());
        }
    }
    (fallback_emoji.to_string(), trimmed.to_string())
}

fn extract_document_summary(content: &str) -> String {
    let mut in_code = false;
    for raw_line in content.lines() {
        let trimmed = raw_line.trim();
        if trimmed.starts_with("```") || trimmed.starts_with("~~~") {
            in_code = !in_code;
            continue;
        }
        if in_code || trimmed.is_empty() || trimmed == "---" || trimmed == "***" {
            continue;
        }
        if trimmed.starts_with('#')
            || trimmed.starts_with('|')
            || trimmed.starts_with("[![")
            || trimmed.starts_with("![")
        {
            continue;
        }
        let candidate = trimmed.strip_prefix("> ").unwrap_or(trimmed).trim();
        if candidate.is_empty() || candidate.starts_with("[!") {
            continue;
        }
        let clean = strip_inline_formatting(candidate);
        if clean.len() < 12 {
            continue;
        }
        return truncate_chars(&clean, 125);
    }
    String::new()
}

fn truncate_chars(s: &str, max_chars: usize) -> String {
    if s.chars().count() <= max_chars {
        return s.to_string();
    }
    let truncated: String = s.chars().take(max_chars.saturating_sub(1)).collect();
    format!("{}…", truncated.trim_end())
}

fn humanize_identifier(raw: &str) -> String {
    raw.split(['_', '-'])
        .filter(|s| !s.is_empty())
        .map(|word| {
            let mut chars = word.chars();
            match chars.next() {
                Some(first) => format!("{}{}", first.to_uppercase(), chars.as_str()),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn strip_inline_formatting(text: &str) -> String {
    let spans = parse_inlines(text);
    let mut out = String::new();
    for sp in spans {
        out.push_str(&sp.text);
    }
    out.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// Resolve um link Markdown com segurança fail-closed.
pub fn resolve_markdown_link(
    source_root: &Path,
    current_doc: &Path,
    raw_href: &str,
) -> MarkdownLinkResolution {
    let href = raw_href.trim().trim_matches(|c| c == '<' || c == '>');
    if href.is_empty() {
        return MarkdownLinkResolution::Unsupported(String::new());
    }
    if href.starts_with('#') {
        return MarkdownLinkResolution::Anchor(href.to_string());
    }
    let lower = href.to_ascii_lowercase();
    if lower.starts_with("http://") || lower.starts_with("https://") {
        return MarkdownLinkResolution::ExternalHttpUrl(href.to_string());
    }

    let (path_part, anchor_part) = match href.split_once('#') {
        Some((p, a)) => (p.trim(), Some(format!("#{a}"))),
        None => (href, None),
    };
    if path_part.is_empty() {
        return MarkdownLinkResolution::Anchor(anchor_part.unwrap_or_default());
    }

    let decoded = percent_decode_simple(path_part);
    let rel_path = Path::new(&decoded);
    if rel_path.is_absolute() {
        return MarkdownLinkResolution::Unsupported(href.to_string());
    }

    let mut candidates = Vec::new();
    if let Some(parent) = current_doc.parent() {
        candidates.push(normalize_lexical(parent.join(rel_path)));
    }
    candidates.push(normalize_lexical(source_root.join(rel_path)));

    for cand in candidates {
        if let Some(safe_doc) = is_safe_doc_path(source_root, &cand) {
            return MarkdownLinkResolution::InternalDocument {
                path: safe_doc,
                anchor: anchor_part,
            };
        }
        if let Some(safe_img) = is_safe_image_path(source_root, &cand) {
            return MarkdownLinkResolution::LocalImage(safe_img);
        }
        if let Some(safe_att) = is_safe_attachment_path(source_root, &cand) {
            return MarkdownLinkResolution::LocalAttachment(safe_att);
        }
    }

    MarkdownLinkResolution::Unsupported(href.to_string())
}

fn normalize_lexical(path: PathBuf) -> PathBuf {
    let mut out = PathBuf::new();
    for comp in path.components() {
        match comp {
            Component::CurDir => {}
            Component::ParentDir => {
                out.pop();
            }
            other => out.push(other),
        }
    }
    out
}

fn percent_decode_simple(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%'
            && i + 2 < bytes.len()
            && let (Some(h), Some(l)) = (hex_val(bytes[i + 1]), hex_val(bytes[i + 2]))
        {
            out.push((h << 4) | l);
            i += 3;
            continue;
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8(out).unwrap_or_else(|_| input.to_string())
}

fn hex_val(b: u8) -> Option<u8> {
    match b {
        b'0'..=b'9' => Some(b - b'0'),
        b'a'..=b'f' => Some(b - b'a' + 10),
        b'A'..=b'F' => Some(b - b'A' + 10),
        _ => None,
    }
}

/// Faz parsing estruturado de Markdown em blocos semânticos (títulos, alertas, listas aninhadas,
/// tabelas, código, imagens locais e cards de anexo).
pub fn parse_markdown(markdown: &str) -> Vec<MarkdownBlock> {
    let lines: Vec<&str> = markdown.lines().collect();
    let mut blocks = Vec::new();
    let mut i = 0;

    while i < lines.len() {
        let raw = lines[i];
        let trimmed = raw.trim();

        if trimmed.is_empty() {
            i += 1;
            continue;
        }

        // Fenced code block (``` ou ~~~)
        if trimmed.starts_with("```") || trimmed.starts_with("~~~") {
            let fence_char = trimmed.chars().next().unwrap_or('`');
            let fence_len = trimmed.chars().take_while(|&c| c == fence_char).count();
            let lang = trimmed[fence_len..].trim().to_string();
            i += 1;
            let mut code = String::new();
            while i < lines.len() {
                let l = lines[i];
                let lt = l.trim();
                if lt.starts_with(fence_char)
                    && lt.chars().all(|c| c == fence_char)
                    && lt.len() >= fence_len
                {
                    i += 1;
                    break;
                }
                code.push_str(l);
                code.push('\n');
                i += 1;
            }
            blocks.push(MarkdownBlock::CodeBlock {
                lang,
                code: code.trim_end().to_string(),
            });
            continue;
        }

        // Horizontal rule
        if is_horizontal_rule(trimmed) {
            blocks.push(MarkdownBlock::HorizontalRule);
            i += 1;
            continue;
        }

        // Heading (# .. ####)
        if let Some((level, text)) = parse_heading_line(trimmed) {
            blocks.push(MarkdownBlock::Heading {
                level,
                raw_text: text.to_string(),
                inlines: parse_inlines(text),
            });
            i += 1;
            continue;
        }

        // Blockquote / GitHub Alert (> [!NOTE], > [!TIP], > [!IMPORTANT], > [!WARNING], > [!CAUTION])
        if trimmed == ">" || trimmed.starts_with("> ") {
            let mut q_lines = Vec::new();
            while i < lines.len() {
                let t = lines[i].trim();
                if t == ">" {
                    q_lines.push(String::new());
                    i += 1;
                } else if let Some(rest) = t.strip_prefix("> ") {
                    q_lines.push(rest.to_string());
                    i += 1;
                } else {
                    break;
                }
            }
            let mut alert = None;
            if let Some(first) = q_lines.first() {
                let ft = first.trim();
                if let Some(inner) = ft.strip_prefix("[!").and_then(|s| s.strip_suffix(']'))
                    && let Some(kind) = AlertKind::from_tag(inner)
                {
                    alert = Some(kind);
                    q_lines.remove(0);
                }
            }
            blocks.push(MarkdownBlock::BlockQuote {
                alert,
                lines: q_lines,
            });
            continue;
        }

        // Table
        if is_potential_table_row(trimmed)
            && i + 1 < lines.len()
            && is_table_separator(lines[i + 1].trim())
        {
            let headers = split_table_cells(trimmed)
                .into_iter()
                .map(|c| parse_inlines(&c))
                .collect();
            i += 2;
            let mut rows = Vec::new();
            while i < lines.len() {
                let row_t = lines[i].trim();
                if !is_potential_table_row(row_t) || is_table_separator(row_t) {
                    break;
                }
                rows.push(
                    split_table_cells(row_t)
                        .into_iter()
                        .map(|c| parse_inlines(&c))
                        .collect(),
                );
                i += 1;
            }
            blocks.push(MarkdownBlock::Table { headers, rows });
            continue;
        }

        // Standalone image: ![alt](src)
        if let Some((alt, src)) = parse_standalone_image(trimmed) {
            blocks.push(MarkdownBlock::Image { alt, src });
            i += 1;
            continue;
        }

        // Standalone local attachment link: [label](file.pdf)
        if let Some((label, src)) = parse_standalone_attachment_link(trimmed) {
            blocks.push(MarkdownBlock::AttachmentCard { label, src });
            i += 1;
            continue;
        }

        // List (bullets, ordered, checkboxes, nested indentation)
        if parse_list_item(raw).is_some() {
            let mut items = Vec::new();
            while i < lines.len() {
                if let Some(item) = parse_list_item(lines[i]) {
                    items.push(item);
                    i += 1;
                } else {
                    break;
                }
            }
            blocks.push(MarkdownBlock::List { items });
            continue;
        }

        // Regular paragraph (single line to preserve compact markdown rhythm)
        blocks.push(MarkdownBlock::Paragraph {
            inlines: parse_inlines(trimmed),
        });
        i += 1;
    }

    blocks
}

fn is_horizontal_rule(s: &str) -> bool {
    let compact: String = s.chars().filter(|c| !c.is_whitespace()).collect();
    compact.len() >= 3
        && (compact.chars().all(|c| c == '-')
            || compact.chars().all(|c| c == '*')
            || compact.chars().all(|c| c == '_'))
}

fn parse_heading_line(s: &str) -> Option<(u8, &str)> {
    let hashes = s.chars().take_while(|&c| c == '#').count();
    if (1..=6).contains(&hashes) {
        let rest = &s[hashes..];
        if let Some(after_space) = rest.strip_prefix(' ') {
            return Some((hashes.min(4) as u8, after_space.trim()));
        }
    }
    None
}

fn is_potential_table_row(s: &str) -> bool {
    s.starts_with('|') && s.ends_with('|') && s.len() >= 3
}

fn is_table_separator(s: &str) -> bool {
    s.starts_with('|')
        && s.contains('-')
        && s.chars()
            .all(|c| c == '|' || c == '-' || c == ':' || c == ' ')
}

fn split_table_cells(line: &str) -> Vec<String> {
    line.trim()
        .trim_matches('|')
        .split('|')
        .map(|s| s.trim().to_string())
        .collect()
}

fn parse_standalone_image(s: &str) -> Option<(String, String)> {
    if !s.starts_with("![") || !s.ends_with(')') {
        return None;
    }
    let mid = s[2..].find("](")?;
    let alt = &s[2..2 + mid];
    let rest = &s[2 + mid + 2..s.len() - 1];
    if rest.contains(')') {
        return None;
    }
    Some((alt.to_string(), rest.trim().to_string()))
}

fn parse_standalone_attachment_link(s: &str) -> Option<(String, String)> {
    if !s.starts_with('[') || s.starts_with("![") || s.starts_with("[![") || !s.ends_with(')') {
        return None;
    }
    let mid = s[1..].find("](")?;
    let label = &s[1..1 + mid];
    let src = s[1 + mid + 2..s.len() - 1].trim();
    if src.contains(')') || src.starts_with("http://") || src.starts_with("https://") || src.starts_with('#') {
        return None;
    }
    let ext = Path::new(src)
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_ascii_lowercase())?;
    if ALLOWED_ATTACHMENT_EXTS.contains(&ext.as_str()) {
        Some((label.to_string(), src.to_string()))
    } else {
        None
    }
}

fn parse_list_item(raw: &str) -> Option<MarkdownListItem> {
    let leading_spaces = raw
        .chars()
        .take_while(|&c| c == ' ' || c == '\t')
        .map(|c| if c == '\t' { 2 } else { 1 })
        .sum::<usize>();
    let indent_level = (leading_spaces / 2).min(4);
    let s = raw.trim_start();

    // Unordered list: "- ", "* ", "+ "
    if let Some(rest) = s
        .strip_prefix("- ")
        .or_else(|| s.strip_prefix("* "))
        .or_else(|| s.strip_prefix("+ "))
    {
        if let Some(task) = rest
            .strip_prefix("[x] ")
            .or_else(|| rest.strip_prefix("[X] "))
        {
            return Some(MarkdownListItem {
                indent_level,
                marker: "☑".to_string(),
                checked: Some(true),
                inlines: parse_inlines(task),
            });
        }
        if let Some(task) = rest.strip_prefix("[ ] ") {
            return Some(MarkdownListItem {
                indent_level,
                marker: "☐".to_string(),
                checked: Some(false),
                inlines: parse_inlines(task),
            });
        }
        return Some(MarkdownListItem {
            indent_level,
            marker: "•".to_string(),
            checked: None,
            inlines: parse_inlines(rest),
        });
    }

    // Ordered list: "1. ", "23. "
    let digits_len = s.chars().take_while(|c| c.is_ascii_digit()).count();
    if digits_len > 0 && digits_len <= 4 {
        let after_digits = &s[digits_len..];
        if let Some(rest) = after_digits.strip_prefix(". ") {
            return Some(MarkdownListItem {
                indent_level,
                marker: format!("{}.", &s[..digits_len]),
                checked: None,
                inlines: parse_inlines(rest),
            });
        }
    }

    None
}

/// Faz parsing de formatação inline: badges, imagens, `<kbd>`, `**bold**`, `~~strike~~`, `*italic*`,
/// `` `code` `` e `[links](url)`.
pub fn parse_inlines(text: &str) -> Vec<MarkdownInlineSpan> {
    let mut spans = Vec::new();
    let mut rest = text;

    while !rest.is_empty() {
        let badge_idx = rest.find("[![");
        let img_idx = rest.find("![");
        let kbd_idx = rest.find("<kbd>");
        let bold_idx = rest.find("**");
        let strike_idx = rest.find("~~");
        let code_idx = rest.find('`');
        let link_idx = rest.find('[');
        let italic_idx = find_italic_start(rest);

        let next_idx = [
            badge_idx, img_idx, kbd_idx, bold_idx, strike_idx, code_idx, link_idx, italic_idx,
        ]
        .into_iter()
        .flatten()
        .min();

        let Some(idx) = next_idx else {
            spans.push(MarkdownInlineSpan {
                kind: MarkdownInlineKind::Text,
                text: rest.to_string(),
                target_url: None,
            });
            break;
        };

        if idx > 0 {
            spans.push(MarkdownInlineSpan {
                kind: MarkdownInlineKind::Text,
                text: rest[..idx].to_string(),
                target_url: None,
            });
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
                        spans.push(MarkdownInlineSpan {
                            kind: MarkdownInlineKind::Badge,
                            text: label.to_string(),
                            target_url: Some(url.to_string()),
                        });
                        rest = &after_img[end_url + 1..];
                        continue;
                    }
                }
            }
            push_plain(&mut spans, "[![");
            rest = &rest[3..];
        } else if rest.starts_with("![") {
            if let Some(close_br) = rest[2..].find("](") {
                let label = &rest[2..2 + close_br];
                let after_br = &rest[2 + close_br + 2..];
                if let Some(close_par) = after_br.find(')') {
                    let src = &after_br[..close_par];
                    spans.push(MarkdownInlineSpan {
                        kind: MarkdownInlineKind::Image,
                        text: label.to_string(),
                        target_url: Some(src.to_string()),
                    });
                    rest = &after_br[close_par + 1..];
                    continue;
                }
            }
            push_plain(&mut spans, "![");
            rest = &rest[2..];
        } else if rest.starts_with("<kbd>") {
            if let Some(end) = rest[5..].find("</kbd>") {
                let inner = &rest[5..5 + end];
                spans.push(MarkdownInlineSpan {
                    kind: MarkdownInlineKind::Kbd,
                    text: inner.to_string(),
                    target_url: None,
                });
                rest = &rest[5 + end + 6..];
                continue;
            }
            push_plain(&mut spans, "<kbd>");
            rest = &rest[5..];
        } else if rest.starts_with("**") {
            if let Some(end) = rest[2..].find("**") {
                let inner = &rest[2..2 + end];
                // Permite código inline dentro de negrito (ex: **`comando`**)
                let mut sub = inner;
                while !sub.is_empty() {
                    if let Some(cs) = sub.find('`') {
                        if cs > 0 {
                            spans.push(MarkdownInlineSpan {
                                kind: MarkdownInlineKind::Bold,
                                text: sub[..cs].to_string(),
                                target_url: None,
                            });
                        }
                        if let Some(ce) = sub[cs + 1..].find('`') {
                            spans.push(MarkdownInlineSpan {
                                kind: MarkdownInlineKind::Code,
                                text: sub[cs + 1..cs + 1 + ce].to_string(),
                                target_url: None,
                            });
                            sub = &sub[cs + 1 + ce + 1..];
                            continue;
                        }
                        spans.push(MarkdownInlineSpan {
                            kind: MarkdownInlineKind::Bold,
                            text: sub[cs..].to_string(),
                            target_url: None,
                        });
                        break;
                    } else {
                        spans.push(MarkdownInlineSpan {
                            kind: MarkdownInlineKind::Bold,
                            text: sub.to_string(),
                            target_url: None,
                        });
                        break;
                    }
                }
                rest = &rest[2 + end + 2..];
                continue;
            }
            push_plain(&mut spans, "**");
            rest = &rest[2..];
        } else if rest.starts_with("~~") {
            if let Some(end) = rest[2..].find("~~") {
                let inner = &rest[2..2 + end];
                spans.push(MarkdownInlineSpan {
                    kind: MarkdownInlineKind::Strikethrough,
                    text: inner.to_string(),
                    target_url: None,
                });
                rest = &rest[2 + end + 2..];
                continue;
            }
            push_plain(&mut spans, "~~");
            rest = &rest[2..];
        } else if rest.starts_with('`') {
            if let Some(end) = rest[1..].find('`') {
                let inner = &rest[1..1 + end];
                spans.push(MarkdownInlineSpan {
                    kind: MarkdownInlineKind::Code,
                    text: inner.to_string(),
                    target_url: None,
                });
                rest = &rest[1 + end + 1..];
                continue;
            }
            push_plain(&mut spans, "`");
            rest = &rest[1..];
        } else if rest.starts_with('[') {
            if let Some(close_br) = rest[1..].find("](") {
                let label = &rest[1..1 + close_br];
                let after_br = &rest[1 + close_br + 2..];
                if let Some(close_par) = after_br.find(')') {
                    let url = &after_br[..close_par];
                    spans.push(MarkdownInlineSpan {
                        kind: MarkdownInlineKind::Link,
                        text: label.to_string(),
                        target_url: Some(url.to_string()),
                    });
                    rest = &after_br[close_par + 1..];
                    continue;
                }
            }
            push_plain(&mut spans, "[");
            rest = &rest[1..];
        } else if rest.starts_with('*') && !rest.starts_with("**") {
            if let Some(end) = rest[1..].find('*')
                && end > 0
                && !rest[1..1 + end].starts_with(' ')
                && !rest[1..1 + end].ends_with(' ')
            {
                spans.push(MarkdownInlineSpan {
                    kind: MarkdownInlineKind::Italic,
                    text: rest[1..1 + end].to_string(),
                    target_url: None,
                });
                rest = &rest[1 + end + 1..];
                continue;
            }
            push_plain(&mut spans, "*");
            rest = &rest[1..];
        } else {
            let ch = rest.chars().next().unwrap();
            let len = ch.len_utf8();
            push_plain(&mut spans, &rest[..len]);
            rest = &rest[len..];
        }
    }

    spans
}

fn find_italic_start(s: &str) -> Option<usize> {
    let bytes = s.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'*' {
            let prev_star = i > 0 && bytes[i - 1] == b'*';
            let next_star = i + 1 < bytes.len() && bytes[i + 1] == b'*';
            if !prev_star && !next_star && i + 1 < bytes.len() && bytes[i + 1] != b' ' {
                if let Some(end) = s[i + 1..].find('*')
                    && end > 0
                    && !s[i + 1..i + 1 + end].ends_with(' ')
                {
                    return Some(i);
                }
            }
        }
        i += 1;
    }
    None
}

fn push_plain(spans: &mut Vec<MarkdownInlineSpan>, s: &str) {
    spans.push(MarkdownInlineSpan {
        kind: MarkdownInlineKind::Text,
        text: s.to_string(),
        target_url: None,
    });
}

/// Exporta o documento atual para um arquivo HTML5 único e autocontido (offline), com barra
/// superior sticky (`☰ Índice` + `↑ Topo`), índice lateral com ScrollSpy, botão de copiar em blocos
/// de código, lightbox para imagens locais embutidas em Base64 e suporte a impressão.
pub fn export_standalone_html(doc: &DocEntryItem, raw_markdown: &str) -> String {
    let blocks = parse_markdown(raw_markdown);
    let mut body = String::new();
    let mut toc = String::new();
    let mut heading_idx = 0usize;

    for block in &blocks {
        match block {
            MarkdownBlock::Heading {
                level,
                raw_text,
                inlines,
            } => {
                let lvl = (*level).clamp(1, 4);
                heading_idx += 1;
                let hid = format!("sec-{heading_idx}");
                body.push_str(&format!(
                    "<h{lvl} id=\"{hid}\">{}</h{lvl}>\n",
                    render_html_inlines(inlines)
                ));
                if lvl <= 3 {
                    let toc_text = html_escape(&strip_inline_formatting(raw_text));
                    toc.push_str(&format!(
                        "<a class=\"toc-item toc-l{lvl}\" href=\"#{hid}\">{toc_text}</a>\n"
                    ));
                }
            }
            MarkdownBlock::Paragraph { inlines } => {
                body.push_str(&format!("<p>{}</p>\n", render_html_inlines(inlines)));
            }
            MarkdownBlock::CodeBlock { lang, code } => {
                let lang_html = if lang.is_empty() {
                    "TEXT".to_string()
                } else {
                    html_escape(&lang.to_ascii_uppercase())
                };
                body.push_str(&format!(
                    "<div class=\"code-card\"><div class=\"code-head\"><span class=\"code-lang\">{lang_html}</span><button type=\"button\" class=\"copy-btn\" onclick=\"copyCode(this)\">📋 Copiar</button></div><pre><code>{}</code></pre></div>\n",
                    html_escape(code)
                ));
            }
            MarkdownBlock::BlockQuote { alert, lines } => {
                let inner_md = lines.join("\n");
                let inner_blocks = parse_markdown(&inner_md);
                let mut inner_html = String::new();
                for ib in &inner_blocks {
                    if let MarkdownBlock::Paragraph { inlines } = ib {
                        inner_html.push_str(&format!("<p>{}</p>", render_html_inlines(inlines)));
                    } else if let MarkdownBlock::CodeBlock { code, .. } = ib {
                        inner_html.push_str(&format!(
                            "<pre><code>{}</code></pre>",
                            html_escape(code)
                        ));
                    } else if let MarkdownBlock::List { items } = ib {
                        inner_html.push_str(&render_html_list(items));
                    }
                }
                if let Some(kind) = alert {
                    body.push_str(&format!(
                        "<blockquote class=\"quote {}\"><div class=\"quote-badge\">{}</div>{}</blockquote>\n",
                        kind.css_class(),
                        html_escape(kind.label()),
                        inner_html
                    ));
                } else {
                    body.push_str(&format!("<blockquote class=\"quote\">{inner_html}</blockquote>\n"));
                }
            }
            MarkdownBlock::List { items } => {
                body.push_str(&render_html_list(items));
            }
            MarkdownBlock::Table { headers, rows } => {
                body.push_str("<div class=\"table-wrap\"><table><thead><tr>");
                for h in headers {
                    body.push_str(&format!("<th>{}</th>", render_html_inlines(h)));
                }
                body.push_str("</tr></thead><tbody>");
                for r in rows {
                    body.push_str("<tr>");
                    for c in r {
                        body.push_str(&format!("<td>{}</td>", render_html_inlines(c)));
                    }
                    body.push_str("</tr>");
                }
                body.push_str("</tbody></table></div>\n");
            }
            MarkdownBlock::HorizontalRule => {
                body.push_str("<hr />\n");
            }
            MarkdownBlock::Image { alt, src } => {
                body.push_str(&render_html_image(doc, alt, src));
            }
            MarkdownBlock::AttachmentCard { label, src } => {
                body.push_str(&format!(
                    "<div class=\"attach-card\">📎 <strong>{}</strong> <code>{}</code></div>\n",
                    html_escape(label),
                    html_escape(src)
                ));
            }
        }
    }

    let title_esc = html_escape(&doc.title);
    let path_esc = html_escape(&format!(
        "{}/{}",
        doc.source_kind.display_prefix(),
        doc.relative_path
    ));
    let date_esc = html_escape(&Local::now().format("%d/%m/%Y %H:%M").to_string());
    let toc_html = if toc.is_empty() {
        "<div class=\"toc-empty\">Sem seções numeradas</div>".to_string()
    } else {
        toc
    };

    format!(
        r##"<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover" />
  <title>{title_esc} — Workstation &amp; Homelab Hub</title>
  <style>
    :root {{ color-scheme: dark; --bg: #0b0f19; --card: #0f172a; --border: #1e293b; --accent: #38bdf8; --text: #e2e8f0; --muted: #94a3b8; }}
    * {{ box-sizing: border-box; }}
    html {{ scroll-behavior: smooth; }}
    body {{ font-family: system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif; background: var(--bg); color: var(--text); margin: 0; line-height: 1.6; overflow-x: hidden; }}
    .topbar {{ position: sticky; top: 0; z-index: 30; display: flex; align-items: center; gap: 10px; padding: 10px 14px; background: rgba(15,23,42,0.95); backdrop-filter: blur(8px); border-bottom: 1px solid var(--border); }}
    .topbar-btn {{ background: #1e293b; color: #f8fafc; border: 1px solid #334155; border-radius: 6px; padding: 6px 11px; font-size: 13px; font-weight: 600; cursor: pointer; white-space: nowrap; }}
    .topbar-btn:hover {{ background: #334155; }}
    .topbar-title {{ flex: 1; min-width: 0; font-size: 14px; font-weight: 600; color: #f8fafc; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }}
    .layout {{ display: flex; width: 100%; min-height: calc(100vh - 52px); }}
    .toc-drawer {{ width: 280px; flex-shrink: 0; background: #0d1424; border-right: 1px solid var(--border); padding: 14px 12px; position: sticky; top: 52px; height: calc(100vh - 52px); overflow-y: auto; }}
    body.toc-collapsed .toc-drawer {{ display: none; }}
    .toc-header {{ font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: .06em; color: var(--muted); padding: 0 8px 10px; border-bottom: 1px solid var(--border); margin-bottom: 8px; }}
    .toc-item {{ display: block; padding: 6px 8px; margin: 2px 0; border-radius: 6px; border-left: 3px solid transparent; color: #cbd5e1; text-decoration: none; font-size: 13px; line-height: 1.35; overflow-wrap: anywhere; transition: background 0.15s ease, color 0.15s ease, border-color 0.15s ease; }}
    .toc-item:hover {{ background: #162238; color: var(--accent); text-decoration: none; }}
    .toc-item.active {{ background: #1e293b; color: var(--accent); border-left-color: var(--accent); font-weight: 600; text-decoration: none; }}
    .toc-l1 {{ font-weight: 700; color: #f8fafc; }}
    .toc-l2 {{ padding-left: 14px; }}
    .toc-l3 {{ padding-left: 24px; font-size: 12px; color: var(--muted); }}
    .toc-empty {{ font-size: 12px; color: var(--muted); padding: 8px; }}
    .toc-backdrop {{ display: none; position: fixed; inset: 0; background: rgba(0,0,0,0.55); z-index: 35; }}
    .content-wrap {{ flex: 1; min-width: 0; padding: 20px 18px 40px; }}
    main {{ max-width: 880px; margin: 0 auto; background: var(--card); border: 1px solid var(--border); border-radius: 12px; padding: 24px 28px; overflow-wrap: anywhere; }}
    .meta {{ display: flex; flex-wrap: wrap; gap: 6px 14px; font-family: 'JetBrains Mono', ui-monospace, monospace; font-size: 11.5px; color: var(--muted); border-bottom: 1px solid var(--border); padding-bottom: 12px; margin-bottom: 18px; overflow-wrap: anywhere; }}
    h1, h2, h3, h4 {{ color: #f8fafc; margin-top: 1.4em; scroll-margin-top: 68px; line-height: 1.3; }}
    h1 {{ font-size: 1.65rem; border-bottom: 1px solid #334155; padding-bottom: 8px; margin-top: 0; }}
    h2 {{ font-size: 1.3rem; color: var(--accent); border-bottom: 1px solid var(--border); padding-bottom: 4px; }}
    h3 {{ font-size: 1.1rem; color: #93c5fd; }}
    a {{ color: var(--accent); text-decoration: none; overflow-wrap: anywhere; }}
    a:hover {{ text-decoration: underline; }}
    code {{ font-family: 'JetBrains Mono', ui-monospace, monospace; background: #1e293b; color: #7dd3fc; padding: 2px 6px; border-radius: 4px; font-size: 0.88em; overflow-wrap: anywhere; }}
    kbd {{ background: #1e293b; color: #fde68a; border: 1px solid #475569; border-radius: 4px; padding: 1px 6px; font-family: ui-monospace, monospace; font-size: 0.85em; }}
    .code-card {{ background: #070b14; border: 1px solid var(--border); border-radius: 8px; margin: 14px 0; overflow: hidden; }}
    .code-head {{ display: flex; justify-content: space-between; align-items: center; background: #1e293b; padding: 5px 10px; }}
    .code-lang {{ color: var(--accent); font-family: ui-monospace, monospace; font-size: 11px; font-weight: 700; }}
    .copy-btn {{ background: #0f172a; color: #e2e8f0; border: 1px solid #334155; border-radius: 4px; padding: 2px 8px; font-size: 11px; cursor: pointer; }}
    pre {{ margin: 0; padding: 12px 14px; overflow-x: auto; }}
    pre code {{ background: transparent; color: var(--text); padding: 0; overflow-wrap: normal; }}
    blockquote.quote {{ --q-accent: #38bdf8; --q-bg: #0f172a; margin: 14px 0; padding: 10px 14px; border: 1px solid var(--q-accent); border-left: 4px solid var(--q-accent); background: var(--q-bg); border-radius: 6px; color: #cbd5e1; }}
    blockquote.alert-note {{ --q-accent: #38bdf8; --q-bg: #0c192c; }}
    blockquote.alert-tip {{ --q-accent: #34d399; --q-bg: #071f1a; }}
    blockquote.alert-important {{ --q-accent: #a78bfa; --q-bg: #1a1433; }}
    blockquote.alert-warning {{ --q-accent: #fbbf24; --q-bg: #271c09; }}
    blockquote.alert-caution {{ --q-accent: #f87171; --q-bg: #2a1215; }}
    .quote-badge {{ font-size: 11.5px; font-weight: 700; margin-bottom: 4px; color: var(--q-accent); letter-spacing: .02em; }}
    ul {{ padding-left: 22px; }}
    .table-wrap {{ overflow-x: auto; margin: 14px 0; border-radius: 6px; }}
    table {{ width: 100%; border-collapse: collapse; font-size: 0.9rem; }}
    th, td {{ border: 1px solid #334155; padding: 8px 10px; text-align: left; }}
    th {{ background: #1e293b; color: #f8fafc; }}
    tr:nth-child(even) td {{ background: #111827; }}
    figure.img-card {{ margin: 16px 0; padding: 10px; background: #070b14; border: 1px solid var(--border); border-radius: 8px; text-align: center; }}
    figure.img-card img {{ max-width: 100%; height: auto; border-radius: 4px; cursor: zoom-in; }}
    figure.img-card figcaption {{ margin-top: 8px; font-size: 12px; color: var(--muted); }}
    .attach-card {{ background: #111c32; border: 1px solid #1e3a8a; border-radius: 8px; padding: 10px 14px; margin: 12px 0; }}
    hr {{ border: 0; border-top: 1px solid var(--border); margin: 18px 0; }}
    .lightbox {{ display: none; position: fixed; inset: 0; z-index: 60; background: rgba(0,0,0,0.9); align-items: center; justify-content: center; padding: 16px; cursor: zoom-out; }}
    .lightbox.open {{ display: flex; }}
    .lightbox img {{ max-width: 96vw; max-height: 92vh; border-radius: 6px; }}
    @media (max-width: 899px) {{
      .toc-drawer {{ position: fixed; top: 0; left: 0; bottom: 0; height: 100vh; z-index: 40; width: 82vw; max-width: 310px; transform: translateX(-105%); box-shadow: 4px 0 24px rgba(0,0,0,0.5); }}
      body.toc-mobile-open .toc-drawer {{ transform: translateX(0); }}
      body.toc-mobile-open .toc-backdrop {{ display: block; }}
      .content-wrap {{ padding: 12px 10px 32px; }}
      main {{ padding: 16px 14px; border-radius: 10px; }}
    }}
    @media print {{ .topbar, .toc-drawer, .toc-backdrop, .copy-btn, .lightbox {{ display: none !important; }} body {{ background: #fff; color: #111; }} main {{ background: #fff; border: 0; padding: 0; }} }}
  </style>
</head>
<body>
  <header class="topbar">
    <button type="button" class="topbar-btn" id="btnToggleToc" aria-label="Abrir ou ocultar índice">☰ Índice</button>
    <div class="topbar-title">{title_esc}</div>
    <button type="button" class="topbar-btn" onclick="window.scrollTo({{top:0,behavior:'smooth'}})">↑ Topo</button>
  </header>
  <div class="toc-backdrop" id="tocBackdrop"></div>
  <div class="layout">
    <aside class="toc-drawer" id="tocDrawer" aria-label="Índice do documento">
      <div class="toc-header">📑 Seções do Documento</div>
      {toc_html}
    </aside>
    <div class="content-wrap">
      <main>
        <div class="meta"><span>📄 {path_esc}</span><span>🕒 Exportado em {date_esc}</span></div>
        {body}
      </main>
    </div>
  </div>
  <div class="lightbox" id="imgLightbox" onclick="this.classList.remove('open')"><img id="imgLightboxTarget" alt="" /></div>
  <script>
    (function () {{
      const btn = document.getElementById('btnToggleToc');
      const backdrop = document.getElementById('tocBackdrop');
      const drawer = document.getElementById('tocDrawer');
      const isMobile = () => window.innerWidth < 900;
      function toggleToc() {{
        if (isMobile()) document.body.classList.toggle('toc-mobile-open');
        else document.body.classList.toggle('toc-collapsed');
      }}
      function closeMobileToc() {{ document.body.classList.remove('toc-mobile-open'); }}
      btn.addEventListener('click', toggleToc);
      backdrop.addEventListener('click', closeMobileToc);
      drawer.querySelectorAll('a.toc-item').forEach(a => a.addEventListener('click', () => {{
        const targetId = (a.getAttribute('href') || '').replace(/^#/, '');
        if (targetId) setActiveToc(targetId, false);
        if (isMobile()) closeMobileToc();
      }}));
      const headings = Array.from(document.querySelectorAll('main h1[id], main h2[id], main h3[id]'));
      const tocLinks = Array.from(drawer.querySelectorAll('a.toc-item[href^="#"]'));
      let lastActiveId = '';
      function setActiveToc(id, autoScroll) {{
        if (!id || id === lastActiveId) return;
        lastActiveId = id;
        tocLinks.forEach(link => {{
          const isMatch = link.getAttribute('href') === '#' + id;
          link.classList.toggle('active', isMatch);
          if (isMatch && autoScroll && !document.body.classList.contains('toc-collapsed')) {{
            const top = link.offsetTop;
            if (top < drawer.scrollTop || top + link.offsetHeight > drawer.scrollTop + drawer.clientHeight) {{
              link.scrollIntoView({{ behavior: 'smooth', block: 'nearest' }});
            }}
          }}
        }});
      }}
      function updateActiveSection() {{
        if (headings.length === 0 || tocLinks.length === 0) return;
        const scrollY = window.scrollY || document.documentElement.scrollTop;
        const docHeight = document.documentElement.scrollHeight;
        let currentId = headings[0].id;
        if (scrollY + window.innerHeight >= docHeight - 15) {{
          currentId = headings[headings.length - 1].id;
        }} else {{
          for (let i = 0; i < headings.length; i++) {{
            if (headings[i].getBoundingClientRect().top <= 110) {{
              currentId = headings[i].id;
            }} else {{
              break;
            }}
          }}
        }}
        setActiveToc(currentId, true);
      }}
      window.addEventListener('scroll', updateActiveSection, {{ passive: true }});
      window.addEventListener('resize', updateActiveSection, {{ passive: true }});
      updateActiveSection();
      document.querySelectorAll('figure.img-card img').forEach(img => {{
        img.addEventListener('click', () => {{
          document.getElementById('imgLightboxTarget').src = img.src;
          document.getElementById('imgLightbox').classList.add('open');
        }});
      }});
    }})();
    function copyCode(btn) {{
      const code = btn.closest('.code-card').querySelector('code').innerText;
      if (navigator.clipboard) navigator.clipboard.writeText(code).then(() => {{ btn.textContent = '✅ Copiado'; setTimeout(() => btn.textContent = '📋 Copiar', 1500); }});
    }}
  </script>
</body>
</html>
"##
    )
}

fn render_html_list(items: &[MarkdownListItem]) -> String {
    let mut out = String::from("<ul>\n");
    for item in items {
        let pad = item.indent_level * 18;
        let prefix = if let Some(checked) = item.checked {
            if checked { "☑ " } else { "☐ " }
        } else if item.marker != "•" {
            &item.marker
        } else {
            ""
        };
        let sep = if !prefix.is_empty() && !prefix.ends_with(' ') {
            " "
        } else {
            ""
        };
        out.push_str(&format!(
            "<li style=\"margin-left:{pad}px\">{prefix}{sep}{}</li>\n",
            render_html_inlines(&item.inlines)
        ));
    }
    out.push_str("</ul>\n");
    out
}

fn render_html_inlines(spans: &[MarkdownInlineSpan]) -> String {
    let mut out = String::new();
    for sp in spans {
        let esc = html_escape(&sp.text);
        match sp.kind {
            MarkdownInlineKind::Text => out.push_str(&esc),
            MarkdownInlineKind::Bold => out.push_str(&format!("<strong>{esc}</strong>")),
            MarkdownInlineKind::Italic => out.push_str(&format!("<em>{esc}</em>")),
            MarkdownInlineKind::Strikethrough => out.push_str(&format!("<del>{esc}</del>")),
            MarkdownInlineKind::Code => out.push_str(&format!("<code>{esc}</code>")),
            MarkdownInlineKind::Kbd => out.push_str(&format!("<kbd>{esc}</kbd>")),
            MarkdownInlineKind::Badge => out.push_str(&format!("<code>[{esc}]</code>")),
            MarkdownInlineKind::Image => out.push_str(&format!("<em>[{esc}]</em>")),
            MarkdownInlineKind::Link => {
                if let Some(url) = &sp.target_url {
                    let lower = url.to_ascii_lowercase();
                    if lower.starts_with("http://") || lower.starts_with("https://") || lower.starts_with('#') {
                        out.push_str(&format!(
                            "<a href=\"{}\" target=\"_blank\" rel=\"noopener noreferrer\">{esc}</a>",
                            html_escape(url)
                        ));
                    } else {
                        out.push_str(&format!("<span>{esc}</span>"));
                    }
                } else {
                    out.push_str(&esc);
                }
            }
        }
    }
    out
}

fn render_html_image(doc: &DocEntryItem, alt: &str, src: &str) -> String {
    let alt_esc = html_escape(alt);
    if let MarkdownLinkResolution::LocalImage(path) =
        resolve_markdown_link(&doc.source_root, &doc.full_path, src)
        && let Ok(bytes) = fs::read(&path)
    {
        let mime = match path
            .extension()
            .and_then(|e| e.to_str())
            .map(|e| e.to_ascii_lowercase())
            .as_deref()
        {
            Some("png") => "image/png",
            Some("jpg") | Some("jpeg") => "image/jpeg",
            Some("gif") => "image/gif",
            Some("webp") => "image/webp",
            Some("bmp") => "image/bmp",
            _ => "application/octet-stream",
        };
        let b64 = encode_base64(&bytes);
        return format!(
            "<figure class=\"img-card\"><img src=\"data:{mime};base64,{b64}\" alt=\"{alt_esc}\" /><figcaption>{alt_esc}</figcaption></figure>\n"
        );
    }
    format!("<p><em>🖼️ [{alt_esc}] ({})</em></p>\n", html_escape(src))
}

fn html_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for ch in s.chars() {
        match ch {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            _ => out.push(ch),
        }
    }
    out
}

fn encode_base64(input: &[u8]) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(input.len().div_ceil(3) * 4);
    for chunk in input.chunks(3) {
        let b0 = chunk[0] as u32;
        let b1 = if chunk.len() > 1 { chunk[1] as u32 } else { 0 };
        let b2 = if chunk.len() > 2 { chunk[2] as u32 } else { 0 };
        let n = (b0 << 16) | (b1 << 8) | b2;
        out.push(TABLE[((n >> 18) & 63) as usize] as char);
        out.push(TABLE[((n >> 12) & 63) as usize] as char);
        out.push(if chunk.len() > 1 {
            TABLE[((n >> 6) & 63) as usize] as char
        } else {
            '='
        });
        out.push(if chunk.len() > 2 {
            TABLE[(n & 63) as usize] as char
        } else {
            '='
        });
    }
    out
}
