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

echo -e "${GREEN}WriterAI has been successfully installed to ${INSTALL_DIR}/WriterAI.app${NC}"
echo -e "${YELLOW}Note: When opening the app for the first time, you may need to go to System Preferences > Security & Privacy and click 'Open Anyway'${NC}"
echo -e "${BLUE}Starting WriterAI...${NC}"
open "${INSTALL_DIR}/WriterAI.app"

exit 0