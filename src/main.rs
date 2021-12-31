use std::env;
use rweb::*;
use serde::{Serialize, Deserialize};

#[derive(Schema, Deserialize, Serialize)]
struct Healthz {
    up: bool,
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
