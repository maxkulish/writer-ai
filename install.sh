#!/bin/bash
# Install script for WriterAI

set -e  # Exit on any error

# Color codes for pretty output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

REPO_OWNER="maxkulish"
REPO_NAME="writer-ai"
DMG_FILENAME="WriterAI.dmg"
INSTALL_DIR="/Applications"
TMP_DIR=$(mktemp -d)
SERVICE_NAME="com.user.writer_ai_rust_service"
LAUNCH_AGENT_DIR="${HOME}/Library/LaunchAgents"
LAUNCH_AGENT_FILE="${LAUNCH_AGENT_DIR}/${SERVICE_NAME}.plist"
LOG_FILE="${HOME}/Library/Logs/writer_ai_rust_service.log"

echo -e "${BLUE}=== WriterAI Installer ===${NC}"
echo "This script will download and install WriterAI to your Applications folder."

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
  echo -e "${RED}Error: This installer only works on macOS.${NC}"
  exit 1
fi

# Get latest release information
echo -e "${BLUE}Fetching latest release...${NC}"
LATEST_RELEASE=$(curl -s "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest")
if [ $? -ne 0 ]; then
  echo -e "${RED}Error: Failed to fetch release information.${NC}"
  exit 1
fi

# Extract version and download URL
VERSION=$(echo "$LATEST_RELEASE" | grep -o '"tag_name": *"[^"]*"' | sed 's/"tag_name": *"//;s/"//')
DOWNLOAD_URL=$(echo "$LATEST_RELEASE" | grep -o '"browser_download_url": *"[^"]*\.dmg"' | sed 's/"browser_download_url": *"//;s/"//')

if [ -z "$DOWNLOAD_URL" ]; then
  echo -e "${RED}Error: Could not find DMG download URL in the latest release.${NC}"
  exit 1
fi

echo -e "${GREEN}Found WriterAI version ${VERSION}${NC}"

# Download the DMG
echo -e "${BLUE}Downloading ${DMG_FILENAME}...${NC}"
curl -L -o "${TMP_DIR}/${DMG_FILENAME}" "$DOWNLOAD_URL"
if [ $? -ne 0 ]; then
  echo -e "${RED}Error: Failed to download ${DMG_FILENAME}.${NC}"
  exit 1
fi

# Mount the DMG
echo -e "${BLUE}Mounting disk image...${NC}"
MOUNT_POINT=$(hdiutil attach "${TMP_DIR}/${DMG_FILENAME}" -nobrowse -readonly | tail -n 1 | awk '{print $NF}')
if [ $? -ne 0 ] || [ -z "$MOUNT_POINT" ]; then
  echo -e "${RED}Error: Failed to mount disk image.${NC}"
  exit 1
fi

# Copy app to Applications folder
echo -e "${BLUE}Installing WriterAI to Applications folder...${NC}"
if [ -d "${MOUNT_POINT}/WriterAI.app" ]; then
  # If app already exists in Applications, remove it first
  if [ -d "${INSTALL_DIR}/WriterAI.app" ]; then
    echo -e "${YELLOW}Removing previous installation...${NC}"
    rm -rf "${INSTALL_DIR}/WriterAI.app"
  fi

  cp -R "${MOUNT_POINT}/WriterAI.app" "${INSTALL_DIR}/"
  if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to copy the application to ${INSTALL_DIR}. Make sure you have the necessary permissions.${NC}"
    hdiutil detach "$MOUNT_POINT" -quiet
    exit 1
  fi
else
  echo -e "${RED}Error: WriterAI.app not found in the disk image.${NC}"
  hdiutil detach "$MOUNT_POINT" -quiet
  exit 1
fi

# Unmount the DMG
echo -e "${BLUE}Cleaning up...${NC}"
hdiutil detach "$MOUNT_POINT" -quiet
rm -rf "${TMP_DIR}"

# Set up configuration directory and files
CONFIG_DIR="${HOME}/.config/writer_ai_service"
echo -e "${BLUE}Setting up configuration directory at ${CONFIG_DIR}...${NC}"
mkdir -p "${CONFIG_DIR}"

# Create default configuration file if it doesn't exist
if [ ! -f "${CONFIG_DIR}/config.toml" ]; then
  echo -e "${BLUE}Creating default configuration file...${NC}"
  # Check if Ollama is installed
  if command -v ollama &> /dev/null; then
    echo -e "${GREEN}Ollama found, using local LLM configuration${NC}"
    cp "${INSTALL_DIR}/WriterAI.app/Contents/Resources/templates/ollama.toml" "${CONFIG_DIR}/config.toml"
    if [ $? -ne 0 ]; then
      # Try to get template from GitHub repo
      echo -e "${YELLOW}Failed to copy template, fetching from repository...${NC}"
      curl -s -L "https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main/templates/ollama.toml" > "${CONFIG_DIR}/config.toml"
    fi
  else
    echo -e "${YELLOW}Ollama not found, using OpenAI configuration template${NC}"
    echo -e "${YELLOW}You'll need to edit ${CONFIG_DIR}/config.toml to add your OpenAI API key${NC}"
    cp "${INSTALL_DIR}/WriterAI.app/Contents/Resources/templates/gpt-4o.toml" "${CONFIG_DIR}/config.toml"
    if [ $? -ne 0 ]; then
      # Try to get template from GitHub repo
      echo -e "${YELLOW}Failed to copy template, fetching from repository...${NC}"
      curl -s -L "https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main/templates/gpt-4o.toml" > "${CONFIG_DIR}/config.toml"
    fi
  fi
fi

# Install the Rust service
echo -e "${BLUE}Installing Rust service...${NC}"
BIN_DIR="${HOME}/.local/bin"
mkdir -p "${BIN_DIR}"

# Determine which binary to download based on architecture
ARCH=$(uname -m)
OS=$(uname -s)

if [ "$OS" = "Darwin" ]; then
  # macOS binaries
  if [ "$ARCH" = "arm64" ]; then
    RUST_BIN_NAME="writer_ai_rust_service-macos-arm64"
  elif [ "$ARCH" = "x86_64" ]; then
    RUST_BIN_NAME="writer_ai_rust_service-macos-x86_64"
  else
    # Fallback to intel binary for other architectures
    RUST_BIN_NAME="writer_ai_rust_service-macos-intel"
  fi
elif [ "$OS" = "Linux" ]; then
  RUST_BIN_NAME="writer_ai_rust_service-linux-amd64"
else
  echo -e "${RED}Unsupported operating system: $OS${NC}"
  exit 1
fi

# Extract the download URL for the appropriate Rust binary from the release
RUST_BIN_URL=$(echo "$LATEST_RELEASE" | grep -o "\"browser_download_url\": *\"[^\"]*${RUST_BIN_NAME}[^\"]*\"" | sed 's/"browser_download_url": *"//;s/"//')

if [ -n "$RUST_BIN_URL" ]; then
  echo -e "${BLUE}Downloading ${RUST_BIN_NAME} from ${RUST_BIN_URL}...${NC}"
  curl -L -o "${BIN_DIR}/writer_ai_rust_service" "$RUST_BIN_URL"
  chmod +x "${BIN_DIR}/writer_ai_rust_service"

  if [ -f "${BIN_DIR}/writer_ai_rust_service" ]; then
    echo -e "${GREEN}Successfully downloaded Rust service${NC}"
    
    # Set up the LaunchAgent
    echo -e "${BLUE}Setting up LaunchAgent for Rust service...${NC}"
    
    # Unload existing agent if it exists
    if [ -f "${LAUNCH_AGENT_FILE}" ]; then
      launchctl unload "${LAUNCH_AGENT_FILE}" 2>/dev/null || true
    fi
    
    # Create LaunchAgent directory if it doesn't exist
    mkdir -p "${LAUNCH_AGENT_DIR}"
    
    # Create LaunchAgent plist file
    echo '<?xml version="1.0" encoding="UTF-8"?>' > "${LAUNCH_AGENT_FILE}"
    echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> "${LAUNCH_AGENT_FILE}"
    echo '<plist version="1.0">' >> "${LAUNCH_AGENT_FILE}"
    echo '<dict>' >> "${LAUNCH_AGENT_FILE}"
    echo '    <key>Label</key>' >> "${LAUNCH_AGENT_FILE}"
    echo "    <string>${SERVICE_NAME}</string>" >> "${LAUNCH_AGENT_FILE}"
    echo '    <key>ProgramArguments</key>' >> "${LAUNCH_AGENT_FILE}"
    echo '    <array>' >> "${LAUNCH_AGENT_FILE}"
    echo "        <string>${BIN_DIR}/writer_ai_rust_service</string>" >> "${LAUNCH_AGENT_FILE}"
    echo '    </array>' >> "${LAUNCH_AGENT_FILE}"
    echo '    <key>RunAtLoad</key>' >> "${LAUNCH_AGENT_FILE}"
    echo '    <true/>' >> "${LAUNCH_AGENT_FILE}"
    echo '    <key>KeepAlive</key>' >> "${LAUNCH_AGENT_FILE}"
    echo '    <true/>' >> "${LAUNCH_AGENT_FILE}"
    echo '    <key>StandardErrorPath</key>' >> "${LAUNCH_AGENT_FILE}"
    echo "    <string>${LOG_FILE}</string>" >> "${LAUNCH_AGENT_FILE}"
    echo '    <key>StandardOutPath</key>' >> "${LAUNCH_AGENT_FILE}"
    echo "    <string>${LOG_FILE}</string>" >> "${LAUNCH_AGENT_FILE}"
    echo '</dict>' >> "${LAUNCH_AGENT_FILE}"
    echo '</plist>' >> "${LAUNCH_AGENT_FILE}"
    
    # Load the LaunchAgent
    echo -e "${BLUE}Starting Rust service via LaunchAgent...${NC}"
    launchctl load "${LAUNCH_AGENT_FILE}"
    
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}Rust service installed and started successfully${NC}"
    else
      echo -e "${RED}Failed to start Rust service via LaunchAgent${NC}"
    fi
  else
    echo -e "${RED}Failed to download Rust service${NC}"
  fi
else
  echo -e "${RED}Could not find appropriate Rust binary URL in release assets${NC}"
  echo -e "${YELLOW}Please install manually or report this issue.${NC}"
fi

echo -e "${GREEN}WriterAI has been successfully installed to ${INSTALL_DIR}/WriterAI.app${NC}"
echo -e "${GREEN}Rust service installed to ${BIN_DIR}/writer_ai_rust_service${NC}"
echo -e "${GREEN}Configuration file created at ${CONFIG_DIR}/config.toml${NC}"
echo -e "${GREEN}Rust service logs will be saved to ${LOG_FILE}${NC}"
echo -e "${YELLOW}Note: When opening the app for the first time, you may need to go to System Preferences > Security & Privacy and click 'Open Anyway'${NC}"
echo -e "${BLUE}Starting WriterAI...${NC}"
open "${INSTALL_DIR}/WriterAI.app"

exit 0