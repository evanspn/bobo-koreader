use std::path::Path;

use anyhow::Result;

use crate::settings::{Settings, UserProfile};

pub fn create_profile(
    settings: &mut Settings,
    settings_path: &Path,
    name: String,
    color: Option<String>,
) -> Result<UserProfile> {
    let existing = if settings.profiles.is_empty() {
        vec![UserProfile { id: 1, name: "Default".to_string(), color: None }]
    } else {
        settings.profiles.clone()
    };

    let next_id = existing.iter().map(|p| p.id).max().unwrap_or(0) + 1;
    let profile = UserProfile { id: next_id, name, color };

    let mut updated = settings.clone();
    if updated.profiles.is_empty() {
        updated.profiles.push(UserProfile { id: 1, name: "Default".to_string(), color: None });
    }
    updated.profiles.push(profile.clone());
    updated.save_to_file(settings_path)?;

    *settings = updated;
    Ok(profile)
}
