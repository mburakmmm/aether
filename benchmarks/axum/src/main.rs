use axum::extract::Json;
use axum::routing::{get, post};
use axum::Router;
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;

#[derive(Serialize)]
struct Pong {
    pong: bool,
}

#[derive(Deserialize, Serialize)]
struct Echo {
    msg: String,
}

async fn ping() -> Json<Pong> {
    Json(Pong { pong: true })
}

async fn echo(Json(body): Json<Echo>) -> Json<Echo> {
    Json(body)
}

#[tokio::main]
async fn main() {
    let port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|raw| raw.parse().ok())
        .unwrap_or(3005);
    let app = Router::new()
        .route("/ping", get(ping))
        .route("/echo", post(echo));
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .unwrap_or_else(|err| panic!("bind {addr}: {err}"));
    axum::serve(listener, app)
        .await
        .unwrap_or_else(|err| panic!("serve {addr}: {err}"));
}
