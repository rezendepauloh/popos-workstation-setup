use crate::app::{AppModel, Message};
use cosmic::iced::{Alignment, Length};
use cosmic::prelude::*;
use cosmic::widget::{self, settings};

pub fn view(app: &AppModel) -> Element<'_, Message> {
    let space_s = cosmic::theme::spacing().space_s;
    let space_m = cosmic::theme::spacing().space_m;

    let header = widget::row::with_capacity(2)
        .spacing(space_s)
        .align_y(Alignment::Center)
        .push(widget::text::title2("Central de VPNs (MPMS & Tailscale)").width(Length::Fill))
        .push(widget::button::standard("Atualizar Status").on_press(Message::RefreshSnapshot));

    let mpms_status = match &app.snapshot.vpn_mpms_ip {
        Some(ip) => format!("✔ Conectado (ppp0 · IP: {ip})"),
        None => "○ Desconectado".to_string(),
    };

    let mpms_controls = widget::row::with_capacity(3)
        .spacing(space_s)
        .align_y(Alignment::Center)
        .push(
            widget::button::suggested("Conectar VPN MPMS")
                .on_press(Message::ConnectVpnMpms),
        )
        .push(
            widget::button::destructive("Desconectar")
                .on_press(Message::StopRunningProcess),
        );

    let mpms_sec = settings::section()
        .title("VPN Corporativa MPMS (FortiGate / openfortivpn)")
        .add(
            settings::item::builder("Status do Túnel")
                .control(widget::text::body(mpms_status)),
        )
        .add(
            settings::item::builder("Token / OTP 2FA")
                .description("Código 2FA de 6 dígitos do aplicativo autenticador.")
                .control(
                    widget::text_input("Digite o código OTP...", &app.vpn_otp_input)
                        .on_input(Message::VpnOtpChanged)
                        .on_submit(|_| Message::ConnectVpnMpms)
                        .width(Length::Fixed(220.0)),
                ),
        )
        .add(
            settings::item::builder("Senha MPMS (Opcional)")
                .description("Preencha apenas se o helper não possuir senha salva.")
                .control(
                    widget::text_input("Senha (opcional)", &app.vpn_pass_input)
                        .on_input(Message::VpnPassChanged)
                        .password()
                        .width(Length::Fixed(220.0)),
                ),
        )
        .add(
            settings::item::builder("Ação")
                .description("Executa via /usr/local/sbin/openfortivpn-mpms-helper no Console PTY.")
                .control(mpms_controls),
        );

    let ts_status = match &app.snapshot.tailscale_ip {
        Some(ip) => format!("✔ Conectado (IP Tailscale: {ip})"),
        None => "○ Desconectado".to_string(),
    };

    let ts_controls = widget::row::with_capacity(3)
        .spacing(space_s)
        .align_y(Alignment::Center)
        .push(
            widget::button::suggested("Conectar")
                .on_press(Message::RunTailscale("up".to_string())),
        )
        .push(
            widget::button::destructive("Desconectar")
                .on_press(Message::RunTailscale("down".to_string())),
        )
        .push(
            widget::button::standard("Ver Status")
                .on_press(Message::RunTailscale("status".to_string())),
        );

    let ts_sec = settings::section()
        .title("Tailscale Mesh VPN (WireGuard)")
        .add(
            settings::item::builder("Status da Rede")
                .control(widget::text::body(ts_status)),
        )
        .add(
            settings::item::builder("Controle Rápido")
                .description("Gerencia a conexão ponto-a-ponto entre Pop!_OS e Homelab.")
                .control(ts_controls),
        );

    let col = widget::column::with_capacity(3)
        .spacing(space_m)
        .push(header)
        .push(mpms_sec)
        .push(ts_sec);

    widget::scrollable(col).height(Length::Fill).into()
}
