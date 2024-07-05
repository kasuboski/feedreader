use std::sync::Arc;
use std::{env, str::FromStr};

use anyhow::{Context, Result};
use chrono::Utc;

use crate::UtcTime;

use super::{Entry, Feed};

#[derive(Clone)]
pub struct DB {
    main_conn: libsql::Connection,
    update_conn: libsql::Connection,
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
    let main_conn = db.connect()?;
    // update is always in memory for now
    let update_conn = libsql::Builder::new_local(":memory:")
        .build()
        .await?
        .connect()?;
    Ok(DB {
        main_conn,
        update_conn,
        db: db.into(),
    })
}

pub enum Ordering {
    Ascending,
    Descending,
}

impl FromStr for Ordering {
    type Err = anyhow::Error;
    fn from_str(s: &str) -> Result<Ordering> {
        Ok(match s {
            "ASC" => Ordering::Ascending,
            "DESC" => Ordering::Descending,
            &_ => Ordering::Ascending,
        })
    }
}

pub enum EntryFilter {
    Unread,
    Starred,
    All,
}

impl FromStr for EntryFilter {
    type Err = anyhow::Error;
    fn from_str(s: &str) -> Result<EntryFilter> {
        Ok(match s {
            "unread" => EntryFilter::Unread,
            "starred" => EntryFilter::Starred,
            _ => EntryFilter::All,
        })
    }
}

impl DB {
    pub(crate) async fn init(&self) -> Result<()> {
        self.main_conn
            .execute_batch(
                r#"
CREATE TABLE IF NOT EXISTS feeds
(
    id           TEXT PRIMARY KEY NOT NULL,
    name         TEXT NOT NULL,
    site_url     TEXT NOT NULL,
    feed_url     TEXT NOT NULL,
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
            .context("couldn't init db")?;
        self.update_conn
            .execute_batch(
                r#"
CREATE TABLE IF NOT EXISTS feed_updates
(
    id          INTEGER PRIMARY KEY NOT NULL,
    feed        TEXT NOT NULL,
    fetch_error TEXT,
    created_at  DATETIME
);
"#,
            )
            .await
            .context("couldn't init update db")?;
        Ok(())
    }

    pub(crate) async fn add_feeds<T>(&self, feeds: T) -> Result<()>
    where
        T: Iterator<Item = Feed>,
    {
        let tx = self.main_conn.transaction().await?;
        {
            let mut stmt = tx
                .prepare(
                    r#"
    INSERT OR REPLACE INTO feeds (id, name, site_url, feed_url, category)
    VALUES (?, ?, ?, ?, ?);
                    "#,
                )
                .await
                .context("couldn't prepare statement")?;

            for f in feeds {
                let _ = stmt
                    .execute((f.id, f.name, f.site_url, f.feed_url, f.category))
                    .await?;
                stmt.reset();
            }
        }
        tx.commit().await?;

        Ok(())
    }

    pub(crate) async fn get_feeds(&self) -> Result<Vec<Feed>> {
        // TODO: Probably still want update info
        let mut stmt = self
            .main_conn
            .prepare("SELECT id, name, site_url, feed_url, category FROM feeds")
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
        let mut stmt = self
            .main_conn
            .prepare("DELETE FROM feeds WHERE id = ?")
            .await?;
        stmt.execute([id]).await?;

        Ok(())
    }

    pub(crate) async fn update_feed_status(&self, id: String, error: Option<String>) -> Result<()> {
        let mut stmt = self
            .update_conn
            .prepare(
                "INSERT INTO feed_updates (feed, fetch_error, created_at)
                      VALUES (?, ?, ?)",
            )
            .await?;

        stmt.execute((id, error, UtcTime(Utc::now()))).await?;

        Ok(())
    }

    pub(crate) async fn add_entries<T>(&self, entries: T) -> Result<()>
    where
        T: Iterator<Item = Entry>,
    {
        let tx = self.main_conn.transaction().await?;
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
            .main_conn
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
                .main_conn
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
                .main_conn
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
