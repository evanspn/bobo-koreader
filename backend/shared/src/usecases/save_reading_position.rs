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

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::NamedTempFile;

    async fn test_db() -> (Database, NamedTempFile) {
        let file = NamedTempFile::new().unwrap();
        let db = Database::new(file.path()).await.unwrap();
        (db, file)
    }

    fn chapter_id() -> ChapterId {
        ChapterId::from_strings("src".into(), "manga-1".into(), "ch-1".into())
    }

    #[tokio::test]
    async fn saves_page_and_offset() {
        let (db, _file) = test_db().await;
        let id = chapter_id();

        save_reading_position(&db, &id, 12, 340).await.unwrap();

        let state = db.find_chapter_state(&id).await.unwrap().unwrap();
        assert_eq!(state.current_page, Some(12));
        assert_eq!(state.scroll_offset, Some(340));
    }

    #[tokio::test]
    async fn overwrites_previous_position() {
        let (db, _file) = test_db().await;
        let id = chapter_id();

        save_reading_position(&db, &id, 5, 0).await.unwrap();
        save_reading_position(&db, &id, 20, 150).await.unwrap();

        let state = db.find_chapter_state(&id).await.unwrap().unwrap();
        assert_eq!(state.current_page, Some(20));
        assert_eq!(state.scroll_offset, Some(150));
    }

    #[tokio::test]
    async fn does_not_clobber_read_flag() {
        let (db, _file) = test_db().await;
        let id = chapter_id();

        // Mark chapter read first
        db.mark_chapter_as_read(&id, Some(true)).await.unwrap();
        // Then save position
        save_reading_position(&db, &id, 8, 0).await.unwrap();

        let state = db.find_chapter_state(&id).await.unwrap().unwrap();
        assert!(state.read, "read flag should be preserved");
        assert_eq!(state.current_page, Some(8));
    }

    #[tokio::test]
    async fn position_defaults_to_none_for_new_chapter() {
        let (db, _file) = test_db().await;
        let id = ChapterId::from_strings("src".into(), "manga-1".into(), "ch-new".into());

        let state = db.find_chapter_state(&id).await.unwrap();
        assert!(state.is_none());
    }
}
