use reqwest::{header, Client};
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
    // Apply prompt template if configured
    let final_prompt = if let Some(template) = &config.prompt_template {
        debug!("Using prompt template: {}", template);
        template.replace("{input}", text)
    } else {
        debug!("No prompt template configured, using raw text");
        text.to_string()
    };

    // Construct payload format based on the LLM URL
    let mut payload = if config.llm_url.contains("ollama")
        || config.llm_url.contains("localhost:11434")
    {
        // Ollama API format for chat endpoint
        serde_json::json!({
            "model": config.model_name,
            "messages": [
                {
                    "role": "system",
                    "content": "You are a text improvement tool that corrects grammar and improves clarity without adding conversational elements. Follow the instructions exactly."
                },
                {
                    "role": "user",
                    "content": final_prompt
                }
            ],
            "temperature": 0.3,
            "top_p": 0.8,
            "stream": false
        })
    } else {
        // OpenAI API format for /v1/responses endpoint
        serde_json::json!({
            "model": config.model_name,
            "input": [
                {
                    "role": "system",
                    "content": [
                        {
                            "type": "input_text",
                            "text": "You are a text improvement tool that corrects grammar and improves clarity without adding conversational elements. Follow the instructions exactly."
                        }
                    ]
                },
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "input_text",
                            "text": final_prompt
                        }
                    ]
                }
            ],
            "text": {
                "format": {
                    "type": "text"
                }
            },
            "reasoning": {},
            "tools": [],
            "temperature": 0.7,
            "max_output_tokens": 2048,
            "top_p": 0.8,
            "store": true
        })
    };

    // Merge optional parameters from config file if they exist
    if let Some(params_value) = &config.llm_params {
        if let Some(params_map) = params_value.as_object() {
            if let Some(payload_map) = payload.as_object_mut() {
                for (key, value) in params_map {
                    // Skip 'prompt_template' if it exists in the llm_params
                    if key != "prompt_template" {
                        payload_map.insert(key.clone(), value.clone());
                    } else {
                        warn!("Skipping 'prompt_template' parameter, as it should not be sent to the API");
                    }
                }
            } else {
                warn!("Payload is not a JSON object, cannot merge llm_params.");
            }
        } else {
            warn!("llm_params in config is not a JSON object.");
        }
    }

    info!("Sending request to LLM API");
    debug!(target: "request_payload", "LLM Payload: {}", payload);

    // Build the request with appropriate headers based on LLM provider
    let mut req_builder = client
        .post(&config.llm_url)
        .header(header::CONTENT_TYPE, "application/json");

    // Add authentication and headers based on LLM provider
    if !(config.llm_url.contains("ollama") || config.llm_url.contains("localhost:11434")) {
        // For OpenAI, we need API key authentication
        let api_key = config.openai_api_key.clone().ok_or_else(|| {
            error!("Missing OpenAI API key. Set OPENAI_API_KEY environment variable.");
            AppError::LlmApiError("Missing OpenAI API key".to_string())
        })?;

        req_builder = req_builder.header("Authorization", format!("Bearer {}", api_key));

        // Add optional organization ID if specified
        if let Some(org_id) = &config.openai_org_id {
            req_builder = req_builder.header("OpenAI-Organization", org_id);
        }

        // Add optional project ID if specified
        if let Some(project_id) = &config.openai_project_id {
            req_builder = req_builder.header("OpenAI-Project", project_id);
        }
    }
    // For Ollama, no additional headers needed

    // Finalize and send the request
    let res = match req_builder.json(&payload).send().await {
        Ok(response) => response,
        Err(e) => {
            // Log detailed error information
            error!("OpenAI API request failed: {}", e);
            if e.is_timeout() {
                error!("Request timed out - consider increasing the timeout value");
            }
            if e.is_connect() {
                error!("Connection error - check your internet connection and OpenAI API status");
            }
            return Err(AppError::LlmApiError(format!(
                "OpenAI API request failed: {}",
                e
            )));
        }
    };

    let status = res.status();
    if !status.is_success() {
        let error_body = res
            .text()
            .await
            .unwrap_or_else(|_| "Failed to read error body".to_string());
        error!(
            "OpenAI API returned error status {}: {}",
            status, error_body
        );
        return Err(AppError::LlmApiError(format!(
            "OpenAI API error (Status {}): {}",
            status, error_body
        )));
    }

    // Parse response based on API used
    let response_data = res.json::<Value>().await?;
    debug!("Received LLM response data: {:?}", response_data);

    // Parse Ollama or OpenAI response format
    if config.llm_url.contains("ollama") || config.llm_url.contains("localhost:11434") {
        // Parse Ollama response format
        if let Some(message) = response_data.get("message") {
            if let Some(content) = message.get("content").and_then(Value::as_str) {
                let trimmed = content.trim();
                let max_length = 2000; // Limit response to 2000 characters
                if trimmed.len() > max_length {
                    info!(
                        "LLM response was truncated from {} to {} characters",
                        trimmed.len(),
                        max_length
                    );
                    return Ok(trimmed[..max_length].to_string() + "...");
                }
                return Ok(trimmed.to_string());
            }
        }
    } else {
        // Parse OpenAI response format for /v1/responses endpoint
        if let Some(output_array) = response_data.get("output").and_then(Value::as_array) {
            // Look for the first message in the output array
            if let Some(first_output) = output_array.get(0) {
                // Check for content array in the message
                if let Some(content_array) = first_output.get("content").and_then(Value::as_array) {
                    // Look for text in the first content item
                    if let Some(first_content) = content_array.get(0) {
                        if let Some(text) = first_content.get("text").and_then(Value::as_str) {
                            let trimmed = text.trim();
                            let max_length = 2000; // Limit response to 2000 characters
                            if trimmed.len() > max_length {
                                info!(
                                    "LLM response was truncated from {} to {} characters",
                                    trimmed.len(),
                                    max_length
                                );
                                return Ok(trimmed[..max_length].to_string() + "...");
                            }
                            return Ok(trimmed.to_string());
                        }
                    }
                }
            }
        }
    }

    // Fallback if response format is unexpected
    warn!("LLM response format not recognized: {:?}", response_data);
    Err(AppError::LlmApiError(format!(
        "Unrecognized LLM response format. Received: {}",
        serde_json::to_string(&response_data)
            .unwrap_or_else(|_| "Non-serializable response".to_string())
    )))
}
