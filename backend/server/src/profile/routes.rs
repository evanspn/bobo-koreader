use axum::extract::{Path, State as StateExtractor};
use axum::routing::{delete, get, patch, post};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use shared::settings::UserProfile;
use shared::usecases;

use crate::state::State;
use crate::AppError;

pub fn routes() -> Router<State> {
    Router::new()
        .route("/profiles", get(list_profiles))
        .route("/profiles", post(create_profile))
        .route("/profiles/{id}", delete(delete_profile))
        .route("/profiles/{id}", patch(update_profile))
        .route("/profiles/{id}/switch", post(switch_profile))
}

#[derive(Serialize)]
struct ProfileResponse {
    id: i64,
    name: String,
    active: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    color: Option<String>,
}

impl ProfileResponse {
    fn from(profile: UserProfile, active_id: i64) -> Self {
        Self {
            active: profile.id == active_id,
            id: profile.id,
            name: profile.name,
            color: profile.color,
        }
    }
}

async fn list_profiles(
    StateExtractor(State { settings, .. }): StateExtractor<State>,
) -> Json<Vec<ProfileResponse>> {
    let settings = settings.lock().await;
    let profiles = usecases::list_profiles(&settings);
    let active_id = settings.active_profile_id;
    Json(
        profiles
            .into_iter()
            .map(|p| ProfileResponse::from(p, active_id))
            .collect(),
    )
}

#[derive(Deserialize)]
struct CreateProfileRequest {
    name: String,
    #[serde(default)]
    color: Option<String>,
}

async fn create_profile(
    StateExtractor(State { settings, settings_path, .. }): StateExtractor<State>,
    Json(body): Json<CreateProfileRequest>,
) -> Result<Json<ProfileResponse>, AppError> {
    let mut settings = settings.lock().await;
    let profile = usecases::create_profile(&mut settings, &settings_path, body.name, body.color)?;
    let active_id = settings.active_profile_id;
    Ok(Json(ProfileResponse::from(profile, active_id)))
}

async fn delete_profile(
    StateExtractor(State { settings, settings_path, .. }): StateExtractor<State>,
    Path(id): Path<i64>,
) -> Result<Json<()>, AppError> {
    let mut settings = settings.lock().await;
    usecases::delete_profile(&mut settings, &settings_path, id)?;
    Ok(Json(()))
}

#[derive(Deserialize)]
struct UpdateProfileRequest {
    #[serde(default)]
    name: Option<String>,
    /// Use double-Option to distinguish "absent" from "explicitly null" (clear color).
    #[serde(default, deserialize_with = "deserialize_optional_color")]
    color: Option<Option<String>>,
}

fn deserialize_optional_color<'de, D>(
    deserializer: D,
) -> Result<Option<Option<String>>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    Ok(Some(Option::<String>::deserialize(deserializer)?))
}

async fn update_profile(
    StateExtractor(State { settings, settings_path, .. }): StateExtractor<State>,
    Path(id): Path<i64>,
    Json(body): Json<UpdateProfileRequest>,
) -> Result<Json<ProfileResponse>, AppError> {
    let mut settings = settings.lock().await;
    let profile =
        usecases::update_profile(&mut settings, &settings_path, id, body.name, body.color)?;
    let active_id = settings.active_profile_id;
    Ok(Json(ProfileResponse::from(profile, active_id)))
}

async fn switch_profile(
    StateExtractor(State { settings, settings_path, database, .. }): StateExtractor<State>,
    Path(id): Path<i64>,
) -> Result<Json<()>, AppError> {
    let home_path = settings_path
        .parent()
        .ok_or_else(|| anyhow::anyhow!("settings path has no parent"))?;
    let mut settings = settings.lock().await;
    let mut database = database.lock().await;
    usecases::switch_profile(&mut settings, &settings_path, &mut database, home_path, id).await?;
    Ok(Json(()))
}
