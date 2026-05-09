use crate::settings::{Settings, UserProfile};

pub fn list_profiles(settings: &Settings) -> Vec<UserProfile> {
    if settings.profiles.is_empty() {
        vec![UserProfile {
            id: 1,
            name: "Default".to_string(),
        }]
    } else {
        settings.profiles.clone()
    }
}
