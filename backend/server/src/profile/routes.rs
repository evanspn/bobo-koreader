use axum::extract::{Path, State as StateExtractor};
use axum::routing::{delete, get, post};
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
        .route("/profiles/:id", delete(delete_profile))
        .route("/profiles/:id/switch", post(switch_profile))
}

#[derive(Serialize)]
struct ProfileResponse {
    id: i64,
    name: String,
    active: bool,
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
            .map(|p| ProfileResponse { active: p.id == active_id, id: p.id, name: p.name })
            .collect(),
    )
}

#[derive(Deserialize)]
struct CreateProfileRequest {
    name: String,
}

async fn create_profile(
    StateExtractor(State { settings, settings_path, .. }): StateExtractor<State>,
    Json(body): Json<CreateProfileRequest>,
) -> Result<Json<UserProfile>, AppError> {
    let mut settings = settings.lock().await;
    let profile = usecases::create_profile(&mut settings, &settings_path, body.name)?;
    Ok(Json(profile))
}

async fn delete_profile(
    StateExtractor(State { settings, settings_path, .. }): StateExtractor<State>,
    Path(id): Path<i64>,
) -> Result<Json<()>, AppError> {
    let mut settings = settings.lock().await;
    usecases::delete_profile(&mut settings, &settings_path, id)?;
    Ok(Json(()))
}

async fn switch_profile(
    StateExtractor(State { settings, settings_path, database, home_path, .. }): StateExtractor<State>,
    Path(id): Path<i64>,
) -> Result<Json<()>, AppError> {
    let mut settings = settings.lock().await;
    let mut database = database.lock().await;
    usecases::switch_profile(&mut settings, &settings_path, &mut database, &home_path, id).await?;
    Ok(Json(()))
}
