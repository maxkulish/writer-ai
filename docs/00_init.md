# Project: Writer-AI - Swift + Rust LLM Assistant for macOS**

**1. Project Goal & Architecture Overview**

*   **Goal:** Create a macOS utility ("Writer-AI") allowing users to select text in any application, press a global hotkey (`Cmd+Shift+W`), have the text processed by a local LLM, and have the result replace the selected text.
*   **Architecture:**
    *   **Swift Frontend (Agent):** A lightweight, background-only macOS application responsible for:
        *   Registering and detecting the global hotkey (`Cmd+Shift+W`) using native `NSEvent`.
        *   Simulating Copy (`Cmd+C`) to get selected text via `NSAppleScript` and `NSPasteboard`.
        *   Sending the text to the Rust backend via HTTP POST.
        *   Receiving the processed text from the backend.
        *   Simulating Paste (`Cmd+V`) to replace the original selection using `NSAppleScript`.
    *   **Rust Backend (Service):** A performant, persistent background service responsible for:
        *   Running an HTTP server (`axum`) listening on localhost.
        *   Loading configuration (LLM endpoint, model, parameters) from a TOML file.
        *   Receiving text processing requests from the Swift frontend.
        *   Interacting with the configured LLM API (`reqwest`).
        *   Returning the LLM's response to the Swift frontend.
    *   **Communication:** Simple HTTP/JSON over `localhost`.
    *   **Persistence:** The Rust backend service is managed by `launchd` for automatic startup and restarts.
    *   **Configuration:** A central TOML file (`~/.config/writer_ai_service/config.toml`).

**2. Prerequisites**

1.  **Xcode:** Install from the Mac App Store (includes Swift compiler).
2.  **Rust:** Install via `rustup`: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
3.  **Text Editor:** Your preferred editor (e.g., VS Code with Rust Analyzer).
4.  **(Recommended) Local LLM:** An accessible LLM server like Ollama running locally. Ensure it's configured and reachable.

**3. Implementation Steps**

**Step 3.1: Define Configuration (`config.toml`)**

1.  Create the directory: `mkdir -p ~/.config/writer_ai_service`
2.  Create the configuration file: `touch ~/.config/writer_ai_service/config.toml`
3.  Add initial content (adjust `llm_url`, `model_name`, `llm_params` for your LLM setup):

    ```toml
    # ~/.config/writer_ai_service/config.toml

    # Port the Rust service will listen on (ensure Swift frontend uses the same)
    port = 8989

    # URL of your local LLM API endpoint (e.g., Ollama non-streaming)
    llm_url = "http://localhost:11434/api/generate"

    # Name of the LLM model to use
    model_name = "llama3" # Replace with your model

    # Optional: Parameters specific to the LLM API request body
    # These will be merged into the JSON payload sent to the LLM
    [llm_params]
    stream = false
    # temperature = 0.7
    # Add other parameters supported by your LLM API here
    ```
    *Note: The Rust service will create this file with defaults if it doesn't exist upon first run.*

**Step 3.2: Create the Rust Backend Service**

1.  **Create Project:**
    ```bash
    cargo new writer_ai_rust_service
    cd writer_ai_rust_service
    ```
2.  **Add Dependencies (`Cargo.toml`):**
    ```toml
    [package]
    name = "writer_ai_rust_service"
    version = "0.1.0"
    edition = "2021"

    [dependencies]
    axum = "0.7"
    tokio = { version = "1", features = ["full"] }
    serde = { version = "1.0", features = ["derive"] }
    serde_json = "1.0"
    reqwest = { version = "0.12", features = ["json", "rustls-tls"] } # Use rustls-tls for better compatibility
    config = { version = "0.14", features = ["toml"] }
    dirs = "5.0"
    tracing = "0.1"
    tracing-subscriber = { version = "0.3", features = ["env-filter"] }
    thiserror = "1.0"
    ```
3.  **Write Code (`src/main.rs`):**
    *(Use the complete Rust code provided in the "Final Step-by-Step Implementation Guide" section of the previous response. This includes `AppConfig`, request/response structs, `AppError`, `main` function with `axum` setup, `process_text_handler`, `query_llm` with parameter merging and flexible response parsing, and `load_config` with default file creation.)*
    ```rust
    // --- Paste the full Rust code from the previous response here ---
    // (Includes imports, structs, AppError, main, process_text_handler,
    // query_llm, find_config_path, load_config)
    use axum::{
        routing::post,
        http::StatusCode,
        response::{IntoResponse, Response},
        Json, Router, Server,
    };
    use serde::{Deserialize, Serialize};
    use serde_json::Value;
    use std::{net::SocketAddr, path::PathBuf, sync::Arc}; // Added Arc
    use reqwest::Client;
    use config::{Config as ConfigLoader, File as ConfigFile, FileFormat, Environment}; // Renamed Config to ConfigLoader
    use tracing::{info, error, warn, instrument, debug}; // Added debug
    use tracing_subscriber::{EnvFilter, fmt};
    use thiserror::Error;

    // --- Configuration Struct ---
    #[derive(Debug, Deserialize, Clone)]
    struct AppConfig {
        port: u16,
        llm_url: String,
        model_name: String,
        #[serde(default)]
        llm_params: Option<Value>,
    }

    // --- Request/Response Structs ---
    #[derive(Deserialize, Debug)]
    struct ProcessRequest {
        text: String,
    }

    #[derive(Serialize, Debug)]
    struct ProcessResponse {
        response: String,
    }

    // --- Custom Error Type ---
    #[derive(Error, Debug)]
    enum AppError {
        #[error("Configuration error: {0}")]
        Config(#[from] config::ConfigError),
        #[error("Network request error: {0}")]
        Reqwest(#[from] reqwest::Error),
        #[error("JSON serialization/deserialization error: {0}")]
        SerdeJson(#[from] serde_json::Error),
        #[error("LLM API returned an error: {0}")] // Simplified message
        LlmApiError(String),
        #[error("IO Error: {0}")]
        Io(#[from] std::io::Error),
        #[error("Missing configuration directory")]
        MissingConfigDir,
        #[error("Could not determine home directory")]
        MissingHomeDir,
        #[error("Internal Server Error: {0}")] // Added message
        Internal(String),
    }

    // Convert AppError into an HTTP response
    impl IntoResponse for AppError {
        fn into_response(self) -> Response {
            let (status, error_message) = match &self {
                AppError::Config(e) => (StatusCode::INTERNAL_SERVER_ERROR, format!("Configuration error: {}", e)),
                AppError::Reqwest(e) => (StatusCode::BAD_GATEWAY, format!("LLM request failed: {}", e)),
                AppError::SerdeJson(e) => (StatusCode::INTERNAL_SERVER_ERROR, format!("JSON processing error: {}", e)),
                AppError::LlmApiError(msg) => (StatusCode::BAD_GATEWAY, msg.clone()),
                AppError::Io(e) => (StatusCode::INTERNAL_SERVER_ERROR, format!("IO error: {}", e)),
                AppError::MissingConfigDir | AppError::MissingHomeDir => (StatusCode::INTERNAL_SERVER_ERROR, self.to_string()),
                AppError::Internal(msg) => (StatusCode::INTERNAL_SERVER_ERROR, msg.clone()),
            };
            error!("Error processing request: {}", error_message); // Log the detailed error server-side
            (status, Json(serde_json::json!({ "error": error_message }))).into_response()
        }
    }

    // --- Main Application Logic ---
    #[tokio::main]
    async fn main() -> Result<(), AppError> {
        // Initialize logging (Read RUST_LOG env var, default to info for our crate)
        fmt::Subscriber::builder()
            .with_env_filter(EnvFilter::from_default_env().add_directive("writer_ai_rust_service=info".parse().unwrap()))
            .with_target(false) // Don't include module path prefix
            .compact()          // Use compact format
            .init();

        info!("Starting Writer AI Rust Service...");

        // Load configuration
        let config = load_config()?;
        let shared_config = Arc::new(config); // Share config safely

        // Build HTTP client
        let http_client = Client::builder()
            .timeout(std::time::Duration::from_secs(180)) // Generous timeout for LLMs
            .build()?;
        let shared_client = Arc::new(http_client); // Share client safely

        // Build application router state
        let app_state = (shared_config.clone(), shared_client);

        // Build application router
        let app = Router::new()
            .route("/process", post(process_text_handler))
            .with_state(app_state); // Pass state to handlers

        // Define the server address
        let addr = SocketAddr::from(([127, 0, 0, 1], shared_config.port));
        info!("Listening on http://{}", addr);

        // Run the server
        Server::bind(&addr)
            .serve(app.into_make_service())
            .await
            .map_err(|e| {
                error!("Server failed: {}", e);
                AppError::Internal(format!("Server failed to start: {}", e))
            })?;

        Ok(())
    }

    // --- Request Handler ---
    #[instrument(skip(state, req))]
    async fn process_text_handler(
        axum::extract::State((config, client)): axum::extract::State<(Arc<AppConfig>, Arc<Client>)>,
        Json(req): Json<ProcessRequest>,
    ) -> Result<Json<ProcessResponse>, AppError> {
        info!("Received text length: {}", req.text.len());
        // debug!("Received text content: {}", req.text); // Uncomment for verbose debugging

        let llm_response = query_llm(&req.text, &config, &client).await?;

        info!("Sending back response length: {}", llm_response.len());
        Ok(Json(ProcessResponse { response: llm_response }))
    }

    // --- LLM Query Function ---
    #[instrument(skip(text, config, client))]
    async fn query_llm(
        text: &str,
        config: &AppConfig,
        client: &Client,
    ) -> Result<String, AppError> {
        // Construct the base payload
        let mut payload = serde_json::json!({
            "model": config.model_name,
            "prompt": text,
            // Default "stream" to false if not specified in config, matching Ollama default
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
        debug!("LLM Payload: {}", payload); // Log payload only if debugging verbosely

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
        // Assuming Ollama non-streaming JSON response structure: {"response": "...", ...}
        // Or potentially OpenAI compatible structure: {"choices": [{"message": {"content": "..."}}], ...}
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

    // --- Configuration Loading ---
    fn find_config_path() -> Result<PathBuf, AppError> {
         let config_dir_base = dirs::config_dir().ok_or(AppError::MissingConfigDir)?;
         Ok(config_dir_base.join("writer_ai_service"))
    }


    fn load_config() -> Result<AppConfig, AppError> {
        let config_dir = find_config_path()?;
        let config_file_path = config_dir.join("config.toml");

        info!("Attempting to load configuration from: {:?}", config_file_path);

        let config_loader = ConfigLoader::builder()
            // Set defaults (consistent with AppConfig struct and TOML example)
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
             warn!("Config file not found at {:?}. Creating a default one.", config_file_path);
             if !config_dir.exists() {
                 std::fs::create_dir_all(&config_dir)?;
                 info!("Created config directory: {:?}", config_dir);
             }
             // Use potentially overridden defaults (from env vars) for the initial creation
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
                app_config.port,
                app_config.llm_url, // Use loaded default or env var if present
                app_config.model_name // Use loaded default or env var if present
            );
             std::fs::write(&config_file_path, default_toml_content)?;
             info!("Created default config file at {:?}", config_file_path);
        } else {
             info!("Loaded configuration successfully from {:?}", config_file_path); // Log success if file existed
        }


        debug!("Effective configuration: {:?}", app_config); // Log the final config being used
        Ok(app_config)
    }

    ```
4.  **Build:**
    ```bash
    cargo build --release
    ```
    The binary is located at `./target/release/writer_ai_rust_service`.

**Step 3.3: Make the Rust Service Persistent (`launchd`)**

1.  **Get Binary Path:** In the `writer_ai_rust_service` project directory, run `pwd` and note the full path. The absolute binary path is `[output_of_pwd]/target/release/writer_ai_rust_service`.
2.  **Create `launchd` plist:** Create `~/Library/LaunchAgents/com.user.writer_ai_rust_service.plist` (replace `com.user` with a unique identifier):

    ```xml
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>com.user.writer_ai_rust_service</string> <!-- CHOOSE A UNIQUE LABEL -->

        <key>ProgramArguments</key>
        <array>
             <!-- IMPORTANT: Use the ACTUAL ABSOLUTE path to your compiled Rust binary -->
            <string>/Users/your_username/path/to/writer_ai_rust_service/target/release/writer_ai_rust_service</string>
        </array>

        <key>RunAtLoad</key>
        <true/> <!-- Start on login -->

        <key>KeepAlive</key>
        <true/> <!-- Restart if it crashes -->

        <!-- Redirect logs for debugging -->
        <key>StandardOutPath</key>
        <string>/tmp/writer_ai_rust_service.log</string>
        <key>StandardErrorPath</key>
        <string>/tmp/writer_ai_rust_service.err</string>

        <!-- Set Environment Variables, e.g., for logging -->
        <key>EnvironmentVariables</key>
        <dict>
            <key>RUST_LOG</key>
            <!-- Adjust log levels: error, warn, info, debug, trace -->
            <string>writer_ai_rust_service=info,warn</string>
        </dict>

        <!-- Prevent rapid restarts on repeated failure -->
        <key>ThrottleInterval</key>
        <integer>10</integer> <!-- seconds -->

    </dict>
    </plist>
    ```
    *   **CRITICAL:** Replace `/Users/your_username/path/to/...` with the correct absolute path from step 1.
3.  **Load and Start Service:**
    ```bash
    # Unload if previously loaded (good practice during updates)
    launchctl unload ~/Library/LaunchAgents/com.user.writer_ai_rust_service.plist 2>/dev/null

    # Load the service definition
    launchctl load ~/Library/LaunchAgents/com.user.writer_ai_rust_service.plist

    # Check status (may take a second) & view logs
    launchctl list | grep writer_ai_rust_service
    echo "Tailing logs (Ctrl+C to stop):"
    tail -f /tmp/writer_ai_rust_service.log /tmp/writer_ai_rust_service.err
    ```

**Step 3.4: Create the Swift Frontend Application (Agent)**

1.  **Create Xcode Project:**
    *   Xcode -> File -> New -> Project... -> macOS -> App.
    *   Product Name: `WriterAIHotkeyAgent`.
    *   Interface: `SwiftUI`. Life Cycle: `SwiftUI App`. Language: `Swift`.
    *   Untick "Include Tests". Create the project.
2.  **Configure as Agent:**
    *   Select project target -> `Info` tab.
    *   Add Key: `Application is agent (UIElement)`, Type: `Boolean`, Value: `YES`.
3.  **Implement Code:**
    *   Replace `WriterAIHotkeyAgentApp.swift`:
        ```swift
        import SwiftUI

        @main
        struct WriterAIHotkeyAgentApp: App {
            @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

            var body: some Scene {
                Settings { EmptyView() } // No visible windows needed
            }
        }
        ```
    *   Create `AppDelegate.swift` (File -> New -> File... -> Swift File):
        *(Use the complete Swift code provided in the "Final Step-by-Step Implementation Guide" section of the previous response. This includes `AppDelegate` class, `NSApplicationDelegate` methods, `NSEvent` global monitor for `Cmd+Shift+W`, `handleHotkey` logic, `NSAppleScript` helpers for copy/paste, `NSPasteboard` management, `URLSession` communication with the Rust service, JSON handling, and optional `NSUserNotification`.)*
        ```swift
        // --- Paste the full Swift AppDelegate code from the previous response here ---
        // (Includes imports AppKit/Foundation, AppDelegate class,
        // applicationDidFinishLaunching, applicationWillTerminate, setupHotkeyMonitor,
        // handleHotkey, simulateCopy, simulatePaste, restorePasteboard, runAppleScript,
        // sendToRustService with error handling, showErrorNotification)
        import AppKit // Use AppKit for NSEvent, NSPasteboard etc.
        import Foundation

        class AppDelegate: NSObject, NSApplicationDelegate {

            private var monitor: Any?
            // Read port from Rust config or use default. Best to match default.
            // Ensure port matches Rust config/default (default is 8989)
            private let rustServiceUrl = URL(string: "http://localhost:8989/process")!

            func applicationDidFinishLaunching(_ notification: Notification) {
                print("WriterAI Hotkey Agent started.")

                // Check Accessibility permissions early
                let checkOpt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                let accessEnabled = AXIsProcessTrustedWithOptions([checkOpt: true] as CFDictionary)

                if accessEnabled {
                    print("Accessibility access granted.")
                } else {
                    print("WARNING: Accessibility access is required for hotkey and paste functionality. Please grant access in System Settings > Privacy & Security > Accessibility.")
                    // Consider showing an alert or notification here if desired for first run
                }

                setupHotkeyMonitor()
                print("Global Hotkey Monitor Cmd+Shift+W set up.")
            }

            func applicationWillTerminate(_ notification: Notification) {
                if let monitor = monitor {
                    NSEvent.removeMonitor(monitor)
                    print("Global Hotkey Monitor removed.")
                }
            }

            private func setupHotkeyMonitor() {
                // Monitor key down events globally
                monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    // Check for Cmd+Shift+W
                    // Modifiers check & comparing lowercase character for case-insensitivity
                    if event.modifierFlags.contains([.command, .shift]) && event.charactersIgnoringModifiers?.lowercased() == "w" {
                        print("Hotkey Cmd+Shift+W detected!")
                        self?.handleHotkey()
                    }
                }
            }

            private func handleHotkey() {
                // 1. Get selected text via Copy simulation
                let originalPasteboardContent = NSPasteboard.general.pasteboardItems?.compactMap { $0.copy() as? NSPasteboardItem }

                simulateCopy { success in
                    guard success else {
                        self.showErrorNotification(title: "Copy Failed", message: "Could not simulate Cmd+C. Check Accessibility permissions.")
                        self.restorePasteboard(originalContent: originalPasteboardContent)
                        return
                    }

                    // Short delay for clipboard to update reliably
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { // 150ms delay
                        guard let selectedText = NSPasteboard.general.string(forType: .string), !selectedText.isEmpty else {
                            print("No text found on clipboard after copy attempt.")
                            self.restorePasteboard(originalContent: originalPasteboardContent)
                            // Optionally notify user if desired (can be noisy)
                            // self.showErrorNotification(title: "No Text Selected", message: "Please select text before using the hotkey.")
                            return
                        }

                        print("Selected Text Length: \(selectedText.count)")

                        // 2. Send text to Rust service
                        self.sendToRustService(text: selectedText) { result in
                            // Ensure UI updates (paste simulation, notifications) are on main thread
                            DispatchQueue.main.async {
                                switch result {
                                case .success(let llmResponse):
                                    print("Received LLM Response Length: \(llmResponse.count)")
                                    // 3. Paste the response
                                    self.simulatePaste(text: llmResponse) { pasteSuccess in
                                        if !pasteSuccess {
                                            self.showErrorNotification(title: "Paste Failed", message: "Could not simulate Cmd+V. Response copied to clipboard. Check Accessibility.")
                                            // Put response on clipboard as fallback
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(llmResponse, forType: .string)
                                        } else {
                                            print("Paste simulation successful.")
                                            // Decide whether to restore original clipboard. Generally NO for replacement tasks.
                                            // self.restorePasteboard(originalContent: originalPasteboardContent)
                                        }
                                    }

                                case .failure(let error):
                                    // Log detailed error
                                    print("Error processing text: \(error.localizedDescription)")
                                    // Show user-friendly notification
                                    let errorMessage = self.friendlyErrorMessage(for: error)
                                    self.showErrorNotification(title: "Processing Error", message: errorMessage)
                                    // Restore original clipboard on error
                                    self.restorePasteboard(originalContent: originalPasteboardContent)
                                }
                            }
                        }
                    }
                }
            }

            // MARK: - Clipboard & Simulation Helpers

            private func simulateCopy(completion: @escaping (Bool) -> Void) {
                print("Simulating Cmd+C...")
                // Clear pasteboard *before* copy to help ensure we get the new content
                NSPasteboard.general.clearContents()
                runAppleScript(script: #"tell application "System Events" to keystroke "c" using {command down}"#, completion: completion)
            }

            private func simulatePaste(text: String, completion: @escaping (Bool) -> Void) {
                print("Simulating Cmd+V...")
                // Set clipboard content *before* pasting
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)

                // Small delay for clipboard to settle before pasting
                 DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { // 100ms delay
                     self.runAppleScript(script: #"tell application "System Events" to keystroke "v" using {command down}"#, completion: completion)
                 }
            }

            private func restorePasteboard(originalContent: [NSPasteboardItem]?) {
                 guard let originalItems = originalContent, !originalItems.isEmpty else { return }
                 NSPasteboard.general.clearContents()
                 NSPasteboard.general.writeObjects(originalItems)
                 print("Original clipboard content restored.")
            }


            private func runAppleScript(script: String, completion: @escaping (Bool) -> Void) {
                var error: NSDictionary?
                guard let appleScript = NSAppleScript(source: script) else {
                    print("Failed to initialize NSAppleScript.")
                    completion(false)
                    return
                }

                // Execute AppleScript off the main thread to avoid blocking UI
                DispatchQueue.global(qos: .userInitiated).async {
                     let descriptor = appleScript.executeAndReturnError(&error)
                     // Return result to main thread for safe completion handling
                     DispatchQueue.main.async {
                         if let err = error {
                             print("AppleScript Error: \(err)")
                             completion(false)
                         } else {
                             // print("AppleScript executed successfully. Descriptor: \(descriptor)") // Optional verbose logging
                             completion(true)
                         }
                     }
                }
            }

            // MARK: - Network Communication

            private func sendToRustService(text: String, completion: @escaping (Result<String, Error>) -> Void) {
                 var request = URLRequest(url: rustServiceUrl)
                 request.httpMethod = "POST"
                 request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                 // Match Rust client timeout (or set a reasonable one for potentially long LLM calls)
                 request.timeoutInterval = 180

                 let payload = ["text": text]
                 guard let jsonData = try? JSONEncoder().encode(payload) else {
                     completion(.failure(AppError.encodingFailed))
                     return
                 }
                 request.httpBody = jsonData

                 print("Sending request to Rust service at \(rustServiceUrl)...")
                 URLSession.shared.dataTask(with: request) { data, response, error in
                     // Handle network errors (e.g., connection refused)
                     if let error = error {
                         completion(.failure(error))
                         return
                     }

                     // Ensure we have an HTTP response
                     guard let httpResponse = response as? HTTPURLResponse else {
                         completion(.failure(AppError.invalidResponse))
                         return
                     }

                     // Ensure we have data
                     guard let data = data else {
                          completion(.failure(AppError.noData))
                          return
                     }

                    // Debugging: Print raw response string
                    // if let rawString = String(data: data, encoding: .utf8) {
                    //     print("Raw response [\(httpResponse.statusCode)]: \(rawString)")
                    // } else {
                    //     print("Raw response data: (Non-UTF8)")
                    // }

                    // Handle non-success HTTP status codes specifically
                     guard (200...299).contains(httpResponse.statusCode) else {
                         // Try to parse error JSON from Rust service if available
                          if let jsonError = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                             let errMsg = jsonError["error"] as? String {
                               completion(.failure(AppError.backendError(status: httpResponse.statusCode, message: errMsg)))
                          } else {
                               // Fallback if error JSON parsing fails or isn't provided
                               let responseBody = String(data: data, encoding: .utf8)?.prefix(500) ?? "Non-UTF8 data"
                               completion(.failure(AppError.serverError(status: httpResponse.statusCode, body: String(responseBody))))
                          }
                         return
                     }


                     // Decode the successful JSON response
                     do {
                         if let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                             if let llmText = jsonResponse["response"] as? String {
                                 completion(.success(llmText))
                             } else {
                                 completion(.failure(AppError.unexpectedStructure)) // Missing "response" key
                             }
                         } else {
                             completion(.failure(AppError.invalidJson)) // Data wasn't a dictionary
                         }
                     } catch {
                          completion(.failure(AppError.decodingFailed(error))) // JSON parsing threw an error
                     }

                 }.resume()
            }

            // MARK: - Error Handling & Notifications

            // Custom Error enum for better error handling in Swift client
            enum AppError: Error, LocalizedError {
                case encodingFailed
                case invalidResponse
                case noData
                case serverError(status: Int, body: String)
                case backendError(status: Int, message: String) // Error explicitly from Rust backend JSON
                case invalidJson
                case unexpectedStructure
                case decodingFailed(Error)

                var errorDescription: String? {
                    switch self {
                    case .encodingFailed: return "Failed to encode request."
                    case .invalidResponse: return "Received an invalid response from the server."
                    case .noData: return "No data received from the server."
                    case .serverError(let status, let body): return "Server returned error \(status). Body: \(body)..."
                    case .backendError(_, let message): return "Backend error: \(message)" // Use message from Rust
                    case .invalidJson: return "Server response was not valid JSON."
                    case .unexpectedStructure: return "Server response JSON structure was unexpected."
                    case .decodingFailed(let underlyingError): return "Failed to decode server response: \(underlyingError.localizedDescription)"
                    }
                }
            }

            // Helper to make error messages slightly more user-friendly
            private func friendlyErrorMessage(for error: Error) -> String {
                if let appError = error as? AppError {
                     return appError.localizedDescription
                 } else if let urlError = error as? URLError {
                    // Provide hints for common network issues
                    switch urlError.code {
                    case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
                        return "Could not connect to the backend service (Port \(rustServiceUrl.port ?? 8989)). Is it running? (\(urlError.localizedDescription))"
                    case .timedOut:
                        return "Request timed out. The LLM might be taking too long or the backend is unresponsive. (\(urlError.localizedDescription))"
                    default:
                        return "Network error: \(urlError.localizedDescription)"
                    }
                 } else {
                     return "An unexpected error occurred: \(error.localizedDescription)"
                 }
            }

            private func showErrorNotification(title: String, message: String) {
                 // Use modern UNUserNotificationCenter for notifications
                 let content = UNMutableNotificationContent()
                 content.title = title
                 content.body = message
                 content.sound = .default

                 let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil) // Show immediately
                 UNUserNotificationCenter.current().add(request) { error in
                     if let error = error {
                         print("Error delivering notification: \(error)")
                     }
                 }
                 // Ensure notification permissions are requested if needed (typically done once at app launch)
                 // UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in ... }
             }
        }
        ```

4.  **Enable Accessibility Access:**
    *   Build and Run (`Cmd+R`) the Swift app from Xcode once.
    *   Go to `System Settings` > `Privacy & Security` > `Accessibility`.
    *   Click `+`, navigate to your app's build folder (e.g., `~/Library/Developer/Xcode/DerivedData/WriterAIHotkeyAgent-xxxx/Build/Products/Debug/`), add `WriterAIHotkeyAgent.app`.
    *   **Ensure the toggle next to `WriterAIHotkeyAgent.app` is ON.** This is essential. You may need to restart the Swift app after enabling.
5.  **(Optional) Configure Login Start:**
    *   Go to `System Settings` > `General` > `Login Items`.
    *   Under "Open at Login", click `+`, find and add your built `WriterAIHotkeyAgent.app`.

**Step 3.5: Run and Test**

1.  **Verify Rust Service:** Check `launchctl list | grep writer_ai_rust_service` shows a PID, or check `/tmp/writer_ai_rust_service.log` for "Listening on..." message. Ensure your LLM (e.g., Ollama) is running.
2.  **Run Swift Agent:** Launch `WriterAIHotkeyAgent.app` (either directly, via Xcode, or by logging out/in if added to Login Items). No window/Dock icon will appear. Check Console.app for logs if needed.
3.  **Test Workflow:**
    *   Select text in an application (e.g., TextEdit, Notes).
    *   Press `Cmd+Shift+W`.
    *   Wait a moment. The selected text should be replaced by the LLM response.
4.  **Check Logs:** If issues occur, check:
    *   Rust logs: `/tmp/writer_ai_rust_service.log` and `/tmp/writer_ai_rust_service.err`.
    *   Swift logs: Xcode console (if running from Xcode) or Console.app (search for `WriterAIHotkeyAgent`).

**Step 3.6: Troubleshooting**

*   **Hotkey Inactive:** Check Accessibility permissions (granted *and* enabled). Ensure Swift app is running (Activity Monitor). Check for hotkey conflicts. Check Swift logs for `addGlobalMonitorForEvents` errors.
*   **Text Not Replaced / Error Notification:** Check Rust logs for config errors, LLM connection issues, or response parsing problems. Verify Rust service is running (`launchctl list`). Confirm LLM server URL/model in `config.toml` is correct and LLM server is active. Check Swift logs for network errors (connection refused, timeout) or JSON errors. Ensure ports match between Swift (`rustServiceUrl`) and Rust (`config.toml` / logs). Verify Accessibility allows paste simulation.
*   **Rust Service Fails (`launchd`):** Double-check the absolute binary path in the `.plist`. Verify `.plist` permissions/ownership (`~/Library/LaunchAgents`). Check `Console.app` for `launchd` errors related to the service label. Examine the error log path (`/tmp/writer_ai_rust_service.err`). Run the Rust binary directly from the terminal to see startup errors.
