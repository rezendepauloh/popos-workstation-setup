use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::os::unix::fs::symlink;
use tempfile_helper::TempSandbox;
use workstation_hub::models::catalog::{
    HOMELAB_SETUP_MODULES, HOMELAB_UTIL_ACTIONS, HOMELAB_WEB_SERVICES, LOCAL_UTIL_ACTIONS,
    SETUP_MODULES,
};
use workstation_hub::models::doc_entry::{
    AlertKind, DocSourceKind, MarkdownBlock, MarkdownInlineKind, MarkdownLinkResolution,
};
use workstation_hub::models::env_entry::{EnvTarget, EnvVarItem, is_secret_key};
use workstation_hub::models::log_entry::AnsiColor;
use workstation_hub::services::ansi_parser::parse_ansi_line;
use workstation_hub::services::doc_service::{
    CATEGORY_ALL, SOURCE_ALL, available_categories, available_sources, discover_all_documents,
    export_standalone_html, filter_documents, parse_inlines, parse_markdown, resolve_markdown_link,
};
use workstation_hub::services::env_service::{load_env_file, save_env_file};
use workstation_hub::services::input_validator::{
    resolve_safe_script, validate_env_key, validate_env_value, validate_identifier,
    validate_module_filename,
};
use workstation_hub::services::progress_service::{
    clear_all_flags, clear_flag, progress_file_path, read_completed_flags,
};
use workstation_hub::services::runner_service::{
    build_remote_homelab_logs_command, build_script_command, build_setup_batch_command,
    build_tailscale_command, build_vpn_mpms_command,
};

mod tempfile_helper {
    use std::fs;
    use std::path::{Path, PathBuf};

    pub struct TempSandbox {
        path: PathBuf,
    }

    impl TempSandbox {
        pub fn new(prefix: &str) -> Self {
            let p = std::env::temp_dir().join(format!(
                "whub_test_{prefix}_{}_{}",
                std::process::id(),
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap()
                    .as_nanos()
            ));
            fs::create_dir_all(&p).unwrap();
            Self { path: p }
        }

        pub fn path(&self) -> &Path {
            &self.path
        }
    }

    impl Drop for TempSandbox {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.path);
        }
    }
}

#[test]
fn test_catalog_has_all_28_modules_and_valid_filenames() {
    assert_eq!(SETUP_MODULES.len(), 28);
    for (idx, m) in SETUP_MODULES.iter().enumerate() {
        let expected_id = format!("{:02}", idx + 1);
        assert_eq!(m.id, expected_id);
        assert!(validate_module_filename(m.filename).is_ok());
        assert!(!m.flag_name.is_empty());
    }
    assert!(!LOCAL_UTIL_ACTIONS.is_empty());
    assert!(!HOMELAB_UTIL_ACTIONS.is_empty());
    assert_eq!(HOMELAB_SETUP_MODULES.len(), 7);
    assert_eq!(HOMELAB_WEB_SERVICES.len(), 22);
}

#[test]
fn test_input_validator_fail_closed_rules() {
    assert!(validate_module_filename("01_otimizacao_sistema.sh").is_ok());
    assert!(validate_module_filename("../evil.sh").is_err());
    assert!(validate_module_filename("01_bad;rm.sh").is_err());

    assert!(validate_identifier("immich").is_ok());
    assert!(validate_identifier("arr-stack").is_ok());
    assert!(validate_identifier("immich; whoami").is_err());
    assert!(validate_identifier("-flag").is_err());

    assert!(validate_env_key("LOCAL_DNS_PRIMARY").is_ok());
    assert!(validate_env_key("1BAD").is_err());
    assert!(validate_env_key("BAD KEY").is_err());

    assert!(validate_env_value("valor seguro 123").is_ok());
    assert!(validate_env_value("linha1\nEVIL=1").is_err());
}

#[test]
fn test_resolve_safe_script_blocks_traversal() {
    let sb = TempSandbox::new("traversal");
    let scripts_dir = sb.path().join("scripts");
    fs::create_dir_all(&scripts_dir).unwrap();
    let ok_script = scripts_dir.join("01_test.sh");
    fs::write(&ok_script, "#!/bin/bash\n").unwrap();

    assert!(resolve_safe_script(sb.path(), "scripts/01_test.sh").is_ok());
    assert!(resolve_safe_script(sb.path(), "../etc/passwd").is_err());
    assert!(resolve_safe_script(sb.path(), "/etc/passwd").is_err());
}

#[test]
fn test_ansi_parser_extracts_colors_and_handles_cr() {
    let parsed = parse_ansi_line("\x1b[0;32m[SUCCESS]\x1b[0m Concluído");
    assert_eq!(parsed.as_plain_text(), "[SUCCESS] Concluído");
    assert_eq!(parsed.segments[0].color, AnsiColor::Green);

    let cr_parsed = parse_ansi_line("Progresso 10%\rProgresso 100%");
    assert_eq!(cr_parsed.as_plain_text(), "Progresso 100%");
}

#[test]
fn test_env_service_masks_secrets_enforces_0600_and_blocks_symlinks() {
    assert!(is_secret_key("VPN_PASSWORD"));
    assert!(is_secret_key("RCLONE_CONFIG_TOKEN"));
    assert!(!is_secret_key("LOCAL_DNS_PRIMARY"));

    let sb = TempSandbox::new("env");
    fs::write(
        sb.path().join(".env.example"),
        "# Comentário preservado\nLOCAL_DNS_PRIMARY=\"192.168.0.10\"\nVPN_PASSWORD=\"placeholder\"\n",
    )
    .unwrap();

    let loaded = load_env_file(sb.path(), EnvTarget::Popos).unwrap();
    assert!(loaded.loaded_from_example);
    assert_eq!(loaded.entries.len(), 2);

    let updated = vec![
        EnvVarItem {
            key: "LOCAL_DNS_PRIMARY".into(),
            value: "192.168.0.50".into(),
            comment: String::new(),
            section: String::new(),
            is_secret: false,
            revealed: false,
        },
        EnvVarItem {
            key: "VPN_PASSWORD".into(),
            value: "segredo_teste_unitario".into(),
            comment: String::new(),
            section: String::new(),
            is_secret: true,
            revealed: false,
        },
    ];

    let saved = save_env_file(sb.path(), EnvTarget::Popos, &updated).unwrap();
    let mode = fs::metadata(&saved).unwrap().permissions().mode() & 0o777;
    assert_eq!(mode, 0o600);

    let raw = fs::read_to_string(&saved).unwrap();
    assert!(raw.contains("# Comentário preservado"));
    assert!(raw.contains("LOCAL_DNS_PRIMARY=\"192.168.0.50\""));

    // Symlink check (fail-closed)
    let link_root = sb.path().join("sym");
    fs::create_dir_all(&link_root).unwrap();
    symlink(&saved, link_root.join(".env")).unwrap();
    assert!(load_env_file(&link_root, EnvTarget::Popos).is_err());
}

#[test]
fn test_progress_tracker_and_command_builders() {
    let sb = TempSandbox::new("progress");
    fs::create_dir_all(sb.path().join("Logs")).unwrap();
    fs::create_dir_all(sb.path().join("scripts")).unwrap();
    fs::write(
        sb.path().join("scripts/01_otimizacao_sistema.sh"),
        "#!/bin/bash\n",
    )
    .unwrap();

    fs::write(
        progress_file_path(sb.path()),
        "OTIMIZACAO_SISTEMA\nCONFIG_TECLADO\n",
    )
    .unwrap();
    let flags = read_completed_flags(sb.path());
    assert!(flags.contains("OTIMIZACAO_SISTEMA"));
    assert!(flags.contains("CONFIG_TECLADO"));

    clear_flag(sb.path(), "OTIMIZACAO_SISTEMA").unwrap();
    let flags2 = read_completed_flags(sb.path());
    assert!(!flags2.contains("OTIMIZACAO_SISTEMA"));
    assert!(flags2.contains("CONFIG_TECLADO"));

    clear_all_flags(sb.path()).unwrap();
    assert!(read_completed_flags(sb.path()).is_empty());

    let cmd = build_script_command(
        "Teste",
        sb.path(),
        "scripts/01_otimizacao_sistema.sh",
        &["--force"],
        true,
    )
    .unwrap();
    assert_eq!(cmd.program, "/usr/bin/pkexec");
    assert_eq!(cmd.args[0], "bash");

    let batch = build_setup_batch_command(
        "Batch",
        sb.path(),
        &["01_otimizacao_sistema.sh".into()],
        false,
    )
    .unwrap();
    assert_eq!(batch.program, "/usr/bin/pkexec");
    if let Some(p) = batch.cleanup_file {
        assert!(p.exists());
        let _ = fs::remove_file(p);
    }

    let vpn = build_vpn_mpms_command("123456", "", sb.path());
    assert_eq!(vpn.program, "/usr/bin/bash");
    assert!(vpn.args.iter().any(|a| a == "123456"));

    let ts = build_tailscale_command("up", sb.path());
    assert_eq!(ts.program, "/usr/bin/pkexec");
    assert_eq!(ts.args, vec!["tailscale", "up"]);

    let rlogs = build_remote_homelab_logs_command("umbrel", "umbrel.local", sb.path());
    assert_eq!(rlogs.program, "ssh");
    assert!(rlogs.args.iter().any(|a| a == "umbrel@umbrel.local"));
}

#[test]
fn test_log_rotation_3mb_max_3_files() {
    let sb = TempSandbox::new("logrot");
    let logs_dir = sb.path().join("logs");
    // Simulate small max_bytes=120 to trigger rotation across 4 writes
    for i in 1..=4 {
        workstation_hub::services::log_service::append_rotated_log_with_limit(
            &logs_dir,
            &format!("Exec_{i}"),
            "linha de log de teste com conteudo suficiente para rotacionar",
            120,
        )
        .unwrap();
    }
    assert!(logs_dir.join("workstation-hub.log").exists());
    assert!(logs_dir.join("workstation-hub.1.log").exists());
    assert!(logs_dir.join("workstation-hub.2.log").exists());
    assert!(!logs_dir.join("workstation-hub.3.log").exists());

    let parsed = workstation_hub::services::log_service::parse_hub_executions(&logs_dir);
    assert!(!parsed.is_empty());
    assert_eq!(parsed[0].label, "Exec_4");
}

#[test]
fn test_env_service_merges_missing_example_keys() {
    let sb = TempSandbox::new("envmerge");
    fs::write(
        sb.path().join(".env.example"),
        "EXISTING_KEY=\"default\"\nNEW_REMOTE_KEY=\"placeholder\"\n",
    )
    .unwrap();
    fs::write(sb.path().join(".env"), "EXISTING_KEY=\"custom\"\n").unwrap();

    let loaded = load_env_file(sb.path(), EnvTarget::Popos).unwrap();
    assert!(!loaded.loaded_from_example);
    assert_eq!(loaded.entries.len(), 2);
    assert_eq!(loaded.entries[0].value, "custom");
    assert_eq!(loaded.entries[1].key, "NEW_REMOTE_KEY");
}

#[test]
fn test_ui_responsiveness_and_padding_helpers() {
    let manifest_dir = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let ui_src = fs::read_to_string(manifest_dir.join("src/views/ui.rs")).unwrap();
    assert!(ui_src.contains("widget::flex_row"));
    assert!(ui_src.contains("Wrapping::WordOrGlyph"));
    assert!(ui_src.contains("padding([8, 16])"));
    assert!(ui_src.contains("padding([0, 14, 0, 0])"));

    let views_dir = manifest_dir.join("src/views");
    for entry in fs::read_dir(&views_dir).unwrap().flatten() {
        let path = entry.path();
        if path.extension().is_some_and(|e| e == "rs") {
            let fname = path.file_name().unwrap().to_str().unwrap();
            if matches!(
                fname,
                "dashboard.rs"
                    | "docker.rs"
                    | "homelab.rs"
                    | "network.rs"
                    | "panel_tray.rs"
                    | "remote.rs"
                    | "settings.rs"
                    | "setup.rs"
                    | "system.rs"
                    | "tests.rs"
                    | "utils.rs"
                    | "vpn.rs"
            ) {
                let content = fs::read_to_string(&path).unwrap();
                assert!(
                    content.contains("ui::page_scroll("),
                    "{fname} deve usar ui::page_scroll para manter margem da barra de rolagem"
                );
            }
        }
    }
}

#[test]
fn test_doc_service_discovery_fulltext_search_and_symlink_blocking() {
    let popos = TempSandbox::new("docs_popos");
    let homelab = TempSandbox::new("docs_homelab");
    let outside = TempSandbox::new("docs_outside");

    fs::create_dir_all(popos.path().join("Docs/guias")).unwrap();
    fs::create_dir_all(popos.path().join("Docs/issues")).unwrap();
    fs::create_dir_all(homelab.path().join("Docs")).unwrap();

    fs::write(
        popos.path().join("README.md"),
        "# 🚀 Workstation Setup\n\n> Guia principal de automação COSMIC Wayland.\n",
    )
    .unwrap();
    fs::write(
        popos.path().join("Docs/guias/backup_android.md"),
        "# 📱 Backup Android ADB\n\nProcedimento rápido para extração de fotos via ADB.\n\nPalavra-chave oculta: `scrcpy_wireless_token`.\n",
    )
    .unwrap();
    fs::write(
        popos.path().join("Docs/issues/issue_cedilha.md"),
        "# 🚨 Cedilha Wayland\n\nPatch binário em ui::CharacterComposer.\n",
    )
    .unwrap();
    fs::write(
        homelab.path().join("Docs/README.md"),
        "# 🏠 Homelab umbrelOS\n\nDocumentação da infraestrutura self-hosted.\n",
    )
    .unwrap();

    // Cria symlink apontando para fora da raiz — deve ser ignorado (fail-closed)
    let secret_outside = outside.path().join("leak.md");
    fs::write(&secret_outside, "# Segredo Externo\n\nNão deve aparecer.").unwrap();
    symlink(&secret_outside, popos.path().join("Docs/guias/symlink_leak.md")).unwrap();

    let docs = discover_all_documents(popos.path(), homelab.path());
    assert_eq!(docs.len(), 4);
    assert!(docs.iter().all(|d| !d.file_name.contains("symlink_leak")));

    let android_doc = docs
        .iter()
        .find(|d| d.file_name == "backup_android.md")
        .unwrap();
    assert_eq!(android_doc.emoji, "📱");
    assert_eq!(android_doc.title, "Backup Android ADB");
    assert_eq!(android_doc.badge_text, "GUIA");
    assert!(android_doc.summary.contains("extração de fotos"));

    let sources = available_sources(&docs);
    assert!(sources.contains(&SOURCE_ALL.to_string()));
    assert!(sources.contains(&DocSourceKind::PoposWorkstation.label().to_string()));
    assert!(sources.contains(&DocSourceKind::Homelab.label().to_string()));

    let cats = available_categories(&docs, DocSourceKind::PoposWorkstation.label());
    assert!(cats.contains(&CATEGORY_ALL.to_string()));
    assert!(cats.contains(&"Guias & Manuais".to_string()));
    assert!(cats.contains(&"Issues & Diagnósticos".to_string()));

    // Busca full-text no corpo do documento
    let hits = filter_documents(&docs, "scrcpy_wireless_token", SOURCE_ALL, CATEGORY_ALL);
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].file_name, "backup_android.md");

    // Filtro por origem
    let homelab_hits = filter_documents(&docs, "", DocSourceKind::Homelab.label(), CATEGORY_ALL);
    assert_eq!(homelab_hits.len(), 1);
    assert_eq!(homelab_hits[0].source_kind, DocSourceKind::Homelab);
}

#[test]
fn test_doc_service_markdown_parser_alerts_lists_inlines_and_links() {
    let md = r#"# Título Principal

> [!WARNING]
> Atenção ao rodar *comando* com ~~risco~~ e `flag`.

1. Primeiro passo
  - Subitem aninhado
- [x] Concluído
- [ ] Pendente

```bash
echo "hello"
```
"#;
    let blocks = parse_markdown(md);
    assert!(matches!(blocks[0], MarkdownBlock::Heading { level: 1, .. }));
    assert!(matches!(
        blocks[1],
        MarkdownBlock::BlockQuote {
            alert: Some(AlertKind::Warning),
            ..
        }
    ));
    let Some(MarkdownBlock::List { items }) = blocks.get(2) else {
        panic!("Bloco de lista esperado");
    };
    assert_eq!(items.len(), 4);
    assert_eq!(items[0].marker, "1.");
    assert_eq!(items[1].indent_level, 1);
    assert_eq!(items[2].checked, Some(true));
    assert_eq!(items[3].checked, Some(false));

    let inlines = parse_inlines("**negrito** *itálico* ~~riscado~~ `cod` <kbd>Ctrl</kbd>");
    assert!(inlines.iter().any(|s| s.kind == MarkdownInlineKind::Bold));
    assert!(inlines.iter().any(|s| s.kind == MarkdownInlineKind::Italic));
    assert!(
        inlines
            .iter()
            .any(|s| s.kind == MarkdownInlineKind::Strikethrough)
    );
    assert!(inlines.iter().any(|s| s.kind == MarkdownInlineKind::Code));
    assert!(inlines.iter().any(|s| s.kind == MarkdownInlineKind::Kbd));

    // Resolução fail-closed de links
    let sb = TempSandbox::new("docs_links");
    fs::create_dir_all(sb.path().join("Docs/img")).unwrap();
    let cur = sb.path().join("Docs/guia.md");
    let target = sb.path().join("Docs/outro.md");
    let img = sb.path().join("Docs/img/foto.png");
    fs::write(&cur, "# Guia").unwrap();
    fs::write(&target, "# Outro").unwrap();
    fs::write(&img, [0x89, b'P', b'N', b'G']).unwrap();

    assert!(matches!(
        resolve_markdown_link(sb.path(), &cur, "outro.md"),
        MarkdownLinkResolution::InternalDocument { .. }
    ));
    assert!(matches!(
        resolve_markdown_link(sb.path(), &cur, "img/foto.png"),
        MarkdownLinkResolution::LocalImage(_)
    ));
    assert!(matches!(
        resolve_markdown_link(sb.path(), &cur, "https://example.com"),
        MarkdownLinkResolution::ExternalHttpUrl(_)
    ));
    assert!(matches!(
        resolve_markdown_link(sb.path(), &cur, "#secao-1"),
        MarkdownLinkResolution::Anchor(_)
    ));
    // Traversal deve ser bloqueado
    assert!(matches!(
        resolve_markdown_link(sb.path(), &cur, "../../../etc/passwd"),
        MarkdownLinkResolution::Unsupported(_)
    ));
}

#[test]
fn test_doc_service_export_standalone_html_embeds_images_and_escapes_xss() {
    let sb = TempSandbox::new("docs_html");
    fs::create_dir_all(sb.path().join("Docs")).unwrap();
    let img = sb.path().join("Docs/sample.png");
    fs::write(&img, [0x89, b'P', b'N', b'G', 0x0D, 0x0A]).unwrap();
    let doc_path = sb.path().join("Docs/manual.md");
    let raw_md = "# 📘 Manual <script>alert(1)</script>\n\n> [!TIP]\n> Dica útil.\n\n![Print](sample.png)\n";
    fs::write(&doc_path, raw_md).unwrap();

    let docs = discover_all_documents(sb.path(), sb.path());
    let doc = docs.iter().find(|d| d.file_name == "manual.md").unwrap();
    let html = export_standalone_html(doc, raw_md);

    assert!(html.contains("<!DOCTYPE html>"));
    assert!(!html.contains("<script>alert(1)</script>"));
    assert!(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"));
    assert!(html.contains("alert-tip"));
    assert!(html.contains("data:image/png;base64,"));
    assert!(html.contains("id=\"btnToggleToc\""));
    assert!(html.contains("↑ Topo"));
    assert!(html.contains("id=\"sec-1\""));
    assert!(html.contains("class=\"toc-item toc-l1\""));
}

#[test]
fn test_docker_update_analyzer_parsers() {
    use workstation_hub::services::probe_service::{
        parse_imagetools_digest, parse_local_image_metadata, parse_remote_manifest_digest,
        short_sha,
    };

    assert_eq!(short_sha("sha256:abcdef1234567890"), "abcdef123456");
    assert_eq!(short_sha(""), "desconhecido");

    let imagetools_out = "Name:      docker.io/dockurr/windows:latest\nMediaType: application/vnd.oci.image.index.v1+json\nDigest:    sha256:16fd7c39a3e48bb946d29c59dc6015942e5b900a1fa5d7e5552053bfc48ee2ea\n";
    assert_eq!(
        parse_imagetools_digest(imagetools_out).as_deref(),
        Some("sha256:16fd7c39a3e48bb946d29c59dc6015942e5b900a1fa5d7e5552053bfc48ee2ea")
    );

    let img_json = r#"[{
        "Config": {
            "Labels": {
                "org.opencontainers.image.version": "1.2.3"
            }
        },
        "RepoDigests": [
            "nginx@sha256:11111111111122222222222233333333"
        ]
    }]"#;
    let (ver, digests, primary) = parse_local_image_metadata(img_json, "sha256:fallback");
    assert_eq!(ver, "1.2.3");
    assert!(digests.contains("sha256:11111111111122222222222233333333"));
    assert_eq!(primary, "sha256:11111111111122222222222233333333");

    let manifest_list_json = r#"[
        {
            "Descriptor": {
                "digest": "sha256:arm64digest0000000000",
                "platform": { "os": "linux", "architecture": "arm64" }
            }
        },
        {
            "Descriptor": {
                "digest": "sha256:amd64digest9999999999",
                "platform": { "os": "linux", "architecture": "amd64" }
            }
        }
    ]"#;
    assert_eq!(
        parse_remote_manifest_digest(manifest_list_json, "amd64").as_deref(),
        Some("sha256:amd64digest9999999999")
    );
    assert_eq!(
        parse_remote_manifest_digest(manifest_list_json, "arm64").as_deref(),
        Some("sha256:arm64digest0000000000")
    );

    let single_manifest_json = r#"{
        "Descriptor": {
            "digest": "sha256:singledigest55555555"
        }
    }"#;
    assert_eq!(
        parse_remote_manifest_digest(single_manifest_json, "amd64").as_deref(),
        Some("sha256:singledigest55555555")
    );
}

#[test]
fn test_parse_onedrive_sync_status_and_winapps_view() {
    use workstation_hub::services::probe_service::parse_onedrive_sync_status;

    let sample = "\u{feff}{\"state\":\"completed\",\"message\":\"Sincronização concluída (34s).\",\"timestamp\":\"2026-11-28T02:43:20\"}";
    let (state, msg, ts) = parse_onedrive_sync_status(sample);
    assert_eq!(state, "completed");
    assert_eq!(msg, "Sincronização concluída (34s).");
    assert_eq!(ts, "2026-11-28T02:43:20");

    let (empty_st, empty_msg, empty_ts) = parse_onedrive_sync_status("not json");
    assert!(empty_st.is_empty());
    assert!(empty_msg.is_empty());
    assert!(empty_ts.is_empty());

    let manifest_dir = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let winapps_view = fs::read_to_string(manifest_dir.join("src/views/winapps.rs")).unwrap();
    assert!(winapps_view.contains("sync_onedrive"));
    assert!(winapps_view.contains("ui::page_scroll"));
    assert!(winapps_view.contains("ui::wrap_row"));
}
