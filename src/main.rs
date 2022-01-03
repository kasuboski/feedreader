use std::env;
use std::sync::Arc;
use futures::lock::Mutex;
use rweb::*;
use askama_warp::Template;
use serde::{Serialize, Deserialize};
use url::{Url};
use chrono::{DateTime, Utc};

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
    url: Url,
    favicon: Url,
    last_fetched: DateTime<Utc>,
    fetch_error: Option<String>,
    category: String,
}

#[derive(Clone, Schema, Deserialize, Serialize)]
struct Entry {
    title: String,
    content_link: Url,
    comments_link: Url,
    robust_link: Url,
    read: bool,
    starred: bool,
    feed: String,
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

    let entries = vec![Entry {
        title: "I'm cool".to_string(),
        content_link: Url::parse("https://hackernews.com/post/cool").unwrap(),
        comments_link: Url::parse("https://hackernews.com/post/cool/comments").unwrap(),
        robust_link: Url::parse("https://archive.li/xwe8s").unwrap(),
        read: false,
        starred: false,
        feed: "HackerNews".to_string(),
    }];

    let feeds = vec![Feed {
        name: "HackerNews".to_string(),
        url: Url::parse("https://hackernews.com").unwrap(),
        favicon: Url::parse("https://hackernews.com/favicon").unwrap(),
        last_fetched: Utc::now(),
        fetch_error: None,
        category: "tech".to_string(),
    }];

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