use crate::app::{AppModel, Message, TestTarget};
use crate::views::ui;
use cosmic::iced::{Alignment, Length};
use cosmic::prelude::*;
use cosmic::widget::{self, settings};

pub fn view(_app: &AppModel) -> Element<'_, Message> {
    let space_s = cosmic::theme::spacing().space_s;
    let space_m = cosmic::theme::spacing().space_m;

    let header = widget::row::with_capacity(2)
        .spacing(space_s)
        .align_y(Alignment::Center)
        .push(widget::text::title2("Suítes de Testes Automatizados").width(Length::Fill));

    let popos_sec = settings::section()
        .title("Workstation Pop!_OS (popos-workstation-setup)")
        .add(
            settings::item::builder("Suíte Unificada (tests/run_all.py)")
                .description("Valida sintaxe Bash, daemons Python, patch binário, segurança e coerência dos 28 módulos.")
                .control(
                    widget::button::suggested("Executar Suíte Pop!_OS")
                        .on_press(Message::RunTestTarget(TestTarget::PoposFull)),
                ),
        )
        .add(
            settings::item::builder("Workstation Hub Rust (cargo test)")
                .description("Executa testes unitários e de integração do próprio aplicativo GUI em Rust.")
                .control(
                    widget::button::standard("Executar cargo test")
                        .on_press(Message::RunTestTarget(TestTarget::HubRust)),
                ),
        )
        .add(
            settings::item::builder("Sandbox End-to-End em Docker (tests/test_in_docker.sh)")
                .description("Constrói e executa validação isolada em container Docker com binários mockados.")
                .control(
                    widget::button::standard("Executar Sandbox Docker")
                        .on_press(Message::RunTestTarget(TestTarget::PoposDocker)),
                ),
        );

    let homelab_sec = settings::section()
        .title("Homelab umbrelOS (umbrelos-scripts)")
        .add(
            settings::item::builder("Suíte Completa do Homelab (tests/run_all.py)")
                .description("Executa todos os testes unitários e de integração remota via SSH.")
                .control(
                    widget::button::suggested("Executar Tudo")
                        .on_press(Message::RunTestTarget(TestTarget::HomelabFull)),
                ),
        )
        .add(
            settings::item::builder("Apenas Testes Unitários (--unit)")
                .description("Valida sintaxe Bash, Compose YAML e consistência sem acessar o Mini PC.")
                .control(
                    widget::button::standard("Unitários (--unit)")
                        .on_press(Message::RunTestTarget(TestTarget::HomelabUnit)),
                ),
        )
        .add(
            settings::item::builder("Apenas Integração Remota (--integration)")
                .description("Verifica discos/montagens, Samba, containers Docker, HTTP e túneis zrok/Tailscale.")
                .control(
                    widget::button::standard("Integração (--integration)")
                        .on_press(Message::RunTestTarget(TestTarget::HomelabIntegration)),
                ),
        );

    let col = widget::column::with_capacity(3)
        .spacing(space_m)
        .push(header)
        .push(popos_sec)
        .push(homelab_sec);

    ui::page_scroll(col)
}
