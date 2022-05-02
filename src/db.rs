use futures::lock::Mutex;
use std::path::Path;
use std::sync::Arc;

use anyhow::{Context, Result};
use chrono::Utc;

use rusqlite::{params, Connection};

use super::{Entry, Feed};

#[derive(Clone)]
pub struct DB {
    conn: Arc<Mutex<Connection>>,
}

pub enum ConnectionBacking<'a> {
    #[allow(dead_code)] // used in tests...
    Memory,
    File(&'a dyn AsRef<Path>),
}

pub async fn connect(conn_back: ConnectionBacking<'_>) -> Result<DB> {
    let conn = match conn_back {
        ConnectionBacking::File(p) => Connection::open(p)?,
        ConnectionBacking::Memory => Connection::open_in_memory()?,
    };
    Ok(DB {
        conn: Arc::new(Mutex::new(conn)),
    })
}

pub enum Ordering {
    Ascending,
    Descending,
}

impl From<String> for Ordering {
    fn from(s: String) -> Ordering {
        match s.as_ref() {
            "ASC" => Ordering::Ascending,
            "DESC" => Ordering::Descending,
            &_ => Ordering::Ascending,
        }
    }
}

type EntryFilter = fn(e: &Entry) -> bool;

pub(crate) fn unread_filter(e: &Entry) -> bool {
    !e.read
}

pub(crate) fn starred_filter(e: &Entry) -> bool {
    e.starred
}

pub(crate) fn name_to_filter(e: &str) -> EntryFilter {
    match e {
        "unread" => unread_filter,
        "starred" => starred_filter,
        _ => |_| true,
    }
}

impl DB {
    pub(crate) async fn init(&self) -> Result<()> {
        let conn = self.conn.lock().await;
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS feeds
(
    id           TEXT PRIMARY KEY NOT NULL,
    name         TEXT NOT NULL,
    site_url     TEXT NOT NULL,
    feed_url     TEXT NOT NULL,
    last_fetched DATETIME,
    fetch_error  TEXT,
    category     TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS entries
(
    id            TEXT PRIMARY KEY NOT NULL,
    title         TEXT NOT NULL,
    content_link  TEXT NOT NULL,
    comments_link TEXT,
    robust_link   TEXT,
    published     DATETIME,
    read          BOOLEAN,
    starred       BOOLEAN,
    feed_name     TEXT
);
                "#,
        )
        .context("couldn't init db")
    }

    pub(crate) async fn add_feeds<T>(&self, feeds: T) -> Result<()>
    where
        T: Iterator<Item = Feed>,
    {
        let mut conn = self.conn.lock().await;
        let tx = conn.transaction()?;
        {
            let mut stmt = tx
                .prepare_cached(
                    r#"
    INSERT OR REPLACE INTO feeds (id, name, site_url, feed_url, last_fetched, fetch_error, category)
    VALUES (?, ?, ?, ?, ?, ?, ?);
                    "#,
                )
                .context("couldn't prepare statement")?;

            for f in feeds {
                let _ = stmt.execute(params![
                    f.id,
                    f.name,
                    f.site_url,
                    f.feed_url,
                    f.last_fetched,
                    f.fetch_error,
                    f.category
                ]);
            }
        }
        tx.commit()?;

        Ok(())
    }

    pub(crate) async fn get_feeds(&self) -> Result<Vec<Feed>> {
        let conn = self.conn.lock().await;
        let mut stmt = conn.prepare_cached("SELECT id, name, site_url, feed_url, last_fetched, fetch_error, category FROM feeds").context("couldn't prepare statement")?;
        let feed_iter = stmt.query_map([], |row| {
            let f = Feed {
                id: row.get(0)?,
                name: row.get(1)?,
                site_url: row.get(2)?,
                feed_url: row.get(3)?,
                last_fetched: row.get(4)?,
                fetch_error: row.get(5)?,
                category: row.get(6)?,
            };
            Ok(f)
        })?;

        let mut feeds: Vec<Feed> = vec![];
        for f in feed_iter {
            feeds.push(f.unwrap())
        }
        Ok(feeds)
    }

    pub(crate) async fn remove_feed(&self, id: String) -> Result<()> {
        let conn = self.conn.lock().await;
        let mut stmt = conn.prepare_cached("DELETE FROM feeds WHERE id = ?")?;
        stmt.execute(params![id])?;

        Ok(())
    }

    pub(crate) async fn update_feed_status(&self, id: String, error: Option<String>) -> Result<()> {
        let conn = self.conn.lock().await;
        let mut stmt = conn.prepare_cached(
            "UPDATE feeds SET fetch_error = ?, last_fetched = ?
                WHERE id = ?",
        )?;

        stmt.execute(params![error, Utc::now(), id])?;

        Ok(())
    }

    pub(crate) async fn add_entries<T>(&self, entries: T) -> Result<()>
    where
        T: Iterator<Item = Entry>,
    {
        let mut conn = self.conn.lock().await;
        let tx = conn.transaction()?;
        {
            let mut stmt = tx.prepare_cached(
                    "INSERT OR IGNORE INTO entries (id, title, content_link, comments_link, robust_link, published, read, starred, feed_name)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
                )?;
            for e in entries {
                let _ = stmt.execute(params![
                    e.id,
                    e.title,
                    e.content_link,
                    e.comments_link,
                    e.robust_link,
                    e.published,
                    e.read,
                    e.starred,
                    e.feed
                ]);
            }
        }
        tx.commit()?;

        Ok(())
    }

    pub(crate) async fn get_entries(&self, filter: EntryFilter, ordering: Ordering) -> Result<Vec<Entry>> {
        let conn = self.conn.lock().await;
        let order = match ordering {
            Ordering::Ascending => "ASC",
            Ordering::Descending => "DESC",
        };
        let mut stmt = conn.prepare_cached(format!("SELECT id, title, content_link, comments_link, robust_link, published, read, starred, feed_name FROM entries ORDER BY published {}", order).as_ref()).context("couldn't prepare statement")?;
        let entry_iter = stmt.query_map([], |row| {
            Ok(Entry {
                id: row.get(0)?,
                title: row.get(1)?,
                content_link: row.get(2)?,
                comments_link: row.get(3)?,
                robust_link: row.get(4)?,
                published: row.get(5)?,
                read: row.get(6)?,
                starred: row.get(7)?,
                feed: row.get(8)?,
            })
        })?;

        let mut entries: Vec<Entry> = vec![];
        for e in entry_iter {
            let e = e.unwrap();
            if filter(&e) {
                entries.push(e)
            }
        }
        Ok(entries)
    }

    pub(crate) async fn get_starred_entries(&self) -> Result<Vec<Entry>> {
        self.get_entries(|e| e.starred, Ordering::Ascending).await
    }

    pub(crate) async fn get_unread_entries(&self) -> Result<Vec<Entry>> {
        self.get_entries(|e| !e.read, Ordering::Ascending).await
    }

    pub(crate) async fn mark_entry_read(
        &self,
        entry_id: String,
        filter: EntryFilter,
        ordering: Ordering,
    ) -> Result<Vec<Entry>> {
        {
            let conn = self.conn.lock().await;
            let mut stmt = conn
                .prepare_cached("UPDATE entries SET read = NOT read WHERE id = ?")
                .context("couldn't prepare statement")?;
            stmt.execute(params![entry_id])?;
        }
        self.get_entries(filter, ordering).await
    }

    pub(crate) async fn mark_entry_starred(
        &self,
        entry_id: String,
        filter: EntryFilter,
        ordering: Ordering,
    ) -> Result<Vec<Entry>> {
        {
            let conn = self.conn.lock().await;
            let mut stmt = conn
                .prepare_cached("UPDATE entries SET starred = NOT starred WHERE id = ?")
                .context("couldn't prepare statement")?;
            stmt.execute(params![entry_id])?;
        }
        self.get_entries(filter, ordering).await
    }}
