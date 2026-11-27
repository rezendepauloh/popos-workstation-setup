use crate::app::{AppModel, Message};
use crate::views::ui;
use cosmic::iced::Alignment;
use cosmic::prelude::*;
use cosmic::widget::{self, settings};
use std::path::PathBuf;

pub fn view(app: &AppModel) -> Element<'_, Message> {
    let hw = &app.snapshot.hardware_info;

    let header = widget::row::with_capacity(3)
        .spacing(12)
        .align_y(Alignment::Center)
        .push(widget::text::title2("Sistema & Hardware (Pop!_OS)"))
        .push(widget::space::horizontal())
        .push(widget::button::standard("Atualizar Painel").on_press(Message::RefreshSnapshot));

    // 1. Saúde & Hardware em Tempo Real
    let mut health_sec = settings::section().title("Saúde & Hardware em Tempo Real");
    health_sec = health_sec
        .add(settings::item(
            "CPU (Carga)",
            widget::text::body(if hw.cpu_load.is_empty() {
                "Carregando...".to_string()
            } else {
                hw.cpu_load.clone()
            }),
        ))
        .add(settings::item(
            "Memória RAM",
            widget::text::body(if hw.ram_summary.is_empty() {
                "Carregando...".to_string()
            } else {
                hw.ram_summary.clone()
            }),
        ))
        .add(settings::item(
            "GPU NVIDIA",
            widget::text::body(if hw.gpu_summary.is_empty() {
                "Carregando...".to_string()
            } else {
                hw.gpu_summary.clone()
            }),
        ));

    for disk in &hw.disks {
        health_sec = health_sec.add(settings::item(
            "Disco",
            widget::text::caption(disk.clone()),
        ));
    }

    // 2. Hardware, Áudio, Iluminação & Streaming
    let mut devices_sec = settings::section().title("Hardware, Áudio, Iluminação & Streaming");
    devices_sec = devices_sec
        .add(settings::item(
            "Sunshine Game Streamer (TV / Moonlight)",
            widget::text::body(if hw.sunshine_active {
                "Ativo"
            } else {
                "Inativo"
            }),
        ))
        .add(
            widget::column::with_capacity(3)
                .spacing(8)
                .padding([8, 12])
                .push(
                    widget::row::with_capacity(3)
                        .spacing(8)
                        .push(
                            widget::button::suggested("Iniciar Sunshine")
                                .on_press(Message::RunSystemAction("sunshine_start".to_string())),
                        )
                        .push(
                            widget::button::destructive("Parar Sunshine")
                                .on_press(Message::RunSystemAction("sunshine_stop".to_string())),
                        )
                        .push(
                            widget::button::standard("Status Sunshine")
                                .on_press(Message::RunSystemAction("sunshine_status".to_string())),
                        ),
                )
                .push(
                    widget::row::with_capacity(3)
                        .spacing(8)
                        .push(
                            widget::button::standard("Áudio: Fone QCY H3S (BT)")
                                .on_press(Message::RunSystemAction("audio_bt".to_string())),
                        )
                        .push(
                            widget::button::standard("Áudio: Caixas de Som")
                                .on_press(Message::RunSystemAction("audio_speakers".to_string())),
                        )
                        .push(
                            widget::button::standard("Reiniciar PipeWire (Áudio)")
                                .on_press(Message::RunSystemAction("audio_restart".to_string())),
                        ),
                ),
        );

    // 2b. Iluminação RGB (OpenRGB)
    let rgb_sec = settings::section()
        .title("Iluminação RGB (OpenRGB — RAM + Placa-mãe/Ventoinhas)")
        .add(
            widget::column::with_capacity(3)
                .spacing(8)
                .padding([8, 12])
                .push(ui::wrap_row(vec![
                    ui::btn_suggested("Roxo COSMIC", Message::OpenRgbSetColor("7A5AF8".to_string())).into(),
                    ui::btn_standard("Ciano", Message::OpenRgbSetColor("00E5FF".to_string())).into(),
                    ui::btn_standard("Branco", Message::OpenRgbSetColor("FFFFFF".to_string())).into(),
                    ui::btn_standard("Vermelho", Message::OpenRgbSetColor("FF2A2A".to_string())).into(),
                    ui::btn_standard("Verde", Message::OpenRgbSetColor("00E676".to_string())).into(),
                    ui::btn_standard("Azul", Message::OpenRgbSetColor("2979FF".to_string())).into(),
                ]))
                .push(
                    widget::row::with_capacity(3)
                        .spacing(8)
                        .push(
                            widget::button::standard("Modo Rainbow")
                                .on_press(Message::RunSystemAction("openrgb_rainbow".to_string())),
                        )
                        .push(
                            widget::button::destructive("Desligar Todos LEDs")
                                .on_press(Message::RunSystemAction("openrgb_off".to_string())),
                        )
                        .push(
                            widget::button::standard("Listar Dispositivos")
                                .on_press(Message::RunSystemAction("openrgb_list".to_string())),
                        ),
                )
                .push(
                    widget::row::with_capacity(2)
                        .spacing(8)
                        .align_y(Alignment::Center)
                        .push(
                            widget::text_input("Cor HEX (ex: 7A5AF8)", &app.openrgb_hex_input)
                                .on_input(Message::OpenRgbHexChanged)
                                .on_submit(|_| Message::ApplyOpenRgbHex),
                        )
                        .push(
                            widget::button::suggested("Aplicar Cor HEX")
                                .on_press(Message::ApplyOpenRgbHex),
                        ),
                ),
        );

    // 3. Nuvem & Backups
    let mut backup_sec = settings::section().title("Nuvem & Backups");
    for r in &hw.rclone_status {
        backup_sec = backup_sec.add(settings::item(
            "Montagem Rclone",
            widget::text::caption(r.clone()),
        ));
    }
    backup_sec = backup_sec
        .add(settings::item(
            "Backups Homelab (/mnt/storage_930/Backups_Homelab)",
            widget::text::caption(hw.homelab_backup_summary.clone()),
        ))
        .add(
            widget::column::with_capacity(2)
                .spacing(8)
                .padding([8, 12])
                .push(ui::wrap_row(vec![
                    ui::btn_suggested(
                        "Backup COSMIC (.config -> Google Drive)",
                        Message::RunSystemAction("backup_cosmic_gdrive".to_string()),
                    )
                    .into(),
                    ui::btn_suggested(
                        "Verificar & Sincronizar disk3 -> Backups_Homelab",
                        Message::RunSystemAction("sync_homelab_disk3".to_string()),
                    )
                    .into(),
                ]))
                .push(ui::wrap_row(vec![
                    ui::btn_standard(
                        "Reiniciar Montagens Rclone",
                        Message::RunSystemAction("rclone_restart".to_string()),
                    )
                    .into(),
                    ui::btn_standard(
                        "Forçar Sync OneDrive (MPMS)",
                        Message::RunSystemAction("onedrive_sync".to_string()),
                    )
                    .into(),
                    ui::btn_standard(
                        "Abrir Backups_Homelab",
                        Message::OpenLocalFolder(PathBuf::from(
                            "/mnt/storage_930/Backups_Homelab",
                        )),
                    )
                    .into(),
                ])),
        );

    // 4. Energia & Sessão COSMIC
    let power_sec = settings::section()
        .title("Energia & Sessão COSMIC")
        .add(
            widget::container(ui::wrap_row(vec![
                ui::btn_standard(
                    "Reparar IDEs (Locks/GPU)",
                    Message::RunSystemAction("repair_ides".to_string()),
                )
                .into(),
                ui::btn_standard(
                    "Reiniciar COSMIC Panel",
                    Message::RunSystemAction("restart_cosmic_panel".to_string()),
                )
                .into(),
                ui::btn_standard(
                    "Suspender",
                    Message::RunSystemAction("power_suspend".to_string()),
                )
                .into(),
                ui::btn_destructive(
                    "Reiniciar PC",
                    Message::RunSystemAction("power_reboot".to_string()),
                )
                .into(),
                ui::btn_destructive(
                    "Desligar PC",
                    Message::RunSystemAction("power_off".to_string()),
                )
                .into(),
            ]))
            .padding([8, 12]),
        );

    let content = widget::column::with_capacity(6)
        .spacing(16)
        .push(header)
        .push(health_sec)
        .push(devices_sec)
        .push(rgb_sec)
        .push(backup_sec)
        .push(power_sec);

    ui::page_scroll(content)
}
