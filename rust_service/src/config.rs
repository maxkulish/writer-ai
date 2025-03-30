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
        .set_default("llm_url", "http://localhost:11434/api/generate")?
        .set_default("model_name", "llama3")?
        // Load config file if it exists
        .add_source(ConfigFile::from(config_file_path.clone()).required(false))
        // Load environment variables (e.g., WRITER_AI_SERVICE_PORT=9000)
        .add_source(Environment::with_prefix("WRITER_AI_SERVICE").separator("__"))
        .build()?;

    let app_config: AppConfig = config_loader.try_deserialize()?;

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
llm_url = "{}" # Example for Ollama
model_name = "{}"

# Optional parameters for the LLM API request body
#[llm_params]
#stream = false
#temperature = 0.7
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
