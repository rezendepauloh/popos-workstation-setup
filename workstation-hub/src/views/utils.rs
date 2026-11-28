use crate::app::{AppModel, Message};
use crate::views::ui;
use crate::models::catalog::LOCAL_UTIL_ACTIONS;
use cosmic::iced::{Alignment, Length};
use cosmic::prelude::*;
use cosmic::widget::{self, settings};

pub fn view(app: &AppModel) -> Element<'_, Message> {
    let space_s = cosmic::theme::spacing().space_s;
    let space_m = cosmic::theme::spacing().space_m;

    let header = widget::row::with_capacity(2)
        .spacing(space_s)
        .align_y(Alignment::Center)
        .push(widget::text::title2("Utilitários da Workstation (util/)").width(Length::Fill))
        .push(
            widget::button::standard("Abrir Pasta util/")
                .on_press(Message::OpenLocalFolder(app.paths.popos_repo.join("util"))),
        );

    let adb_text = if app.snapshot.adb_devices.is_empty() {
        "Nenhum dispositivo ADB detectado no momento (conecte USB com Depuração USB).".to_string()
    } else {
        format!("Aparelhos detectados: {}", app.snapshot.adb_devices.join(", "))
    };

    let backups_text = if app.snapshot.local_android_backups.is_empty() {
        "Nenhuma pasta android-backup-* encontrada localmente.".to_string()
    } else {
        format!(
            "Backups recentes ({}): {}",
            app.snapshot.local_android_backups.len(),
            app.snapshot
                .local_android_backups
                .iter()
                .take(3)
                .cloned()
                .collect::<Vec<_>>()
                .join(", ")
        )
    };

    let status_section = settings::section()
        .title("Diagnóstico de Ferramentas Locais")
        .add(settings::item::builder("Android ADB").control(widget::text::body(adb_text)))
        .add(settings::item::builder("Backups Android").control(widget::text::body(backups_text)))
        .add(
            settings::item::builder("Antigravity IDE")
                .control(widget::text::body(app.snapshot.antigravity_version.clone())),
        )
        .add(settings::item::builder("Docker / WinApps").control(widget::text::body(
            if app.snapshot.winapps_running {
                "Docker ativo · Container winapps-windows em execução"
            } else if app.snapshot.docker_active {
                "Docker ativo · winapps-windows parado"
            } else {
                "Docker dormente (ativação via socket)"
            },
        )));

    let groups = [
        "Android (ADB)",
        "Docker Local",
        "Google Antigravity IDE",
        "Manutenção Rápida",
    ];

    let mut col = widget::column::with_capacity(groups.len() + 3)
        .spacing(space_m)
        .push(header)
        .push(status_section);

    for group_name in groups {
        let mut sec = settings::section().title(group_name);
        for act in LOCAL_UTIL_ACTIONS.iter().filter(|a| a.group == group_name) {
            let btn = if act.requires_root {
                widget::button::suggested("Executar (Admin)")
                    .on_press(Message::RunLocalUtil(act.id.to_string()))
            } else {
                widget::button::standard("Executar")
                    .on_press(Message::RunLocalUtil(act.id.to_string()))
            };

            let desc = if act.interactive {
                format!("{} (Interativo no Console PTY)", act.subtitle)
            } else {
                act.subtitle.to_string()
            };

            sec = sec.add(
                settings::item::builder(act.title)
                    .description(desc)
                    .control(btn),
            );
        }
        col = col.push(sec);
    }

    let winapps_section = settings::section()
        .title("WinApps & Scripts Windows (util/winapps)")
        .add(
            settings::item::builder("Scripts de Otimização & AutoLogon da VM")
                .description("Contém otimizar_winapps_vm.ps1, setup_autologon.bat e ícone onedrive.svg.")
                .control(
                    widget::button::standard("Abrir Pasta util/winapps").on_press(
                        Message::OpenLocalFolder(app.paths.popos_repo.join("util").join("winapps")),
                    ),
                ),
        );
    col = col.push(winapps_section);

    ui::page_scroll(col)
}
