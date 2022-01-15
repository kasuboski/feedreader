use std::env;
use std::time::Duration;

use rweb::*;
use askama_warp::Template;
use serde::{Serialize, Deserialize};
use chrono::{DateTime, Utc};
use feed_rs::parser;
use tokio::{task, time};

#[derive(Schema, Deserialize, Serialize)]
struct Healthz {
    up: bool,
}

#[derive(Schema, Deserialize, Serialize)]
struct Dump {
    feeds: Vec<Feed>,
    entries: Vec<Entry>,
}

#[derive(Debug, Clone, Schema, Deserialize, Serialize)]
struct Feed {
    name: String,
    site_url: String,
    feed_url: String,
    favicon: String,
    last_fetched: DateTime<Utc>,
    fetch_error: Option<String>,
    category: String,
}

#[derive(Default, Debug, Clone, Schema, Deserialize, Serialize)]
struct Entry {
    id: String,
    title: String,
    content_link: String,
    comments_link: Option<String>,
    robust_link: String,
    published: Option<DateTime<Utc>>,
    read: bool,
    starred: bool,
    feed: String,
}

impl From<&feed_rs::model::Entry> for Entry {
    fn from(e: &feed_rs::model::Entry) -> Self {
        let content_link = e.links
            .iter()
            .take(1)
            .map(|l| l.href.to_string())
            .nth(0)
            .unwrap_or("".to_string());

        let title = match &e.title {
            Some(t) => &t.content,
            None => "",
        };

        Entry {
            id: e.id.clone(),
            title: title.to_string(),
            content_link: content_link,
            comments_link: None,
            published: e.published,
            read: false,
            starred: false,
            ..Default::default()
        }
    }
}

#[derive(Template)]
#[template(path = "index.html")]
struct IndexTemplate<'a> {
    title: &'a str,
    entries: Vec<Entry>,
}

mod filters {
    use chrono::{DateTime, Utc};
    use chrono_humanize::HumanTime;
    use std::fmt;

    pub fn humandate(s: &Option<DateTime<Utc>>) -> ::askama::Result<String> {
        let date = s.ok_or(fmt::Error)?;
        Ok(format!("{}", HumanTime::from(date)))

    }
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

    let feeds = vec![Feed {
        name: "HackerNews".to_string(),
        site_url: "https://news.ycombinator.com".to_string(),
        feed_url: "https://news.ycombinator.com/rss".to_string(),
        favicon: "https://hackernews.com/favicon".to_string(),
        last_fetched: Utc::now(),
        fetch_error: None,
        category: "tech".to_string(),
    }];

    let db: db::DB = Default::default();
    db.add_feeds(feeds.into_iter()).await;

    let update_db = db.clone();
    let updater = task::spawn(async move {
        let time_interval = 30;
        let mut interval = time::interval(Duration::from_secs(time_interval));
        let client = reqwest::Client::new();

        loop {
            interval.tick().await;

            let feeds = update_db.get_feeds().await;

            let mut updated = 0;
            for f in feeds.iter() {
                let feed_resp = client.get(&f.feed_url)
                    .send()
                    .await
                    .unwrap();
                
                if feed_resp.status() != reqwest::StatusCode::OK {
                    let _ = update_db.update_feed_status(f.feed_url.clone(), Some("response code not ok".to_string())).await;
                    continue;
                }
                // we don't actually care if this works
                let _ = update_db.update_feed_status(f.feed_url.clone(), None).await;

                let body = feed_resp.bytes().await.unwrap();
                
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
                update_db.add_entries(entries.into_iter()).await;
            }
            println!("found {} entries", updated)
        }
    });

    let routes = index(db.clone())
        .or(healthz())
        .or(dump(db.clone()))
        .with(log)
        .with(cors);

    warp::serve(routes).run(([0, 0, 0, 0], 3030)).await;
    updater.await.expect("updater failed");
}

#[get("/")]
async fn index(#[data] db: db::DB) -> Result<IndexTemplate<'static>, Rejection> {
    let entries = db.get_entries().await;
    Ok(IndexTemplate {
        title: "feedreader",
        entries: entries,
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
    let feeds = db.get_feeds().await;
    let entries = db.get_entries().await;

    Ok(Dump {
        feeds,
        entries,
    }.into())
}

mod db {
    use futures::lock::Mutex;
    use std::collections::HashMap;
    use std::sync::Arc;
    use chrono::{Utc};

    use super::{Feed, Entry};

    #[derive(Clone, Default)]
    pub struct DB {
        feeds: Arc<Mutex<Vec<Feed>>>,
        entries: Arc<Mutex<HashMap<String, Entry>>>,
    }

    impl DB {
        pub(crate) async fn add_feeds<T>(&self, feeds: T) 
        where T: Iterator<Item = Feed> {
            self.feeds.lock().await.extend(feeds);
        }

        pub(crate) async fn get_feeds(&self) -> Vec<Feed>{
            self.feeds.lock().await.to_vec()
        }

        pub(crate) async fn update_feed_status(&self, feed_url: String, error: Option<String>) -> Result<(), &str> {
            let mut feeds = self.feeds.lock().await;
            let pos = feeds
                .iter()
                .position(|f| f.feed_url == feed_url);
            
            match pos {
                Some(p) => {
                    let f = &mut feeds[p];
                    f.last_fetched = Utc::now();
                    f.fetch_error = error;
                    Ok(())
                },
                None => Err("not found")
            }
        }

        pub(crate) async fn add_entries<T>(&self, entries: T)
        where T: Iterator<Item = Entry> {
            let mut out = self.entries.lock().await;
            for e in entries.into_iter() {
                let stored_e = e.clone();
                out.entry(e.id).or_insert(stored_e);
            }
        }

        pub(crate) async fn get_entries(&self) -> Vec<Entry> {
            let mut e = self.entries.lock().await
                .values()
                .cloned()
                .collect::<Vec<Entry>>();

            e.sort_by(|a, b| b.published.cmp(&a.published));
            e
        }
    }
}
