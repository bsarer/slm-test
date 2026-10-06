# SLM Test

A small local chat app for [Ollama](https://ollama.com) on [Omarchy](https://omarchy.org) Linux.
It talks only to Ollama at `http://127.0.0.1:11434/api/chat`. Nothing leaves your machine.

- **Orb in the bar:** a glowing orb in the Omarchy top bar, on every monitor. It breathes when ready,
  pulses while the model is answering, and dims if Ollama isn't running.
- **Full-page chat:** click the orb or press **Super + Ctrl + M** to open a full-page chat overlay
  that follows your Omarchy theme. **Esc** closes it.
- **Opens Omarchy panels:** ask in plain words ("open my Wi-Fi settings", "I want to change the volume")
  and the model opens Wi-Fi, Bluetooth, Audio, Display, Calendar, Power, Clipboard history,
  Emoji picker or the Omarchy menu. The 🔧 Tools button lists them all.
- **Browser version:** right-click the orb, or run `slm-test`, to use the chat in your browser.
- **Speed stats:** tokens, tokens/sec and total time under every answer. Handy for comparing small models.
- Only Python's standard library is used, with no extra packages.

## Install

Requires Omarchy, Ollama, and at least one model (default `llama3.2`; tools need a model with tool support).

```bash
ollama pull llama3.2
git clone https://github.com/bsarer/slm-test.git
cd slm-test
./install.sh
```

The installer sets up:

| What | Where |
|------|-------|
| Chat server + app menu entry | `~/.local/share/slm-test`, `~/.local/bin/slm-test` |
| Background service (starts at login) | `~/.config/systemd/user/slm-test.service` |
| Shell plugin: orb + chat overlay | `~/.config/omarchy/plugins/bsarer.slm-test/` |
| Shortcut **Super + Ctrl + M** | marked block at the end of `~/.config/hypr/bindings.lua` (backed up first) |

Remove everything with `./uninstall.sh`.

## How it works

```
orb / Super+Ctrl+M ──► Omarchy shell overlay (Chat.qml) ─┐
browser (index.html) ────────────────────────────────────┤
                                                         ▼
                                   slm-test server (127.0.0.1:8765) ──► Ollama /api/chat
                                                         │
                                   tool calls ──► omarchy-shell shell summon <panel>
```

- The server forwards chats to Ollama and streams replies back.
- **Safe tool use:** the model can only pick from a fixed list of tools. Each tool runs one
  hard-coded `omarchy-shell` command, and nothing the model writes is ever executed.
- **Fewer false triggers:** tools are only offered when your message mentions a related word,
  because small models tend to call *some* tool whenever tools are available.
- **Fixing small-model mistakes:** replies that are tool calls written as plain JSON text are
  caught and handled.
- **Only reachable from your machine:** the server listens on `127.0.0.1` and rejects
  requests coming from other websites.

To add a panel, add an entry to `TOOLS` in [`slm-test`](slm-test). The Tools menu picks it up automatically.

## Files

| File | Purpose |
|------|---------|
| `slm-test` | Local server (Python, standard library only) |
| `index.html` | Browser chat page |
| `orb/` | Omarchy shell plugin: `Orb.qml` (bar widget), `Chat.qml` (overlay), `manifest.json` |
| `slm-test.service` | systemd user service |
| `install.sh` / `uninstall.sh` | Install / remove everything |
