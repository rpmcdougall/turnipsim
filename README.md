# Turnip28 Simulator

Multiplayer tabletop simulator for [Turnip 28](https://www.patreon.com/Turnip28) — the grimdark root-vegetable wargame.

## Stack

- **Engine**: Godot 4.6.2 (GDScript)
- **Architecture**: Authoritative server + thin clients over ENet
- **Renderer**: gl_compatibility (no Vulkan requirement)

## Project Structure

```
godot/              # Single Godot project — server/client mode at runtime
├── entry.tscn      # Branches to server or client based on --server flag
├── autoloads/      # NetworkManager singleton
├── game/           # Pure logic (no node dependencies), data-driven rulesets
├── server/         # Server-only scenes and scripts
├── client/         # Client-only scenes and scripts
└── tests/
deploy/             # Systemd unit + deployment scripts
rules_export/       # Turnip 28 rulebook PDFs and changelists
```

## Running

Open `godot/project.godot` in Godot 4.6.2, then:

- **Client mode**: F5 (default)
- **Server mode**: Set CLI args to `--server` in Project Settings → Run, then F5

## Status

Early development — see `turnip28-sim-plan-godot.md` for the full roadmap.
