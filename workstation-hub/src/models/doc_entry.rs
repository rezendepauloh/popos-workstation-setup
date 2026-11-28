use std::path::PathBuf;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DocSourceKind {
    PoposWorkstation,
    Homelab,
}

impl DocSourceKind {
    pub fn label(self) -> &'static str {
        match self {
            Self::PoposWorkstation => "Pop!_OS Workstation",
            Self::Homelab => "Homelab (umbrelOS)",
        }
    }

    pub fn badge_text(self) -> &'static str {
        match self {
            Self::PoposWorkstation => "POP!_OS",
            Self::Homelab => "HOMELAB",
        }
    }

    pub fn badge_colors(self) -> ([f32; 3], [f32; 3]) {
        match self {
            // (bg_rgb, fg_rgb)
            Self::PoposWorkstation => ([0.12, 0.16, 0.24], [0.58, 0.72, 0.90]),
            Self::Homelab => ([0.05, 0.29, 0.43], [0.49, 0.83, 0.99]),
        }
    }

    pub fn display_prefix(self) -> &'static str {
        match self {
            Self::PoposWorkstation => "Pop!_OS",
            Self::Homelab => "Homelab",
        }
    }

    pub fn sort_order(self) -> u8 {
        match self {
            Self::PoposWorkstation => 0,
            Self::Homelab => 1,
        }
    }
}

#[derive(Debug, Clone)]
pub struct DocEntryItem {
    pub title: String,
    pub emoji: String,
    pub file_name: String,
    pub relative_path: String,
    pub full_path: PathBuf,
    pub source_root: PathBuf,
    pub source_kind: DocSourceKind,
    pub category_key: String,
    pub category_label: String,
    pub badge_text: String,
    pub badge_bg: [f32; 3],
    pub badge_fg: [f32; 3],
    pub summary: String,
    pub last_modified_display: String,
    pub category_sort_order: u8,
    pub is_index_readme: bool,
    pub search_blob: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AlertKind {
    Note,
    Tip,
    Important,
    Warning,
    Caution,
}

impl AlertKind {
    pub fn from_tag(tag: &str) -> Option<Self> {
        match tag.trim().to_ascii_uppercase().as_str() {
            "NOTE" => Some(Self::Note),
            "TIP" => Some(Self::Tip),
            "IMPORTANT" => Some(Self::Important),
            "WARNING" => Some(Self::Warning),
            "CAUTION" => Some(Self::Caution),
            _ => None,
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Note => "ℹ️ Nota",
            Self::Tip => "💡 Dica",
            Self::Important => "📌 Importante",
            Self::Warning => "⚠️ Atenção",
            Self::Caution => "🚨 Cuidado",
        }
    }

    pub fn accent_rgb(self) -> [f32; 3] {
        match self {
            Self::Note => [0.22, 0.74, 0.97],      // sky-400
            Self::Tip => [0.20, 0.83, 0.60],       // emerald-400
            Self::Important => [0.65, 0.55, 0.98], // violet-400
            Self::Warning => [0.98, 0.75, 0.14],   // amber-400
            Self::Caution => [0.97, 0.44, 0.44],   // red-400
        }
    }

    pub fn bg_rgb(self) -> [f32; 3] {
        match self {
            Self::Note => [0.07, 0.14, 0.22],
            Self::Tip => [0.05, 0.18, 0.14],
            Self::Important => [0.14, 0.10, 0.24],
            Self::Warning => [0.22, 0.16, 0.06],
            Self::Caution => [0.24, 0.08, 0.09],
        }
    }

    pub fn css_class(self) -> &'static str {
        match self {
            Self::Note => "alert-note",
            Self::Tip => "alert-tip",
            Self::Important => "alert-important",
            Self::Warning => "alert-warning",
            Self::Caution => "alert-caution",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MarkdownInlineKind {
    Text,
    Bold,
    Italic,
    Strikethrough,
    Code,
    Kbd,
    Link,
    Badge,
    Image,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MarkdownInlineSpan {
    pub kind: MarkdownInlineKind,
    pub text: String,
    pub target_url: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MarkdownListItem {
    pub indent_level: usize,
    pub marker: String,
    pub checked: Option<bool>,
    pub inlines: Vec<MarkdownInlineSpan>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MarkdownBlock {
    Heading {
        level: u8,
        raw_text: String,
        inlines: Vec<MarkdownInlineSpan>,
    },
    Paragraph {
        inlines: Vec<MarkdownInlineSpan>,
    },
    CodeBlock {
        lang: String,
        code: String,
    },
    BlockQuote {
        alert: Option<AlertKind>,
        lines: Vec<String>,
    },
    List {
        items: Vec<MarkdownListItem>,
    },
    Table {
        headers: Vec<Vec<MarkdownInlineSpan>>,
        rows: Vec<Vec<Vec<MarkdownInlineSpan>>>,
    },
    HorizontalRule,
    Image {
        alt: String,
        src: String,
    },
    AttachmentCard {
        label: String,
        src: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MarkdownLinkResolution {
    InternalDocument { path: PathBuf, anchor: Option<String> },
    Anchor(String),
    ExternalHttpUrl(String),
    LocalImage(PathBuf),
    LocalAttachment(PathBuf),
    Unsupported(String),
}
