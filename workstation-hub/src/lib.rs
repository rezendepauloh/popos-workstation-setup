pub mod app;
pub mod models;
pub mod services;
pub mod views;

pub fn run() -> cosmic::iced::Result {
    let settings = cosmic::app::Settings::default().size_limits(
        cosmic::iced::Limits::NONE
            .min_width(960.0)
            .min_height(640.0),
    );

    cosmic::app::run::<app::AppModel>(settings, ())
}
