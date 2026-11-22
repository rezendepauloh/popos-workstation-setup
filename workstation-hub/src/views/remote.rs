use crate::app::{AppModel, Message};
use crate::models::status::{HomelabNetworkMode, SamsungTarget};
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

    let win_btns = widget::row::with_capacity(8)
        .spacing(space_s)
        .push(widget::button::standard("Testar SSH/RDP").on_press(Message::RunRemoteAction("win_check".to_string())))
        .push(widget::button::standard("Status & Disco").on_press(Message::RunRemoteAction("win_status".to_string())))
        .push(widget::button::suggested("Limpar Cache & Temp").on_press(Message::RunRemoteAction("win_clean".to_string())))
        .push(widget::button::standard("Winget Upgrade").on_press(Message::RunRemoteAction("win_winget".to_string())))
        .push(widget::button::suggested("Abrir Tela (Moonlight)").on_press(Message::RunRemoteAction("win_moonlight".to_string())))
        .push(widget::button::standard("Abrir RDP").on_press(Message::RunRemoteAction("win_rdp".to_string())))
        .push(widget::button::standard("Ligar (WoL)").on_press(Message::RunRemoteAction("win_wol".to_string())))
        .push(widget::button::standard("Setup OpenSSH").on_press(Message::RunRemoteAction("win_setup_ssh".to_string())));

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

    let android_btns = widget::row::with_capacity(5)
        .spacing(space_s)
        .push(widget::button::standard("Conectar ADB").on_press(Message::RunRemoteAction("android_connect".to_string())))
        .push(widget::button::standard("Status & Espaço").on_press(Message::RunRemoteAction("android_status".to_string())))
        .push(widget::button::suggested("Limpar Cache Apps").on_press(Message::RunRemoteAction("android_clean".to_string())))
        .push(widget::button::suggested("Espelhar Tela (scrcpy)").on_press(Message::RunRemoteAction("android_scrcpy".to_string())))
        .push(widget::button::destructive("Desconectar").on_press(Message::RunRemoteAction("android_disconnect".to_string())));

    let android_sec = settings::section()
        .title(format!("📱 {} (ADB Wi-Fi + scrcpy)", rd.android_label))
        .add(settings::item::builder("Destino").control(widget::text::body(android_info)))
        .add(widget::container(android_btns).padding(4));

    let samsung_ip = match app.samsung_target {
        SamsungTarget::Tv => rd.tv_ip.as_str(),
        SamsungTarget::Projector => rd.projector_ip.as_str(),
    };
    let samsung_selector = widget::row::with_capacity(3)
        .spacing(space_s)
        .align_y(Alignment::Center)
        .push(samsung_btn(&rd.tv_label, SamsungTarget::Tv, app.samsung_target))
        .push(samsung_btn(&rd.projector_label, SamsungTarget::Projector, app.samsung_target))
        .push(widget::text::caption(if samsung_ip.is_empty() {
            "Configure REMOTE_TV_IP / REMOTE_PROJECTOR_IP no .env"
        } else {
            samsung_ip
        }));

    let samsung_btns = widget::row::with_capacity(8)
        .spacing(space_s)
        .push(widget::button::standard("Status API").on_press(Message::RunSamsungAction("status".to_string())))
        .push(widget::button::suggested("Ligar (WoL)").on_press(Message::RunSamsungAction("wol".to_string())))
        .push(widget::button::destructive("Power").on_press(Message::RunSamsungAction("KEY_POWER".to_string())))
        .push(widget::button::standard("Vol +").on_press(Message::RunSamsungAction("KEY_VOLUP".to_string())))
        .push(widget::button::standard("Vol -").on_press(Message::RunSamsungAction("KEY_VOLDOWN".to_string())))
        .push(widget::button::standard("Mute").on_press(Message::RunSamsungAction("KEY_MUTE".to_string())))
        .push(widget::button::standard("Home").on_press(Message::RunSamsungAction("KEY_HOME".to_string())))
        .push(widget::button::standard("Source").on_press(Message::RunSamsungAction("KEY_SOURCE".to_string())));

    let samsung_sec = settings::section()
        .title("📺 Smart TV & Projetor Samsung (Tizen LAN + WoL)")
        .add(widget::container(samsung_selector).padding(4))
        .add(widget::container(samsung_btns).padding(4));

    let alexa_ctrl = widget::row::with_capacity(3)
        .spacing(space_s)
        .align_y(Alignment::Center)
        .push(
            widget::text_input("Falar na Alexa (TTS via Home Assistant)...", &app.alexa_tts_input)
                .on_input(Message::AlexaTtsInputChanged)
                .on_submit(|_| Message::SendAlexaTts)
                .width(Length::Fill),
        )
        .push(widget::button::suggested("Enviar TTS").on_press(Message::SendAlexaTts))
        .push(widget::button::standard("Testar HA API").on_press(Message::RunRemoteAction("ha_check".to_string())));

    let other_sec = settings::section()
        .title("🔊 Alexa (Home Assistant) & 🍏 Apple (iPhone / iPad)")
        .add(
            settings::item::builder("Alexa / Home Assistant")
                .description(if rd.ha_configured {
                    "Integrado via HA_URL e HA_TOKEN do .env."
                } else {
                    "Preencha HA_URL e HA_TOKEN em Configurações -> .env para enviar rotinas/TTS."
                })
                .control(alexa_ctrl),
        )
        .add(
            settings::item::builder("iPhone & iPad (iOS / iPadOS)")
                .description("Por restrição da Apple, não há SSH/RDP ou limpeza remota via rede. Use 'Escanear Rede' para presença mDNS, LocalSend para arquivos ou cabo USB (libimobiledevice) para backups.")
                .control(widget::text::caption("Somente mDNS / LocalSend / USB")),
        );

    let col = widget::column::with_capacity(5)
        .spacing(space_m)
        .push(header)
        .push(win_sec)
        .push(android_sec)
        .push(samsung_sec)
        .push(other_sec);

    widget::scrollable(col).height(Length::Fill).into()
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

fn samsung_btn(
    label: &str,
    target: SamsungTarget,
    active: SamsungTarget,
) -> Element<'_, Message> {
    if target == active {
        widget::button::suggested(label)
            .on_press(Message::SetSamsungTarget(target))
            .into()
    } else {
        widget::button::standard(label)
            .on_press(Message::SetSamsungTarget(target))
            .into()
    }
}
