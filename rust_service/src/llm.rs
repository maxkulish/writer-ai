use reqwest::Client;
use serde_json::Value;
use tracing::{debug, error, info, instrument, warn};

use crate::config::AppConfig;
use crate::errors::AppError;

// --- LLM Query Function ---
#[instrument(skip_all)]
pub async fn query_llm(
    text: &str,
    config: &AppConfig,
    client: &Client,
) -> Result<String, AppError> {
    // Construct the base payload
    let mut payload = serde_json::json!({
        "model": config.model_name,
        "prompt": text,
        // Default "stream" to false if not specified in config
        "stream": false,
    });

    // Merge optional parameters from config file if they exist
    if let Some(params_value) = &config.llm_params {
        if let Some(params_map) = params_value.as_object() {
            if let Some(payload_map) = payload.as_object_mut() {
                for (key, value) in params_map {
                    payload_map.insert(key.clone(), value.clone());
                }
            } else {
                warn!("Payload is not a JSON object, cannot merge llm_params.");
            }
        } else {
            warn!("llm_params in config is not a JSON object.");
        }
    }

    info!("Sending request to LLM URL: {}", config.llm_url);
    debug!(target: "request_payload", "LLM Payload: {}", payload);

    let res = client
        .post(&config.llm_url)
        .json(&payload)
        .send()
        .await?;

    let status = res.status();
    if !status.is_success() {
        let error_body = res.text().await.unwrap_or_else(|_| "Failed to read error body".to_string());
        error!("LLM API returned error status {}: {}", status, error_body);
        return Err(AppError::LlmApiError(format!(
            "LLM API error (Status {}): {}", status, error_body
        )));
    }

    // --- Adapt Response Parsing ---
    // Support multiple response formats (Ollama, OpenAI, etc.)
    let response_data = res.json::<Value>().await?;
    debug!("Received LLM response data: {:?}", response_data);

    // Try Ollama format
    if let Some(response_str) = response_data.get("response").and_then(Value::as_str) {
        return Ok(response_str.trim().to_string());
    }

    // Try OpenAI format
    if let Some(choices) = response_data.get("choices").and_then(Value::as_array) {
        if let Some(first_choice) = choices.get(0) {
            if let Some(message) = first_choice.get("message") {
                if let Some(content) = message.get("content").and_then(Value::as_str) {
                    return Ok(content.trim().to_string());
                }
            }
        }
    }

    // Fallback if format is unknown
    warn!("LLM response format not recognized: {:?}", response_data);
    Err(AppError::LlmApiError(format!(
        "Unrecognized LLM response format. Received: {}",
        serde_json::to_string(&response_data).unwrap_or_else(|_| "Non-serializable response".to_string())
    )))
}