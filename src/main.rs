#![warn(clippy::needless_pass_by_value)]

use std::env;
use std::fs::File;
use std::time::Duration;

#[macro_use]
extern crate log;

use anyhow::anyhow;

use askama_warp::Template;
use chrono::{DateTime, Utc};
use feed_rs::parser;
use opml::OPML;
use rweb::*;
use serde::{Deserialize, Serialize};
use tokio::signal::unix::{signal, SignalKind};
use tokio::time;
use tokio_stream::wrappers::{IntervalStream, SignalStream};
use warp::http::Uri;

use futures::stream::StreamExt;
use futures::{future, stream};

use lazy_static::lazy_static;
use regex::Regex;

mod db;

#[derive(Debug, Clone, Schema, Deserialize, Serialize)]
#[serde(transparent)]
struct UtcTime(DateTime<Utc>);

impl From<DateTime<Utc>> for UtcTime {
    fn from(c: DateTime<Utc>) -> UtcTime {
        UtcTime(c)
    }
}

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
    last_fetched: Option<UtcTime>,
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
    published: Option<UtcTime>,
    read: bool,
    starred: bool,
    feed: String,
}

impl Entry {
    pub fn new(
        id: &str,
        title: String,
        content_link: String,
        comments_link: String,
        published: Option<UtcTime>,
    ) -> Self {
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
        let content_link = e
            .links
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

        let published = if let Some(p) = e.published {
            Some(UtcTime(p))
        } else if let Some(u) = e.updated {
            Some(UtcTime(u))
        } else {
            None
        };

        Entry::new(
            &e.id,
            title.to_string(),
            content_link,
            comments_link,
            published,
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
        Feed::new(
            form.feed_name,
            form.site_url,
            form.feed_url,
            form.feed_category,
        )
    }
}

mod filters {
    use chrono_humanize::HumanTime;

    use crate::UtcTime;

    pub fn humandate(s: &Option<UtcTime>) -> ::askama::Result<String> {
        if let Some(date) = s {
            Ok(format!("{}", HumanTime::from(date.0)))
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

    let db_path = env::var("FEED_DB_PATH")
        .or::<Result<String, env::VarError>>(Ok("./feeds.db".to_string()))
        .expect("couldn't set db path");
    let db: db::DB = db::connect(db::ConnectionBacking::File(&db_path))
        .await
        .expect("couldn't open db");
    db.init().await.expect("couldn't init db");

    if let Ok(f) = env::var("FEED_OPML_FILE") {
        let path = f.clone();
        let mut file = File::open(path).expect("Couldn't open opml file");
        let document = OPML::from_reader(&mut file).expect("Couldn't parse opml file");

        let feeds = parse_opml_document(&document).expect("Couldn't parse opml to feeds");
        db.add_feeds(feeds.into_iter())
            .await
            .expect("couldn't add feeds");
        info!("parsed and loaded {}", f);
    }

    let mut exit = stream::select_all(vec![
        SignalStream::new(signal(SignalKind::interrupt()).unwrap()),
        SignalStream::new(signal(SignalKind::terminate()).unwrap()),
        SignalStream::new(signal(SignalKind::quit()).unwrap()),
    ]);

    let default_time = 3 * 60;
    let time_interval = match env::var("FEED_REFRESH_INTERVAL") {
        Ok(i) => i.parse().unwrap_or(default_time),
        Err(_) => default_time,
    };
    let interval = time::interval(Duration::from_secs(time_interval));

    let update_db = db.clone();
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(120))
        .gzip(true)
        .brotli(true)
        .build()
        .expect("couldn't build request client");

    let stream = IntervalStream::new(interval)
        .take_until(exit.next())
        .for_each(|_| async {
            let start = time::Instant::now();
            let feeds = match update_db.get_feeds().await {
                Ok(feeds) => feeds,
                Err(err) => {
                    error!("couldn't get feeds, {}", err);
                    return;
                }
            };

            let mut updated = 0;
            for f in feeds.iter() {
                let feed_resp = client.get(&f.feed_url).send().await;

                let feed_resp = match feed_resp {
                    Ok(r) => r,
                    Err(_) => {
                        let _ = update_db
                            .update_feed_status(
                                f.id.clone(),
                                Some("couldn't get response".to_string()),
                            )
                            .await;
                        continue;
                    }
                };

                if feed_resp.status() != reqwest::StatusCode::OK {
                    let _ = update_db
                        .update_feed_status(f.id.clone(), Some("response code not ok".to_string()))
                        .await;
                    continue;
                }
                // we don't actually care if this works
                let _ = update_db.update_feed_status(f.id.clone(), None).await;

                let bytes = feed_resp.bytes().await;

                let body = match bytes {
                    Ok(b) => b,
                    Err(_) => {
                        let _ = update_db
                            .update_feed_status(
                                f.id.clone(),
                                Some("couldn't get bytes".to_string()),
                            )
                            .await;
                        continue;
                    }
                };

                let feed = match parser::parse_with_uri(body.as_ref(), Some(&f.feed_url)) {
                    Ok(f) => f,
                    Err(e) => {
                        error!("Couldn't parse feed {}: {}", &f.feed_url, e);
                        let _ = update_db
                            .update_feed_status(
                                f.id.clone(),
                                Some("couldn't parse feed".to_string()),
                            )
                            .await;
                        continue;
                    }
                };
                let entries: Vec<Entry> = feed
                    .entries
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

                // set feed error to empty if we made it this far
                let _ = update_db.update_feed_status(f.id.clone(), None).await;
            }
            info!(
                "found {} entries in {}s",
                updated,
                start.elapsed().as_secs()
            )
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
    )
    .await;
}

#[get("/")]
async fn index(#[data] db: db::DB) -> Result<IndexTemplate, Rejection> {
    let entries = db.get_unread_entries().await.map_err(reject_anyhow)?;
    Ok(IndexTemplate { entries })
}

#[get("/history.html")]
async fn history(#[data] db: db::DB) -> Result<HistoryTemplate, Rejection> {
    let entries = db
        .get_entries(db::EntryFilter::All, db::Ordering::Descending)
        .await
        .map_err(reject_anyhow)?;
    Ok(HistoryTemplate { entries })
}

#[get("/feeds.html")]
async fn get_feeds(#[data] db: db::DB) -> Result<FeedsTemplate, Rejection> {
    let feeds = db.get_feeds().await.map_err(reject_anyhow)?;
    Ok(FeedsTemplate { feeds })
}

#[get("/starred.html")]
async fn get_starred(#[data] db: db::DB) -> Result<StarredTemplate, Rejection> {
    let entries = db.get_starred_entries().await.map_err(reject_anyhow)?;
    Ok(StarredTemplate { entries })
}

#[get("/add_feed.html")]
async fn add_feed() -> Result<AddFeedTemplate, Rejection> {
    Ok(AddFeedTemplate {})
}

#[post("/feeds")]
async fn post_feed(#[form] body: AddFeedForm, #[data] db: db::DB) -> Result<impl Reply, Rejection> {
    db.add_feeds(vec![body.into()].into_iter())
        .await
        .map_err(reject_anyhow)?;
    Ok(warp::redirect(Uri::from_static("/feeds.html")))
}

#[delete("/feeds/{feed_url}")]
async fn remove_feed(feed_url: String, #[data] db: db::DB) -> Result<FeedListTemplate, Rejection> {
    db.remove_feed(feed_url).await.map_err(reject_anyhow)?;
    let feeds = db.get_feeds().await.map_err(reject_anyhow)?;
    Ok(FeedListTemplate { feeds })
}

#[post("/read/{entry_id}")]
async fn mark_entry_read(
    entry_id: String,
    #[header = "entry_filter"] entry_filter: String,
    #[header = "ordering"] ordering: String,
    #[data] db: db::DB,
) -> Result<EntryListTemplate, Rejection> {
    let entries = db
        .mark_entry_read(entry_id, entry_filter.into(), ordering.into())
        .await
        .map_err(reject_anyhow)?;
    Ok(EntryListTemplate { entries })
}

#[post("/starred/{entry_id}")]
async fn mark_entry_starred(
    entry_id: String,
    #[header = "entry_filter"] entry_filter: String,
    #[header = "ordering"] ordering: String,
    #[data] db: db::DB,
) -> Result<EntryListTemplate, Rejection> {
    let entries = db
        .mark_entry_starred(entry_id, entry_filter.into(), ordering.into())
        .await
        .map_err(reject_anyhow)?;
    Ok(EntryListTemplate { entries })
}

#[get("/healthz")]
fn healthz() -> Json<Healthz> {
    Healthz { up: true }.into()
}

#[get("/dump")]
async fn dump(#[data] db: db::DB) -> Result<Json<Dump>, Rejection> {
    let feeds = db
        .get_feeds()
        .await
        .map_err(|err| warp::reject::custom(AppError(err)))?;
    let entries = db
        .get_entries(db::EntryFilter::All, db::Ordering::Descending)
        .await
        .map_err(|err| warp::reject::custom(AppError(err)))?;

    Ok(Dump { feeds, entries }.into())
}

fn parse_opml_document(document: &opml::OPML) -> Result<Vec<Feed>, anyhow::Error> {
    let mut feeds = vec![];
    for c in document.body.outlines.iter() {
        // expect outlines for each category that consists of an outline for each feed
        let category_text = c.text.clone();
        for f in c.outlines.iter() {
            let name = f.text.clone();
            let site_url = f
                .html_url
                .as_ref()
                .ok_or(anyhow!("Missing html url in feed {}", name))?;
            let feed_url = f
                .xml_url
                .as_ref()
                .ok_or(anyhow!("Missing xml url in feed {}", name))?;
            let f = Feed::new(
                name,
                site_url.clone(),
                feed_url.clone(),
                category_text.clone(),
            );
            feeds.push(f);
        }
    }

    Ok(feeds)
}

#[cfg(test)]
mod test {
    use super::*;

    #[test]
    fn parse_opml_export() {
        let mut file = File::open("feeds.opml").expect("Couldn't open feeds.opml");
        let document = OPML::from_reader(&mut file).expect("Couldn't parse feeds.opml");

        let feeds = parse_opml_document(&document).expect("Couldn't parse opml to feeds");
        assert_eq!(feeds.len(), 77);
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
                last_fetched: Some(Utc::now().into()),
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
            },
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
            Entry::new(
                "my-entry",
                "Cool Post".to_string(),
                "https://content.com/1".to_string(),
                "".to_string(),
                Some(Utc::now().into()),
            ),
            Entry::new(
                "your-entry",
                "Gross Post".to_string(),
                "https://content.com/2".to_string(),
                "".to_string(),
                Some(Utc::now().into()),
            ),
        ];

        db.add_entries(entries.into_iter()).await?;
        let es = db
            .get_entries(db::EntryFilter::All, db::Ordering::Ascending)
            .await?;
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
                last_fetched: Some(Utc::now().into()),
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
            },
        ];
        let temp = FeedsTemplate { feeds };

        assert!(temp.render().is_ok(), "template failed to render");
    }
}
