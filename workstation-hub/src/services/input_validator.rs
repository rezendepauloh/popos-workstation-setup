use std::path::{Path, PathBuf};

/// Validates a Pop!_OS setup module filename (`NN_name.sh`).
pub fn validate_module_filename(name: &str) -> Result<(), String> {
    if name.len() < 6 || !name.ends_with(".sh") {
        return Err(format!("Nome de módulo inválido: {name}"));
    }
    let bytes = name.as_bytes();
    if !bytes[0].is_ascii_digit() || !bytes[1].is_ascii_digit() || bytes[2] != b'_' {
        return Err(format!("Prefixo numérico inválido em módulo: {name}"));
    }
    let stem = &name[3..name.len() - 3];
    if stem.is_empty()
        || !stem
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_')
    {
        return Err(format!("Caracteres inválidos no módulo: {name}"));
    }
    Ok(())
}

/// Validates a generic service/stack/host identifier against safe ASCII characters.
pub fn validate_identifier(value: &str) -> Result<(), String> {
    if value.is_empty() || value.len() > 128 {
        return Err("Identificador vazio ou longo demais.".to_string());
    }
    if !value
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-' | ':'))
    {
        return Err(format!("Identificador contém caracteres proibidos: {value}"));
    }
    if value.starts_with('-') {
        return Err(format!("Identificador não pode iniciar com '-': {value}"));
    }
    Ok(())
}

/// Validates `.env` variable name (`^[A-Za-z_][A-Za-z0-9_]*$`).
pub fn validate_env_key(key: &str) -> Result<(), String> {
    let mut chars = key.chars();
    let Some(first) = chars.next() else {
        return Err("Chave de variável vazia.".to_string());
    };
    if !(first.is_ascii_alphabetic() || first == '_') {
        return Err(format!("Chave inválida: {key}"));
    }
    if !chars.all(|c| c.is_ascii_alphanumeric() || c == '_') {
        return Err(format!("Chave contém caracteres inválidos: {key}"));
    }
    Ok(())
}

/// Validates `.env` variable value (disallows control/newline injection).
pub fn validate_env_value(value: &str) -> Result<(), String> {
    if value.contains('\n') || value.contains('\r') || value.contains('\0') {
        return Err("Valor não pode conter quebras de linha ou byte nulo.".to_string());
    }
    Ok(())
}

/// Resolves a relative script path strictly inside `repo_root` (fail-closed against path traversal).
pub fn resolve_safe_script(repo_root: &Path, rel_path: &str) -> Result<PathBuf, String> {
    if rel_path.is_empty() || rel_path.starts_with('/') || rel_path.contains("..") {
        return Err(format!("Caminho relativo inseguro: {rel_path}"));
    }
    let root_canon = repo_root
        .canonicalize()
        .map_err(|e| format!("Repositório inválido ({}): {e}", repo_root.display()))?;
    let candidate = root_canon.join(rel_path);
    let canon = candidate
        .canonicalize()
        .map_err(|e| format!("Script não encontrado ({}): {e}", candidate.display()))?;
    if !canon.starts_with(&root_canon) {
        return Err(format!(
            "Acesso negado fora do repositório: {}",
            canon.display()
        ));
    }
    if !canon.is_file() {
        return Err(format!("Alvo não é um arquivo regular: {}", canon.display()));
    }
    Ok(canon)
}
