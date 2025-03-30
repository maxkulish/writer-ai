.PHONY: build install uninstall clean restart

BINARY_NAME := writer_ai_rust_service
INSTALL_PATH := /usr/local/bin
SERVICE_NAME := com.user.writer_ai_rust_service
LAUNCH_AGENT_DIR := $(HOME)/Library/LaunchAgents
LAUNCH_AGENT_FILE := $(LAUNCH_AGENT_DIR)/$(SERVICE_NAME).plist

build:
	@echo "Building $(BINARY_NAME)..."
	cd $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST)))) && cargo build --release

install: build
	@echo "Installing $(BINARY_NAME) to $(INSTALL_PATH)..."
	sudo install -m 755 target/release/$(BINARY_NAME) $(INSTALL_PATH)/
	@echo "Creating LaunchAgent plist..."
	mkdir -p $(LAUNCH_AGENT_DIR)
	echo '<?xml version="1.0" encoding="UTF-8"?>' > $(LAUNCH_AGENT_FILE)
	echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> $(LAUNCH_AGENT_FILE)
	echo '<plist version="1.0">' >> $(LAUNCH_AGENT_FILE)
	echo '<dict>' >> $(LAUNCH_AGENT_FILE)
	echo '	<key>Label</key>' >> $(LAUNCH_AGENT_FILE)
	echo '	<string>$(SERVICE_NAME)</string>' >> $(LAUNCH_AGENT_FILE)
	echo '	<key>ProgramArguments</key>' >> $(LAUNCH_AGENT_FILE)
	echo '	<array>' >> $(LAUNCH_AGENT_FILE)
	echo '		<string>$(INSTALL_PATH)/$(BINARY_NAME)</string>' >> $(LAUNCH_AGENT_FILE)
	echo '	</array>' >> $(LAUNCH_AGENT_FILE)
	echo '	<key>RunAtLoad</key>' >> $(LAUNCH_AGENT_FILE)
	echo '	<true/>' >> $(LAUNCH_AGENT_FILE)
	echo '	<key>KeepAlive</key>' >> $(LAUNCH_AGENT_FILE)
	echo '	<true/>' >> $(LAUNCH_AGENT_FILE)
	echo '	<key>StandardErrorPath</key>' >> $(LAUNCH_AGENT_FILE)
	echo '	<string>$(HOME)/Library/Logs/$(BINARY_NAME).log</string>' >> $(LAUNCH_AGENT_FILE)
	echo '	<key>StandardOutPath</key>' >> $(LAUNCH_AGENT_FILE)
	echo '	<string>$(HOME)/Library/Logs/$(BINARY_NAME).log</string>' >> $(LAUNCH_AGENT_FILE)
	echo '</dict>' >> $(LAUNCH_AGENT_FILE)
	echo '</plist>' >> $(LAUNCH_AGENT_FILE)
	@echo "Starting service"
	launchctl load $(LAUNCH_AGENT_FILE)

uninstall:
	@echo "Uninstalling $(BINARY_NAME)..."
	launchctl unload $(LAUNCH_AGENT_FILE) 2>/dev/null || true
	sudo rm -f $(INSTALL_PATH)/$(BINARY_NAME)
	rm -f $(LAUNCH_AGENT_FILE)

clean:
	@echo "Cleaning build artifacts..."
	cd $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST)))) && cargo clean

restart: build
	@echo "Restarting $(BINARY_NAME)..."
	launchctl unload $(LAUNCH_AGENT_FILE) 2>/dev/null || true
	@echo "Installing new binary to $(INSTALL_PATH)..."
	sudo install -m 755 target/release/$(BINARY_NAME) $(INSTALL_PATH)/
	@echo "Reloading service..."
	launchctl load $(LAUNCH_AGENT_FILE)
	@echo "Service restarted"
