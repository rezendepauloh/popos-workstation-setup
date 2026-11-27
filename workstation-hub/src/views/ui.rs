use crate::app::Message;
use cosmic::prelude::*;
use cosmic::widget;
use std::borrow::Cow;

/// Botão padrão com padding interno confortável e altura automática (evita corte de texto em 2+ linhas).
pub fn btn_standard<'a>(
    label: impl Into<Cow<'a, str>> + 'a,
    on_press: Message,
) -> widget::Button<'a, Message> {
    widget::button::custom(widget::text::body(label))
        .padding([8, 16])
        .class(cosmic::theme::Button::Standard)
        .on_press(on_press)
}

/// Botão de ação sugerida/primária com padding interno confortável e altura automática.
pub fn btn_suggested<'a>(
    label: impl Into<Cow<'a, str>> + 'a,
    on_press: Message,
) -> widget::Button<'a, Message> {
    widget::button::custom(widget::text::body(label))
        .padding([8, 16])
        .class(cosmic::theme::Button::Suggested)
        .on_press(on_press)
}

/// Botão de ação destrutiva com padding interno confortável e altura automática.
pub fn btn_destructive<'a>(
    label: impl Into<Cow<'a, str>> + 'a,
    on_press: Message,
) -> widget::Button<'a, Message> {
    widget::button::custom(widget::text::body(label))
        .padding([8, 16])
        .class(cosmic::theme::Button::Destructive)
        .on_press(on_press)
}

/// Linha responsiva que quebra automaticamente os itens para a próxima linha quando a janela é reduzida.
pub fn wrap_row<'a>(items: Vec<Element<'a, Message>>) -> Element<'a, Message> {
    widget::flex_row(items)
        .row_spacing(8)
        .column_spacing(8)
        .into()
}

/// Scrollable padrão de página com margem direita para a barra de rolagem não encostar no conteúdo.
pub fn page_scroll<'a>(content: impl Into<Element<'a, Message>>) -> Element<'a, Message> {
    widget::scrollable(
        widget::container(content)
            .padding([0, 14, 0, 0])
            .width(cosmic::iced::Length::Fill),
    )
    .height(cosmic::iced::Length::Fill)
    .into()
}
