use std::path::Path;

use anyhow::{bail, Result};

use crate::settings::{Settings, UserProfile};

/// Updates an existing profile's name and/or color. Either field can be `None`
/// to leave it unchanged. Renaming the implicit default profile (when
/// `settings.profiles` is empty) is supported by materializing it into the list.
pub fn update_profile(
    settings: &mut Settings,
    settings_path: &Path,
    profile_id: i64,
    name: Option<String>,
    color: Option<Option<String>>,
) -> Result<UserProfile> {
    let mut updated = settings.clone();

    // Materialize the implicit Default profile so it can be edited.
    if updated.profiles.is_empty() && profile_id == 1 {
        updated.profiles.push(UserProfile {
            id: 1,
            name: "Default".to_string(),
            color: None,
        });
    }

    let pos = updated
        .profiles
        .iter()
        .position(|p| p.id == profile_id)
        .ok_or_else(|| anyhow::anyhow!("profile {} not found", profile_id))?;

    if let Some(name) = name {
        let trimmed = name.trim();
        if trimmed.is_empty() {
            bail!("profile name cannot be empty");
        }
        updated.profiles[pos].name = trimmed.to_string();
    }
    if let Some(color) = color {
        updated.profiles[pos].color = color;
    }

    updated.save_to_file(settings_path)?;
    let result = updated.profiles[pos].clone();
    *settings = updated;
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::NamedTempFile;

    fn settings_with(profiles: Vec<UserProfile>) -> Settings {
        Settings { profiles, ..Settings::default() }
    }

    #[test]
    fn renames_an_existing_profile() {
        let mut settings = settings_with(vec![
            UserProfile { id: 1, name: "Old".into(), color: None },
            UserProfile { id: 2, name: "Bob".into(), color: Some("blue".into()) },
        ]);
        let path = NamedTempFile::new().unwrap();

        let updated =
            update_profile(&mut settings, path.path(), 2, Some("Bobby".into()), None).unwrap();

        assert_eq!(updated.name, "Bobby");
        assert_eq!(settings.profiles[1].name, "Bobby");
        // color must be preserved when not specified.
        assert_eq!(settings.profiles[1].color.as_deref(), Some("blue"));
    }

    #[test]
    fn updates_color_only() {
        let mut settings =
            settings_with(vec![UserProfile { id: 1, name: "Bob".into(), color: None }]);
        let path = NamedTempFile::new().unwrap();

        update_profile(&mut settings, path.path(), 1, None, Some(Some("red".into()))).unwrap();
        assert_eq!(settings.profiles[0].color.as_deref(), Some("red"));
        assert_eq!(settings.profiles[0].name, "Bob");
    }

    #[test]
    fn clears_color_when_explicitly_set_to_none() {
        let mut settings = settings_with(vec![UserProfile {
            id: 1,
            name: "Bob".into(),
            color: Some("red".into()),
        }]);
        let path = NamedTempFile::new().unwrap();

        update_profile(&mut settings, path.path(), 1, None, Some(None)).unwrap();
        assert!(settings.profiles[0].color.is_none());
    }

    #[test]
    fn materializes_implicit_default_profile_when_renaming_id_1() {
        // Empty profiles list — id=1 is the implicit "Default".
        let mut settings = settings_with(vec![]);
        let path = NamedTempFile::new().unwrap();

        update_profile(&mut settings, path.path(), 1, Some("Me".into()), None).unwrap();

        assert_eq!(settings.profiles.len(), 1);
        assert_eq!(settings.profiles[0].id, 1);
        assert_eq!(settings.profiles[0].name, "Me");
    }

    #[test]
    fn rejects_empty_name() {
        let mut settings =
            settings_with(vec![UserProfile { id: 1, name: "Bob".into(), color: None }]);
        let path = NamedTempFile::new().unwrap();

        let err = update_profile(&mut settings, path.path(), 1, Some("   ".into()), None)
            .unwrap_err()
            .to_string();
        assert!(err.contains("empty"), "expected empty-name error, got: {err}");
    }

    #[test]
    fn errors_on_unknown_id() {
        let mut settings =
            settings_with(vec![UserProfile { id: 1, name: "Bob".into(), color: None }]);
        let path = NamedTempFile::new().unwrap();

        assert!(update_profile(&mut settings, path.path(), 99, Some("X".into()), None).is_err());
    }
}
