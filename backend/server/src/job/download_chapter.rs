use shared::{
    chapter_storage::ChapterStorage, database::Database, model::ChapterId,
    source_collection::SourceCollection, source_manager::SourceManager,
    usecases::{self, ChapterDownloadResult},
};
use std::sync::Arc;
use tokio::sync::watch;
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

use crate::{AppError, ErrorResponse};

use super::state::{Job, JobState};

type JobSender = watch::Sender<Option<Result<Arc<ChapterDownloadResult>, ErrorResponse>>>;
type JobReceiver = watch::Receiver<Option<Result<Arc<ChapterDownloadResult>, ErrorResponse>>>;

pub struct DownloadChapterJob {
    tx: JobSender,
    rx: JobReceiver,
    handle: JoinHandle<()>,
    cancellation_token: CancellationToken,
}

impl DownloadChapterJob {
    pub fn spawn_new(
        source_manager: Arc<tokio::sync::Mutex<SourceManager>>,
        db: Arc<tokio::sync::Mutex<Database>>,
        chapter_storage: ChapterStorage,
        chapter_id: ChapterId,
        concurrent_requests_pages: usize,
        optimize_image: bool,
    ) -> Self {
        let (tx, rx) =
            watch::channel::<Option<Result<Arc<ChapterDownloadResult>, ErrorResponse>>>(None);

        let cancellation_token = CancellationToken::new();
        let tx_clone = tx.clone();
        let token_clone = cancellation_token.clone();
        let handle = tokio::spawn(async move {
            let result = Self::do_job(
                token_clone,
                source_manager,
                db,
                chapter_storage,
                chapter_id,
                concurrent_requests_pages,
                optimize_image,
            )
            .await
            .map(Arc::new);

            let _ = tx_clone.send_replace(Some(result));
        });

        Self {
            tx,
            rx,
            handle,
            cancellation_token,
        }
    }

    async fn do_job(
        cancellation_token: CancellationToken,
        source_manager: Arc<tokio::sync::Mutex<SourceManager>>,
        db: Arc<tokio::sync::Mutex<Database>>,
        chapter_storage: ChapterStorage,
        chapter_id: ChapterId,
        concurrent_requests_pages: usize,
        optimize_image: bool,
    ) -> Result<ChapterDownloadResult, ErrorResponse> {
        let source = {
            let mgr = source_manager.lock().await;
            mgr.get_by_id(chapter_id.source_id())
                .cloned()
                .ok_or(AppError::SourceNotFound)?
        };
        let db: tokio::sync::MutexGuard<'_, Database> = { db.lock().await };

        Ok(usecases::fetch_manga_chapter(
            &cancellation_token,
            &db,
            &source,
            &chapter_storage,
            &chapter_id,
            concurrent_requests_pages,
            optimize_image,
        )
        .await
        .map_err(AppError::from)?)
    }
}

impl Job for DownloadChapterJob {
    type Progress = ();
    type Output = Arc<ChapterDownloadResult>;
    type Error = ErrorResponse;

    async fn cancel(&self) -> Result<(), AppError> {
        self.cancellation_token.cancel();
        self.handle.abort();

        let _ = self.tx.send(Some(Err(ErrorResponse {
            message: "Download was canceled by user".into(),
        })));

        Ok(())
    }

    async fn poll(&self) -> JobState<Self::Progress, Self::Output, Self::Error> {
        match self.rx.borrow().as_ref() {
            None => JobState::InProgress(()),
            Some(Ok(path)) => JobState::Completed(path.clone()),
            Some(Err(e)) => JobState::Errored(e.clone()),
        }
    }
}
