use std::path::Path;

use anyhow::{bail, Result};

use crate::settings::Settings;

pub fn delete_profile(
    settings: &mut Settings,
    settings_path: &Path,
    profile_id: i64,
) -> Result<()> {
    if profile_id == settings.active_profile_id {
        bail!("cannot delete the active profile");
    }

    let pos = settings.profiles.iter().position(|p| p.id == profile_id);
    match pos {
        None => bail!("profile {} not found", profile_id),
        Some(i) => {
            let mut updated = settings.clone();
            updated.profiles.remove(i);
            updated.save_to_file(settings_path)?;
            *settings = updated;
            Ok(())
        }
    }
}
