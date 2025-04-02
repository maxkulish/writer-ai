# WriterAI

WriterAI is a productivity tool that enhances your writing with LLM assistance. It runs in the background and can be triggered with a customizable hotkey to instantly improve your text.

## Features

- Runs quietly in the background with minimal resource usage
- Responds to customizable keyboard shortcuts (default: Shift+Control+N)
- Seamlessly processes selected text and replaces it with improved content
- Supports multiple LLM backends through the Rust service
- Maintains privacy by processing text locally when using local LLMs

## Installation

### macOS

1. Download the latest release `.dmg` file from the [Releases](https://github.com/your-username/writer-ai/releases) page
2. Open the DMG file
3. Drag the WriterAI app to your Applications folder
4. Open WriterAI from your Applications folder
5. When prompted, grant Accessibility permissions in System Settings

### Building from Source

#### Prerequisites
- macOS 13.0 or later
- [Xcode](https://apps.apple.com/us/app/xcode/id497799835) (not just Command Line Tools)
- [Rust and Cargo](https://www.rust-lang.org/tools/install)

#### Option 1: Using the Packaging Script

1. Clone this repository
   ```bash
   git clone https://github.com/your-username/writer-ai.git
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
4. Press the hotkey (default: Shift+Control+N)
5. Wait for the text to be processed and replaced with improved content

## Configuration

### Hotkey Configuration

The default hotkey is Shift+Control+N. You can customize it by editing the `Info.plist` file. For more information, see [Hotkey Configuration Guide](docs/hotkey_configuration.md).

### LLM Configuration

WriterAI supports various LLM backends through its Rust service. Configuration files for different models are provided in the `rust_service/tests/config_files` directory.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
