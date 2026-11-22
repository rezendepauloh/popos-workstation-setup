use crate::models::log_entry::{AnsiColor, LogLine, LogSegment};

#[derive(Debug, Clone, Copy)]
struct StyleState {
    color: AnsiColor,
    bold: bool,
}

impl Default for StyleState {
    fn default() -> Self {
        Self {
            color: AnsiColor::Default,
            bold: false,
        }
    }
}

/// Parses a single line containing ANSI CSI SGR sequences (`\x1b[...m`) into styled segments.
pub fn parse_ansi_line(raw: &str) -> LogLine {
    // Handle carriage return overwrites (spinners/progress bars) by taking the final visible segment
    let clean_raw = if let Some(pos) = raw.rfind('\r') {
        let after = &raw[pos + 1..];
        if after.trim().is_empty() {
            raw[..pos].trim_end_matches('\r')
        } else {
            after
        }
    } else {
        raw
    };

    let mut segments: Vec<LogSegment> = Vec::new();
    let mut style = StyleState::default();
    let mut current = String::new();
    let bytes = clean_raw.as_bytes();
    let mut i = 0;

    while i < bytes.len() {
        if bytes[i] == 0x1b && i + 1 < bytes.len() && bytes[i + 1] == b'[' {
            // Flush accumulated text
            if !current.is_empty() {
                segments.push(LogSegment {
                    text: std::mem::take(&mut current),
                    color: style.color,
                    bold: style.bold,
                });
            }
            // Scan until final CSI byte (0x40..=0x7e)
            let mut j = i + 2;
            while j < bytes.len() && !(0x40..=0x7e).contains(&bytes[j]) {
                j += 1;
            }
            if j < bytes.len() {
                if bytes[j] == b'm' {
                    let params = std::str::from_utf8(&bytes[i + 2..j]).unwrap_or("");
                    apply_sgr_params(params, &mut style);
                }
                i = j + 1;
                continue;
            }
        }

        // Advance UTF-8 char
        if let Some(ch) = clean_raw[i..].chars().next() {
            if !ch.is_control() || ch == '\t' {
                current.push(ch);
            }
            i += ch.len_utf8();
        } else {
            i += 1;
        }
    }

    if !current.is_empty() {
        segments.push(LogSegment {
            text: current,
            color: style.color,
            bold: style.bold,
        });
    }

    if segments.is_empty() {
        LogLine::plain("", AnsiColor::Default, false)
    } else {
        LogLine { segments }
    }
}

fn apply_sgr_params(params: &str, style: &mut StyleState) {
    if params.is_empty() {
        *style = StyleState::default();
        return;
    }
    for token in params.split(';') {
        match token.parse::<u16>() {
            Ok(0) => *style = StyleState::default(),
            Ok(1) => style.bold = true,
            Ok(22) => style.bold = false,
            Ok(2) | Ok(90) => style.color = AnsiColor::Muted,
            Ok(31) | Ok(91) => style.color = AnsiColor::Red,
            Ok(32) | Ok(92) => style.color = AnsiColor::Green,
            Ok(33) | Ok(93) => style.color = AnsiColor::Yellow,
            Ok(34) | Ok(94) => style.color = AnsiColor::Blue,
            Ok(35) | Ok(95) => style.color = AnsiColor::Magenta,
            Ok(36) | Ok(96) => style.color = AnsiColor::Cyan,
            Ok(37) | Ok(39) | Ok(97) => style.color = AnsiColor::Default,
            _ => {}
        }
    }
}
