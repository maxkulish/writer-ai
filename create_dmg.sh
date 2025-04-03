#!/bin/bash
# Script to create DMG for WriterAI

set -e  # Exit on any error

RELEASE_DIR="./release"
APP_NAME="WriterAI.app"

echo "===== Creating WriterAI DMG ====="

if [ ! -d "${RELEASE_DIR}/${APP_NAME}" ]; then
    if [ -d "${RELEASE_DIR}/WriterAIHotkeyAgent.app" ]; then
        echo "Renaming WriterAIHotkeyAgent.app to ${APP_NAME}..."
        mv "${RELEASE_DIR}/WriterAIHotkeyAgent.app" "${RELEASE_DIR}/${APP_NAME}"
    else
        echo "Error: Neither ${APP_NAME} nor WriterAIHotkeyAgent.app found in ${RELEASE_DIR}"
        exit 1
    fi
fi

echo "Creating DMG..."
hdiutil create -volname "WriterAI" -srcfolder "${RELEASE_DIR}/${APP_NAME}" -ov -format UDZO "${RELEASE_DIR}/WriterAI.dmg"

echo "===== DMG Creation Complete ====="
echo "DMG is available at: ${RELEASE_DIR}/WriterAI.dmg"