use crate::app::{AppModel, Message};
use crate::models::status::{HomelabNetworkMode, SamsungTarget};
use crate::views::ui;
use cosmic::iced::{Alignment, Length};
use cosmic::prelude::*;
use cosmic::widget::{self, settings};

pub fn view(app: &AppModel) -> Element<'_, Message> {
    let space_s = cosmic::theme::spacing().space_s;
    let space_m = cosmic::theme::spacing().space_m;
    let rd = &app.snapshot.remote_devices;

    let header = widget::row::with_capacity(4)
        .spacing(space_s)
        .align_y(Alignment::Center)
        .push(widget::text::title2("Dispositivos & Controle Remoto").width(Length::Fill))
        .push(net_btn("Local (LAN)", HomelabNetworkMode::Local, app.remote_network_mode))
        .push(net_btn("Tailscale", HomelabNetworkMode::Tailscale, app.remote_network_mode))
        .push(
            widget::button::suggested("Escanear Rede")
                .on_press(Message::RunRemoteAction("net_scan".to_string())),
        );

    let rustdesk_status = if !rd.rustdesk_installed {
        "○ RustDesk não instalado (execute o módulo 23 para instalar v1.5.3)".to_string()
    } else {
        let svc = if rd.rustdesk_service_active {
            "Serviço ativo (pronto para receber)"
        } else {
            "Serviço parado"
        };
        let id_str = if rd.rustdesk_id.is_empty() {
            "ID indisponível".to_string()
        } else {
            format!("Seu ID: {}", rd.rustdesk_id)
        };
        format!("✔ Instalado | {svc} | {id_str}")
    };

    let rustdesk_controls = ui::wrap_row(vec![
        widget::text_input("ID remoto (ex: computador da Kamila)", &app.rustdesk_target_id)
            .on_input(Message::RustDeskTargetChanged)
            .width(Length::Fixed(280.0))
            .into(),
        ui::btn_suggested("Conectar", Message::RustDeskConnect).into(),
        ui::btn_standard("Abrir RustDesk", Message::RustDeskOpen).into(),
        ui::btn_standard("Ativar/Reiniciar Serviço", Message::RustDeskToggleService).into(),
    ]);

    let rustdesk_sec = settings::section()
        .title("🖥️ RustDesk (Acesso Remoto P2P v1.5.3)")
        .add(settings::item::builder("Status & Meu ID").control(widget::text::body(rustdesk_status)))
        .add(widget::container(rustdesk_controls).padding(4));

    let win_host = match app.remote_network_mode {
        HomelabNetworkMode::Local => rd.win_lan_host.as_str(),
        HomelabNetworkMode::Tailscale => {
            if rd.win_ts_host.is_empty() {
                rd.win_lan_host.as_str()
            } else {
                rd.win_ts_host.as_str()
            }
        }
    };
    let win_status = match rd.win_online {
        None => format!(
            "Host: {} (Configure REMOTE_WIN_* na aba Configurações -> .env)",
            if win_host.is_empty() { "não configurado" } else { win_host }
        ),
        Some(true) => format!("✔ Online ({}@{win_host})", rd.win_user),
        Some(false) => format!("○ Offline/Inacessível ({}@{win_host})", rd.win_user),
    };

    let win_btns = ui::wrap_row(vec![
        ui::btn_standard("Testar SSH/RDP", Message::RunRemoteAction("win_check".to_string())).into(),
        ui::btn_standard("Status & Disco", Message::RunRemoteAction("win_status".to_string())).into(),
        ui::btn_suggested("Limpar Cache & Temp", Message::RunRemoteAction("win_clean".to_string())).into(),
        ui::btn_standard("Winget Upgrade", Message::RunRemoteAction("win_winget".to_string())).into(),
        ui::btn_suggested("Abrir Tela (Moonlight)", Message::RunRemoteAction("win_moonlight".to_string())).into(),
        ui::btn_standard("Abrir RDP", Message::RunRemoteAction("win_rdp".to_string())).into(),
        ui::btn_standard("Ligar (WoL)", Message::RunRemoteAction("win_wol".to_string())).into(),
        ui::btn_standard("Setup OpenSSH", Message::RunRemoteAction("win_setup_ssh".to_string())).into(),
    ]);

    let win_sec = settings::section()
        .title(format!("💻 {} (Windows 11)", rd.win_label))
        .add(settings::item::builder("Estado").control(widget::text::body(win_status)))
        .add(widget::container(win_btns).padding(4));

    let android_host = match app.remote_network_mode {
        HomelabNetworkMode::Local => rd.android_lan_host.as_str(),
        HomelabNetworkMode::Tailscale => {
            if rd.android_ts_host.is_empty() {
                rd.android_lan_host.as_str()
            } else {
                rd.android_ts_host.as_str()
            }
        }
    };
    let android_info = if android_host.is_empty() {
        "Configure REMOTE_ANDROID_LAN_HOST na aba Configurações -> .env".to_string()
    } else {
        format!("Alvo ADB: {android_host}:{}", rd.android_port)
    };

    let android_btns = ui::wrap_row(vec![
        ui::btn_standard("Conectar ADB", Message::RunRemoteAction("android_connect".to_string())).into(),
        ui::btn_standard("Status & Espaço", Message::RunRemoteAction("android_status".to_string())).into(),
        ui::btn_suggested("Limpar Cache Apps", Message::RunRemoteAction("android_clean".to_string())).into(),
        ui::btn_suggested("Espelhar Tela (scrcpy)", Message::RunRemoteAction("android_scrcpy".to_string())).into(),
        ui::btn_destructive("Desconectar", Message::RunRemoteAction("android_disconnect".to_string())).into(),
    ]);

    let android_sec = settings::section()
        .title(format!("📱 {} (ADB Wi-Fi + scrcpy)", rd.android_label))
        .add(settings::item::builder("Destino").control(widget::text::body(android_info)))
        .add(widget::container(android_btns).padding(4));

    let tablet_host = match app.remote_network_mode {
        HomelabNetworkMode::Local => rd.tablet_lan_host.as_str(),
        HomelabNetworkMode::Tailscale => {
            if rd.tablet_ts_host.is_empty() {
                rd.tablet_lan_host.as_str()
            } else {
                rd.tablet_ts_host.as_str()
            }
        }
    };
    let tablet_info = if tablet_host.is_empty() {
        "Configure REMOTE_TABLET_ANDROID_LAN_HOST na aba Configurações -> .env".to_string()
    } else {
        format!("Alvo ADB: {tablet_host}:{}", rd.tablet_port)
    };

    let tablet_btns = ui::wrap_row(vec![
        ui::btn_standard("Conectar ADB", Message::RunRemoteAction("tablet_connect".to_string())).into(),
        ui::btn_standard("Status & Espaço", Message::RunRemoteAction("tablet_status".to_string())).into(),
        ui::btn_suggested("Limpar Cache Apps", Message::RunRemoteAction("tablet_clean".to_string())).into(),
        ui::btn_suggested("Espelhar Tela (scrcpy)", Message::RunRemoteAction("tablet_scrcpy".to_string())).into(),
        ui::btn_destructive("Desconectar", Message::RunRemoteAction("tablet_disconnect".to_string())).into(),
    ]);

    let tablet_sec = settings::section()
        .title(format!("📲 {} (ADB Wi-Fi + scrcpy)", rd.tablet_label))
        .add(settings::item::builder("Destino").control(widget::text::body(tablet_info)))
        .add(widget::container(tablet_btns).padding(4));

    let tv_sec = samsung_card(
        format!("📺 {} (Tizen LAN + WoL)", rd.tv_label),
        &rd.tv_ip,
        "Configure REMOTE_TV_IP no .env",
        SamsungTarget::Tv,
        space_s,
    );

    let projector_sec = samsung_card(
        format!("📽️ {} (Tizen LAN + WoL)", rd.projector_label),
        &rd.projector_ip,
        "Configure REMOTE_PROJECTOR_IP no .env",
        SamsungTarget::Projector,
        space_s,
    );

    let alexa_ctrl = ui::wrap_row(vec![
        widget::text_input("Falar na Alexa (TTS via Home Assistant)...", &app.alexa_tts_input)
            .on_input(Message::AlexaTtsInputChanged)
            .on_submit(|_| Message::SendAlexaTts)
            .width(Length::Fixed(300.0))
            .into(),
        ui::btn_suggested("Enviar TTS", Message::SendAlexaTts).into(),
        ui::btn_standard("Testar HA API", Message::RunRemoteAction("ha_check".to_string())).into(),
    ]);

    let other_sec = settings::section()
        .title("🔊 Alexa (Home Assistant) & 🍏 Apple (iPhone / iPad)")
        .add(
            settings::item::builder("Alexa / Home Assistant")
                .description(if rd.ha_configured {
                    "Integrado via HA_URL e HA_TOKEN do .env."
                } else {
                    "Preencha HA_URL e HA_TOKEN em Configurações -> .env para enviar rotinas/TTS."
                })
                .control(widget::text::caption(if rd.ha_configured {
                    "Configurado"
                } else {
                    "Não configurado"
                })),
        )
        .add(widget::container(alexa_ctrl).padding(4))
        .add(
            settings::item::builder("iPhone & iPad (iOS / iPadOS)")
                .description("Por restrição da Apple, não há SSH/RDP ou limpeza remota via rede. Use 'Escanear Rede' para presença mDNS, LocalSend para arquivos ou cabo USB (libimobiledevice) para backups.")
                .control(widget::text::caption("Somente mDNS / LocalSend / USB")),
        );

    let col = widget::column::with_capacity(8)
        .spacing(space_m)
        .push(header)
        .push(rustdesk_sec)
        .push(win_sec)
        .push(android_sec)
        .push(tablet_sec)
        .push(tv_sec)
        .push(projector_sec)
        .push(other_sec);

    ui::page_scroll(col)
}

fn samsung_card<'a>(
    title: String,
    ip: &'a str,
    empty_hint: &'static str,
    target: SamsungTarget,
    _space_s: u16,
) -> settings::Section<'a, Message> {
    let btns = ui::wrap_row(vec![
        ui::btn_standard("Status API", Message::RunSamsungTargetAction(target, "status".to_string())).into(),
        ui::btn_suggested("Ligar (WoL)", Message::RunSamsungTargetAction(target, "wol".to_string())).into(),
        ui::btn_destructive("Power", Message::RunSamsungTargetAction(target, "KEY_POWER".to_string())).into(),
        ui::btn_standard("Vol +", Message::RunSamsungTargetAction(target, "KEY_VOLUP".to_string())).into(),
        ui::btn_standard("Vol -", Message::RunSamsungTargetAction(target, "KEY_VOLDOWN".to_string())).into(),
        ui::btn_standard("Mute", Message::RunSamsungTargetAction(target, "KEY_MUTE".to_string())).into(),
        ui::btn_standard("Home", Message::RunSamsungTargetAction(target, "KEY_HOME".to_string())).into(),
        ui::btn_standard("Source", Message::RunSamsungTargetAction(target, "KEY_SOURCE".to_string())).into(),
    ]);

    settings::section()
        .title(title)
        .add(settings::item::builder("Endereço").control(widget::text::caption(if ip.is_empty() {
            empty_hint
        } else {
            ip
        })))
        .add(widget::container(btns).padding(4))
}

fn net_btn(
    label: &'static str,
    target: HomelabNetworkMode,
    active: HomelabNetworkMode,
) -> Element<'static, Message> {
    if target == active {
        widget::button::suggested(label)
            .on_press(Message::SetRemoteNetworkMode(target))
            .into()
    } else {
        widget::button::standard(label)
            .on_press(Message::SetRemoteNetworkMode(target))
            .into()
    }
}
