#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AnsiColor {
    Default,
    Red,
    Green,
    Yellow,
    Blue,
    Magenta,
    Cyan,
    Muted,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LogSegment {
    pub text: String,
    pub color: AnsiColor,
    pub bold: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LogLine {
    pub segments: Vec<LogSegment>,
}

impl LogLine {
    pub fn plain(text: impl Into<String>, color: AnsiColor, bold: bool) -> Self {
        Self {
            segments: vec![LogSegment {
                text: text.into(),
                color,
                bold,
            }],
        }
    }

    pub fn as_plain_text(&self) -> String {
        let mut out = String::new();
        for seg in &self.segments {
            out.push_str(&seg.text);
        }
        out
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RunStatus {
    Idle,
    Running { label: String },
    Succeeded { label: String, duration_ms: u128 },
    Failed { label: String, exit_code: i32, duration_ms: u128 },
}
