# GitHub CI/CD for WriterAI

This document describes the GitHub Actions workflows for continuous integration and deployment of WriterAI.

## Workflow Overview

WriterAI has two main GitHub workflow files:

1. `.github/workflows/rust.yml` - For building and testing the Rust service
   - Runs tests for PRs and pushes to the main branch
   - Builds platform-specific binaries when pushing to main or creating tags
   - Creates GitHub releases with Rust binaries when tags are pushed

2. `.github/workflows/swift-release.yml` - For building and releasing the complete macOS app
   - Builds both Rust service and Swift app
   - Creates a universal binary for Intel and Apple Silicon Macs
   - Packages everything into a DMG file
   - Uploads the DMG to GitHub Releases

## CI/CD Pipeline Jobs

The CI/CD pipeline consists of three main jobs:

### 1. Test

- Runs on Ubuntu
- Installs Rust toolchain
- Caches dependencies for faster builds
- Runs all tests with `cargo test`

### 2. Build

Uses a matrix strategy to build for multiple platforms in parallel:
- Linux (x86_64)
- macOS Intel (x86_64)
- macOS Apple Silicon (ARM64)

For each platform:
- Installs appropriate Rust toolchain
- Builds optimized release binary with `cargo build --release`
- Uploads compiled binary as an artifact

### 3. Create Release

Only runs when a new tag is pushed (starting with "v"):
- Downloads all artifacts from the build job
- Creates a GitHub release with generated release notes
- Attaches platform-specific binaries to the release

## Setting up the GitHub Token

To allow the GitHub Actions workflows to create releases, you need to set up a GitHub token with the appropriate permissions:

1. Go to your GitHub repository's settings
2. Click on "Secrets and variables" → "Actions"
3. Click "New repository secret"
4. Name: `GH_TOKEN`
5. Value: Create a personal access token with the `repo` scope at https://github.com/settings/tokens
6. Click "Add secret"

## Creating a Release

To create a new release:

1. Update versions in:
   - `rust_service/Cargo.toml`:
     ```toml
     [package]
     name = "writer_ai_rust_service"
     version = "0.2.0"  # Update this version
     ```
   - `swift_agent/WriterAIHotkeyAgent/WriterAIHotkeyAgent/Info.plist`:
     Update the `CFBundleShortVersionString` and `CFBundleVersion` values

2. Create and push a new tag:
   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```

3. GitHub Actions will automatically:
   - Build Rust binaries for all platforms
   - Build the Swift macOS application
   - Create a GitHub release
   - Attach binaries and DMG to the release

## Installation Options

### One-Line Installer (Recommended)

The simplest way to install WriterAI is with the provided installation script:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/maxkulish/writer-ai/HEAD/install.sh)"
```

This script will:
1. Fetch the latest release from GitHub
2. Download the DMG file
3. Mount the DMG and install to your Applications folder

### Manual Installation

#### Complete macOS App

1. Download the latest `WriterAI.dmg` from the [GitHub Releases](https://github.com/maxkulish/writer-ai/releases) page
2. Open the DMG file
3. Drag the WriterAI app to your Applications folder

#### Rust Service Only

If you only need the Rust backend service:

1. Download the appropriate binary for your platform from [GitHub Releases](https://github.com/maxkulish/writer-ai/releases):
   - `writer_ai_rust_service-macos-arm64` - for Apple Silicon (M1/M2/M3) Macs
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

4. Create a configuration file:
   ```bash
   mkdir -p ~/.config/writer_ai_service
   touch ~/.config/writer_ai_service/config.toml
   ```

## Manual Build and DMG Creation

If you need to build and package the app manually:

1. Run the package script to build both Rust and Swift components:
   ```bash
   ./package_app.sh
   ```

2. If the DMG isn't created properly, use the create_dmg.sh script:
   ```bash
   ./create_dmg.sh
   ```