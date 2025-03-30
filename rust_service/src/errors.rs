use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use tracing::error;
use thiserror::Error;

// --- Custom Error Type ---
#[derive(Error, Debug)]
pub enum AppError {
    #[error("Configuration error: {0}")]
    Config(#[from] config::ConfigError),
    #[error("Network request error: {0}")]
    Reqwest(#[from] reqwest::Error),
    #[error("JSON serialization/deserialization error: {0}")]
    SerdeJson(#[from] serde_json::Error),
    #[error("LLM API returned an error: {0}")]
    LlmApiError(String),
    #[error("IO Error: {0}")]
    Io(#[from] std::io::Error),
    #[error("Missing configuration directory")]
    MissingConfigDir,
    #[error("Could not determine home directory")]
    MissingHomeDir,
    #[error("Internal Server Error: {0}")]
    Internal(String),
}

// Convert AppError into an HTTP response
impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, error_message) = match &self {
            AppError::Config(e) => (StatusCode::INTERNAL_SERVER_ERROR, format!("Configuration error: {}", e)),
            AppError::Reqwest(e) => (StatusCode::BAD_GATEWAY, format!("LLM request failed: {}", e)),
            AppError::SerdeJson(e) => (StatusCode::INTERNAL_SERVER_ERROR, format!("JSON processing error: {}", e)),
            AppError::LlmApiError(msg) => (StatusCode::BAD_GATEWAY, msg.clone()),
            AppError::Io(e) => (StatusCode::INTERNAL_SERVER_ERROR, format!("IO error: {}", e)),
            AppError::MissingConfigDir => (StatusCode::INTERNAL_SERVER_ERROR, self.to_string()),
            AppError::MissingHomeDir => (StatusCode::INTERNAL_SERVER_ERROR, self.to_string()),
            AppError::Internal(msg) => (StatusCode::INTERNAL_SERVER_ERROR, msg.clone()),
        };
        error!("Error processing request: {}", error_message);
        (status, Json(serde_json::json!({ "error": error_message }))).into_response()
    }
}