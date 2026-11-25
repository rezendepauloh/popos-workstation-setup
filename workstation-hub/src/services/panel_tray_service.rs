use crate::models::status::{
    ManagedIndicatorInfo, PanelAndTrayInfo, PanelAppletInfo, PanelSegment, TrayItemInfo,
};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;
use tokio::process::Command;

fn cosmic_panel_dir() -> PathBuf {
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("/tmp"))
        .join("cosmic/com.system76.CosmicPanel.Panel/v1")
}

fn parse_ron_string_list(text: &str) -> Vec<String> {
    let mut items = Vec::new();
    let mut in_quotes = false;
    let mut escaped = false;
    let mut current = String::new();
    for ch in text.chars() {
        if escaped {
            current.push(ch);
            escaped = false;
            continue;
        }
        if ch == '\\' && in_quotes {
            escaped = true;
            continue;
        }
        if ch == '"' {
            if in_quotes {
                if !current.is_empty() {
                    items.push(current.clone());
                    current.clear();
                }
                in_quotes = false;
            } else {
                in_quotes = true;
            }
        } else if in_quotes {
            current.push(ch);
        }
    }
    items
}

pub fn parse_panel_wings(raw: &str) -> (Vec<String>, Vec<String>) {
    if let Some((left, right)) = raw.split_once("],") {
        (parse_ron_string_list(left), parse_ron_string_list(right))
    } else {
        (Vec::new(), parse_ron_string_list(raw))
    }
}

pub fn parse_panel_center(raw: &str) -> Vec<String> {
    parse_ron_string_list(raw)
}

fn format_ron_array(items: &[String]) -> String {
    if items.is_empty() {
        return "[]".to_string();
    }
    let mut out = String::from("[\n");
    for item in items {
        out.push_str(&format!("    \"{item}\",\n"));
    }
    out.push(']');
    out
}

pub fn set_applet_segment(applet_id: &str, target: PanelSegment) -> Result<(), String> {
    let dir = cosmic_panel_dir();
    if !dir.exists() {
        return Err(format!(
            "Diretório do Painel COSMIC não encontrado: {}",
            dir.display()
        ));
    }

    let wings_path = dir.join("plugins_wings");
    let center_path = dir.join("plugins_center");

    let wings_raw = fs::read_to_string(&wings_path).unwrap_or_default();
    let center_raw = fs::read_to_string(&center_path).unwrap_or_default();

    let (mut start, mut end) = parse_panel_wings(&wings_raw);
    let mut center = parse_panel_center(&center_raw);

    start.retain(|id| id != applet_id);
    center.retain(|id| id != applet_id);
    end.retain(|id| id != applet_id);

    match target {
        PanelSegment::Start => start.push(applet_id.to_string()),
        PanelSegment::Center => center.push(applet_id.to_string()),
        PanelSegment::End => end.push(applet_id.to_string()),
        PanelSegment::Hidden => {}
    }

    let wings_out = format!(
        "Some(({}, {}))\n",
        format_ron_array(&start),
        format_ron_array(&end)
    );
    let center_out = format!("Some({})\n", format_ron_array(&center));

    fs::write(&wings_path, wings_out)
        .map_err(|e| format!("Falha ao gravar plugins_wings: {e}"))?;
    fs::write(&center_path, center_out)
        .map_err(|e| format!("Falha ao gravar plugins_center: {e}"))?;
    Ok(())
}

struct DesktopEntryMeta {
    name: String,
    comment: String,
    icon: String,
    is_cosmic_applet: bool,
}

fn find_icon_file(icon_name: &str) -> String {
    let trimmed = icon_name.trim();
    if trimmed.is_empty() {
        return String::new();
    }
    if Path::new(trimmed).is_absolute() && Path::new(trimmed).exists() {
        return trimmed.to_string();
    }

    let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("/home"));
    let search_roots = [
        home.join(".local/share/icons"),
        home.join(".local/share/flatpak/exports/share/icons"),
        PathBuf::from("/usr/share/icons/Cosmic"),
        PathBuf::from("/usr/share/icons/hicolor"),
        PathBuf::from("/usr/share/pixmaps"),
        PathBuf::from("/var/lib/flatpak/exports/share/icons"),
    ];

    for root in &search_roots {
        if !root.exists() {
            continue;
        }
        for ext in ["svg", "png"] {
            let fname = format!("{trimmed}.{ext}");
            for sub in [
                "",
                "hicolor/scalable/apps",
                "hicolor/48x48/apps",
                "hicolor/64x64/apps",
                "hicolor/128x128/apps",
                "scalable/apps",
                "48x48/apps",
                "64x64/apps",
                "24x24/apps",
                "scalable/status",
            ] {
                let p = if sub.is_empty() {
                    root.join(&fname)
                } else {
                    root.join(sub).join(&fname)
                };
                if p.is_file() {
                    return p.to_string_lossy().to_string();
                }
            }
        }
    }

    trimmed.to_string()
}

fn parse_desktop_file(path: &Path) -> Option<DesktopEntryMeta> {
    let content = fs::read_to_string(path).ok()?;
    let mut in_desktop_entry = false;
    let mut name_default = String::new();
    let mut name_pt = String::new();
    let mut name_pt_br = String::new();
    let mut comment_default = String::new();
    let mut comment_pt = String::new();
    let mut comment_pt_br = String::new();
    let mut icon = String::new();
    let mut is_cosmic_applet = false;

    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with('[') {
            in_desktop_entry = trimmed == "[Desktop Entry]";
            continue;
        }
        if !in_desktop_entry || trimmed.starts_with('#') || trimmed.is_empty() {
            continue;
        }
        let Some((k, v)) = trimmed.split_once('=') else {
            continue;
        };
        let key = k.trim();
        let val = v.trim();
        match key {
            "Name" => name_default = val.to_string(),
            "Name[pt]" => name_pt = val.to_string(),
            "Name[pt_BR]" => name_pt_br = val.to_string(),
            "Comment" => comment_default = val.to_string(),
            "Comment[pt]" => comment_pt = val.to_string(),
            "Comment[pt_BR]" => comment_pt_br = val.to_string(),
            "Icon" => icon = val.to_string(),
            "X-CosmicApplet" => is_cosmic_applet = val.eq_ignore_ascii_case("true"),
            _ => {}
        }
    }

    let name = if !name_pt_br.is_empty() {
        name_pt_br
    } else if !name_pt.is_empty() {
        name_pt
    } else {
        name_default
    };
    if name.is_empty() {
        return None;
    }

    let comment = if !comment_pt_br.is_empty() {
        comment_pt_br
    } else if !comment_pt.is_empty() {
        comment_pt
    } else {
        comment_default
    };

    Some(DesktopEntryMeta {
        name,
        comment,
        icon,
        is_cosmic_applet,
    })
}

fn load_desktop_applets() -> HashMap<String, DesktopEntryMeta> {
    let mut map = HashMap::new();
    let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("/home"));
    let dirs_to_scan = [
        PathBuf::from("/usr/share/applications"),
        PathBuf::from("/usr/local/share/applications"),
        home.join(".local/share/applications"),
        home.join(".local/share/flatpak/exports/share/applications"),
        PathBuf::from("/var/lib/flatpak/exports/share/applications"),
    ];

    for dir in dirs_to_scan {
        let Ok(entries) = fs::read_dir(&dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let p = entry.path();
            if p.extension().is_some_and(|e| e == "desktop")
                && let Some(stem) = p.file_stem().and_then(|s| s.to_str())
                && let Some(mut meta) = parse_desktop_file(&p)
                && (meta.is_cosmic_applet
                    || stem.contains("CosmicApplet")
                    || stem.contains("CosmicPanel")
                    || stem.contains("YapCap"))
            {
                meta.icon = find_icon_file(&meta.icon);
                map.insert(stem.to_string(), meta);
            }
        }
    }
    map
}

fn extract_gdbus_str_prop(output: &str, key: &str) -> String {
    let needle = format!("'{key}': <'");
    if let Some(after) = output.split(&needle).nth(1)
        && let Some(val) = after.split("'>").next()
    {
        return val.to_string();
    }
    String::new()
}

fn map_sni_unit(id: &str, title: &str) -> Option<String> {
    let k = format!("{} {}", id.to_ascii_lowercase(), title.to_ascii_lowercase());
    if k.contains("espanso") {
        Some("espanso-indicator.service".to_string())
    } else if k.contains("gdrive") || k.contains("google drive") {
        Some("gdrive-indicator.service".to_string())
    } else if k.contains("onedrive-pessoal") || k.contains("onedrive pessoal") {
        Some("onedrive-pessoal-indicator.service".to_string())
    } else if k.contains("onedrive") {
        Some("onedrive-indicator.service".to_string())
    } else if k.contains("mega") {
        Some("mega-indicator.service".to_string())
    } else {
        None
    }
}

fn fallback_sni_icon(id: &str, title: &str, raw_icon: &str) -> String {
    if !raw_icon.trim().is_empty() {
        return find_icon_file(raw_icon);
    }
    let key = format!("{} {}", id.to_ascii_lowercase(), title.to_ascii_lowercase());
    let candidate = if key.contains("copyq") {
        "copyq"
    } else if key.contains("openrgb") {
        "org.openrgb.OpenRGB"
    } else if key.contains("nextcloud") {
        "com.nextcloud.desktopclient.nextcloud"
    } else if key.contains("sunshine") {
        "dev.lizardbyte.app.Sunshine"
    } else if key.contains("artcraft") {
        "ai.storyteller.artcraft-launcher"
    } else if key.contains("kando") {
        "kando"
    } else if key.contains("kde connect") {
        "kdeconnect"
    } else if key.contains("remmina") {
        "org.remmina.Remmina"
    } else {
        "application-x-executable-symbolic"
    };
    find_icon_file(candidate)
}

async fn probe_tray_items() -> Vec<TrayItemInfo> {
    let Ok(Ok(out)) = tokio::time::timeout(
        Duration::from_secs(2),
        Command::new("gdbus")
            .args([
                "call",
                "--session",
                "--dest",
                "org.kde.StatusNotifierWatcher",
                "--object-path",
                "/StatusNotifierWatcher",
                "--method",
                "org.freedesktop.DBus.Properties.Get",
                "org.kde.StatusNotifierWatcher",
                "RegisteredStatusNotifierItems",
            ])
            .output(),
    )
    .await
    else {
        return Vec::new();
    };
    if !out.status.success() {
        return Vec::new();
    }

    let raw = String::from_utf8_lossy(&out.stdout);
    let mut targets = Vec::new();
    for part in raw.split('\'') {
        let s = part.trim();
        if s.starts_with(':') || s.starts_with("org.") || s.starts_with("com.") {
            let (bus, path) = if let Some((b, p)) = s.split_once('/') {
                (b.to_string(), format!("/{p}"))
            } else {
                (s.to_string(), "/StatusNotifierItem".to_string())
            };
            targets.push((bus, path));
        }
    }

    let mut futs = Vec::with_capacity(targets.len());
    for (bus, path) in targets {
        futs.push(async move {
            let Ok(Ok(prop_out)) = tokio::time::timeout(
                Duration::from_secs(1),
                Command::new("gdbus")
                    .args([
                        "call",
                        "--session",
                        "--dest",
                        &bus,
                        "--object-path",
                        &path,
                        "--method",
                        "org.freedesktop.DBus.Properties.GetAll",
                        "org.kde.StatusNotifierItem",
                    ])
                    .output(),
            )
            .await
            else {
                return None;
            };
            if !prop_out.status.success() {
                return None;
            }
            let text = String::from_utf8_lossy(&prop_out.stdout);
            let id = extract_gdbus_str_prop(&text, "Id");
            let mut title = extract_gdbus_str_prop(&text, "Title");
            if title.is_empty() {
                title = if id.is_empty() { bus.clone() } else { id.clone() };
            }
            let raw_icon = extract_gdbus_str_prop(&text, "IconName");
            let icon = fallback_sni_icon(&id, &title, &raw_icon);
            let status = extract_gdbus_str_prop(&text, "Status");
            let systemd_unit = map_sni_unit(&id, &title);
            Some(TrayItemInfo {
                bus_name: bus,
                object_path: path,
                id,
                title,
                icon,
                status: if status.is_empty() { "Active".to_string() } else { status },
                systemd_unit,
            })
        });
    }

    futures::future::join_all(futs)
        .await
        .into_iter()
        .flatten()
        .collect()
}

async fn probe_managed_indicators() -> Vec<ManagedIndicatorInfo> {
    let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("/home"));
    let specs = vec![
        (
            "espanso-indicator.service",
            "Espanso (Snippets)",
            "/usr/share/pixmaps/espanso.png".to_string(),
        ),
        (
            "gdrive-indicator.service",
            "Google Drive Pessoal",
            home.join(".local/share/icons/hicolor/48x48/apps/google-drive.png")
                .to_string_lossy()
                .to_string(),
        ),
        (
            "onedrive-pessoal-indicator.service",
            "OneDrive Pessoal",
            home.join(".local/share/icons/hicolor/48x48/apps/onedrive-pessoal.png")
                .to_string_lossy()
                .to_string(),
        ),
        (
            "mega-indicator.service",
            "MEGA Pessoal",
            home.join(".local/share/icons/hicolor/48x48/apps/mega.png")
                .to_string_lossy()
                .to_string(),
        ),
        (
            "onedrive-indicator.service",
            "OneDrive MPMS",
            home.join(".local/share/icons/hicolor/48x48/apps/onedrive.png")
                .to_string_lossy()
                .to_string(),
        ),
    ];

    let mut out = Vec::with_capacity(specs.len());
    for (unit, label, icon_path) in specs {
        let active = tokio::time::timeout(
            Duration::from_secs(1),
            Command::new("systemctl")
                .args(["--user", "is-active", unit])
                .output(),
        )
        .await
        .is_ok_and(|r| r.is_ok_and(|o| o.status.success()));

        out.push(ManagedIndicatorInfo {
            unit: unit.to_string(),
            label: label.to_string(),
            icon: find_icon_file(&icon_path),
            active,
        });
    }
    out
}

pub async fn probe_panel_and_tray() -> PanelAndTrayInfo {
    let dir = cosmic_panel_dir();
    let wings_raw = fs::read_to_string(dir.join("plugins_wings")).unwrap_or_default();
    let center_raw = fs::read_to_string(dir.join("plugins_center")).unwrap_or_default();

    let (start_ids, end_ids) = parse_panel_wings(&wings_raw);
    let center_ids = parse_panel_center(&center_raw);

    let mut desktop_map = load_desktop_applets();
    let mut applets = Vec::new();

    let mut push_id = |id: &str, seg: PanelSegment| {
        if let Some(meta) = desktop_map.remove(id) {
            applets.push(PanelAppletInfo {
                id: id.to_string(),
                name: meta.name,
                comment: meta.comment,
                icon: meta.icon,
                segment: seg,
            });
        } else {
            applets.push(PanelAppletInfo {
                id: id.to_string(),
                name: id.rsplit('.').next().unwrap_or(id).to_string(),
                comment: id.to_string(),
                icon: find_icon_file(id),
                segment: seg,
            });
        }
    };

    for id in &start_ids {
        push_id(id, PanelSegment::Start);
    }
    for id in &center_ids {
        push_id(id, PanelSegment::Center);
    }
    for id in &end_ids {
        push_id(id, PanelSegment::End);
    }

    let mut hidden: Vec<(String, DesktopEntryMeta)> = desktop_map.into_iter().collect();
    hidden.sort_by(|a, b| a.1.name.cmp(&b.1.name));
    for (id, meta) in hidden {
        if id == "com.system76.CosmicSettings.Panel" {
            continue;
        }
        applets.push(PanelAppletInfo {
            id,
            name: meta.name,
            comment: meta.comment,
            icon: meta.icon,
            segment: PanelSegment::Hidden,
        });
    }

    let (tray_items, managed_indicators) =
        tokio::join!(probe_tray_items(), probe_managed_indicators());

    PanelAndTrayInfo {
        applets,
        tray_items,
        managed_indicators,
    }
}
