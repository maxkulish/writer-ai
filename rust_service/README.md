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
llm_url = "http://localhost:11434/api/generate" # Example for Ollama
model_name = "llama3"

# Optional parameters for the LLM API request body
#[llm_params]
#stream = false
#temperature = 0.7
```

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

The service will start on the configured port (default: 8989).

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
  -d '{"text":"What is the capital of France?"}'
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

## Development

To run in development mode with verbose logging:

```bash
RUST_LOG=debug cargo run
```

## License

[MIT License](LICENSE)
