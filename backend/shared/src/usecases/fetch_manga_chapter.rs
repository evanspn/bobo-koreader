use std::path::{Path, PathBuf};

use anyhow::anyhow;
use serde::{Deserialize, Serialize};
use tokio_util::sync::CancellationToken;

use crate::{
    chapter_downloader::{
        ensure_chapter_is_in_storage, DownloadError, Error as ChapterDownloaderError,
    },
    chapter_storage::ChapterStorage,
    database::Database,
    model::ChapterId,
    source::Source,
};

/// The result of fetching a chapter, returned by `fetch_manga_chapter`.
/// Includes the on-disk path, page count (0 for novels), and any per-page errors.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChapterDownloadResult {
    pub path: PathBuf,
    pub page_count: usize,
    pub errors: Vec<DownloadError>,
}

/// Count image pages inside a CBZ (ZIP) file.
/// Returns 0 for epub/novel chapters or if the archive cannot be read.
pub fn count_cbz_pages(path: &Path) -> usize {
    if path.extension().and_then(|e| e.to_str()) != Some("cbz") {
        return 0;
    }
    let Ok(file) = std::fs::File::open(path) else {
        return 0;
    };
    let Ok(archive) = zip::ZipArchive::new(file) else {
        return 0;
    };
    archive
        .file_names()
        .filter(|name| !name.ends_with(".xml") && !name.starts_with('.'))
        .count()
}

pub async fn fetch_manga_chapter(
    token: &CancellationToken,
    database: &Database,
    source: &Source,
    chapter_storage: &ChapterStorage,
    chapter_id: &ChapterId,
    concurrent_requests_pages: usize,
    optimize_image: bool,
) -> Result<ChapterDownloadResult, Error> {
    let manga = database
        .find_cached_manga_information(chapter_id.manga_id())
        .await?
        .ok_or_else(|| anyhow!("Expected manga to be in the database"))?;

    let chapter = database
        .find_cached_chapter_information(chapter_id)
        .await?
        .ok_or_else(|| anyhow!("Expected chapter to be in the database"))?;

    let (path, errors) = ensure_chapter_is_in_storage(
        token,
        chapter_storage,
        source,
        &manga,
        &chapter,
        concurrent_requests_pages,
        optimize_image,
    )
    .await
    .map_err(|e| match e {
        ChapterDownloaderError::DownloadError(e) => Error::DownloadError(e),
        ChapterDownloaderError::Other(e) => Error::Other(e),
    })?;

    let page_count = count_cbz_pages(&path);

    Ok(ChapterDownloadResult { path, page_count, errors })
}

#[derive(thiserror::Error, Debug)]
pub enum Error {
    #[error("an error occurred while downloading the chapter pages")]
    DownloadError(#[source] anyhow::Error),
    #[error("unknown error")]
    Other(#[from] anyhow::Error),
}
