# WriterAI Hotkey Configuration Guide

## Changing Hotkey Combination

You can change the default hotkey combination used by the WriterAI macOS agent without editing code. This is done by modifying the `Info.plist` file in the application bundle.

### Finding the Info.plist File

1. Locate the WriterAI app in your Applications folder or wherever you installed it
2. Right-click on the app and select "Show Package Contents"
3. Navigate to Contents/Info.plist
4. Open this file in a text editor or Xcode

### Modifying the Hotkey Configuration

Look for the `HotkeyConfiguration` section in the Info.plist file:

```xml
<key>HotkeyConfiguration</key>
<dict>
    <key>ModifierFlags</key>
    <string>option,shift</string>
    <key>KeyCode</key>
    <integer>13</integer>
    <key>KeyName</key>
    <string>W</string>
    <key>HotkeyDisplayName</key>
    <string>⇧⌥W (Shift+Option+W)</string>
</dict>
```

#### Elements to Modify:

1. **ModifierFlags**: A comma-separated list of modifier keys. Valid values are:
   - `command` or `cmd`
   - `shift`
   - `control` or `ctrl`
   - `option` or `alt`
   - `function` or `fn`

2. **KeyCode**: The numeric keycode for the key to press. Common keycodes:
   - A-Z: 0-25 (A=0, B=1, ..., Z=25)
   - 0-9: 29-38 (0=29, 1=30, ..., 9=38)
   - Arrow keys: Left=123, Right=124, Down=125, Up=126
   - Function keys: F1=122, F2=120, etc.
   - Return=36, Space=49, Tab=48, Escape=53
   - N=45 (as used in the default configuration)

3. **KeyName**: The display name of the key (used in logs and debugging)

4. **HotkeyDisplayName**: How the hotkey appears in the menu. Use these symbols for modifiers:
   - Command: ⌘
   - Shift: ⇧
   - Control: ⌃
   - Option: ⌥
   - Function: fn

### Common Hotkey Examples

#### Command+Shift+W
```xml
<key>ModifierFlags</key>
<string>command,shift</string>
<key>KeyCode</key>
<integer>13</integer>
<key>KeyName</key>
<string>W</string>
<key>HotkeyDisplayName</key>
<string>⇧⌘W (Shift+Command+W)</string>
```

#### Option+Space
```xml
<key>ModifierFlags</key>
<string>option</string>
<key>KeyCode</key>
<integer>49</integer>
<key>KeyName</key>
<string>Space</string>
<key>HotkeyDisplayName</key>
<string>⌥Space (Option+Space)</string>
```

### Note About Conflicts

Be careful to choose a key combination that doesn't conflict with system or application shortcuts. After changing the configuration, you'll need to restart the WriterAI agent for the changes to take effect.