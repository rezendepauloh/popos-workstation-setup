use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

pub fn progress_file_path(popos_repo: &Path) -> PathBuf {
    popos_repo.join("Logs").join(".setup_progress.log")
}

pub fn read_completed_flags(popos_repo: &Path) -> HashSet<String> {
    let path = progress_file_path(popos_repo);
    let Ok(content) = fs::read_to_string(path) else {
        return HashSet::new();
    };
    content
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .map(ToString::to_string)
        .collect()
}

pub fn clear_flag(popos_repo: &Path, flag_name: &str) -> Result<(), String> {
    let path = progress_file_path(popos_repo);
    if !path.exists() {
        return Ok(());
    }
    let content = fs::read_to_string(&path)
        .map_err(|e| format!("Erro ao ler {}: {e}", path.display()))?;
    let filtered: Vec<&str> = content
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && *l != flag_name)
        .collect();
    let new_content = if filtered.is_empty() {
        String::new()
    } else {
        format!("{}\n", filtered.join("\n"))
    };
    fs::write(&path, new_content)
        .map_err(|e| format!("Erro ao atualizar {}: {e}", path.display()))
}

pub fn clear_all_flags(popos_repo: &Path) -> Result<(), String> {
    let path = progress_file_path(popos_repo);
    if path.exists() {
        fs::remove_file(&path)
            .map_err(|e| format!("Erro ao remover {}: {e}", path.display()))?;
    }
    Ok(())
}
