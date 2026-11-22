use crate::models::status::HubPaths;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

fn config_file_path() -> Option<PathBuf> {
    dirs::config_dir().map(|d| d.join("workstation-hub").join("paths.json"))
}

pub fn discover_paths() -> HubPaths {
    if let Some(saved) = load_saved_paths()
        && saved.popos_repo.join("setup_popos.sh").is_file()
    {
        return saved;
    }

    let popos_repo = discover_popos_repo();
    let homelab_repo = discover_homelab_repo(&popos_repo);

    HubPaths {
        popos_repo,
        homelab_repo,
    }
}

fn discover_popos_repo() -> PathBuf {
    if let Ok(env_dir) = std::env::var("WORKSTATION_HUB_POPOS_DIR") {
        let p = PathBuf::from(env_dir);
        if p.join("setup_popos.sh").is_file() {
            return p;
        }
    }

    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    if let Some(parent) = manifest_dir.parent()
        && parent.join("setup_popos.sh").is_file()
    {
        return parent.to_path_buf();
    }

    if let Ok(cwd) = std::env::current_dir() {
        for ancestor in cwd.ancestors() {
            if ancestor.join("setup_popos.sh").is_file() {
                return ancestor.to_path_buf();
            }
        }
    }

    if let Some(home) = dirs::home_dir() {
        for candidate in [
            home.join("Documentos/DevProjects/Bash/popos-workstation-setup"),
            home.join("Documents/DevProjects/Bash/popos-workstation-setup"),
            home.join("popos-workstation-setup"),
        ] {
            if candidate.join("setup_popos.sh").is_file() {
                return candidate;
            }
        }
        return home.join("Documentos/DevProjects/Bash/popos-workstation-setup");
    }

    PathBuf::from(".")
}

fn discover_homelab_repo(popos_repo: &Path) -> PathBuf {
    if let Ok(env_dir) = std::env::var("WORKSTATION_HUB_HOMELAB_DIR") {
        let p = PathBuf::from(env_dir);
        if p.join("setup_umbrelos.sh").is_file() {
            return p;
        }
    }

    if let Some(parent) = popos_repo.parent() {
        let sibling = parent.join("umbrelos-scripts");
        if sibling.join("setup_umbrelos.sh").is_file() {
            return sibling;
        }
    }

    if let Some(home) = dirs::home_dir() {
        for candidate in [
            home.join("Documentos/DevProjects/Bash/umbrelos-scripts"),
            home.join("Documents/DevProjects/Bash/umbrelos-scripts"),
            home.join("umbrelos-scripts"),
        ] {
            if candidate.join("setup_umbrelos.sh").is_file() {
                return candidate;
            }
        }
        return home.join("Documentos/DevProjects/Bash/umbrelos-scripts");
    }

    PathBuf::from("../umbrelos-scripts")
}

pub fn load_saved_paths() -> Option<HubPaths> {
    let path = config_file_path()?;
    let content = fs::read_to_string(path).ok()?;
    serde_json::from_str(&content).ok()
}

pub fn save_paths(paths: &HubPaths) -> Result<(), String> {
    let cfg_path = config_file_path().ok_or_else(|| "Diretório de configuração indisponível.".to_string())?;
    let parent = cfg_path
        .parent()
        .ok_or_else(|| "Caminho pai inválido.".to_string())?;
    fs::create_dir_all(parent).map_err(|e| format!("Erro ao criar {}: {e}", parent.display()))?;
    let json = serde_json::to_string_pretty(paths)
        .map_err(|e| format!("Erro ao serializar caminhos: {e}"))?;

    let mut file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .open(&cfg_path)
        .map_err(|e| format!("Erro ao salvar {}: {e}", cfg_path.display()))?;
    file.set_permissions(fs::Permissions::from_mode(0o600))
        .map_err(|e| format!("Erro ao aplicar permissão 0600: {e}"))?;
    file.write_all(json.as_bytes())
        .map_err(|e| format!("Erro ao gravar configuração: {e}"))?;
    Ok(())
}

pub fn is_valid_popos_repo(path: &Path) -> bool {
    path.join("setup_popos.sh").is_file() && path.join("scripts").is_dir()
}

pub fn is_valid_homelab_repo(path: &Path) -> bool {
    path.join("setup_umbrelos.sh").is_file() && path.join("scripts").is_dir()
}
