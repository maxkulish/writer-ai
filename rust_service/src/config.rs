use config::{Config as ConfigLoader, Environment, File as ConfigFile};
use serde::Deserialize;
use serde_json::Value;
use std::path::PathBuf;
use tracing::{debug, info, warn};

use crate::errors::AppError;

// --- Configuration Struct ---
#[derive(Debug, Deserialize, Clone)]
pub struct AppConfig {
    pub port: u16,
    pub llm_url: String,
    pub model_name: String,
    #[serde(default)]
    pub llm_params: Option<Value>,
    #[serde(default)]
    pub prompt_template: Option<String>,
    #[serde(default)]
    pub openai_api_key: Option<String>,
    #[serde(default)]
    pub openai_org_id: Option<String>,
    #[serde(default)]
    pub openai_project_id: Option<String>,
}

// --- Configuration Loading ---
pub fn find_config_path() -> Result<PathBuf, AppError> {
    // Only use ~/.config/writer_ai_service as the config directory
    let mut config_path = dirs::home_dir().ok_or(AppError::MissingHomeDir)?;
    config_path.push(".config/writer_ai_service");
    Ok(config_path)
}

pub fn load_config() -> Result<AppConfig, AppError> {
    let config_dir = find_config_path()?;
    let config_file_path = config_dir.join("config.toml");

    info!(
        "Attempting to load configuration from: {:?}",
        config_file_path
    );

    let config_loader = ConfigLoader::builder()
        // Set defaults
        .set_default("port", 8989)?
        .set_default("llm_url", "https://api.openai.com/v1/responses")?
        .set_default("model_name", "gpt-4o")?
        // Extract OpenAI API key from environment if available
        .add_source(Environment::with_prefix("OPENAI").separator("_"))
        // Load config file if it exists
        .add_source(ConfigFile::from(config_file_path.clone()).required(false))
        // Load environment variables (e.g., WRITER_AI_SERVICE_PORT=9000)
        .add_source(Environment::with_prefix("WRITER_AI_SERVICE").separator("__"))
        .build()?;

    let app_config: AppConfig = config_loader.try_deserialize()?;
    
    // Load auth variables from environment if not in config
    let mut updated_config = app_config.clone();
    let mut config_updated = false;

    // --- Handle OpenAI API Key ---
    if updated_config.openai_api_key.is_none() {
        if let Ok(api_key) = std::env::var("OPENAI_API_KEY") {
            // Mask most of the key for security in logs
            let masked_key = if api_key.len() > 8 {
                format!("{}...{}", &api_key[..4], &api_key[api_key.len()-4..])
            } else {
                "[too short]".to_string()
            };
            info!("Using OPENAI_API_KEY from environment: {}", masked_key);
            updated_config.openai_api_key = Some(api_key);
            config_updated = true;
        } else {
            warn!("No OPENAI_API_KEY found in config or environment");
        }
    } else {
        let api_key = updated_config.openai_api_key.as_ref().unwrap();
        let masked_key = if api_key.len() > 8 {
            format!("{}...{}", &api_key[..4], &api_key[api_key.len()-4..])
        } else {
            "[too short]".to_string()
        };
        info!("Using OPENAI_API_KEY from config: {}", masked_key);
    }
    
    // --- Handle OpenAI Organization ID ---
    if updated_config.openai_org_id.is_none() {
        if let Ok(org_id) = std::env::var("OPENAI_ORG_ID") {
            info!("Using OPENAI_ORG_ID from environment: {}", org_id);
            updated_config.openai_org_id = Some(org_id);
            config_updated = true;
        }
    } else {
        info!("Using OPENAI_ORG_ID from config: {}", 
              updated_config.openai_org_id.as_ref().unwrap());
    }
    
    // --- Handle OpenAI Project ID ---
    if updated_config.openai_project_id.is_none() {
        if let Ok(project_id) = std::env::var("OPENAI_PROJECT_ID") {
            info!("Using OPENAI_PROJECT_ID from environment: {}", project_id);
            updated_config.openai_project_id = Some(project_id);
            config_updated = true;
        }
    } else {
        info!("Using OPENAI_PROJECT_ID from config: {}", 
              updated_config.openai_project_id.as_ref().unwrap());
    }
    
    // Return the updated config if any changes were made
    if config_updated {
        return Ok(updated_config);
    }

    // Check if config file exists, create default if not
    if !config_file_path.exists() {
        warn!(
            "Config file not found at {:?}. Creating a default one.",
            config_file_path
        );
        if !config_dir.exists() {
            std::fs::create_dir_all(&config_dir)?;
            info!("Created config directory: {:?}", config_dir);
        }

        // Use potentially overridden defaults for the initial creation
        let default_toml_content = format!(
            r#"# Default LLM Service Configuration
# Created because the file was missing. Review and adjust as needed.

port = {}
llm_url = "{}" # OpenAI API endpoint
model_name = "{}"

# Authentication for OpenAI API
# Can also be set via environment variables: OPENAI_API_KEY, OPENAI_ORG_ID, OPENAI_PROJECT_ID
openai_api_key = "" # Your OpenAI API key (required)
#openai_org_id = "org-EVPAPa0e5FSeelWefXSvJr8r" # Optional: Your OpenAI Organization ID
#openai_project_id = "" # Optional: Your OpenAI Project ID

# Optional parameters for the LLM API request body
[llm_params]
temperature = 0.7
max_output_tokens = 500
top_p = 1

# Optional prompt template - uses {{input}} as placeholder for user text
prompt_template = """Improve the provided text input for clarity, grammar, and overall communication, ensuring it's fluently expressed in English.

# Steps

1. **Identify Errors**: Examine the input text for grammatical, spelling, and punctuation errors.
2. **Improve Clarity**: Rephrase sentences to improve clarity and flow while maintaining the original meaning.
3. **Ensure Fluency**: Adjust the text to sound natural and fluent in English.
4. **Check Consistency**: Ensure the tone remains consistent throughout the text.
5. **Produce Improved Text**: Deliver the revised version focusing on correctness and readability.

# Output Format

- Provide a single improved version of the input text as a plain sentence or paragraph. 
- Do not include the original text in the response.

# Examples

**Example 1:**

- **Input**: "My English is no such god. Howe ar you?"
- **Output**: "My English isn't very good. How are you?"

**Example 2:**

- **Input**: "Weather here change alot. I not used it."
- **Output**: "The weather here changes a lot. I'm not used to it."

# Notes

- Maintain the main idea or intent of the original input.
- Focus on improving readability and grammatical correctness.
- Consider cultural nuances if necessary to preserve meaning.

{{input}}
"""
"#,
            app_config.port, app_config.llm_url, app_config.model_name
        );

        std::fs::write(&config_file_path, default_toml_content)?;
        info!("Created default config file at {:?}", config_file_path);
    } else {
        info!(
            "Loaded configuration successfully from {:?}",
            config_file_path
        );
    }

    debug!("Effective configuration: {:?}", app_config);
    Ok(app_config)
}
