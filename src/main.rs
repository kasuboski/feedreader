use std::env;
use rweb::*;
use serde::{Serialize, Deserialize};
use url::{Url};
use chrono::{DateTime, Utc};

#[derive(Schema, Deserialize, Serialize)]
struct Healthz {
    up: bool,
}

#[derive(Schema, Deserialize, Serialize)]
struct Dump {
    feeds: Vec<Feed>,
    posts: Vec<Post>,
}

#[derive(Schema, Deserialize, Serialize)]
struct Feed {
    name: String,
    url: Url,
    favicon: Url,
    last_fetched: DateTime<Utc>,
    fetch_error: Option<String>,
    category: String,
}

#[derive(Schema, Deserialize, Serialize)]
struct Post {
    title: String,
    content_link: Url,
    comments_link: Url,
    robust_link: Url,
    read: bool,
    starred: bool,
    feed: String,
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

    let index = warp::get()
        .and(warp::path::end())
        .and(warp::fs::file("./index.html"));

    let routes = index
        .or(healthz())
        .or(dump())
        .with(log)
        .with(cors);

    warp::serve(routes).run(([0, 0, 0, 0], 3030)).await;
}

#[get("/healthz")]
fn healthz() -> Json<Healthz> {
    Healthz {
        up: true
    }.into()
}

#[get("/dump")]
fn dump() -> Json<Dump> {
    let posts = vec![Post {
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

    Dump {
        feeds,
        posts,
    }.into()
}
