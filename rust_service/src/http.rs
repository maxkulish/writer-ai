use axum::Json;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{info, instrument};

use crate::config::AppConfig;
use crate::errors::AppError;
use crate::llm::query_llm;

// --- Request/Response Structs ---
#[derive(Deserialize, Debug)]
pub struct ProcessRequest {
    pub text: String,
}

#[derive(Serialize, Debug)]
pub struct ProcessResponse {
    pub response: String,
}

// --- Request Handler ---
#[instrument(skip_all)]
pub async fn process_text_handler(
    axum::extract::State((config, client)): axum::extract::State<(Arc<AppConfig>, Arc<Client>)>,
    Json(req): Json<ProcessRequest>,
) -> Result<Json<ProcessResponse>, AppError> {
    info!("Received text length: {}", req.text.len());
    // debug!("Received text content: {}", req.text); // Uncomment for verbose debugging

    let start_time = std::time::Instant::now();
    let llm_response = query_llm(&req.text, &config, &client).await?;
    let elapsed = start_time.elapsed();
    
    info!("Response time: {:.3}ms", elapsed.as_secs_f64() * 1000.0);
    info!("Sending back response length: {}", llm_response.len());
    Ok(Json(ProcessResponse {
        response: llm_response,
    }))
}
