# Project Setup

This guide walks you through setting up the Turnip28 Simulator development environment.

## Prerequisites

### Required
- **Godot 4.6.2 stable** - Download from [godotengine.org](https://godotengine.org/download)
- **Git** - For version control
- **GitHub CLI (`gh`)** - For project board management (optional but recommended)

### Recommended
- **Visual Studio Code** with GDScript extension
- **Terminal** - For running headless tests

## Platform-Specific Setup

### macOS
```bash
# Godot executable location
/Applications/Godot.app/Contents/MacOS/Godot

# Add to PATH (optional)
echo 'export PATH="/Applications/Godot.app/Contents/MacOS:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### Linux
```bash
# Download Godot 4.6.2
wget https://github.com/godotengine/godot/releases/download/4.6.2-stable/Godot_v4.6.2-stable_linux.x86_64.zip
unzip Godot_v4.6.2-stable_linux.x86_64.zip
sudo mv Godot_v4.6.2-stable_linux.x86_64 /usr/local/bin/godot
chmod +x /usr/local/bin/godot
```

### Windows
```powershell
# Download from godotengine.org and install
# Add to PATH: C:\Program Files\Godot\

# Or use winget
winget install GodotEngine.GodotEngine
```

## Clone the Repository

```bash
git clone https://github.com/rpmcdougall/turnipsim.git
cd turnipsim
```

## Verify Installation

### 1. Run Tests
```bash
cd godot/

# Phase 1 tests (19 tests)
/Applications/Godot.app/Contents/MacOS/Godot --headless -s tests/test_runner.gd

# Phase 4 engine tests (38 tests)
/Applications/Godot.app/Contents/MacOS/Godot --headless -s tests/test_game_engine.gd

# UI instantiation tests
/Applications/Godot.app/Contents/MacOS/Godot --headless -s tests/test_ui_instantiate.gd
```

### 2. Run Server
```bash
cd godot/
/Applications/Godot.app/Contents/MacOS/Godot project.godot --server
```

You should see:
```
[ServerMain] Starting dedicated server on port 9999
[ServerMain] ENet server listening on *:9999
```

### 3. Run Client
```bash
cd godot/
/Applications/Godot.app/Contents/MacOS/Godot project.godot
```

The client should open the main menu.

## Project Structure

```
turnipsim/
├── godot/              # Main Godot project
│   ├── game/           # Pure game logic (RefCounted only)
│   ├── server/         # Server-only code
│   ├── client/         # Client-only code
│   ├── autoloads/      # Singleton managers
│   └── tests/          # Automated tests
├── docs/               # Documentation
│   └── wiki/           # Developer wiki
├── memory/             # Session checkpoints
└── rules_export/       # Turnip28 rulebook PDFs
```

## Editor Configuration

### Godot Editor Settings
1. Open `godot/project.godot` in Godot editor
2. **Editor > Editor Settings**:
   - Text Editor > Behavior > Files > Trim Trailing Whitespace: **On**
   - Text Editor > Indent > Type: **Tabs**
   - Text Editor > Indent > Size: **4**

### VSCode (Optional)
If using VSCode with GDScript extension:

```json
// .vscode/settings.json
{
  "editor.insertSpaces": false,
  "editor.tabSize": 4,
  "files.trimTrailingWhitespace": true,
  "[gdscript]": {
    "editor.detectIndentation": false
  }
}
```

## Environment Variables

For server deployments, you can set:

```bash
# Optional: Custom port
export GODOT_SERVER_PORT=9999

# Optional: Max clients
export GODOT_MAX_CLIENTS=32
```

## Troubleshooting

### "Command not found: godot"
- Ensure Godot is in your PATH
- Use full path: `/Applications/Godot.app/Contents/MacOS/Godot`

### Tests fail with "Scene not found"
- Ensure you're running from `godot/` directory
- Use `-s` flag, not `--script`

### Server won't start
- Check port 9999 is not in use: `lsof -i :9999`
- Verify firewall settings allow UDP on port 9999

### Client can't connect to localhost
- Ensure server is running first
- Check server logs for "peer connected" messages
- Try explicit IP: `127.0.0.1:9999`

## Next Steps

- Read [Architecture Overview](Architecture-Overview.md) to understand the codebase
- Review [Development Process](Development-Process.md) before making changes
- Check [Testing Guidelines](Testing-Guidelines.md) for writing tests
