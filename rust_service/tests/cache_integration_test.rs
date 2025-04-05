use std::sync::Arc;
use tempfile::TempDir;
use axum::extract::State;
use axum::Json;
use reqwest::Client;
use wiremock::{MockServer, Mock, ResponseTemplate};
use wiremock::matchers::{method, path};
use serde_json::json;

use writer_ai_rust_service::config::AppConfig;
use writer_ai_rust_service::cache::CacheManager;
use writer_ai_rust_service::http::{process_text_handler, ProcessRequest};

/// Test that the caching functionality works end-to-end
#[tokio::test]
async fn test_cache_integration() {
    // Start a mock server to simulate the LLM API
    let mock_server = MockServer::start().await;
    
    // Create a temporary directory for the cache
    let temp_dir = TempDir::new().unwrap();
    let cache_path = temp_dir.path().join("test_cache.sled");
    
    // Create configuration for this test
    let app_config = AppConfig {
        port: 8989,
        llm_url: format!("{}/v1/responses", mock_server.uri()),
        model_name: "test-model".to_string(),
        llm_params: None,
        prompt_template: None,
        openai_api_key: Some("fake-api-key".to_string()),
        openai_org_id: None,
        openai_project_id: None,
        cache: writer_ai_rust_service::cache::CacheConfig {
            enabled: true,
            ttl_days: 30,
            max_size_mb: 100,
        },
    };
    
    // Set up the shared state
    let client = Arc::new(Client::new());
    let cache_manager = Arc::new(CacheManager::new(cache_path, app_config.cache.clone()).unwrap());
    let app_state = (Arc::new(app_config.clone()), client.clone(), cache_manager.clone());
    
    // Create test request
    let request = ProcessRequest {
        text: "Test input for caching".to_string(),
    };
    
    // Configure first mock response - use a more specific matcher for the first request
    Mock::given(method("POST"))
        .and(path("/v1/responses"))
        .and(wiremock::matchers::body_string_contains("Test input for caching"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "output": [
                {
                    "content": [
                        {
                            "text": "This is a mocked LLM response"
                        }
                    ]
                }
            ]
        })))
        .expect(1) // We expect this to be called only once (on cache miss)
        .mount(&mock_server)
        .await;
    
    // First request should result in a cache miss and call the mock server
    let first_response = process_text_handler(State(app_state.clone()), Json(request.clone())).await.unwrap();
    assert_eq!(first_response.response, "This is a mocked LLM response");
    
    // Second request with the same input should be served from cache (no call to mock server)
    let second_response = process_text_handler(State(app_state.clone()), Json(request.clone())).await.unwrap();
    assert_eq!(second_response.response, "This is a mocked LLM response");
    
    // Create a request with different text (should miss cache)
    let different_request = ProcessRequest {
        text: "Different test input".to_string(),
    };
    
    // Set up another expectation for the different request
    Mock::given(method("POST"))
        .and(path("/v1/responses"))
        .and(wiremock::matchers::body_string_contains("Different test input"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "output": [
                {
                    "content": [
                        {
                            "text": "Different mocked response"
                        }
                    ]
                }
            ]
        })))
        .expect(1)
        .mount(&mock_server)
        .await;
    
    // This should miss the cache and call the mock server again
    let different_response = process_text_handler(State(app_state.clone()), Json(different_request)).await.unwrap();
    assert_eq!(different_response.response, "Different mocked response");
    
    // Original request should still be in cache
    let original_request = ProcessRequest {
        text: "Test input for caching".to_string(),
    };
    
    // Should still be in cache
    let cached_response = process_text_handler(State(app_state), Json(original_request)).await.unwrap();
    assert_eq!(cached_response.response, "This is a mocked LLM response");
}

/// Test that disabling the cache works correctly
#[tokio::test]
async fn test_disabled_cache() {
    // Start a mock server to simulate the LLM API
    let mock_server = MockServer::start().await;
    
    // Configure mock to return a fixed response - expect it to be called twice
    Mock::given(method("POST"))
        .and(path("/v1/responses"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "output": [
                {
                    "content": [
                        {
                            "text": "This is a mocked LLM response"
                        }
                    ]
                }
            ]
        })))
        .expect(2) // We expect this to be called twice when cache is disabled
        .mount(&mock_server)
        .await;
    
    // Create a temporary directory for the cache
    let temp_dir = TempDir::new().unwrap();
    let cache_path = temp_dir.path().join("test_cache.sled");
    
    // Create configuration with cache disabled
    let app_config = AppConfig {
        port: 8989,
        llm_url: format!("{}/v1/responses", mock_server.uri()),
        model_name: "test-model".to_string(),
        llm_params: None,
        prompt_template: None,
        openai_api_key: Some("fake-api-key".to_string()),
        openai_org_id: None,
        openai_project_id: None,
        cache: writer_ai_rust_service::cache::CacheConfig {
            enabled: false, // Cache is disabled
            ttl_days: 30,
            max_size_mb: 100,
        },
    };
    
    // Set up the shared state
    let client = Arc::new(Client::new());
    let cache_manager = Arc::new(CacheManager::new(cache_path, app_config.cache.clone()).unwrap());
    let app_state = (Arc::new(app_config.clone()), client.clone(), cache_manager.clone());
    
    // Create test request
    let request = ProcessRequest {
        text: "Test input for disabled cache".to_string(),
    };
    
    // First request should call the LLM API
    let first_response = process_text_handler(State(app_state.clone()), Json(request.clone())).await.unwrap();
    assert_eq!(first_response.response, "This is a mocked LLM response");
    
    // Second request with the same input should also call the LLM API
    // because caching is disabled
    let second_response = process_text_handler(State(app_state), Json(request)).await.unwrap();
    assert_eq!(second_response.response, "This is a mocked LLM response");
}