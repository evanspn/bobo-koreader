use anyhow::Result;

use crate::{database::Database, model::ChapterId};

pub async fn save_reading_position(
    db: &Database,
    id: &ChapterId,
    page: i32,
    offset: i32,
) -> Result<()> {
    db.save_reading_position(id, page, offset).await?;
    Ok(())
}
