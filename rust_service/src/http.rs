use axum::Json;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{info, instrument, warn};

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
    let response_len = llm_response.len();
    info!("Sending back response length: {}", response_len);
    
    // Check for suspiciously long responses that might indicate LLM hallucinations
    if response_len > 1000 {
        warn!("Response is unusually long ({}). Consider reviewing the prompt template.", response_len);
    }
    Ok(Json(ProcessResponse {
        response: llm_response,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::extract::State;
    use axum::Json;
    use std::sync::Arc;

    // In a real test implementation, we'd use dependency injection for the query_llm function.
    // For this simplified test, we'll just use the real function since it's not the focus of this test.
    
    #[tokio::test]
    #[ignore] // Mark as ignored since it would make an actual API call
    async fn test_process_text_handler_success() {
        // Since we can't easily mock the query_llm function without refactoring,
        // we'll mark this test as ignored so it doesn't actually run in normal tests
        
        // In a real application, we'd refactor the code to use dependency injection
        // so that we could properly mock the LLM API
        
        // For now, we'll just verify the test framework without making assertions
        // The test is ignored anyway
    }

    #[tokio::test]
    async fn test_process_text_handler_error() {
        // Similar to the success test, but simulate a failure in query_llm
        // Create real dependencies
        let config = Arc::new(AppConfig {
            port: 8989,
            llm_url: "https://api.openai.com/v1/responses".to_string(),
            model_name: "gpt-4o".to_string(),
            llm_params: None,
            prompt_template: None,
            openai_api_key: None, // This will cause an error when query_llm is called
            openai_org_id: None,
            openai_project_id: None,
        });
        let client = Arc::new(Client::new());
        let app_state = (config, client);
        
        // Create test request
        let request = ProcessRequest {
            text: "Test input text".to_string(),
        };
        
        // We expect this to fail because the OpenAI API key is missing
        let result = process_text_handler(State(app_state), Json(request)).await;
        
        // Verify the error
        assert!(result.is_err());
        if let Err(app_error) = result {
            match app_error {
                AppError::LlmApiError(msg) => {
                    assert!(msg.contains("Missing OpenAI API key"));
                }
                _ => panic!("Expected LlmApiError, got: {:?}", app_error),
            }
        }
    }
}
