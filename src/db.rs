use std::env;
use std::sync::Arc;

use anyhow::{Context, Result};
use chrono::Utc;

use crate::UtcTime;

use super::{Entry, Feed};

#[derive(Clone)]
pub struct DB {
    conn: libsql::Connection,
    #[allow(dead_code)] // someday
    db: Arc<libsql::Database>,
}

pub enum ConnectionBacking {
    #[allow(dead_code)] // used in tests...
    Memory,
    File(String),
    Remote(TursoCreds),
    RemoteReplica(TursoCreds, String),
}

pub struct TursoCreds {
    pub url: String,
    pub token: String,
}

impl TursoCreds {
    pub fn from_env() -> Option<Self> {
        Some(Self {
            url: env::var("TURSO_URL").ok()?,
            token: env::var("TURSO_TOKEN").ok()?,
        })
    }
}

pub async fn connect(conn_back: ConnectionBacking) -> Result<DB> {
    let db = match conn_back {
        ConnectionBacking::Remote(creds) => {
            libsql::Builder::new_remote(creds.url, creds.token)
                .build()
                .await?
        }
        ConnectionBacking::RemoteReplica(creds, p) => {
            libsql::Builder::new_remote_replica(p, creds.url, creds.token)
                .build()
                .await?
        }
        ConnectionBacking::File(p) => libsql::Builder::new_local(p).build().await?,
        ConnectionBacking::Memory => libsql::Builder::new_local(":memory:").build().await?,
    };
    let conn = db.connect()?;
    Ok(DB {
        conn,
        db: db.into(),
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

pub enum EntryFilter {
    Unread,
    Starred,
    All,
}

impl From<String> for EntryFilter {
    fn from(s: String) -> EntryFilter {
        match s.as_str() {
            "unread" => EntryFilter::Unread,
            "starred" => EntryFilter::Starred,
            _ => EntryFilter::All,
        }
    }
}

impl DB {
    pub(crate) async fn init(&self) -> Result<()> {
        self.conn
            .execute_batch(
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
    feed          TEXT
);
                "#,
            )
            .await
            .context("couldn't init db")
    }

    pub(crate) async fn add_feeds<T>(&self, feeds: T) -> Result<()>
    where
        T: Iterator<Item = Feed>,
    {
        let tx = self.conn.transaction().await?;
        {
            let mut stmt = tx
                .prepare(
                    r#"
    INSERT OR REPLACE INTO feeds (id, name, site_url, feed_url, last_fetched, fetch_error, category)
    VALUES (?, ?, ?, ?, ?, ?, ?);
                    "#,
                )
                .await
                .context("couldn't prepare statement")?;

            for f in feeds {
                let _ = stmt
                    .execute((
                        f.id,
                        f.name,
                        f.site_url,
                        f.feed_url,
                        f.last_fetched,
                        f.fetch_error,
                        f.category,
                    ))
                    .await?;
                stmt.reset();
            }
        }
        tx.commit().await?;

        Ok(())
    }

    pub(crate) async fn get_feeds(&self) -> Result<Vec<Feed>> {
        let mut stmt = self.conn.prepare("SELECT id, name, site_url, feed_url, last_fetched, fetch_error, category FROM feeds")
        .await
        .context("couldn't prepare statement")?;
        let mut rows = stmt.query(()).await?;
        let mut feeds: Vec<Feed> = vec![];
        // TODO: Use .into_stream
        while let Some(row) = rows.next().await.unwrap() {
            let feed = libsql::de::from_row(&row)?;
            feeds.push(feed);
        }

        Ok(feeds)
    }

    pub(crate) async fn remove_feed(&self, id: String) -> Result<()> {
        let mut stmt = self.conn.prepare("DELETE FROM feeds WHERE id = ?").await?;
        stmt.execute([id]).await?;

        Ok(())
    }

    pub(crate) async fn update_feed_status(&self, id: String, error: Option<String>) -> Result<()> {
        let mut stmt = self
            .conn
            .prepare(
                "UPDATE feeds SET fetch_error = ?, last_fetched = ?
                WHERE id = ?",
            )
            .await?;

        stmt.execute((error, UtcTime(Utc::now()), id)).await?;

        Ok(())
    }

    pub(crate) async fn add_entries<T>(&self, entries: T) -> Result<()>
    where
        T: Iterator<Item = Entry>,
    {
        let tx = self.conn.transaction().await?;
        {
            let mut stmt = tx.prepare(
                    "INSERT OR IGNORE INTO entries (id, title, content_link, comments_link, robust_link, published, read, starred, feed)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
                ).await?;
            for e in entries {
                let _ = stmt
                    .execute((
                        e.id,
                        e.title,
                        e.content_link,
                        e.comments_link,
                        e.robust_link,
                        e.published,
                        e.read,
                        e.starred,
                        e.feed,
                    ))
                    .await?;
                stmt.reset();
            }
        }
        tx.commit().await?;

        Ok(())
    }

    pub(crate) async fn get_entries(
        &self,
        filter: EntryFilter,
        ordering: Ordering,
    ) -> Result<Vec<Entry>> {
        let order_clause = match ordering {
            Ordering::Ascending => "ORDER BY published ASC",
            Ordering::Descending => "ORDER BY published DESC",
        };

        let where_clause = match filter {
            EntryFilter::Starred => "WHERE starred = true",
            EntryFilter::Unread => "WHERE read = false",
            EntryFilter::All => "",
        };
        let statement_string = format!("SELECT id, title, content_link, comments_link, robust_link, published, read, starred, feed FROM entries {} {}", where_clause, order_clause);
        let mut stmt = self
            .conn
            .prepare(&statement_string)
            .await
            .context("couldn't prepare statement")?;
        let mut rows = stmt.query(()).await?;
        let mut entries: Vec<Entry> = vec![];
        // TODO: Use .into_stream
        while let Some(row) = rows.next().await? {
            let entry = libsql::de::from_row(&row)?;
            entries.push(entry);
        }
        Ok(entries)
    }

    pub(crate) async fn get_starred_entries(&self) -> Result<Vec<Entry>> {
        self.get_entries(EntryFilter::Starred, Ordering::Ascending)
            .await
    }

    pub(crate) async fn get_unread_entries(&self) -> Result<Vec<Entry>> {
        self.get_entries(EntryFilter::Unread, Ordering::Ascending)
            .await
    }

    pub(crate) async fn mark_entry_read(
        &self,
        entry_id: String,
        filter: EntryFilter,
        ordering: Ordering,
    ) -> Result<Vec<Entry>> {
        {
            let mut stmt = self
                .conn
                .prepare("UPDATE entries SET read = NOT read WHERE id = ?")
                .await
                .context("couldn't prepare statement")?;
            stmt.execute([entry_id]).await?;
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
            let mut stmt = self
                .conn
                .prepare("UPDATE entries SET starred = NOT starred WHERE id = ?")
                .await
                .context("couldn't prepare statement")?;
            stmt.execute([entry_id]).await?;
        }
        self.get_entries(filter, ordering).await
    }
}

impl From<UtcTime> for libsql::Value {
    fn from(t: UtcTime) -> libsql::Value {
        libsql::Value::Text(t.0.to_rfc3339())
    }
}
