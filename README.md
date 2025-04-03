# WriterAI

WriterAI is a productivity tool that enhances your writing with LLM assistance. It runs in the background and can be triggered with a customizable hotkey to instantly improve your text.

[![GitHub release (latest by date)](https://img.shields.io/github/v/release/maxkulish/writer-ai)](https://github.com/maxkulish/writer-ai/releases/latest)
[![GitHub license](https://img.shields.io/github/license/maxkulish/writer-ai)](https://github.com/maxkulish/writer-ai/blob/main/LICENSE)

**Quick Install:**
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/maxkulish/writer-ai/HEAD/install.sh)"
```

## Features

- Runs quietly in the background with minimal resource usage
- Responds to customizable keyboard shortcuts (default: Shift+Control+E)
- Seamlessly processes selected text and replaces it with improved content
- Supports multiple LLM backends through the Rust service
- Maintains privacy by processing text locally when using local LLMs like Ollama
- Works with OpenAI models for top-quality text improvements

## Installation

### One-Line Installer (Recommended)

The easiest way to install WriterAI is with the one-line installer:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/maxkulish/writer-ai/HEAD/install.sh)"
```

This script will:
1. Fetch the latest release from GitHub
2. Download the DMG file
3. Mount the DMG and install to your Applications folder
4. Launch the app automatically

### Manual Installation (macOS)

1. Download the latest release `.dmg` file from the [Releases](https://github.com/maxkulish/writer-ai/releases) page
2. Open the DMG file
3. Drag the WriterAI app to your Applications folder
4. Open WriterAI from your Applications folder
5. When prompted, grant Accessibility permissions in System Settings

### Download Prebuilt Binaries

You can download just the Rust service binary from the [GitHub Releases](https://github.com/maxkulish/writer-ai/releases) page:

1. Choose the appropriate binary for your platform:
   - `writer_ai_rust_service-macos-arm64` - for Apple Silicon (M1/M2) Macs
   - `writer_ai_rust_service-macos-intel` - for Intel Macs
   - `writer_ai_rust_service-linux-amd64` - for Linux systems

2. Make the binary executable:
   ```bash
   chmod +x writer_ai_rust_service-*
   ```

3. Move it to a location in your PATH:
   ```bash
   sudo mv writer_ai_rust_service-* /usr/local/bin/writer_ai_rust_service
   ```

### Building from Source

#### Prerequisites
- macOS 13.0 or later
- [Xcode](https://apps.apple.com/us/app/xcode/id497799835) (not just Command Line Tools)
- [Rust and Cargo](https://www.rust-lang.org/tools/install)

#### Option 1: Using the Packaging Script

1. Clone this repository
   ```bash
   git clone https://github.com/maxkulish/writer-ai.git
   cd writer-ai
   ```

2. Run the packaging script
   ```bash
   ./package_app.sh
   ```

3. The built application and DMG installer will be available in the `release` directory

#### Option 2: Building Manually

1. Build the Rust backend service
   ```bash
   cd rust_service
   cargo build --release
   ```

2. Open the Swift project in Xcode
   ```bash
   open swift_agent/WriterAIHotkeyAgent/WriterAIHotkeyAgent.xcodeproj
   ```

3. In Xcode:
   - Select the "WriterAIHotkeyAgent" scheme
   - Choose "Product > Build" (or press ⌘B)
   - Ensure all app icons are properly set up in Assets.xcassets

4. To create a distributable package:
   - In Xcode, choose "Product > Archive"
   - In the Archives window, select your archive and click "Distribute App"
   - Choose "Copy App" or "Developer ID Distribution" (if you have a developer certificate)
   - Save the exported app

5. To create a DMG installer manually:
   ```bash
   # Create a DMG (replace path/to/exported/app with your actual path)
   hdiutil create -volname "WriterAI" -srcfolder path/to/exported/WriterAI.app -ov -format UDZO WriterAI.dmg
   ```

## Usage

1. Start WriterAI from your Applications folder
2. Grant the necessary permissions when prompted
3. Select text in any application
4. Press the hotkey (default: Shift+Control+E)
5. Wait for the text to be processed and replaced with improved content

## Configuration

### Hotkey Configuration

The default hotkey is **Shift+Control+E** (previously was Shift+Control+N, but changed to avoid conflicts with system commands). You can customize it by editing the `Info.plist` file. For more information, see [Hotkey Configuration Guide](docs/hotkey_configuration.md).

### Rust Service and LLM Configuration

WriterAI uses a Rust service to connect to LLM backends. The service needs to be running for the app to work.

After installation, the Rust service is automatically configured and started. Configuration files are created at:
```
~/.config/writer_ai_service/config.toml
```

#### Using Local LLMs (Ollama)

If you have [Ollama](https://ollama.ai/) installed, WriterAI will detect it and configure itself to use your local LLMs.

1. Make sure Ollama is running: `ollama serve`
2. Pull the model you want to use (if not already downloaded): `ollama pull mistral:latest`
3. The default configuration uses `mistral:latest` but you can edit the config to use any model available in your Ollama installation

#### Using OpenAI Models

To use OpenAI models:

1. Edit the config file: `~/.config/writer_ai_service/config.toml`
2. Add your OpenAI API key: `openai_api_key = "sk-your-actual-api-key"`
3. Restart the Rust service: 
   ```bash
   pkill writer_ai_rust_service
   ~/.local/bin/writer_ai_rust_service &
   ```

#### Manual Control of the Rust Service

- Start: `~/.local/bin/writer_ai_rust_service`
- Check status: `ps aux | grep writer_ai_rust_service`
- Stop: `pkill writer_ai_rust_service`

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
