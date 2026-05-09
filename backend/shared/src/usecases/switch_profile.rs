use std::path::Path;

use anyhow::{bail, Result};

use crate::{database::Database, settings::Settings};

pub async fn switch_profile(
    settings: &mut Settings,
    settings_path: &Path,
    database: &mut Database,
    home_path: &Path,
    profile_id: i64,
) -> Result<()> {
    if profile_id == settings.active_profile_id {
        return Ok(());
    }

    let valid = if settings.profiles.is_empty() {
        profile_id == 1
    } else {
        settings.profiles.iter().any(|p| p.id == profile_id)
    };

    if !valid {
        bail!("profile {} not found", profile_id);
    }

    let db_path = home_path
        .join("profiles")
        .join(profile_id.to_string())
        .join("database.db");

    database.switch_to(&db_path).await?;

    let mut updated = settings.clone();
    updated.active_profile_id = profile_id;
    updated.save_to_file(settings_path)?;

    *settings = updated;
    Ok(())
}
