//! Reading stats for the active profile. The Database the caller holds
//! is already scoped to the active profile (see `Database::switch_to`),
//! so this use case naturally segregates stats by profile.
//!
//! Aggregation is split between SQL (the heavy COUNT/GROUP BY work) and
//! pure Rust (binning timestamps into weeks, counting tags, computing
//! streaks). The pure-Rust half is unit-tested without a database.

use anyhow::Result;
use serde::Serialize;

use crate::database::{Database, ReadMangaSummary};

const TOP_MANGA_LIMIT: usize = 10;
const TOP_GENRES_LIMIT: usize = 10;
const WEEKS_OF_HISTORY: usize = 12;
const SECONDS_PER_DAY: i64 = 86_400;
const SECONDS_PER_WEEK: i64 = SECONDS_PER_DAY * 7;

#[derive(Serialize)]
pub struct LibraryStats {
    pub chapters_read: i64,
    pub mangas_read: i64,
    pub last_read: Option<i64>,
    pub current_streak_days: i64,
    pub longest_streak_days: i64,
    pub days_active: i64,
    /// Weekly read counts, oldest → newest, always exactly
    /// `WEEKS_OF_HISTORY` entries (missing weeks render as zero so the
    /// frontend can draw a uniform-width chart).
    pub weeks: Vec<WeeklyCount>,
    pub top_manga: Vec<TopManga>,
    pub top_genres: Vec<GenreCount>,
}

#[derive(Serialize)]
pub struct WeeklyCount {
    /// Unix timestamp of the start of the week (Monday 00:00 UTC).
    pub start: i64,
    pub chapters: i64,
}

#[derive(Serialize)]
pub struct TopManga {
    pub source_id: String,
    pub manga_id: String,
    pub title: String,
    pub chapters_read: i64,
    pub last_read: Option<i64>,
}

#[derive(Serialize)]
pub struct GenreCount {
    pub name: String,
    pub manga_count: i64,
}

pub async fn get_library_stats(db: &Database) -> Result<LibraryStats> {
    let totals = db.read_chapters_total().await?;
    let timestamps = db.read_chapter_timestamps().await?;
    let summaries = db.read_manga_summary().await?;
    let tags_json = db.read_manga_tags().await?;

    let now = chrono::Utc::now().timestamp();
    Ok(build_stats(now, totals.chapters, totals.mangas, totals.last_read, &timestamps, summaries, &tags_json))
}

fn build_stats(
    now: i64,
    chapters_read: i64,
    mangas_read: i64,
    last_read: Option<i64>,
    timestamps: &[i64],
    summaries: Vec<ReadMangaSummary>,
    tags_json: &[Option<String>],
) -> LibraryStats {
    let weeks = bin_into_weeks(now, timestamps, WEEKS_OF_HISTORY);
    let (current_streak_days, longest_streak_days, days_active) = streaks(now, timestamps);
    let top_manga = top_manga(summaries, TOP_MANGA_LIMIT);
    let top_genres = top_genres(tags_json, TOP_GENRES_LIMIT);

    LibraryStats {
        chapters_read,
        mangas_read,
        last_read,
        current_streak_days,
        longest_streak_days,
        days_active,
        weeks,
        top_manga,
        top_genres,
    }
}

/// Snap `t` down to the most recent Monday 00:00 UTC.
fn week_start(t: i64) -> i64 {
    // The Unix epoch (1970-01-01) was a Thursday, so day-of-week-from-epoch
    // = (days + 3) % 7 where Monday = 0.
    let days_since_epoch = t.div_euclid(SECONDS_PER_DAY);
    let dow = (days_since_epoch + 3).rem_euclid(7); // Mon=0..Sun=6
    (days_since_epoch - dow) * SECONDS_PER_DAY
}

fn bin_into_weeks(now: i64, timestamps: &[i64], buckets: usize) -> Vec<WeeklyCount> {
    let current_week_start = week_start(now);
    let oldest_week_start = current_week_start - ((buckets as i64) - 1) * SECONDS_PER_WEEK;

    let mut counts = vec![0i64; buckets];
    for &t in timestamps {
        if t < oldest_week_start {
            continue;
        }
        let idx = ((t - oldest_week_start) / SECONDS_PER_WEEK) as usize;
        if idx < buckets {
            counts[idx] += 1;
        }
    }

    counts
        .into_iter()
        .enumerate()
        .map(|(i, chapters)| WeeklyCount {
            start: oldest_week_start + (i as i64) * SECONDS_PER_WEEK,
            chapters,
        })
        .collect()
}

/// Returns `(current_streak, longest_streak, days_active)` measured in
/// distinct UTC days where at least one chapter was marked as read.
/// The current streak ends at "today" or "yesterday" — gapping past
/// yesterday breaks the streak.
fn streaks(now: i64, timestamps: &[i64]) -> (i64, i64, i64) {
    if timestamps.is_empty() {
        return (0, 0, 0);
    }

    let mut days: Vec<i64> = timestamps
        .iter()
        .map(|t| t.div_euclid(SECONDS_PER_DAY))
        .collect();
    days.sort_unstable();
    days.dedup();

    let days_active = days.len() as i64;

    let mut longest = 1i64;
    let mut run = 1i64;
    for w in days.windows(2) {
        if w[1] == w[0] + 1 {
            run += 1;
            if run > longest {
                longest = run;
            }
        } else {
            run = 1;
        }
    }

    let today = now.div_euclid(SECONDS_PER_DAY);
    let last = *days.last().unwrap();
    let current = if last < today - 1 {
        0
    } else {
        // Walk backwards from `last`, extending while days stay consecutive.
        let mut count = 1i64;
        let mut prev = last;
        for i in (0..days.len() - 1).rev() {
            if days[i] + 1 == prev {
                count += 1;
                prev = days[i];
            } else {
                break;
            }
        }
        count
    };

    (current, longest, days_active)
}

fn top_manga(mut summaries: Vec<ReadMangaSummary>, limit: usize) -> Vec<TopManga> {
    summaries.sort_by(|a, b| {
        b.chapters_read
            .cmp(&a.chapters_read)
            .then_with(|| b.last_read.unwrap_or(0).cmp(&a.last_read.unwrap_or(0)))
            .then_with(|| a.title.cmp(&b.title))
    });
    summaries
        .into_iter()
        .take(limit)
        .map(|s| TopManga {
            source_id: s.source_id,
            manga_id: s.manga_id,
            title: s.title,
            chapters_read: s.chapters_read,
            last_read: s.last_read,
        })
        .collect()
}

fn top_genres(tags_json: &[Option<String>], limit: usize) -> Vec<GenreCount> {
    use std::collections::HashMap;

    let mut counts: HashMap<String, i64> = HashMap::new();
    for raw in tags_json.iter().flatten() {
        let parsed: Result<Vec<String>, _> = serde_json::from_str(raw);
        let Ok(tags) = parsed else { continue };
        // De-dup per-manga so a manga listing "Action" twice doesn't
        // inflate the genre.
        let mut seen = std::collections::HashSet::new();
        for tag in tags {
            let tag = tag.trim().to_string();
            if tag.is_empty() {
                continue;
            }
            if seen.insert(tag.clone()) {
                *counts.entry(tag).or_default() += 1;
            }
        }
    }

    let mut out: Vec<GenreCount> = counts
        .into_iter()
        .map(|(name, manga_count)| GenreCount { name, manga_count })
        .collect();
    out.sort_by(|a, b| {
        b.manga_count
            .cmp(&a.manga_count)
            .then_with(|| a.name.cmp(&b.name))
    });
    out.truncate(limit);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ts(year: i32, month: u32, day: u32) -> i64 {
        chrono::NaiveDate::from_ymd_opt(year, month, day)
            .unwrap()
            .and_hms_opt(12, 0, 0)
            .unwrap()
            .and_utc()
            .timestamp()
    }

    #[test]
    fn week_start_lands_on_monday_00_00_utc() {
        // 2024-01-03 (Wednesday) → 2024-01-01 (Monday)
        let wed = ts(2024, 1, 3);
        let mon = chrono::NaiveDate::from_ymd_opt(2024, 1, 1)
            .unwrap()
            .and_hms_opt(0, 0, 0)
            .unwrap()
            .and_utc()
            .timestamp();
        assert_eq!(week_start(wed), mon);

        // Monday at noon snaps to that same Monday at 00:00.
        let mon_noon = ts(2024, 1, 1);
        assert_eq!(week_start(mon_noon), mon);

        // Sunday snaps back to the previous Monday.
        let sun = ts(2024, 1, 7);
        assert_eq!(week_start(sun), mon);
    }

    #[test]
    fn bin_into_weeks_drops_older_than_window_and_aligns_index() {
        // "now" = Wednesday 2024-01-10. 4 buckets means weeks of
        // 12/18, 12/25, 1/1, 1/8 — and any read before 12/18 is dropped.
        let now = ts(2024, 1, 10);
        let timestamps = vec![
            ts(2023, 12, 1),  // dropped (too old)
            ts(2023, 12, 20), // bucket 0
            ts(2023, 12, 26), // bucket 1
            ts(2024, 1, 2),   // bucket 2
            ts(2024, 1, 2),   // bucket 2
            ts(2024, 1, 10),  // bucket 3
        ];
        let weeks = bin_into_weeks(now, &timestamps, 4);
        assert_eq!(weeks.len(), 4);
        assert_eq!(weeks[0].chapters, 1);
        assert_eq!(weeks[1].chapters, 1);
        assert_eq!(weeks[2].chapters, 2);
        assert_eq!(weeks[3].chapters, 1);
        // The last bucket starts at the Monday of the week containing `now`.
        assert_eq!(weeks[3].start, week_start(now));
    }

    #[test]
    fn streak_counts_consecutive_days_back_from_today_or_yesterday() {
        let today = ts(2024, 6, 10); // Monday
        let timestamps = vec![
            ts(2024, 6, 10), // today
            ts(2024, 6, 9),  // yesterday
            ts(2024, 6, 8),
            ts(2024, 6, 6), // gap
        ];
        let (current, longest, active) = streaks(today, &timestamps);
        assert_eq!(current, 3);
        assert_eq!(longest, 3);
        assert_eq!(active, 4);
    }

    #[test]
    fn streak_allows_a_one_day_grace_when_last_read_is_yesterday() {
        let now = ts(2024, 6, 10);
        let yesterday = ts(2024, 6, 9);
        let (current, _, _) = streaks(now, &[yesterday]);
        assert_eq!(current, 1);
    }

    #[test]
    fn streak_resets_when_last_read_is_older_than_yesterday() {
        let now = ts(2024, 6, 10);
        let two_days_ago = ts(2024, 6, 8);
        let (current, longest, _) = streaks(now, &[two_days_ago]);
        assert_eq!(current, 0);
        assert_eq!(longest, 1);
    }

    #[test]
    fn empty_timestamps_produce_zeroed_streaks() {
        let now = ts(2024, 6, 10);
        let (current, longest, active) = streaks(now, &[]);
        assert_eq!(current, 0);
        assert_eq!(longest, 0);
        assert_eq!(active, 0);
    }

    fn manga(source: &str, id: &str, title: &str, chapters: i64, last_read: Option<i64>) -> ReadMangaSummary {
        ReadMangaSummary {
            source_id: source.into(),
            manga_id: id.into(),
            title: title.into(),
            chapters_read: chapters,
            last_read,
        }
    }

    #[test]
    fn top_manga_sorts_by_chapters_then_recency_then_title() {
        let rows = vec![
            manga("s", "a", "Alpha", 5, Some(100)),
            manga("s", "b", "Bravo", 10, Some(200)),
            manga("s", "c", "Charlie", 10, Some(300)),
            manga("s", "d", "Delta", 10, Some(300)),
        ];
        let top = top_manga(rows, 3);
        assert_eq!(top.len(), 3);
        // 10 chapters, last_read=300: Charlie vs Delta — same recency,
        // tie-broken by title (Charlie wins).
        assert_eq!(top[0].title, "Charlie");
        assert_eq!(top[1].title, "Delta");
        assert_eq!(top[2].title, "Bravo");
    }

    #[test]
    fn top_genres_counts_each_manga_once_and_skips_nulls() {
        let tags = vec![
            Some(r#"["Action","Romance"]"#.into()),
            Some(r#"["Action","Action","Comedy"]"#.into()), // de-duped per manga
            Some(r#"["Romance"]"#.into()),
            None,
            Some("not valid json".into()),
        ];
        let g = top_genres(&tags, 5);
        let lookup: std::collections::HashMap<_, _> =
            g.iter().map(|x| (x.name.as_str(), x.manga_count)).collect();
        assert_eq!(lookup["Action"], 2);
        assert_eq!(lookup["Romance"], 2);
        assert_eq!(lookup["Comedy"], 1);
    }

    #[test]
    fn build_stats_threads_inputs_through_correctly() {
        let now = ts(2024, 6, 10);
        let stats = build_stats(
            now,
            7,
            2,
            Some(ts(2024, 6, 9)),
            &[ts(2024, 6, 9), ts(2024, 6, 10)],
            vec![manga("s", "a", "Alpha", 7, Some(now))],
            &[Some(r#"["Action"]"#.into())],
        );
        assert_eq!(stats.chapters_read, 7);
        assert_eq!(stats.mangas_read, 2);
        assert_eq!(stats.current_streak_days, 2);
        assert_eq!(stats.weeks.len(), WEEKS_OF_HISTORY);
        assert_eq!(stats.top_manga.len(), 1);
        assert_eq!(stats.top_genres[0].name, "Action");
    }
}
