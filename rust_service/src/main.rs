mod cache;
mod config;
mod errors;
mod http;
mod llm;

use axum::{routing::post, Router};
use reqwest::Client;
use std::{net::SocketAddr, sync::Arc, path::PathBuf};
use tokio::net::TcpListener;
use tracing::{error, info, warn};
use tracing_subscriber::{fmt, EnvFilter};

use crate::cache::CacheManager;
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
        .timeout(std::time::Duration::from_secs(60)) // 60 seconds timeout for LLMs
        .build()?;
    let shared_client = Arc::new(http_client.clone());
    
    // Test LLM API connectivity on startup based on the configured LLM provider
    let is_ollama = shared_config.llm_url.contains("ollama") || shared_config.llm_url.contains("localhost:11434");
    
    if is_ollama {
        // Ollama doesn't require API key
        info!("Testing connection to Ollama API");
        info!("Using Ollama endpoint: {}", shared_config.llm_url);
        info!("Using model: {}", shared_config.model_name);
        
        // Test connection to Ollama API using the list models endpoint
        let test_url = if shared_config.llm_url.ends_with("/chat") {
            shared_config.llm_url.replace("/chat", "/models")
        } else {
            "http://localhost:11434/api/models".to_string()
        };
        
        info!("Testing Ollama API connectivity...");
        match http_client.get(&test_url).timeout(std::time::Duration::from_secs(5)).send().await {
            Ok(resp) => {
                if resp.status().is_success() {
                    info!("✅ Successfully connected to Ollama API");
                    let model_name = &shared_config.model_name;
                    info!("Using model: {}", model_name);
                } else {
                    warn!("⚠️ Ollama API responded with status code: {}", resp.status());
                    match resp.text().await {
                        Ok(body) => warn!("Response body: {}", body),
                        Err(_) => warn!("Could not read error response body"),
                    }
                }
            },
            Err(e) => {
                warn!("⚠️ Failed to connect to Ollama API: {}", e);
                if e.is_timeout() {
                    warn!("Connection timed out - Ollama may not be running");
                } else if e.is_connect() {
                    warn!("Connection error - check if Ollama is running and accessible at localhost:11434");
                }
            }
        }
    } else {
        // OpenAI API connectivity test
        info!("Testing connection to OpenAI API");
        
        // Verify API key is configured
        match &shared_config.openai_api_key {
            Some(api_key) if !api_key.is_empty() => {
                // Only show masking for actual keys, not empty ones
                if api_key.len() > 8 {
                    let masked_key = format!("{}...{}", &api_key[..4], &api_key[api_key.len()-4..]);
                    info!("✅ OpenAI API key is configured: {}", masked_key);
                } else {
                    info!("✅ OpenAI API key is configured");
                }
                
                // Log org ID if present
                if let Some(org_id) = &shared_config.openai_org_id {
                    if !org_id.is_empty() {
                        info!("✅ Using OpenAI Organization ID: {}", org_id);
                    }
                }
                
                // Log project ID if present
                if let Some(project_id) = &shared_config.openai_project_id {
                    if !project_id.is_empty() {
                        info!("✅ Using OpenAI Project ID: {}", project_id);
                    }
                }
                
                // Test connection to OpenAI API using the models endpoint
                info!("Testing OpenAI API connectivity...");
                let mut req_builder = http_client
                    .get("https://api.openai.com/v1/models")
                    .timeout(std::time::Duration::from_secs(5))
                    .header("Authorization", format!("Bearer {}", api_key));
                
                // Add org ID if configured
                if let Some(org_id) = &shared_config.openai_org_id {
                    if !org_id.is_empty() {
                        req_builder = req_builder.header("OpenAI-Organization", org_id);
                    }
                }
                
                // Add project ID if configured
                if let Some(project_id) = &shared_config.openai_project_id {
                    if !project_id.is_empty() {
                        req_builder = req_builder.header("OpenAI-Project", project_id);
                    }
                }
                
                // Send test request
                match req_builder.send().await {
                    Ok(resp) => {
                        if resp.status().is_success() {
                            info!("✅ Successfully connected to OpenAI API");
                            let model_name = &shared_config.model_name;
                            info!("Using model: {}", model_name);
                        } else {
                            warn!("⚠️ OpenAI API responded with status code: {}", resp.status());
                            match resp.text().await {
                                Ok(body) => warn!("Response body: {}", body),
                                Err(_) => warn!("Could not read error response body"),
                            }
                        }
                    },
                    Err(e) => {
                        warn!("⚠️ Failed to connect to OpenAI API: {}", e);
                        if e.is_timeout() {
                            warn!("Connection timed out - OpenAI API may be temporarily unavailable");
                        } else if e.is_connect() {
                            warn!("Connection error - check your internet connection and firewall settings");
                        }
                    }
                }
            },
            _ => {
                warn!("⚠️ No OpenAI API key configured! The service will not work with OpenAI.");
                warn!("Set the OPENAI_API_KEY environment variable or add it to the config file.");
            }
        }
    }

    // Initialize the cache
    let cache_dir = dirs::cache_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("writer_ai_service");
    
    std::fs::create_dir_all(&cache_dir)
        .map_err(|e| AppError::Io(e))?;
    
    let cache_path = cache_dir.join("response_cache.sled");
    info!("Initializing cache at: {:?}", cache_path);
    
    let cache_manager = Arc::new(CacheManager::new(
        cache_path, 
        shared_config.cache.clone()
    )?);
    
    if shared_config.cache.enabled {
        info!("Response caching is enabled (TTL: {} days, Max size: {} MB)", 
            shared_config.cache.ttl_days, 
            shared_config.cache.max_size_mb);
    } else {
        info!("Response caching is disabled");
    }

    // Build application router state
    let app_state = (shared_config.clone(), shared_client, cache_manager);

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
