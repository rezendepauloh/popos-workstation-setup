use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::os::unix::fs::symlink;
use tempfile_helper::TempSandbox;
use workstation_hub::models::catalog::{
    HOMELAB_SETUP_MODULES, HOMELAB_UTIL_ACTIONS, HOMELAB_WEB_SERVICES, LOCAL_UTIL_ACTIONS,
    SETUP_MODULES,
};
use workstation_hub::models::env_entry::{EnvTarget, EnvVarItem, is_secret_key};
use workstation_hub::models::log_entry::AnsiColor;
use workstation_hub::services::ansi_parser::parse_ansi_line;
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
