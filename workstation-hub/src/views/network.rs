use crate::app::{AppModel, Message};
use crate::views::ui;
use cosmic::iced::{Alignment, Length};
use cosmic::prelude::*;
use cosmic::widget::{self, settings};

pub fn view(app: &AppModel) -> Element<'_, Message> {
    let net = &app.snapshot.network_info;
    let online_count = net.hosts.iter().filter(|h| h.online).count();
    let total_count = net.hosts.len();

    let header = widget::row::with_capacity(3)
        .spacing(12)
        .align_y(Alignment::Center)
        .push(widget::text::title2("Monitoramento de Rede (LAN + Tailscale)"))
        .push(widget::space::horizontal())
        .push(widget::button::standard("Atualizar Latência & Scan").on_press(Message::RefreshSnapshot));

    // 1. Dispositivos Monitorados (Ping & Latência)
    let mut hosts_sec = settings::section().title(format!(
        "Dispositivos & Serviços Monitorados ({online_count}/{total_count} online)"
    ));

    if net.hosts.is_empty() {
        hosts_sec = hosts_sec.add(settings::item(
            "Aguardando coleta...",
            widget::text::caption("Clique em Atualizar Latência & Scan para verificar a rede."),
        ));
    } else {
        for h in &net.hosts {
            let status_txt = if h.online {
                format!("ONLINE ({})", h.latency_ms)
            } else {
                h.latency_ms.clone()
            };
            let title = format!("[{}] {}", h.network_type, h.label);
            let sub = format!("Host: {}", h.host);

            hosts_sec = hosts_sec.add(settings::item_row(vec![
                widget::column::with_capacity(2)
                    .spacing(2)
                    .width(Length::Fill)
                    .push(widget::text::body(title))
                    .push(widget::text::caption(sub))
                    .into(),
                widget::text::body(status_txt).into(),
            ]));
        }
    }

    // 2. Ferramentas de Diagnóstico Rápido
    let tools_sec = settings::section()
        .title("Diagnóstico & Descoberta de Rede")
        .add(
            widget::container(ui::wrap_row(vec![
                ui::btn_suggested(
                    "Varrer Rede Local (Ping Sweep)",
                    Message::RunNetworkAction("lan_sweep".to_string()),
                )
                .into(),
                ui::btn_standard(
                    "Testar DNS & Internet",
                    Message::RunNetworkAction("dns_check".to_string()),
                )
                .into(),
                ui::btn_standard(
                    "Portas Abertas (ss)",
                    Message::RunNetworkAction("listening_ports".to_string()),
                )
                .into(),
                ui::btn_standard(
                    "Tailscale Status Completo",
                    Message::RunNetworkAction("tailscale_status".to_string()),
                )
                .into(),
            ]))
            .padding([8, 12]),
        );

    // 3. Nós da Malha Tailscale
    let mut ts_sec = settings::section().title("Nós na Rede Tailscale (Mesh VPN)");
    if net.tailscale_peers.is_empty() {
        ts_sec = ts_sec.add(settings::item(
            "Tailscale",
            widget::text::caption("Nenhum nó retornado (Tailscale desconectado ou sem resposta)."),
        ));
    } else {
        for p in &net.tailscale_peers {
            ts_sec = ts_sec.add(settings::item(
                format!("{} ({})", p.hostname, p.os),
                widget::text::caption(format!("{} — {}", p.ip, p.status)),
            ));
        }
    }

    // 4. Interfaces Locais & Tabela ARP
    let mut local_sec = settings::section().title("Interfaces Locais & Vizinhos ARP (LAN)");
    if !net.gateway_ip.is_empty() {
        local_sec = local_sec.add(settings::item(
            "Gateway Padrão (Roteador)",
            widget::text::body(net.gateway_ip.clone()),
        ));
    }
    for iface in &net.local_interfaces {
        local_sec = local_sec.add(settings::item(
            "Interface",
            widget::text::caption(iface.clone()),
        ));
    }
    for neigh in &net.lan_neighbors {
        local_sec = local_sec.add(settings::item(
            "Dispositivo ARP",
            widget::text::caption(neigh.clone()),
        ));
    }

    let content = widget::column::with_capacity(5)
        .spacing(16)
        .push(header)
        .push(hosts_sec)
        .push(tools_sec)
        .push(ts_sec)
        .push(local_sec);

    ui::page_scroll(content)
}
