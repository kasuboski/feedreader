use std::env;
use std::time::Duration;

use rweb::*;
use warp::http::Uri;
use askama_warp::Template;
use serde::{Serialize, Deserialize};
use chrono::{DateTime, Utc};
use feed_rs::parser;
use tokio::{task, time};

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
    name: String,
    site_url: String,
    feed_url: String,
    favicon: String,
    last_fetched: Option<DateTime<Utc>>,
    fetch_error: Option<String>,
    category: String,
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

        let id = base64::encode_config(e.id.as_bytes(), base64::URL_SAFE);

        let published = if let Some(_p) = e.published {
            e.published 
        } else if let Some(_u) = e.updated { 
            e.updated 
        } else { 
            None 
        };

        Entry {
            id,
            title: title.to_string(),
            content_link,
            comments_link,
            published,
            read: false,
            starred: false,
            ..Default::default()
        }
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
        Feed {
            name: form.feed_name,
            site_url: form.site_url,
            feed_url: form.feed_url,
            category: form.feed_category,
            ..Default::default()
        }
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

    let feeds = vec![
        Feed {
            name: "HackerNews".to_string(),
            site_url: "https://news.ycombinator.com".to_string(),
            feed_url: "https://news.ycombinator.com/rss".to_string(),
            favicon: "https://hackernews.com/favicon".to_string(),
            last_fetched: Some(Utc::now()),
            fetch_error: None,
            category: "tech".to_string(),
        },
        Feed {
            name: "Product Hunt".to_string(),
            site_url: "https://www.producthunt.com".to_string(),
            feed_url: "https://www.producthunt.com/feed".to_string(),
            favicon: "https://www.producthunt.com/favicon".to_string(),
            last_fetched: Some(Utc::now()),
            fetch_error: None,
            category: "tech".to_string(),
        }
    ];

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
                    .await;

                let feed_resp = match feed_resp {
                    Ok(r) => r,
                    Err(_) => {
                        let _ = update_db.update_feed_status(f.feed_url.clone(), Some("couldn't get response".to_string())).await;
                        continue;
                    },
                };

                
                if feed_resp.status() != reqwest::StatusCode::OK {
                    let _ = update_db.update_feed_status(f.feed_url.clone(), Some("response code not ok".to_string())).await;
                    continue;
                }
                // we don't actually care if this works
                let _ = update_db.update_feed_status(f.feed_url.clone(), None).await;

                let bytes = feed_resp.bytes().await;

                let body = match bytes {
                    Ok(b) => b,
                    Err(_) => {
                        let _ = update_db.update_feed_status(f.feed_url.clone(), Some("couldn't get bytes".to_string())).await;
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
                update_db.add_entries(entries.into_iter()).await;
            }
            println!("found {} entries", updated)
        }
    });

    let routes = index(db.clone())
        .or(history(db.clone()))
        .or(get_feeds(db.clone()))
        .or(get_starred(db.clone()))
        .or(add_feed())
        .or(post_feed(db.clone()))
        .or(mark_entry_read(db.clone()))
        .or(mark_entry_starred(db.clone()))
        .or(healthz())
        .or(dump(db.clone()))
        .with(log)
        .with(cors);

    warp::serve(routes).run(([0, 0, 0, 0], 3030)).await;
    updater.await.expect("updater failed");
}

#[get("/")]
async fn index(#[data] db: db::DB) -> Result<IndexTemplate, Rejection> {
    let entries = db.get_unread_entries().await;
    Ok(IndexTemplate {
        entries,
    })
}

#[get("/history.html")]
async fn history(#[data] db: db::DB) -> Result<HistoryTemplate, Rejection> {
    let entries = db.get_entries(|_| true).await;
    Ok(HistoryTemplate {
        entries,
    })
}

#[get("/feeds.html")]
async fn get_feeds(#[data] db: db::DB) -> Result<FeedsTemplate, Rejection> {
    let feeds = db.get_feeds().await;
    Ok(FeedsTemplate {
        feeds,
    })
}

#[get("/starred.html")]
async fn get_starred(#[data] db: db::DB) -> Result<StarredTemplate, Rejection> {
    let entries = db.get_starred_entries().await;
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
    db.add_feeds(vec![body.into()].into_iter()).await;
    Ok(warp::redirect(Uri::from_static("/feeds.html")))
}

#[post("/read/{entry_id}")]
async fn mark_entry_read(entry_id: String, #[header = "entry_filter"] entry_filter: String, #[data] db: db::DB) -> Result<EntryListTemplate, Rejection> {
    let entries = db
        .mark_entry_read(entry_id, db::name_to_filter(entry_filter))
        .await.map_err(|_| warp::reject::not_found())?;
    Ok(EntryListTemplate {
        entries,
    })
}

#[post("/starred/{entry_id}")]
async fn mark_entry_starred(entry_id: String, #[header = "entry_filter"] entry_filter: String, #[data] db: db::DB) -> Result<EntryListTemplate, Rejection> {
    let entries = db.mark_entry_starred(entry_id, db::name_to_filter(entry_filter))
        .await.map_err(|_| warp::reject::not_found())?;
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
    let feeds = db.get_feeds().await;
    let entries = db.get_entries(|_| true).await;

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

    type EntryFilter = fn(e: &Entry) -> bool;

    pub(crate) fn unread_filter(e: &Entry) -> bool {
        !e.read
    }

    pub(crate) fn starred_filter(e: &Entry) -> bool {
        e.starred
    }

    pub(crate) fn name_to_filter(e: String) -> EntryFilter {
        match e.as_ref() {
            "unread" => unread_filter,
            "starred" => starred_filter,
            _ => |_| true,
        }
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
                    f.last_fetched = Some(Utc::now());
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

        pub(crate) async fn get_entries(&self, filter: EntryFilter) -> Vec<Entry> {
            let mut e = self.entries.lock().await
                .values()
                .cloned()
                .filter(filter)
                .collect::<Vec<Entry>>();

            e.sort_by(|a, b| a.published.cmp(&b.published));
            e
        }

        pub(crate) async fn get_starred_entries(&self) -> Vec<Entry> {
            self.get_entries(|e| e.starred).await
                .into_iter()
                .collect()
        }

        pub(crate) async fn get_unread_entries(&self) -> Vec<Entry> {
            self.get_entries(|e| !e.read).await
                .into_iter()
                .collect()
        }

        pub(crate) async fn mark_entry_read(&self, entry_id: String, filter: EntryFilter) -> Result<Vec<Entry>, &str> {
            {
                let mut out = self.entries.lock().await;
                let mut e = out.get_mut(&entry_id).ok_or("entry not found")?;
                e.read = !e.read;
            }
            Ok(self.get_entries(filter).await)
        }

        pub(crate) async fn mark_entry_starred(&self, entry_id: String, filter: EntryFilter) -> Result<Vec<Entry>, &str> {
            {
                let mut out = self.entries.lock().await;
                let mut e = out.get_mut(&entry_id).ok_or("entry not found")?;
                e.starred = !e.starred;
            }
            Ok(self.get_entries(filter).await)
        }
    }
}

#[cfg(test)]
mod test {
    use super::*;

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
    async fn add_list_feeds() {
        let db: db::DB = Default::default();
        let feeds = vec![
            Feed {
                name: "HackerNews".to_string(),
                site_url: "https://news.ycombinator.com".to_string(),
                feed_url: "https://news.ycombinator.com/rss".to_string(),
                favicon: "https://hackernews.com/favicon".to_string(),
                last_fetched: Some(Utc::now()),
                fetch_error: None,
                category: "tech".to_string(),
            },
            Feed {
                name: "Product Hunt".to_string(),
                site_url: "https://www.producthunt.com".to_string(),
                feed_url: "https://www.producthunt.com/feed".to_string(),
                favicon: "https://www.producthunt.com/favicon".to_string(),
                last_fetched: None,
                fetch_error: None,
                category: "tech".to_string(),
            }
        ];

        db.add_feeds(feeds.into_iter()).await;
        let f = db.get_feeds().await;
        assert_eq!(f.len(), 2);
        assert_eq!(f[0].name, "HackerNews");
    }

    #[test]
    fn render_feedstemplate() {
        let feeds = vec![
            Feed {
                name: "HackerNews".to_string(),
                site_url: "https://news.ycombinator.com".to_string(),
                feed_url: "https://news.ycombinator.com/rss".to_string(),
                favicon: "https://hackernews.com/favicon".to_string(),
                last_fetched: Some(Utc::now()),
                fetch_error: None,
                category: "tech".to_string(),
            },
            Feed {
                name: "Product Hunt".to_string(),
                site_url: "https://www.producthunt.com".to_string(),
                feed_url: "https://www.producthunt.com/feed".to_string(),
                favicon: "https://www.producthunt.com/favicon".to_string(),
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
