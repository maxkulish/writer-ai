# Writer AI Rust Service

This is the Rust backend service for the Writer AI application. It provides an API endpoint for processing text through a Large Language Model (LLM).

## Features

- Simple REST API for text processing
- Integration with local LLM services like Ollama
- Configurable via TOML file and environment variables
- Structured logging

## Requirements

- Rust (latest stable version recommended)
- Cargo (comes with Rust)
- An LLM service (e.g., Ollama running locally)

## Installation and Setup

### 1. Install Rust

If you don't have Rust installed, install it via [rustup](https://rustup.rs/):

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

For Windows, download and run rustup-init.exe from the [rustup website](https://rustup.rs/).

### 2. Clone the Repository

```bash
git clone https://github.com/maxkulish/writer-ai.git
cd writer-ai/rust_service
```

### 3. Build the Project

```bash
cargo build --release
```

The compiled binary will be available at `target/release/writer_ai_rust_service`.

## Configuration

The service uses a configuration system with the following priority (highest to lowest):

1. Environment variables (e.g., `WRITER_AI_SERVICE__PORT=9000`)
2. Configuration file at `~/.config/writer_ai_service/config.toml`
3. Default values

### Default Configuration

On first run, if no config file exists, a default one will be created with these settings:

```toml
# Default LLM Service Configuration
port = 8989
llm_url = "https://api.openai.com/v1/responses" # Default OpenAI API endpoint
model_name = "gpt-4o"

# Authentication for OpenAI API
# Can also be set via environment variables: OPENAI_API_KEY, OPENAI_ORG_ID, OPENAI_PROJECT_ID
openai_api_key = "" # Your OpenAI API key (required)
#openai_org_id = "" # Optional: Your OpenAI Organization ID
#openai_project_id = "" # Optional: Your OpenAI Project ID

# Optional parameters for the LLM API request body
[llm_params]
temperature = 0.7
max_output_tokens = 500
top_p = 1

# Optional prompt template - uses {{input}} as placeholder for user text
prompt_template = """Improve the provided text input for clarity, grammar, and overall communication, ensuring it's fluently expressed in English."""
```

### Working with OpenAI

The service can be configured to use OpenAI's API:

1. **Get API Key**: Sign up for an OpenAI account and get an API key from [OpenAI's platform](https://platform.openai.com/).

2. **Configuration**:
   - Set the `openai_api_key` in your config file, or
   - Set the `OPENAI_API_KEY` environment variable

3. **Optional Parameters**:
   - `openai_org_id`: Your organization ID if you're part of a multi-user organization
   - `openai_project_id`: Your project ID for tracking usage and billing

4. **Model Selection**:
   - Set the `model_name` to the model you want to use (e.g., `gpt-4o`, `gpt-3.5-turbo`, etc.)
   - The URL should be `https://api.openai.com/v1/responses`

Example configuration for OpenAI:

```toml
port = 8989
llm_url = "https://api.openai.com/v1/responses"
model_name = "gpt-4o"
openai_api_key = "your-api-key-here"

[llm_params]
temperature = 0.7
max_output_tokens = 500
```

### Working with Local Models via Ollama

For privacy or to reduce costs, you can use local models with [Ollama](https://ollama.ai/):

1. **Install Ollama**:
   - Download and install from [ollama.ai](https://ollama.ai/)
   - Start the Ollama service

2. **Pull a Model**:
   ```bash
   ollama pull llama3 # or another model
   ```

3. **Configuration**:
   ```toml
   port = 8989
   llm_url = "http://localhost:11434/api/chat"
   model_name = "llama3"

   [llm_params]
   temperature = 0.3
   top_p = 0.8
   stream = false
   ```

4. **Performance Notes**:
   - Local models may be slower than cloud-based ones depending on your hardware
   - Different models have different capabilities and specializations
   - Smaller models (7B parameters) are faster but less capable than larger ones (13B, 70B)

### Environment Variables

You can override configuration with environment variables:

- `WRITER_AI_SERVICE__PORT`: Server port
- `WRITER_AI_SERVICE__LLM_URL`: URL of the LLM API
- `WRITER_AI_SERVICE__MODEL_NAME`: Name of the model to use

## Running the Service

### From Source

```bash
cargo run --release
```

### Using the Compiled Binary

```bash
./target/release/writer_ai_rust_service
```

### Running as a Service with launchd (macOS)

1. Create a launchd plist file in your LaunchAgents directory:

```bash
# Create the plist file
touch ~/Library/LaunchAgents/com.user.writer_ai_rust_service.plist
```

2. Edit the plist file with the following content (replace the path with your actual binary path):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.writer_ai_rust_service</string>

    <key>ProgramArguments</key>
    <array>
        <string>/Users/your_username/path/to/writer_ai_rust_service/target/release/writer_ai_rust_service</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/tmp/writer_ai_rust_service.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/writer_ai_rust_service.err</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>RUST_LOG</key>
        <string>writer_ai_rust_service=info,warn</string>
    </dict>
</dict>
</plist>
```

3. Load the service:

```bash
launchctl load ~/Library/LaunchAgents/com.user.writer_ai_rust_service.plist
```

The service will start on the configured port (default: 8989).

## Updating and Restarting the Service

When you update the configuration or the application:

1. Edit your configuration file at `~/.config/writer_ai_service/config.toml`

2. Unload and reload the service:

```bash
# Unload the service
launchctl unload ~/Library/LaunchAgents/com.user.writer_ai_rust_service.plist

# Reload the service
launchctl load ~/Library/LaunchAgents/com.user.writer_ai_rust_service.plist
```

3. Check the logs to verify the service restarted correctly:

```bash
tail -f /tmp/writer_ai_rust_service.log /tmp/writer_ai_rust_service.err
```

For quick model changes without editing the config file, use environment variables:

```bash
launchctl unload ~/Library/LaunchAgents/com.user.writer_ai_rust_service.plist
WRITER_AI_SERVICE__MODEL_NAME=different-model launchctl load ~/Library/LaunchAgents/com.user.writer_ai_rust_service.plist
```

## Customizing Prompts

You can customize how the service processes text by configuring the `prompt_template` in your config file. This template controls the instructions sent to the LLM.

The template should include the placeholder `{input}` which will be replaced with the user's text. For example:

```toml
prompt_template = """Improve the provided text input for clarity, grammar, and overall communication, ensuring it's fluently expressed in English.

# Steps

1. **Identify Errors**: Examine the input text for grammatical, spelling, and punctuation errors.
2. **Improve Clarity**: Rephrase sentences to improve clarity and flow while maintaining the original meaning.
3. **Ensure Fluency**: Adjust the text to sound natural and fluent in English.

{input}
"""
```

This allows you to tailor the behavior of the LLM without changing the application code.

## API Usage

The service exposes a single endpoint for text processing:

### POST /process

Request body:

```json
{
  "text": "Your text to process"
}
```

Response:

```json
{
  "response": "The processed text from the LLM"
}
```

Example with curl:

```bash
curl -X POST http://localhost:8989/process \
  -H "Content-Type: application/json" \
  -d '{"text":"My English is no such god. Howe ar you?"}'
```

Expected response:

```json
{
  "response": "My English isn't very good. How are you?"
}
```

## Logging

The service uses structured logging via the `tracing` crate. Log level can be controlled with the `RUST_LOG` environment variable:

```bash
RUST_LOG=info cargo run --release
```

Available log levels: error, warn, info, debug, trace

## Project Structure

The codebase is organized into modules:

- `main.rs`: Application entry point and server setup
- `config.rs`: Configuration loading and management
- `errors.rs`: Error types and handling
- `http.rs`: HTTP request/response handling
- `llm.rs`: LLM interaction logic

## Testing

The service includes both unit tests and integration tests:

### Running Unit Tests

To run the unit tests:

```bash
cargo test
```

This runs all tests except those marked with `#[ignore]`.

### Running Integration Tests with LLMs

The project includes integration tests for LLM responses in `tests/llm_integration_tests.rs`. These tests are marked with `#[ignore]` to avoid running them automatically, as they require external API access and may incur costs.

To run the integration tests:

```bash
# Set your API key for tests that use OpenAI
export OPENAI_API_KEY='your-api-key'

# Run the integration tests
cargo test --test llm_integration_tests -- --include-ignored
```

The integration tests:
1. Read test sentences from `tests/llm_test_sentences.toml`
2. Process each sentence through different LLM configurations
3. Save the responses to `tests/llm_responses/[model_name]/`
4. Require manual review to evaluate the quality of the responses

### Test Files

- **Unit Tests**: Located within each source file in the `#[cfg(test)]` module
- **Integration Tests**:
  - `tests/llm_integration_tests.rs`: Main integration test file
  - `tests/llm_test_sentences.toml`: Test sentences for LLM evaluation
  - `tests/config_files/`: Configuration files for different LLM setups
  - `tests/llm_responses/`: Directory where test responses are saved (created during test run)

### Adding More Tests

To add more test sentences, edit `tests/llm_test_sentences.toml`.

To test with additional LLM configurations, add new config files to `tests/config_files/` and update the `test_llm_responses` function in `tests/llm_integration_tests.rs`.

## Development

To run in development mode with verbose logging:

```bash
RUST_LOG=debug cargo run
```

## License

[MIT License](LICENSE)
