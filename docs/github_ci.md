# GitHub CI/CD for WriterAI

This document describes the GitHub Actions workflow for continuous integration and deployment of the WriterAI Rust service.

## Workflow Overview

The GitHub workflow defined in `.github/workflows/rust.yml` automatically:

1. Runs tests for PRs and pushes to the main branch
2. Builds platform-specific binaries when pushing to main or creating tags
3. Creates GitHub releases with binaries when tags are pushed

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

## Creating a Release

To create a new release:

1. Update version in `rust_service/Cargo.toml`:
   ```toml
   [package]
   name = "writer_ai_rust_service"
   version = "0.2.0"  # Update this version
   ```

2. Create and push a new tag:
   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```

3. GitHub Actions will automatically:
   - Build binaries for all platforms
   - Create a GitHub release
   - Attach binaries to the release

## Downloading Binaries

Released binaries can be downloaded from the [GitHub Releases](https://github.com/your-username/writer-ai/releases) page.

Choose the appropriate binary for your platform:
- `writer_ai_rust_service-macos-arm64` - for Apple Silicon (M1/M2/M3) Macs
- `writer_ai_rust_service-macos-intel` - for Intel Macs
- `writer_ai_rust_service-linux-amd64` - for Linux systems

## Manual Installation

After downloading:

1. Make the binary executable:
   ```bash
   chmod +x writer_ai_rust_service-*
   ```

2. Move it to a location in your PATH:
   ```bash
   sudo mv writer_ai_rust_service-* /usr/local/bin/writer_ai_rust_service
   ```

3. Create a configuration file:
   ```bash
   mkdir -p ~/.config/writer_ai_service
   touch ~/.config/writer_ai_service/config.toml
   ```

4. Edit the configuration file with your preferred text editor and add your settings.