use crate::models::log_entry::{AnsiColor, LogLine};
use crate::services::ansi_parser::parse_ansi_line;
use crate::services::input_validator::resolve_safe_script;
use portable_pty::{CommandBuilder, PtySize, native_pty_system};
use std::fs::{self, OpenOptions};
use std::io::{Read, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::{Arc, Mutex};
use std::time::Instant;
use tokio::sync::mpsc::UnboundedSender;

#[derive(Debug, Clone)]
pub enum RunnerEvent {
    Started { label: String },
    Line(LogLine),
    Finished {
        label: String,
        exit_code: i32,
        duration_ms: u128,
    },
    Error { label: String, message: String },
}

#[derive(Clone)]
pub struct RunningProcessHandle {
    writer: Arc<Mutex<Option<Box<dyn Write + Send>>>>,
    killer: Arc<Mutex<Option<Box<dyn portable_pty::ChildKiller + Send + Sync>>>>,
}

impl RunningProcessHandle {
    pub fn send_input(&self, line: &str) -> Result<(), String> {
        let mut guard = self
            .writer
            .lock()
            .map_err(|_| "Falha ao acessar stdin do processo.".to_string())?;
        let Some(writer) = guard.as_mut() else {
            return Err("Nenhum processo em execução.".to_string());
        };
        writer
            .write_all(format!("{line}\n").as_bytes())
            .map_err(|e| format!("Erro ao enviar entrada: {e}"))?;
        writer
            .flush()
            .map_err(|e| format!("Erro ao sincronizar entrada: {e}"))?;
        Ok(())
    }

    pub fn terminate(&self) -> Result<(), String> {
        let mut guard = self
            .killer
            .lock()
            .map_err(|_| "Falha ao acessar controle do processo.".to_string())?;
        if let Some(killer) = guard.as_mut() {
            killer
                .kill()
                .map_err(|e| format!("Falha ao encerrar processo: {e}"))?;
        }
        Ok(())
    }
}

#[derive(Debug, Clone)]
pub struct CommandSpec {
    pub label: String,
    pub program: String,
    pub args: Vec<String>,
    pub workdir: PathBuf,
    pub cleanup_file: Option<PathBuf>,
}

/// Builds a safe command for running a validated local/homelab script (optionally with `pkexec`).
pub fn build_script_command(
    label: impl Into<String>,
    repo_root: &Path,
    rel_script: &str,
    extra_args: &[&str],
    requires_root: bool,
) -> Result<CommandSpec, String> {
    let canon = resolve_safe_script(repo_root, rel_script)?;
    let runner = if canon.extension().is_some_and(|e| e == "py") {
        "python3"
    } else {
        "bash"
    };

    let mut args = Vec::new();
    let program = if requires_root {
        args.push(runner.to_string());
        args.push(canon.to_string_lossy().to_string());
        "/usr/bin/pkexec".to_string()
    } else {
        args.push(canon.to_string_lossy().to_string());
        runner.to_string()
    };

    for a in extra_args {
        args.push((*a).to_string());
    }

    Ok(CommandSpec {
        label: label.into(),
        program,
        args,
        workdir: repo_root.to_path_buf(),
        cleanup_file: None,
    })
}

/// Builds a single-elevation `pkexec` batch script executing multiple validated Pop!_OS modules.
pub fn build_setup_batch_command(
    label: impl Into<String>,
    popos_repo: &Path,
    module_filenames: &[String],
    force: bool,
) -> Result<CommandSpec, String> {
    if module_filenames.is_empty() {
        return Err("Nenhum módulo selecionado para execução.".to_string());
    }

    let mut script_body = String::from("#!/bin/bash\nset -e\n");
    for fname in module_filenames {
        let rel = format!("scripts/{fname}");
        let canon = resolve_safe_script(popos_repo, &rel)?;
        let quoted_path = shell_single_quote(&canon.to_string_lossy());
        if force {
            script_body.push_str(&format!("bash {quoted_path} --force\n"));
        } else {
            script_body.push_str(&format!("bash {quoted_path}\n"));
        }
    }

    let runtime_dir = std::env::var("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| std::env::temp_dir());
    let batch_path = runtime_dir.join(format!(
        "workstation-hub-batch-{}-{}.sh",
        std::process::id(),
        chrono::Utc::now().timestamp_millis()
    ));

    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o700)
        .open(&batch_path)
        .map_err(|e| format!("Erro ao criar script temporário de lote: {e}"))?;
    file.write_all(script_body.as_bytes())
        .map_err(|e| format!("Erro ao gravar script de lote: {e}"))?;
    drop(file);

    Ok(CommandSpec {
        label: label.into(),
        program: "/usr/bin/pkexec".to_string(),
        args: vec![
            "/usr/bin/bash".to_string(),
            batch_path.to_string_lossy().to_string(),
        ],
        workdir: popos_repo.to_path_buf(),
        cleanup_file: Some(batch_path),
    })
}

pub fn build_cargo_test_command(hub_dir: &Path) -> CommandSpec {
    CommandSpec {
        label: "Suíte Rust (workstation-hub cargo test)".to_string(),
        program: "cargo".to_string(),
        args: vec!["test".to_string(), "--lib".to_string(), "--tests".to_string()],
        workdir: hub_dir.to_path_buf(),
        cleanup_file: None,
    }
}

pub fn build_vpn_mpms_command(otp: &str, pass: &str, workdir: &Path) -> CommandSpec {
    CommandSpec {
        label: "VPN Corporativa MPMS (openfortivpn)".to_string(),
        program: "/usr/bin/bash".to_string(),
        args: vec![
            "-c".to_string(),
            "printf '%s\\n%s\\n' \"$1\" \"$2\" | sudo /usr/local/sbin/openfortivpn-mpms-helper".to_string(),
            "_".to_string(),
            otp.to_string(),
            pass.to_string(),
        ],
        workdir: workdir.to_path_buf(),
        cleanup_file: None,
    }
}

pub fn build_tailscale_command(action: &str, workdir: &Path) -> CommandSpec {
    let (label, program, args) = match action {
        "up" => (
            "Conectar Tailscale VPN",
            "/usr/bin/pkexec",
            vec!["tailscale".to_string(), "up".to_string()],
        ),
        "down" => (
            "Desconectar Tailscale VPN",
            "/usr/bin/pkexec",
            vec!["tailscale".to_string(), "down".to_string()],
        ),
        _ => (
            "Status Tailscale VPN",
            "tailscale",
            vec!["status".to_string()],
        ),
    };
    CommandSpec {
        label: label.to_string(),
        program: program.to_string(),
        args,
        workdir: workdir.to_path_buf(),
        cleanup_file: None,
    }
}

pub fn build_remote_homelab_logs_command(user: &str, host: &str, workdir: &Path) -> CommandSpec {
    let target = format!("{user}@{host}");
    CommandSpec {
        label: format!("Logs Remotos do Homelab ({target})"),
        program: "ssh".to_string(),
        args: vec![
            "-o".to_string(),
            "ConnectTimeout=4".to_string(),
            target,
            "echo '=== /data/homelab-daemon.log ==='; tail -n 100 /data/homelab-daemon.log 2>/dev/null || echo '(não encontrado)'; echo ''; echo '=== Containers Docker ==='; docker ps --format 'table {{.Names}}\\t{{.Status}}' 2>/dev/null || true".to_string(),
        ],
        workdir: workdir.to_path_buf(),
        cleanup_file: None,
    }
}

/// Spawns a `CommandSpec` inside a real PTY and streams parsed ANSI lines to the UI.
pub fn spawn_pty_command(
    spec: CommandSpec,
    sender: UnboundedSender<RunnerEvent>,
) -> RunningProcessHandle {
    let writer_slot: Arc<Mutex<Option<Box<dyn Write + Send>>>> = Arc::new(Mutex::new(None));
    let killer_slot: Arc<Mutex<Option<Box<dyn portable_pty::ChildKiller + Send + Sync>>>> =
        Arc::new(Mutex::new(None));

    let handle = RunningProcessHandle {
        writer: Arc::clone(&writer_slot),
        killer: Arc::clone(&killer_slot),
    };

    std::thread::spawn(move || {
        let started = Instant::now();
        let _ = sender.send(RunnerEvent::Started {
            label: spec.label.clone(),
        });
        let _ = sender.send(RunnerEvent::Line(LogLine::plain(
            format!("▶ Executando: {} {}", spec.program, spec.args.join(" ")),
            AnsiColor::Cyan,
            true,
        )));

        let pty_system = native_pty_system();
        let pair = match pty_system.openpty(PtySize {
            rows: 40,
            cols: 120,
            pixel_width: 0,
            pixel_height: 0,
        }) {
            Ok(p) => p,
            Err(err) => {
                cleanup_temp(&spec.cleanup_file);
                let _ = sender.send(RunnerEvent::Error {
                    label: spec.label,
                    message: format!("Falha ao abrir PTY: {err}"),
                });
                return;
            }
        };

        let mut cmd = CommandBuilder::new(&spec.program);
        cmd.args(&spec.args);
        cmd.cwd(&spec.workdir);

        let mut child = match pair.slave.spawn_command(cmd) {
            Ok(c) => c,
            Err(err) => {
                cleanup_temp(&spec.cleanup_file);
                let _ = sender.send(RunnerEvent::Error {
                    label: spec.label,
                    message: format!("Falha ao iniciar processo: {err}"),
                });
                return;
            }
        };
        drop(pair.slave);

        if let Ok(writer) = pair.master.take_writer()
            && let Ok(mut guard) = writer_slot.lock()
        {
            *guard = Some(writer);
        }
        if let Ok(mut guard) = killer_slot.lock() {
            *guard = Some(child.clone_killer());
        }

        let mut reader = match pair.master.try_clone_reader() {
            Ok(r) => r,
            Err(err) => {
                cleanup_temp(&spec.cleanup_file);
                let _ = sender.send(RunnerEvent::Error {
                    label: spec.label,
                    message: format!("Falha ao ler saída PTY: {err}"),
                });
                return;
            }
        };

        let mut buf = [0u8; 4096];
        let mut line_acc = String::new();

        loop {
            match reader.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => {
                    let chunk = String::from_utf8_lossy(&buf[..n]);
                    line_acc.push_str(&chunk);
                    while let Some(idx) = line_acc.find('\n') {
                        let raw_line = line_acc[..idx].trim_end_matches('\r').to_string();
                        line_acc.drain(..=idx);
                        let parsed = parse_ansi_line(&raw_line);
                        let _ = sender.send(RunnerEvent::Line(parsed));
                    }
                }
                Err(_) => break,
            }
        }

        if !line_acc.trim().is_empty() {
            let parsed = parse_ansi_line(line_acc.trim_end_matches('\r'));
            let _ = sender.send(RunnerEvent::Line(parsed));
        }

        let exit_code = match child.wait() {
            Ok(status) => i32::try_from(status.exit_code()).unwrap_or(1),
            Err(_) => 1,
        };

        if let Ok(mut guard) = writer_slot.lock() {
            *guard = None;
        }
        if let Ok(mut guard) = killer_slot.lock() {
            *guard = None;
        }
        cleanup_temp(&spec.cleanup_file);

        let _ = sender.send(RunnerEvent::Finished {
            label: spec.label,
            exit_code,
            duration_ms: started.elapsed().as_millis(),
        });
    });

    handle
}

pub fn launch_in_cosmic_term(args: &[&str], workdir: &Path) -> Result<(), String> {
    let mut cmd = Command::new("cosmic-term");
    cmd.current_dir(workdir);
    if !args.is_empty() {
        cmd.arg("--");
        cmd.args(args);
    }
    cmd.spawn()
        .map(|_| ())
        .map_err(|e| format!("Não foi possível abrir o cosmic-term: {e}"))
}

fn cleanup_temp(path: &Option<PathBuf>) {
    if let Some(p) = path {
        let _ = fs::remove_file(p);
    }
}

fn shell_single_quote(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\"'\"'"))
}
