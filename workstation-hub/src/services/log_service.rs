use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::Path;

pub const MAX_LOG_FILE_BYTES: u64 = 3 * 1024 * 1024; // 3 MB

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HubExecutionRecord {
    pub timestamp: String,
    pub label: String,
    pub body: String,
}

/// Parses `=== [timestamp] EXEC: label ===` blocks from `workstation-hub.log` (newest first).
pub fn parse_hub_executions(logs_dir: &Path) -> Vec<HubExecutionRecord> {
    let active = logs_dir.join("workstation-hub.log");
    let Ok(content) = fs::read_to_string(&active) else {
        return Vec::new();
    };

    let mut records = Vec::new();
    let mut current_ts = String::new();
    let mut current_label = String::new();
    let mut current_lines: Vec<&str> = Vec::new();

    for line in content.lines() {
        if let Some(rest) = line.strip_prefix("=== [")
            && let Some((ts, after_ts)) = rest.split_once("] EXEC: ")
            && let Some(label) = after_ts.strip_suffix(" ===")
        {
            if !current_label.is_empty() {
                records.push(HubExecutionRecord {
                    timestamp: std::mem::take(&mut current_ts),
                    label: std::mem::take(&mut current_label),
                    body: current_lines.join("\n").trim().to_string(),
                });
                current_lines.clear();
            }
            current_ts = ts.to_string();
            current_label = label.to_string();
            continue;
        }
        if !current_label.is_empty() {
            current_lines.push(line);
        }
    }

    if !current_label.is_empty() {
        records.push(HubExecutionRecord {
            timestamp: current_ts,
            label: current_label,
            body: current_lines.join("\n").trim().to_string(),
        });
    }

    records.reverse();
    records
}

pub fn delete_hub_execution(
    logs_dir: &Path,
    target_timestamp: &str,
    target_label: &str,
) -> Result<(), String> {
    let target_header = format!("=== [{target_timestamp}] EXEC: {target_label} ===");
    for fname in [
        "workstation-hub.log",
        "workstation-hub.log.1",
        "workstation-hub.log.2",
    ] {
        let p = logs_dir.join(fname);
        let Ok(raw) = fs::read_to_string(&p) else {
            continue;
        };
        let mut out = String::with_capacity(raw.len());
        let mut skipping = false;
        let mut changed = false;
        for line in raw.lines() {
            let trimmed = line.trim();
            if trimmed.starts_with("=== [") && trimmed.contains("] EXEC: ") && trimmed.ends_with(" ===") {
                if trimmed == target_header && !changed {
                    skipping = true;
                    changed = true;
                    continue;
                }
                skipping = false;
            }
            if !skipping {
                out.push_str(line);
                out.push('\n');
            }
        }
        if changed {
            fs::write(&p, out).map_err(|e| format!("Falha ao atualizar {}: {e}", p.display()))?;
            return Ok(());
        }
    }
    Ok(())
}

pub fn clear_hub_executions(logs_dir: &Path) -> Result<(), String> {
    for fname in [
        "workstation-hub.log",
        "workstation-hub.log.1",
        "workstation-hub.log.2",
    ] {
        let p = logs_dir.join(fname);
        if p.exists() {
            fs::remove_file(&p)
                .map_err(|e| format!("Falha ao remover {}: {e}", p.display()))?;
        }
    }
    Ok(())
}

pub fn append_rotated_log(logs_dir: &Path, label: &str, content: &str) -> Result<(), String> {
    append_rotated_log_with_limit(logs_dir, label, content, MAX_LOG_FILE_BYTES)
}

pub fn append_rotated_log_with_limit(
    logs_dir: &Path,
    label: &str,
    content: &str,
    max_bytes: u64,
) -> Result<(), String> {
    fs::create_dir_all(logs_dir)
        .map_err(|e| format!("Erro ao criar diretório de logs {}: {e}", logs_dir.display()))?;

    let active = logs_dir.join("workstation-hub.log");
    let rot1 = logs_dir.join("workstation-hub.1.log");
    let rot2 = logs_dir.join("workstation-hub.2.log");

    let ts = chrono::Local::now().format("%Y-%m-%d %H:%M:%S");
    let block = format!("=== [{ts}] EXEC: {label} ===\n{content}\n\n");

    let current_size = fs::metadata(&active).map(|m| m.len()).unwrap_or(0);
    if current_size > 0 && current_size + block.len() as u64 > max_bytes {
        if rot2.exists() {
            let _ = fs::remove_file(&rot2);
        }
        if rot1.exists() {
            let _ = fs::rename(&rot1, &rot2);
        }
        let _ = fs::rename(&active, &rot1);
    }

    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(&active)
        .map_err(|e| format!("Erro ao abrir {}: {e}", active.display()))?;
    file.write_all(block.as_bytes())
        .map_err(|e| format!("Erro ao gravar log: {e}"))?;
    Ok(())
}
