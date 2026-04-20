# Project Setup

Environment setup for Turnip28 Simulator development.

## Prerequisites

- **Godot 4.6.2 stable** — [godotengine.org/download](https://godotengine.org/download)
- **Git** — version control
- **Bash shell** — required by `scripts/test-stack.sh` (Git Bash on Windows, built-in elsewhere)
- **GitHub CLI (`gh`)** — optional, needed to drive the project board from the command line

## Install Godot

### macOS

Drag `Godot.app` into `/Applications/`. The binary lives at:

```
/Applications/Godot.app/Contents/MacOS/Godot
```

### Windows

Extract the Godot zip to `C:\tools\Godot\`. The launcher script expects the binary at:

```
C:\tools\Godot\Godot_v4.6.2-stable_win64.exe
```

If you install elsewhere, update the `GODOT` path in `scripts/test-stack.sh`.

### Linux

```bash
wget https://github.com/godotengine/godot/releases/download/4.6.2-stable/Godot_v4.6.2-stable_linux.x86_64.zip
unzip Godot_v4.6.2-stable_linux.x86_64.zip
sudo mv Godot_v4.6.2-stable_linux.x86_64 /usr/local/bin/godot
chmod +x /usr/local/bin/godot
```

`scripts/test-stack.sh` doesn't yet branch for Linux — patch the case statement if you're running Linux.

## Clone the Repository

```bash
git clone https://github.com/rpmcdougall/turnipsim.git
cd turnipsim
```

## Verify the Install

### Run the automated suites

These call Godot in headless mode. Substitute `$GODOT` with the path from the section above (or set `GODOT=...` in your shell).

```bash
cd godot/

# Phase 1 (19 tests): types, ruleset loader, roster validation
$GODOT --headless -s tests/test_runner.gd

# Phase 4 engine (48 tests): order state machine, combat, victory
$GODOT --headless -s tests/test_game_engine.gd
```

Both should report `Failed: 0`.

### Run a local stack

The canonical way to bring up a server + two clients is the launcher:

```bash
scripts/test-stack.sh
```

It detects the platform, starts a headless server plus two windowed clients, writes per-process logs to `test-logs/`, and tears everything down on Ctrl+C. See [Manual Testing Guide](Manual-Testing-Guide.md) for what to drive through the UI.

For solo runs (server + one client): `scripts/test-stack.sh --solo`.

## Project Structure

```
turnipsim/
├── godot/              # Main Godot project
│   ├── game/           # Pure game logic (RefCounted only, no Node deps)
│   ├── server/         # Server-only code
│   ├── client/         # Client-only code
│   ├── autoloads/      # NetworkManager, NetworkClient (registered in project.godot)
│   └── tests/          # Automated tests
├── docs/wiki/          # Developer wiki (this file lives here)
├── memory/             # Session checkpoints
├── rules_export/       # Turnip28 rulebook PDFs
└── scripts/            # Local tooling (test-stack.sh)
```

## Editor Configuration

Open `godot/project.godot` in the Godot editor, then **Editor → Editor Settings**:

- Text Editor → Behavior → Files → Trim Trailing Whitespace: **On**
- Text Editor → Indent → Type: **Tabs**
- Text Editor → Indent → Size: **4**

### VSCode (optional)

With the GDScript extension installed:

```json
// .vscode/settings.json
{
  "editor.insertSpaces": false,
  "editor.tabSize": 4,
  "files.trimTrailingWhitespace": true,
  "[gdscript]": { "editor.detectIndentation": false }
}
```

## Troubleshooting

### `Command not found: godot` / `$GODOT: unbound variable`

The snippets assume you've set `GODOT=...` in your shell, or you substitute the full path manually. For convenience, add it to your profile:

```bash
# macOS (~/.zshrc)
export GODOT="/Applications/Godot.app/Contents/MacOS/Godot"

# Windows Git Bash (~/.bashrc)
export GODOT="/c/tools/Godot/Godot_v4.6.2-stable_win64.exe"
```

### Tests fail with "Scene not found" or "Identifier not declared"

Most often you're running from the wrong directory — tests need to run from `godot/` so paths resolve. If you see `Identifier 'NetworkClient' not declared`, the project hasn't been imported yet. Run it once with `$GODOT --headless --editor --quit` to build the script class cache, then retry.

### Server won't start — port 9999 in use

```bash
# macOS / Linux
lsof -i :9999

# Windows
netstat -ano | grep 9999
```

Kill the stale process before relaunching.

## Next Steps

- [Architecture Overview](Architecture-Overview.md) — system design and layering
- [Development Process](Development-Process.md) — branch / commit / review workflow
- [Testing Guidelines](Testing-Guidelines.md) — writing and running tests
- [Manual Testing Guide](Manual-Testing-Guide.md) — local multiplayer smoke-test procedure
