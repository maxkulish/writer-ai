use writer_ai_rust_service::config::AppConfig;
use writer_ai_rust_service::http::{process_text_handler, ProcessRequest};
use axum::extract::State;
use axum::Json;
use reqwest::Client;
use std::sync::Arc;
use tokio::fs;
use std::path::PathBuf;

// Helper function to load test configs
fn load_test_config(config_file_name: &str) -> Result<AppConfig, String> {
    let config_dir = PathBuf::from("tests/config_files");
    let config_file_path = config_dir.join(config_file_name);

    println!("Loading test config from: {:?}", config_file_path);

    let config_loader = config::Config::builder()
        .add_source(config::File::from(config_file_path).required(true))
        .build()
        .map_err(|e| format!("Config loading error: {}", e))?;

    config_loader.try_deserialize::<AppConfig>().map_err(|e| format!("Config deserialization error: {}", e))
}

// Only run these tests when explicitly requested, as they call external APIs
#[tokio::test]
#[ignore] // Skip by default, run with: cargo test --test llm_integration_tests -- --include-ignored
async fn test_llm_responses() {
    // Check for API key in environment
    let api_key = std::env::var("OPENAI_API_KEY").unwrap_or_else(|_| {
        println!("⚠️  OPENAI_API_KEY environment variable not set. OpenAI tests will be skipped.");
        String::new()
    });

    // Read test sentences
    let test_sentences_str = fs::read_to_string("tests/llm_test_sentences.toml")
        .await
        .expect("Failed to read test sentences file");
    let test_sentences_config: toml::Value = toml::from_str(&test_sentences_str)
        .expect("Failed to parse test sentences TOML");
    let sentences = test_sentences_config["sentences"]
        .as_array()
        .expect("Sentences array not found in TOML");

    // Define LLM configurations to test
    let mut llm_configs = Vec::new();

    // Only add OpenAI if we have an API key
    if !api_key.is_empty() {
        match load_test_config("config_openai_gpt4o.toml") {
            Ok(mut config) => {
                // Set the API key from environment
                config.openai_api_key = Some(api_key.clone());
                llm_configs.push(config);
            }
            Err(e) => println!("Failed to load OpenAI config: {}", e),
        }
    }

    // Only add Ollama if it's available (localhost:11434)
    // You could add a simple check here to see if Ollama is running
    let ollama_check = reqwest::Client::new()
        .get("http://localhost:11434/api/version")
        .timeout(std::time::Duration::from_secs(1))
        .send()
        .await;

    if ollama_check.is_ok() {
        match load_test_config("config_ollama_llama2.toml") {
            Ok(config) => llm_configs.push(config),
            Err(e) => println!("Failed to load Ollama config: {}", e),
        }
    } else {
        println!("⚠️  Ollama server not detected at localhost:11434. Ollama tests will be skipped.");
    }

    // If no configs were loaded, skip the test
    if llm_configs.is_empty() {
        println!("No LLM configurations available for testing. Skipping test.");
        return;
    }

    // Create response directory if it doesn't exist
    fs::create_dir_all("tests/llm_responses").await.expect("Failed to create response directory");

    for (i, sentence_value) in sentences.iter().enumerate() {
        let sentence = sentence_value
            .as_str()
            .expect("Sentence is not a string");
        println!("--- Testing sentence #{}: '{}' ---", i + 1, sentence);

        for config in &llm_configs {
            let model_name = &config.model_name;
            println!("  Testing with model: '{}'", model_name);

            let client = Arc::new(Client::new());
            let app_state = (Arc::new(config.clone()), client);
            let request = ProcessRequest {
                text: sentence.to_string(),
            };

            let result = process_text_handler(State(app_state), Json(request)).await;

            match result {
                Ok(response) => {
                    println!("    Response from {}: {}", model_name, response.response);
                    // Save response to a file
                    let response_dir = format!(
                        "tests/llm_responses/{}",
                        model_name.replace("/", "_")
                    ); // Sanitize model name for directory
                    fs::create_dir_all(&response_dir)
                        .await
                        .expect("Failed to create response dir");
                    let sentence_file_name = format!(
                        "sentence_{}.txt",
                        i + 1
                    );
                    let file_path = format!("{}/{}", response_dir, sentence_file_name);
                    fs::write(&file_path, &response.response)
                        .await
                        .expect("Failed to save response");
                    println!("    Response saved to: {}", file_path);
                }
                Err(e) => {
                    println!("    Error from {}: {:?}", model_name, e);
                    // Save error message
                    let response_dir = format!(
                        "tests/llm_responses/{}",
                        model_name.replace("/", "_")
                    );
                    fs::create_dir_all(&response_dir)
                        .await
                        .expect("Failed to create response dir");
                    let sentence_file_name = format!(
                        "sentence_{}_ERROR.txt",
                        i + 1
                    );
                    let file_path = format!("{}/{}", response_dir, sentence_file_name);
                    fs::write(&file_path, format!("ERROR: {:?}", e))
                        .await
                        .expect("Failed to save error");
                }
            }
        }
        println!("--- Sentence test complete ---\n");
    }

    // Suggest manual review of results
    println!("\nℹ️  LLM integration tests completed.");
    println!("ℹ️  Results saved in tests/llm_responses/");
    println!("ℹ️  Please manually review the responses to evaluate LLM performance.");
}