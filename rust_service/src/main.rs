mod config;
mod errors;
mod http;
mod llm;

use axum::{routing::post, Router};
use reqwest::Client;
use std::{net::SocketAddr, sync::Arc};
use tokio::net::TcpListener;
use tracing::{error, info};
use tracing_subscriber::{fmt, EnvFilter};

use crate::config::load_config;
use crate::errors::AppError;
use crate::http::process_text_handler;

// --- Main Application Logic ---
#[tokio::main]
async fn main() -> Result<(), AppError> {
    // Initialize logging (Read RUST_LOG env var, default to info for our crate)
    fmt::Subscriber::builder()
        .with_env_filter(
            EnvFilter::from_default_env()
                .add_directive("writer_ai_rust_service=info".parse().unwrap()),
        )
        .with_target(false)
        .compact()
        .init();

    info!("Starting Writer AI Rust Service...");

    // Load configuration
    let config = load_config()?;
    let shared_config = Arc::new(config);

    // Build HTTP client
    let http_client = Client::builder()
        .timeout(std::time::Duration::from_secs(10)) // 10 seconds timeout for LLMs
        .build()?;
    let shared_client = Arc::new(http_client);

    // Build application router state
    let app_state = (shared_config.clone(), shared_client);

    // Build application router
    let app = Router::new()
        .route("/process", post(process_text_handler))
        .with_state(app_state);

    // Define the server address
    let addr = SocketAddr::from(([127, 0, 0, 1], shared_config.port));
    info!("Listening on http://{}", addr);

    // Run the server
    let listener = TcpListener::bind(addr).await.map_err(|e| {
        error!("Failed to bind to address: {}", e);
        AppError::Internal(format!("Failed to bind to address: {}", e))
    })?;

    axum::serve(listener, app.into_make_service())
        .await
        .map_err(|e| {
            error!("Server failed: {}", e);
            AppError::Internal(format!("Server failed to start: {}", e))
        })?;

    Ok(())
}
