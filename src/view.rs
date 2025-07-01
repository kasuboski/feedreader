use anyhow::anyhow;
use askama::Template;
use axum::{
    extract::{Path, State},
    http::HeaderMap,
    response::{Html, IntoResponse, Redirect},
    routing::{delete, get, post},
    Form, Router,
};
use serde::{Deserialize, Serialize};

use crate::{
    db::{self, EntryFilter, Ordering},
    AppError, AppState,
};

use super::{Entry, Feed};

macro_rules! impl_template_response {
    ($($template:ty),*) => {
        $(
            impl IntoResponse for $template {
                fn into_response(self) -> axum::response::Response {
                    match self.render() {
                        Ok(html) => Html(html).into_response(),
                        Err(_) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, "Template error").into_response(),
                    }
                }
            }
        )*
    };
}

impl_template_response!(
    IndexTemplate,
    HistoryTemplate,
    EntryListTemplate,
    FeedsTemplate,
    FeedListTemplate,
    StarredTemplate,
    AddFeedTemplate
);

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/", get(index))
        .route("/history.html", get(history))
        .route("/feeds.html", get(get_feeds))
        .route("/starred.html", get(get_starred))
        .route("/add_feed.html", get(add_feed))
        .route("/feeds", post(post_feed))
        .route("/feeds/{feed_url}", delete(remove_feed))
        .route("/read/{entry_id}", post(mark_entry_read))
        .route("/starred/{entry_id}", post(mark_entry_starred))
}

pub fn display_some<T>(value: &Option<T>) -> String
where
    T: std::fmt::Display,
{
    value
        .as_ref()
        .map_or_else(|| String::new(), |value| value.to_string())
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

async fn index(State(AppState { db }): State<AppState>) -> Result<IndexTemplate, AppError> {
    let entries = db.get_unread_entries().await?;
    Ok(IndexTemplate { entries })
}

async fn history(State(AppState { db }): State<AppState>) -> Result<HistoryTemplate, AppError> {
    let entries = db
        .get_entries(db::EntryFilter::All, db::Ordering::Descending)
        .await?;
    Ok(HistoryTemplate { entries })
}

async fn get_feeds(State(AppState { db }): State<AppState>) -> Result<FeedsTemplate, AppError> {
    let feeds = db.get_feeds().await?;
    Ok(FeedsTemplate { feeds })
}

async fn get_starred(State(AppState { db }): State<AppState>) -> Result<StarredTemplate, AppError> {
    let entries = db.get_starred_entries().await?;
    Ok(StarredTemplate { entries })
}

async fn add_feed() -> Result<AddFeedTemplate, AppError> {
    Ok(AddFeedTemplate {})
}

async fn post_feed(
    State(AppState { db }): State<AppState>,
    Form(body): Form<AddFeedForm>,
) -> Result<impl IntoResponse, AppError> {
    db.add_feeds(vec![body.into()].into_iter()).await?;
    Ok(Redirect::to("/feeds.html"))
}

async fn remove_feed(
    Path(feed_url): Path<String>,
    State(AppState { db }): State<AppState>,
) -> Result<FeedListTemplate, AppError> {
    db.remove_feed(feed_url).await?;
    let feeds = db.get_feeds().await?;
    Ok(FeedListTemplate { feeds })
}

async fn mark_entry_read(
    Path(entry_id): Path<String>,
    headers: HeaderMap,
    State(AppState { db }): State<AppState>,
) -> Result<EntryListTemplate, AppError> {
    let entry_filter = headers
        .get("entry_filter")
        .ok_or_else(|| anyhow!("missing entry_filter header"))?
        .to_str()?
        .parse::<EntryFilter>()?;
    let ordering = headers
        .get("ordering")
        .ok_or_else(|| anyhow!("missing ordering header"))?
        .to_str()?
        .parse::<Ordering>()?;
    let entries = db.mark_entry_read(entry_id, entry_filter, ordering).await?;
    Ok(EntryListTemplate { entries })
}

async fn mark_entry_starred(
    Path(entry_id): Path<String>,
    headers: HeaderMap,
    State(AppState { db }): State<AppState>,
) -> Result<EntryListTemplate, AppError> {
    let entry_filter = headers
        .get("entry_filter")
        .ok_or_else(|| anyhow!("missing entry_filter header"))?
        .to_str()?
        .parse::<EntryFilter>()?;
    let ordering = headers
        .get("ordering")
        .ok_or_else(|| anyhow!("missing ordering header"))?
        .to_str()?
        .parse::<Ordering>()?;
    let entries = db
        .mark_entry_starred(entry_id, entry_filter, ordering)
        .await?;
    Ok(EntryListTemplate { entries })
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

    #[test]
    fn render_feedstemplate() {
        let feeds = vec![
            Feed::new(
                "HackerNews".to_string(),
                "https://news.ycombinator.com".to_string(),
                "https://news.ycombinator.com/rss".to_string(),
                "tech".to_string(),
            ),
            Feed::new(
                "Product Hunt".to_string(),
                "https://www.producthunt.com".to_string(),
                "https://www.producthunt.com/feed".to_string(),
                "tech".to_string(),
            ),
        ];
        let temp = FeedsTemplate { feeds };

        assert!(temp.render().is_ok(), "template failed to render");
    }
}
