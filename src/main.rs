use std::env;
use std::sync::Arc;
use futures::lock::Mutex;
use rweb::*;
use askama_warp::Template;
use serde::{Serialize, Deserialize};
use chrono::{DateTime, Utc};
use feed_rs::parser;

#[derive(Schema, Deserialize, Serialize)]
struct Healthz {
    up: bool,
}

#[derive(Clone, Default)]
struct DB {
    feeds: Arc<Mutex<Vec<Feed>>>,
    entries: Arc<Mutex<Vec<Entry>>>,
}

#[derive(Schema, Deserialize, Serialize)]
struct Dump {
    feeds: Vec<Feed>,
    entries: Vec<Entry>,
}

#[derive(Clone, Schema, Deserialize, Serialize)]
struct Feed {
    name: String,
    site_url: String,
    feed_url: String,
    favicon: String,
    last_fetched: DateTime<Utc>,
    fetch_error: Option<String>,
    category: String,
}

#[derive(Default, Clone, Schema, Deserialize, Serialize)]
struct Entry {
    title: String,
    content_link: String,
    comments_link: Option<String>,
    robust_link: String,
    read: bool,
    starred: bool,
    feed: String,
}

impl From<feed_rs::model::Entry> for Entry {
    fn from(e: feed_rs::model::Entry) -> Self {
        let content_link = e.links.into_iter().nth(0).map(|l| l.href.to_string()).unwrap_or("".to_string()).clone();
        Entry {
            title: default_text(e.title),
            content_link: content_link,
            comments_link: None,
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

    let hn = &feeds[0];
    let hn_resp = reqwest::get(hn.feed_url.to_string())
        .await
        .expect("couldn't get feed")
        .bytes()
        .await
        .expect("couldn't pull bytes");

    let hn_feed = match parser::parse_with_uri(hn_resp.as_ref(), Some(&hn.feed_url.to_string())) {
        Ok(feed) => feed,
        Err(_error) => panic!(),
    };

    let entries: Vec<Entry> = hn_feed.entries.into_iter()
        .map(|e| {
            let mut o: Entry = e.into();
            o.feed = hn.site_url.to_string();
            o
        })
        .collect();

    let db: DB = Default::default();
    {
        db.entries.lock().await.extend(entries);
        db.feeds.lock().await.extend(feeds);
    }

    let routes = index(db.clone())
        .or(healthz())
        .or(dump(db.clone()))
        .with(log)
        .with(cors);

    warp::serve(routes).run(([0, 0, 0, 0], 3030)).await;
}

#[get("/")]
async fn index(#[data] db: DB) -> Result<IndexTemplate<'static>, Rejection> {
    let entries = db.entries.lock().await.to_vec();
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
async fn dump(#[data] db: DB) -> Result<Json<Dump>, Rejection> {
    let feeds = db.feeds.lock().await.to_vec();
    let entries = db.entries.lock().await.to_vec();

    Ok(Dump {
        feeds,
        entries,
    }.into())
}

fn default_text(text: Option<feed_rs::model::Text>) -> String {
    text.and_then(|t| Some(t.content)).unwrap_or("".to_string())
}