use crate::models::env_entry::{EnvTarget, EnvVarItem, is_secret_key};
use crate::services::input_validator::{validate_env_key, validate_env_value};
use std::collections::HashMap;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone)]
pub struct LoadedEnvFile {
    pub target: EnvTarget,
    pub path: PathBuf,
    pub loaded_from_example: bool,
    pub entries: Vec<EnvVarItem>,
}

pub fn resolve_env_paths(repo_root: &Path, target: EnvTarget) -> (PathBuf, PathBuf) {
    match target {
        EnvTarget::Popos => (repo_root.join(".env"), repo_root.join(".env.example")),
        EnvTarget::Homelab => (
            repo_root.join("config.env"),
            repo_root.join("config.env.example"),
        ),
    }
}

pub fn load_env_file(repo_root: &Path, target: EnvTarget) -> Result<LoadedEnvFile, String> {
    let (primary, example) = resolve_env_paths(repo_root, target);
    let (read_path, loaded_from_example) = if primary.exists() {
        ensure_not_symlink(&primary)?;
        (primary.clone(), false)
    } else if example.exists() {
        ensure_not_symlink(&example)?;
        (example.clone(), true)
    } else {
        return Err(format!(
            "Nenhum arquivo .env ou .example encontrado em {}",
            repo_root.display()
        ));
    };

    let content = fs::read_to_string(&read_path)
        .map_err(|e| format!("Erro ao ler {}: {e}", read_path.display()))?;
    let mut entries = parse_env_content(&content);

    // Merge newly added template keys and enrich section/comment metadata from .example
    if !loaded_from_example && example.exists() && ensure_not_symlink(&example).is_ok()
        && let Ok(ex_content) = fs::read_to_string(&example)
    {
        let ex_entries = parse_env_content(&ex_content);
        let ex_meta: HashMap<String, (String, String)> = ex_entries
            .iter()
            .map(|e| (e.key.clone(), (e.section.clone(), e.comment.clone())))
            .collect();

        for item in &mut entries {
            if let Some((sec, cmt)) = ex_meta.get(&item.key) {
                if !sec.is_empty() && sec != "Geral" {
                    item.section = sec.clone();
                }
                if item.comment.is_empty() && !cmt.is_empty() {
                    item.comment = cmt.clone();
                }
            }
        }

        let existing_keys: std::collections::HashSet<String> =
            entries.iter().map(|e| e.key.clone()).collect();
        for ex_item in ex_entries {
            if !existing_keys.contains(&ex_item.key) {
                entries.push(ex_item);
            }
        }
    }

    Ok(LoadedEnvFile {
        target,
        path: primary,
        loaded_from_example,
        entries,
    })
}

pub fn parse_env_content(content: &str) -> Vec<EnvVarItem> {
    let mut entries = Vec::new();
    let mut current_section = String::from("Geral");
    let mut pending_comments: Vec<String> = Vec::new();

    for raw_line in content.lines() {
        let trimmed = raw_line.trim();
        if trimmed.is_empty() {
            pending_comments.clear();
            continue;
        }
        if trimmed.starts_with('#') {
            let clean_comment = trimmed.trim_start_matches('#').trim();
            if !clean_comment.starts_with("===") && !clean_comment.starts_with("---") {
                if looks_like_section_header(clean_comment) {
                    current_section = clean_comment.to_string();
                    pending_comments.clear();
                } else if !clean_comment.is_empty() {
                    // Also handle commented-out KEY=VALUE templates in .env.example
                    if let Some((k, v)) = split_assignment(clean_comment)
                        && validate_env_key(k).is_ok()
                    {
                        entries.push(EnvVarItem {
                            key: k.to_string(),
                            value: strip_outer_quotes(v),
                            comment: "Opcional (descomentado ao salvar)".to_string(),
                            section: current_section.clone(),
                            is_secret: is_secret_key(k),
                            revealed: false,
                        });
                    } else {
                        pending_comments.push(clean_comment.to_string());
                    }
                }
            }
            continue;
        }

        if let Some((key, val)) = split_assignment(trimmed)
            && validate_env_key(key).is_ok()
        {
            entries.push(EnvVarItem {
                key: key.to_string(),
                value: strip_outer_quotes(val),
                comment: pending_comments.join(" · "),
                section: current_section.clone(),
                is_secret: is_secret_key(key),
                revealed: false,
            });
            pending_comments.clear();
        }
    }

    entries
}

/// Atomically saves `.env` / `config.env` preserving existing comments and enforcing `chmod 0600`.
pub fn save_env_file(repo_root: &Path, target: EnvTarget, entries: &[EnvVarItem]) -> Result<PathBuf, String> {
    let (dest_path, example_path) = resolve_env_paths(repo_root, target);
    if dest_path.exists() {
        ensure_not_symlink(&dest_path)?;
    }

    let mut updates: HashMap<&str, &str> = HashMap::new();
    for item in entries {
        validate_env_key(&item.key)?;
        validate_env_value(&item.value)?;
        updates.insert(item.key.as_str(), item.value.as_str());
    }

    let base_content = if dest_path.exists() {
        fs::read_to_string(&dest_path)
            .map_err(|e| format!("Falha ao ler {}: {e}", dest_path.display()))?
    } else if example_path.exists() {
        fs::read_to_string(&example_path)
            .map_err(|e| format!("Falha ao ler {}: {e}", example_path.display()))?
    } else {
        String::new()
    };

    let mut written_keys = std::collections::HashSet::new();
    let mut output_lines: Vec<String> = Vec::new();

    for raw_line in base_content.lines() {
        let trimmed = raw_line.trim();
        if !trimmed.is_empty()
            && !trimmed.starts_with('#')
            && let Some((key, _)) = split_assignment(trimmed)
            && let Some(new_val) = updates.get(key)
        {
            output_lines.push(format_assignment(key, new_val));
            written_keys.insert(key.to_string());
            continue;
        }
        output_lines.push(raw_line.to_string());
    }

    for item in entries {
        if !written_keys.contains(&item.key) && !item.value.is_empty() {
            output_lines.push(format_assignment(&item.key, &item.value));
        }
    }

    let final_content = format!("{}\n", output_lines.join("\n"));

    let parent = dest_path
        .parent()
        .ok_or_else(|| "Diretório pai inválido.".to_string())?;
    let tmp_name = format!(
        ".{}.tmp.{}",
        dest_path
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("env"),
        std::process::id()
    );
    let tmp_path = parent.join(tmp_name);
    let _ = fs::remove_file(&tmp_path);

    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&tmp_path)
        .map_err(|e| format!("Erro ao criar arquivo temporário seguro: {e}"))?;

    file.set_permissions(fs::Permissions::from_mode(0o600))
        .map_err(|e| format!("Erro ao aplicar permissão 0600: {e}"))?;
    file.write_all(final_content.as_bytes())
        .map_err(|e| format!("Erro ao gravar {}: {e}", tmp_path.display()))?;
    file.sync_all()
        .map_err(|e| format!("Erro ao sincronizar disco: {e}"))?;
    drop(file);

    fs::rename(&tmp_path, &dest_path)
        .map_err(|e| format!("Erro ao finalizar gravação em {}: {e}", dest_path.display()))?;
    fs::set_permissions(&dest_path, fs::Permissions::from_mode(0o600))
        .map_err(|e| format!("Erro ao garantir 0600 em {}: {e}", dest_path.display()))?;

    Ok(dest_path)
}

/// Reads quick `KEY -> value` map without mutating anything (used for Homelab host/user discovery).
pub fn read_env_map(path: &Path) -> HashMap<String, String> {
    let mut map = HashMap::new();
    if ensure_not_symlink(path).is_err() {
        return map;
    }
    let Ok(content) = fs::read_to_string(path) else {
        return map;
    };
    for item in parse_env_content(&content) {
        map.insert(item.key, item.value);
    }
    map
}

fn ensure_not_symlink(path: &Path) -> Result<(), String> {
    if let Ok(meta) = fs::symlink_metadata(path)
        && meta.file_type().is_symlink()
    {
        return Err(format!(
            "Bloqueado por segurança: {} é um link simbólico.",
            path.display()
        ));
    }
    Ok(())
}

fn looks_like_section_header(text: &str) -> bool {
    text.chars().next().is_some_and(|c| c.is_ascii_digit() && text.contains('.'))
        || (text.len() >= 6 && text == text.to_uppercase() && text.chars().any(|c| c.is_alphabetic()))
}

fn split_assignment(line: &str) -> Option<(&str, &str)> {
    let (k, v) = line.split_once('=')?;
    let k = k.trim();
    if k.is_empty() {
        return None;
    }
    Some((k, v.trim()))
}

fn strip_outer_quotes(raw: &str) -> String {
    let trimmed = raw.trim();
    if trimmed.len() >= 2
        && ((trimmed.starts_with('"') && trimmed.ends_with('"'))
            || (trimmed.starts_with('\'') && trimmed.ends_with('\'')))
    {
        trimmed[1..trimmed.len() - 1].to_string()
    } else {
        trimmed.to_string()
    }
}

fn format_assignment(key: &str, value: &str) -> String {
    if value.contains('\'') {
        let escaped = value.replace('"', "\\\"");
        format!("{key}=\"{escaped}\"")
    } else if value.starts_with('{') || value.contains('$') {
        format!("{key}='{value}'")
    } else {
        let escaped = value.replace('"', "\\\"");
        format!("{key}=\"{escaped}\"")
    }
}
