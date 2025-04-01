# WriterAI Installation Guide

This guide provides detailed instructions for installing and setting up WriterAI on your macOS system.

## System Requirements

- macOS 13.0 (Ventura) or later
- Approximately 150MB of disk space
- Internet connection (for non-local LLM models)

## Installation from DMG

1. Download the latest release `.dmg` file from the [Releases page](https://github.com/your-username/writer-ai/releases)
2. Locate the downloaded `.dmg` file in your Downloads folder
3. Double-click the `.dmg` file to mount it
4. A window will open showing the WriterAI application
5. Drag the WriterAI application to the Applications folder shortcut provided in the window
6. Eject the mounted disk image by dragging it to the Trash (which becomes an Eject button)

## Icon Generation Guide

### Required Icon Sizes for macOS Application

The WriterAI application requires the following icon sizes for macOS:

- 16x16 (1x and 2x)
- 32x32 (1x and 2x)
- 128x128 (1x and 2x)
- 256x256 (1x and 2x)
- 512x512 (1x and 2x)
- 1024x1024

### Icon Generation Prompt

Use the following prompt with your preferred AI image generation tool (such as DALL-E, Midjourney, or Stable Diffusion):

```
Create a minimalist app icon for an AI writing assistant called "WriterAI". The icon should be simple, elegant, and professional. 
It should incorporate elements that suggest both writing (like a pen, pencil, or document) and artificial intelligence (subtle neural network patterns or a clean, modern design).
Use a color palette that evokes creativity and technology - blues, purples, or teals work well.
Make sure the design is recognizable even at small sizes (16x16 pixels).
The icon should have a clean background suitable for both light and dark mode interfaces.
Style: Flat design, modern, minimalist
Format: Square icon with transparent background
```

### Updating Application Icons

1. Generate a high-resolution (1024x1024 px) icon using the prompt above
2. Use a tool like [Icon Generator](https://appicon.co/) or [MakeAppIcon](https://makeappicon.com/) to create all required sizes
3. Replace the existing icon files in:
   ```
   swift_agent/WriterAIHotkeyAgent/WriterAIHotkeyAgent/Assets.xcassets/AppIcon.appiconset/
   ```
4. Ensure all files are named according to the pattern in Contents.json:
   - 16.png (16x16)
   - 32.png (32x32 and 16x16@2x)
   - 64.png (32x32@2x)
   - 128.png (128x128)
   - 256.png (256x256 and 128x128@2x)
   - 512.png (512x512 and 256x256@2x)
   - 1024.png (512x512@2x)

5. Rebuild the application to apply the new icons

## First Launch and Permissions

1. Open your Applications folder and double-click WriterAI to launch it
2. When prompted about permissions, follow these steps:

### Accessibility Permissions

WriterAI needs accessibility permissions to detect hotkeys and simulate keyboard input:

1. When prompted, click "Open Accessibility Settings"
2. In the System Settings window that opens, find WriterAI in the list
3. Make sure the checkbox next to WriterAI is checked
4. Close System Settings

### Notification Permissions

WriterAI uses notifications to inform you about its status:

1. When prompted, click "Allow" to permit notifications
2. You can manage notification settings later in System Settings > Notifications

## Verifying Installation

After installation, WriterAI runs in the background. You can verify it's running by:

1. Looking for the WriterAI icon in your menu bar (top-right of your screen)
2. Clicking the icon to open the menu, which displays:
   - Status information
   - Hotkey configuration
   - Options to test functionality

## Uninstallation

To uninstall WriterAI:

1. Quit the application (click the menu bar icon and select "Quit")
2. Move the WriterAI app from your Applications folder to the Trash
3. Empty the Trash

## Troubleshooting

### WriterAI Doesn't Respond to Hotkey

1. Check that the app is running (the icon should be visible in the menu bar)
2. Verify accessibility permissions are granted in System Settings > Privacy & Security > Accessibility
3. Try restarting the app (quit and restart)
4. Make sure you're not using the hotkey in an application that already uses the same key combination

### Error Connecting to Rust Service

1. Make sure the Rust service is properly installed (it should be included in the application bundle)
2. Check your network connection if using remote LLMs
3. Review any error messages in the notification for specific details

For additional help, please [open an issue](https://github.com/your-username/writer-ai/issues) on our GitHub repository.