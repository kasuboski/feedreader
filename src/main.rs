#![warn(clippy::needless_pass_by_value)]

use std::env;
use std::fs::File;
use std::time::Duration;

#[macro_use] extern crate log;

use anyhow::anyhow;

use rweb::*;
use warp::http::Uri;
use askama_warp::Template;
use serde::{Serialize, Deserialize};
use chrono::{DateTime, Utc};
use feed_rs::parser;
use opml::OPML;
use tokio::time;
use tokio::signal::unix::{signal, SignalKind};
use tokio_stream::wrappers::{IntervalStream, SignalStream};

use futures::stream::StreamExt;
use futures::{future, stream};

use regex::Regex;
use lazy_static::lazy_static;

#[derive(Schema, Deserialize, Serialize)]
struct Healthz {
    up: bool,
}

#[derive(Schema, Deserialize, Serialize)]
struct Dump {
    feeds: Vec<Feed>,
    entries: Vec<Entry>,
}

#[derive(Default, Debug, Clone, Schema, Deserialize, Serialize)]
struct Feed {
    id: String,
    name: String,
    site_url: String,
    feed_url: String,
    last_fetched: Option<DateTime<Utc>>,
    fetch_error: Option<String>,
    category: String,
}

impl Feed {
    pub fn new(name: String, site_url: String, feed_url: String, category: String) -> Self {
        Feed {
            id: base64::encode_config(&feed_url, base64::URL_SAFE),
            name,
            site_url,
            feed_url,
            category,
            ..Default::default()
        }
    }
}

#[derive(Default, Debug, Clone, Schema, Deserialize, Serialize)]
struct Entry {
    id: String,
    title: String,
    content_link: String,
    comments_link: String,
    robust_link: String,
    published: Option<DateTime<Utc>>,
    read: bool,
    starred: bool,
    feed: String,
}

impl Entry {
    pub fn new(id: &str, title: String, content_link: String, comments_link: String, published: Option<DateTime<Utc>>) -> Self {
        Entry {
            id: base64::encode_config(id.as_bytes(), base64::URL_SAFE),
            title: title,
            content_link,
            comments_link,
            published,
            read: false,
            starred: false,
            ..Default::default()
        }
    }
}

impl From<&feed_rs::model::Entry> for Entry {
    fn from(e: &feed_rs::model::Entry) -> Self {
        let content_link = e.links
            .iter()
            .take(1)
            .map(|l| l.href.to_string())
            .next()
            .unwrap_or_else(|| "".to_string());

        let title = match &e.title {
            Some(t) => &t.content,
            None => "",
        };

        lazy_static! {
            static ref LINK: Regex = Regex::new(r#"href="(?P<url>.*)""#).unwrap();
        }

        let summary = match &e.summary {
            Some(s) => &s.content,
            None => "",
        };

        let caps = LINK.captures(summary);
        let url_match = match caps {
            Some(c) => c.name("url"),
            None => None,
        };

        let comments_link = match url_match {
            Some(u) => u.as_str().to_string(),
            None => "".to_string(),
        };

        let published = if let Some(_p) = e.published {
            e.published 
        } else if let Some(_u) = e.updated { 
            e.updated 
        } else { 
            None 
        };

        Entry::new(
            &e.id,
            title.to_string(),
            content_link,
            comments_link,
            published
        )
    }
}

#[derive(Template)]
#[template(path = "index.html")]
struct IndexTemplate {
    entries: Vec<Entry>,
}

#[derive(Template)]
#[template(path = "history.html")]
struct HistoryTemplate {
    entries: Vec<Entry>,
}

#[derive(Template)]
#[template(path = "entry_list.html")]
struct EntryListTemplate {
    entries: Vec<Entry>,
}

#[derive(Template)]
#[template(path = "feeds.html")]
struct FeedsTemplate {
    feeds: Vec<Feed>,
}

#[derive(Template)]
#[template(path = "feed_list.html")]
struct FeedListTemplate {
    feeds: Vec<Feed>,
}

#[derive(Template)]
#[template(path = "starred.html")]
struct StarredTemplate {
    entries: Vec<Entry>,
}

#[derive(Template)]
#[template(path = "add_feed.html")]
struct AddFeedTemplate {}

#[derive(Serialize, Deserialize)]
struct AddFeedForm {
    feed_name: String,
    site_url: String,
    feed_url: String,
    feed_category: String,
}

impl From<AddFeedForm> for Feed {
    fn from(form: AddFeedForm) -> Self {
        Feed::new(form.feed_name, form.site_url, form.feed_url, form.feed_category)
    }
}

mod filters {
    use chrono::{DateTime, Utc};
    use chrono_humanize::HumanTime;

    pub fn humandate(s: &Option<DateTime<Utc>>) -> ::askama::Result<String> {
        if let Some(date) = s {
            Ok(format!("{}", HumanTime::from(*date)))
        } else {
            Ok("".to_string())
        }

    }
}

#[derive(Debug)]
struct AppError(anyhow::Error);
impl rweb::reject::Reject for AppError {}

fn reject_anyhow(err: anyhow::Error) -> Rejection {
    warp::reject::custom(AppError(err))
}

#[tokio::main]
async fn main() {
    if env::var_os("RUST_LOG").is_none() {
        env::set_var("RUST_LOG", "feedreader=info");
    }
    pretty_env_logger::init();
    let log = warp::log("feedreader");

    let cors = warp::cors()
        .allow_any_origin()
        .allow_headers(vec![
            "Authorization",
            "Content-Type",
            "User-Agent",
            "Sec-Fetch-Mode",
            "Referer",
            "Origin",
            "Access-Control-Request-Method",
            "Access-Control-Request-Headers",
        ])
        .allow_methods(vec!["GET", "HEAD", "POST", "DELETE"]);

    let mut file = File::open("feeds.opml").expect("Couldn't open feeds.opml");
    let document = OPML::from_reader(&mut file).expect("Couldn't parse feeds.opml");

    let feeds = parse_opml_document(&document).expect("Couldn't parse opml to feeds");

    let db: db::DB = db::connect(db::ConnectionBacking::File("./feeds.db".to_string())).await.expect("couldn't open db");
    db.init().await.expect("couldn't init db");
    db.add_feeds(feeds.into_iter()).await.expect("couldn't add feeds");

    let mut exit = stream::select_all(vec![
        SignalStream::new(signal(SignalKind::interrupt()).unwrap()),
        SignalStream::new(signal(SignalKind::terminate()).unwrap()),
        SignalStream::new(signal(SignalKind::quit()).unwrap()),
    ]);

    let time_interval = 30;
    let interval = time::interval(Duration::from_secs(time_interval));

    let update_db = db.clone();
    let stream = IntervalStream::new(interval)
        .take_until(exit.next())
        .for_each(|_| async {
            let client = reqwest::Client::new();

            let start = time::Instant::now();
            let feeds = match update_db.get_feeds().await {
                Ok(feeds) => feeds,
                Err(err) => {
                    error!("couldn't get feeds, {}", err);
                    return;
                },
            };

            let mut updated = 0;
            for f in feeds.iter() {
                let feed_resp = client.get(&f.feed_url)
                    .send()
                    .await;

                let feed_resp = match feed_resp {
                    Ok(r) => r,
                    Err(_) => {
                        let _ = update_db.update_feed_status(f.id.clone(), Some("couldn't get response".to_string())).await;
                        continue;
                    },
                };

                
                if feed_resp.status() != reqwest::StatusCode::OK {
                    let _ = update_db.update_feed_status(f.id.clone(), Some("response code not ok".to_string())).await;
                    continue;
                }
                // we don't actually care if this works
                let _ = update_db.update_feed_status(f.id.clone(), None).await;

                let bytes = feed_resp.bytes().await;

                let body = match bytes {
                    Ok(b) => b,
                    Err(_) => {
                        let _ = update_db.update_feed_status(f.id.clone(), Some("couldn't get bytes".to_string())).await;
                        continue;
                    },
                };
                
                let feed = parser::parse_with_uri(body.as_ref(), Some(&f.feed_url)).unwrap();
                let entries: Vec<Entry> = feed.entries
                    .iter()
                    .map(|e| {
                        let mut o: Entry = e.into();
                        o.feed = f.name.clone();
                        o
                    })
                    .collect();

                updated += entries.len();
                if let Err(e) = update_db.add_entries(entries.into_iter()).await {
                    error!("couldn't update entries, {:?}", e);
                }
            }
            println!("found {} entries in {}s", updated, start.elapsed().as_secs())
        });

    let routes = index(db.clone())
        .or(history(db.clone()))
        .or(get_feeds(db.clone()))
        .or(get_starred(db.clone()))
        .or(add_feed())
        .or(post_feed(db.clone()))
        .or(remove_feed(db.clone()))
        .or(mark_entry_read(db.clone()))
        .or(mark_entry_starred(db.clone()))
        .or(healthz())
        .or(dump(db.clone()))
        .with(log)
        .with(cors)
        .recover(|err: Rejection| async move {
            if let Some(AppError(ae)) = err.find() {
                error!("app error found, {:?}", ae);
                Ok(warp::hyper::StatusCode::INTERNAL_SERVER_ERROR)
            } else {
                Err(err)
            }
        });

    future::select(
        Box::pin(stream),
        Box::pin(warp::serve(routes).run(([0, 0, 0, 0], 3030))),
    ).await;
}

#[get("/")]
async fn index(#[data] db: db::DB) -> Result<IndexTemplate, Rejection> {
    let entries = db.get_unread_entries().await.map_err(reject_anyhow)?;
    Ok(IndexTemplate {
        entries,
    })
}

#[get("/history.html")]
async fn history(#[data] db: db::DB) -> Result<HistoryTemplate, Rejection> {
    let entries = db.get_entries(|_| true).await.map_err(reject_anyhow)?;
    Ok(HistoryTemplate {
        entries,
    })
}

#[get("/feeds.html")]
async fn get_feeds(#[data] db: db::DB) -> Result<FeedsTemplate, Rejection> {
    let feeds = db.get_feeds().await.map_err(reject_anyhow)?;
    Ok(FeedsTemplate {
        feeds,
    })
}

#[get("/starred.html")]
async fn get_starred(#[data] db: db::DB) -> Result<StarredTemplate, Rejection> {
    let entries = db.get_starred_entries().await.map_err(reject_anyhow)?;
    Ok(StarredTemplate {
        entries,
    })
}

#[get("/add_feed.html")]
async fn add_feed() -> Result<AddFeedTemplate, Rejection> {
    Ok(AddFeedTemplate{})
}

#[post("/feeds")]
async fn post_feed(#[form] body: AddFeedForm,#[data] db: db::DB) -> Result<impl Reply, Rejection> {
    db.add_feeds(vec![body.into()].into_iter()).await.map_err(reject_anyhow)?;
    Ok(warp::redirect(Uri::from_static("/feeds.html")))
}

#[delete("/feeds/{feed_url}")]
async fn remove_feed(feed_url: String, #[data] db: db::DB) -> Result<FeedListTemplate, Rejection> {
    db.remove_feed(feed_url).await.map_err(reject_anyhow)?;
    let feeds = db.get_feeds().await.map_err(reject_anyhow)?;
    Ok(FeedListTemplate {
        feeds,
    })
}

#[post("/read/{entry_id}")]
async fn mark_entry_read(entry_id: String, #[header = "entry_filter"] entry_filter: String, #[data] db: db::DB) -> Result<EntryListTemplate, Rejection> {
    let entries = db
        .mark_entry_read(entry_id, db::name_to_filter(&entry_filter))
        .await.map_err(reject_anyhow)?;
    Ok(EntryListTemplate {
        entries,
    })
}

#[post("/starred/{entry_id}")]
async fn mark_entry_starred(entry_id: String, #[header = "entry_filter"] entry_filter: String, #[data] db: db::DB) -> Result<EntryListTemplate, Rejection> {
    let entries = db.mark_entry_starred(entry_id, db::name_to_filter(&entry_filter))
        .await.map_err(reject_anyhow)?;
    Ok(EntryListTemplate {
        entries,
    })
}

#[get("/healthz")]
fn healthz() -> Json<Healthz> {
    Healthz {
        up: true
    }.into()
}

#[get("/dump")]
async fn dump(#[data] db: db::DB) -> Result<Json<Dump>, Rejection> {
    let feeds = db.get_feeds().await.map_err(|err| warp::reject::custom(AppError(err)))?;
    let entries = db.get_entries(|_| true).await.map_err(|err| warp::reject::custom(AppError(err)))?;

    Ok(Dump {
        feeds,
        entries,
    }.into())
}

fn parse_opml_document(document: &opml::OPML) -> Result<Vec<Feed>, anyhow::Error> {
    let mut feeds = vec![];
    for c in document.body.outlines.iter() {
        // expect outlines for each category that consists of an outline for each feed
        let category_text = c.text.clone();
        for f in c.outlines.iter() {
            let name = f.text.clone();
            let site_url = f.html_url.as_ref().ok_or(anyhow!("Missing html url in feed {}", name))?;
            let feed_url = f.xml_url.as_ref().ok_or(anyhow!("Missing xml url in feed {}", name))?;
            let f = Feed::new(name, site_url.clone(), feed_url.clone(), category_text.clone());
            feeds.push(f);
        }
    }

    Ok(feeds)
}

mod db {
    use std::sync::Arc;
    use futures::lock::Mutex;

    use chrono::{Utc};
    use anyhow::{Context, Result};

    use rusqlite::{Connection, params};

    use super::{Feed, Entry};

    #[derive(Clone)]
    pub struct DB {
        conn: Arc<Mutex<Connection>>,
    }

    pub enum ConnectionBacking {
        #[allow(dead_code)] // used in tests...
        Memory,
        File(String),
    }

    pub async fn connect(conn_back: ConnectionBacking) -> Result<DB> {
        let conn = match conn_back {
            ConnectionBacking::File(p) => Connection::open(p)?,
            ConnectionBacking::Memory => Connection::open_in_memory()?,
        };
        Ok(DB {
            conn: Arc::new(Mutex::new(conn)),
        })
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
                "#
            ).context("couldn't init db")
        }

        pub(crate) async fn add_feeds<T>(&self, feeds: T) -> Result<()>
        where T: Iterator<Item = Feed> {
            let mut conn = self.conn.lock().await;
            let tx = conn.transaction()?;
            {
                let mut stmt = tx.prepare_cached(
                    r#"
    INSERT OR REPLACE INTO feeds (id, name, site_url, feed_url, last_fetched, fetch_error, category)
    VALUES (?, ?, ?, ?, ?, ?, ?);
                    "#
                ).context("couldn't prepare statement")?;

                for f in feeds {
                    let _ = stmt.execute(params![f.id, f.name, f.site_url, f.feed_url, f.last_fetched, f.fetch_error, f.category]);
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
                WHERE id = ?"
            )?;

            stmt.execute(params![error, Utc::now(), id])?;

            Ok(())
        }

        pub(crate) async fn add_entries<T>(&self, entries: T) -> Result<()>
        where T: Iterator<Item = Entry> {
            let mut conn = self.conn.lock().await;
            let tx = conn.transaction()?;
            {
                let mut stmt = tx.prepare_cached(
                    "INSERT OR IGNORE INTO entries (id, title, content_link, comments_link, robust_link, published, read, starred, feed_name)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
                )?;
                for e in entries {
                    let _ = stmt.execute(params![e.id, e.title, e.content_link, e.comments_link, e.robust_link, e.published, e.read, e.starred, e.feed]);
                }
            }
            tx.commit()?;

            Ok(())
        }

        pub(crate) async fn get_entries(&self, filter: EntryFilter) -> Result<Vec<Entry>> {
            let conn = self.conn.lock().await;
            let mut stmt = conn.prepare_cached("SELECT id, title, content_link, comments_link, robust_link, published, read, starred, feed_name FROM entries ORDER BY published").context("couldn't prepare statement")?;
            let entry_iter = stmt.query_map([], |row| {
                Ok(
                    Entry {
                        id: row.get(0)?,
                        title: row.get(1)?,
                        content_link: row.get(2)?,
                        comments_link: row.get(3)?,
                        robust_link: row.get(4)?,
                        published: row.get(5)?,
                        read: row.get(6)?,
                        starred: row.get(7)?,
                        feed: row.get(8)?,
                    }
                )
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
            self.get_entries(|e| e.starred).await
        }

        pub(crate) async fn get_unread_entries(&self) -> Result<Vec<Entry>> {
            self.get_entries(|e| !e.read).await
        }

        pub(crate) async fn mark_entry_read(&self, entry_id: String, filter: EntryFilter) -> Result<Vec<Entry>> {
            {
                let conn = self.conn.lock().await;
                let mut stmt = conn.prepare_cached("UPDATE entries SET read = NOT read WHERE id = ?").context("couldn't prepare statement")?;
                stmt.execute(params![entry_id])?;
            }
            self.get_entries(filter).await
        }

        pub(crate) async fn mark_entry_starred(&self, entry_id: String, filter: EntryFilter) -> Result<Vec<Entry>> {
            {
                let conn = self.conn.lock().await;
                let mut stmt = conn.prepare_cached("UPDATE entries SET starred = NOT starred WHERE id = ?").context("couldn't prepare statement")?;
                stmt.execute(params![entry_id])?;
            }
            self.get_entries(filter).await
        }
    }
}

#[cfg(test)]
mod test {
    use super::*;

    #[test]
    fn parse_opml_export() {
        let mut file = File::open("feeds.opml").expect("Couldn't open feeds.opml");
        let document = OPML::from_reader(&mut file).expect("Couldn't parse feeds.opml");

        let feeds = parse_opml_document(&document).expect("Couldn't parse opml to feeds");
        assert_eq!(feeds.len(), 79);
        assert_eq!(feeds[0].name, "BetterExplained");
        assert_eq!(feeds[3].name, "Austin Monitor");
        assert_eq!(feeds[3].category, "Austin");
        assert_eq!(feeds[3].feed_url, "http://www.austinmonitor.com/feed/");
    }

    #[test]
    fn addfeedform_toform() {
        let form = AddFeedForm {
            feed_name: "Martin Fowler".to_string(),
            feed_url: "https://martinfowler.com/feed.atom".to_string(),
            site_url: "https://martinfowler.com".to_string(),
            feed_category: "tech".to_string(),
        };

        let feed: Feed = form.into();
        assert_eq!(feed.name, "Martin Fowler");
        assert_eq!(feed.feed_url, "https://martinfowler.com/feed.atom");
    }

    #[tokio::test]
    async fn add_list_feeds() -> Result<(), anyhow::Error> {
        let db: db::DB = db::connect(db::ConnectionBacking::Memory).await?;
        db.init().await?;
        let feeds = vec![
            Feed {
                id: base64::encode_config("HackerNews", base64::URL_SAFE),
                name: "HackerNews".to_string(),
                site_url: "https://news.ycombinator.com".to_string(),
                feed_url: "https://news.ycombinator.com/rss".to_string(),
                last_fetched: Some(Utc::now()),
                fetch_error: None,
                category: "tech".to_string(),
            },
            Feed {
                id: base64::encode_config("Product Hunt", base64::URL_SAFE),
                name: "Product Hunt".to_string(),
                site_url: "https://www.producthunt.com".to_string(),
                feed_url: "https://www.producthunt.com/feed".to_string(),
                last_fetched: None,
                fetch_error: None,
                category: "tech".to_string(),
            }
        ];

        db.add_feeds(feeds.into_iter()).await?;
        let f = db.get_feeds().await?;
        assert_eq!(f.len(), 2);
        assert_eq!(f[0].name, "HackerNews");
        Ok(())
    }

    #[tokio::test]
    async fn add_list_entries() -> Result<(), anyhow::Error> {
        let db: db::DB = db::connect(db::ConnectionBacking::Memory).await?;
        db.init().await?;
        let entries = vec![
            Entry::new("my-entry", "Cool Post".to_string(), "https://content.com/1".to_string(), "".to_string(), Some(Utc::now())),
            Entry::new("your-entry", "Gross Post".to_string(), "https://content.com/2".to_string(), "".to_string(), Some(Utc::now())),
        ];

        db.add_entries(entries.into_iter()).await?;
        let es = db.get_entries(db::name_to_filter("all")).await?;
        assert_eq!(es.len(), 2);
        assert_eq!(es[0].title, "Cool Post");
        assert_ne!(es[0].id, "my-entry");
        Ok(())
    }

    #[test]
    fn render_feedstemplate() {
        let feeds = vec![
            Feed {
                id: base64::encode_config("HackerNews", base64::URL_SAFE),
                name: "HackerNews".to_string(),
                site_url: "https://news.ycombinator.com".to_string(),
                feed_url: "https://news.ycombinator.com/rss".to_string(),
                last_fetched: Some(Utc::now()),
                fetch_error: None,
                category: "tech".to_string(),
            },
            Feed {
                id: base64::encode_config("Product Hunt", base64::URL_SAFE),
                name: "Product Hunt".to_string(),
                site_url: "https://www.producthunt.com".to_string(),
                feed_url: "https://www.producthunt.com/feed".to_string(),
                last_fetched: None,
                fetch_error: None,
                category: "tech".to_string(),
            }
        ];
        let temp = FeedsTemplate {
            feeds,
        };

        assert!(
            temp.render().is_ok(),
            "template failed to render"
        );

    }
}
