#[derive(Debug, Clone)]
pub struct EnvVarItem {
    pub key: String,
    pub value: String,
    pub comment: String,
    pub section: String,
    pub is_secret: bool,
    pub revealed: bool,
}

pub fn is_secret_key(key: &str) -> bool {
    let upper = key.to_ascii_uppercase();
    upper.contains("PASS")
        || upper.contains("TOKEN")
        || upper.contains("SECRET")
        || upper.contains("KEY")
        || upper.contains("CERT")
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EnvTarget {
    Popos,
    Homelab,
}

impl EnvTarget {
    pub fn label(self) -> &'static str {
        match self {
            Self::Popos => "Workstation (.env)",
            Self::Homelab => "Homelab (config.env)",
        }
    }
}
