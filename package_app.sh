#!/bin/bash
# Script to build and package WriterAI for production

set -e  # Exit on any error

# Define paths
APP_DIR="./swift_agent/WriterAIHotkeyAgent"
BUILD_DIR="${APP_DIR}/build"
APP_NAME="WriterAI.app"
RELEASE_DIR="./release"
RUST_SERVICE_DIR="./rust_service"

echo "===== Building WriterAI Application ====="

# Check for Xcode or use alternative approach
if ! xcode-select -p &> /dev/null; then
    echo "Xcode command line tools not found. Installing..."
    xcode-select --install
    echo "Please run this script again after Xcode tools installation is complete."
    exit 1
fi

# Check if we have full Xcode or just command line tools
if [[ $(xcode-select -p) == *"CommandLineTools"* ]]; then
    echo "Warning: You have Command Line Tools but not full Xcode."
    echo "Using manual build approach instead of xcodebuild..."
    USE_MANUAL_BUILD=true
else
    USE_MANUAL_BUILD=false
fi

# Create release directory if it doesn't exist
mkdir -p "${RELEASE_DIR}"

# Build Rust service
echo "Building Rust service..."
cd "${RUST_SERVICE_DIR}"
cargo build --release
cd -

# Copy Rust service binary to a location within the app bundle
RUST_BIN="${RUST_SERVICE_DIR}/target/release/writer_ai_rust_service"
if [ ! -f "${RUST_BIN}" ]; then
    echo "Error: Rust binary not found at ${RUST_BIN}"
    echo "Checking for available binaries..."
    find "${RUST_SERVICE_DIR}/target" -type f -name "writer_ai*" 2>/dev/null || echo "No binaries found with 'writer_ai' prefix"
    exit 1
fi

# Clean any previous build
echo "Cleaning previous build..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

if [ "$USE_MANUAL_BUILD" = true ]; then
    # Manual approach for systems without full Xcode
    echo "Building app bundle manually..."
    
    # Create basic app structure
    APP_PATH="${RELEASE_DIR}/${APP_NAME}"
    mkdir -p "${APP_PATH}/Contents/MacOS"
    mkdir -p "${APP_PATH}/Contents/Resources"
    
    # Copy existing pre-built app if available, otherwise create a placeholder
    PREBUILT_APP="/Applications/WriterAIHotkeyAgent.app"
    if [ -d "$PREBUILT_APP" ]; then
        echo "Found pre-built app at $PREBUILT_APP - copying..."
        cp -R "$PREBUILT_APP/"* "${APP_PATH}/"
    else
        echo "Creating minimal app structure (not usable without Swift build)..."
        cat > "${APP_PATH}/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>WriterAI</string>
    <key>CFBundleIdentifier</key>
    <string>com.writer-ai.WriterAIHotkeyAgent</string>
    <key>CFBundleName</key>
    <string>WriterAI</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF
        echo "NOTE: This is a partial build only. You'll need full Xcode to build the Swift components."
        echo "The Rust service will still be included properly."
    fi
else
    # Regular Xcode build approach
    echo "Building Swift application with Xcode..."
    cd "${APP_DIR}"
    xcodebuild -project WriterAIHotkeyAgent.xcodeproj -scheme WriterAIHotkeyAgent -configuration Release -destination 'platform=macOS' clean build
    cd -

    # Check if build succeeded
    APP_PATH="${BUILD_DIR}/Release/${APP_NAME}"
    if [ ! -d "${APP_PATH}" ]; then
        echo "Looking for app in alternate locations..."
        # Check common Xcode build paths
        for alt_path in \
            "./DerivedData/Build/Products/Release/${APP_NAME}" \
            "${APP_DIR}/DerivedData/Build/Products/Release/${APP_NAME}" \
            "${APP_DIR}/build/Release/${APP_NAME}" \
            "$(xcodebuild -project ${APP_DIR}/WriterAIHotkeyAgent.xcodeproj -showBuildSettings 2>/dev/null | grep -m 1 "BUILT_PRODUCTS_DIR" | awk '{print $3}')/${APP_NAME}" \
            "$(find ~/Library/Developer/Xcode/DerivedData -name "WriterAIHotkeyAgent.app" -type d -path "*/Build/Products/Release/*" | head -n 1)"
        do
            if [ -d "${alt_path}" ]; then
                echo "Found app at: ${alt_path}"
                APP_PATH="${alt_path}"
                break
            fi
        done
        
        if [ ! -d "${APP_PATH}" ]; then
            echo "Error: Build failed, app not found in any known location."
            echo "Please check Xcode build settings or build the project manually."
            exit 1
        fi
    fi
fi

# Copy to release directory if not already there
if [[ "$APP_PATH" != "${RELEASE_DIR}/${APP_NAME}" ]]; then
    echo "Copying app to release directory..."
    mkdir -p "${RELEASE_DIR}"
    cp -R "${APP_PATH}" "${RELEASE_DIR}/"
    APP_PATH="${RELEASE_DIR}/${APP_NAME}"
fi

# Create a directory for the Rust service inside the app bundle
RESOURCES_DIR="${APP_PATH}/Contents/Resources"
mkdir -p "${RESOURCES_DIR}/rust_service"

# Copy Rust binary and any needed config files
cp "${RUST_BIN}" "${RESOURCES_DIR}/rust_service/"
cp "${RUST_SERVICE_DIR}/config.toml" "${RESOURCES_DIR}/rust_service/" 2>/dev/null || echo "No config.toml found, using defaults"

# Copy template files to Resources
echo "Copying template files to Resources..."
mkdir -p "${RESOURCES_DIR}/templates"
cp -R ./templates/* "${RESOURCES_DIR}/templates/"

# Copy the app to the release directory if paths are different
echo "Copying app to release directory..."
if [[ "$APP_PATH" != "${RELEASE_DIR}/${APP_NAME}" ]]; then
    rm -rf "${RELEASE_DIR}/${APP_NAME}"  # Remove any existing app first
    cp -R "${APP_PATH}" "${RELEASE_DIR}/"
else
    echo "App is already in release directory, no need to copy"
fi

# Create a DMG for distribution if the app was fully built
if [ "$USE_MANUAL_BUILD" = true ] && [ ! -d "$PREBUILT_APP" ]; then
    echo "Skipping DMG creation as this is a partial build without Swift components."
    echo ""
    echo "===== Partial Build Complete ====="
    echo "Rust service has been built and is available at: ${RESOURCES_DIR}/rust_service/"
    echo ""
    echo "To complete the build:"
    echo "1. Install Xcode (not just Command Line Tools) from the App Store"
    echo "2. Open the Swift project in Xcode: ${APP_DIR}/WriterAIHotkeyAgent.xcodeproj"
    echo "3. Build the project in Xcode (Product > Build)"
    echo "4. Run this script again to package everything"
else
    echo "Creating DMG..."
    # Check which app exists in the release directory
    REAL_APP_PATH=""
    if [ -d "${RELEASE_DIR}/${APP_NAME}" ]; then
        REAL_APP_PATH="${RELEASE_DIR}/${APP_NAME}"
    elif [ -d "${RELEASE_DIR}/WriterAIHotkeyAgent.app" ]; then
        REAL_APP_PATH="${RELEASE_DIR}/WriterAIHotkeyAgent.app"
        # Rename the app to match expected name
        mv "${RELEASE_DIR}/WriterAIHotkeyAgent.app" "${RELEASE_DIR}/${APP_NAME}"
        REAL_APP_PATH="${RELEASE_DIR}/${APP_NAME}"
    fi
    
    if [ -z "$REAL_APP_PATH" ]; then
        echo "Error: No app found in ${RELEASE_DIR} to create DMG"
        exit 1
    fi
    
    hdiutil create -volname "WriterAI" -srcfolder "${REAL_APP_PATH}" -ov -format UDZO "${RELEASE_DIR}/WriterAI.dmg"

    echo "===== Build Complete ====="
    echo "Application is ready at: ${RELEASE_DIR}/${APP_NAME}"
    echo "DMG installer is available at: ${RELEASE_DIR}/WriterAI.dmg"
    echo ""
    echo "To install, open the DMG and drag WriterAI to your Applications folder."
fi