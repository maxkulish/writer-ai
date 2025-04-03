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
    cat > "${CONFIG_DIR}/config.toml" << 'EOT'
# WriterAI Ollama Configuration
port = 8989
llm_url = "http://localhost:11434/api/chat"
# You can change the model to any model available in your Ollama installation
model_name = "mistral:latest"

# Optional params for model behavior
[llm_params]
temperature = 0.7
max_output_tokens = 2048
top_p = 1

# Prompt template for improving text
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

{{input}}
"""
EOT
  else
    echo -e "${YELLOW}Ollama not found, using OpenAI configuration template${NC}"
    echo -e "${YELLOW}You'll need to edit ${CONFIG_DIR}/config.toml to add your OpenAI API key${NC}"
    cat > "${CONFIG_DIR}/config.toml" << 'EOT'
# WriterAI OpenAI Configuration
port = 8989
llm_url = "https://api.openai.com/v1/responses"
model_name = "gpt-4o"

# Authentication for OpenAI API
# Replace with your actual API key
openai_api_key = "YOUR_OPENAI_API_KEY_HERE"
# openai_org_id = "YOUR_ORGANIZATION_ID" # Optional 

# Optional params for model behavior
[llm_params]
temperature = 0.7
max_output_tokens = 2048
top_p = 1

# Prompt template for improving text
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

{{input}}
"""
EOT
  fi
fi

# Copy the Rust service to a user-accessible location
echo -e "${BLUE}Installing Rust service...${NC}"
RUST_SERVICE="${MOUNT_POINT}/WriterAI.app/Contents/Resources/rust_service/writer_ai_rust_service"
BIN_DIR="${HOME}/.local/bin"
mkdir -p "${BIN_DIR}"
cp "${RUST_SERVICE}" "${BIN_DIR}/"
chmod +x "${BIN_DIR}/writer_ai_rust_service"

echo -e "${GREEN}WriterAI has been successfully installed to ${INSTALL_DIR}/WriterAI.app${NC}"
echo -e "${GREEN}Rust service installed to ${BIN_DIR}/writer_ai_rust_service${NC}"
echo -e "${GREEN}Configuration file created at ${CONFIG_DIR}/config.toml${NC}"
echo -e "${YELLOW}Note: When opening the app for the first time, you may need to go to System Preferences > Security & Privacy and click 'Open Anyway'${NC}"
echo -e "${BLUE}Starting WriterAI...${NC}"
open "${INSTALL_DIR}/WriterAI.app"

echo -e "${BLUE}Starting Rust service...${NC}"
"${BIN_DIR}/writer_ai_rust_service" &

exit 0