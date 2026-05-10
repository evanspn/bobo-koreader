use crate::settings::{Settings, UserProfile};

pub fn list_profiles(settings: &Settings) -> Vec<UserProfile> {
    if settings.profiles.is_empty() {
        vec![UserProfile {
            id: 1,
            name: "Default".to_string(),
            color: None,
        }]
    } else {
        settings.profiles.clone()
    }
}
