#!/bin/bash
# Installs SLM Test for the current user:
#   - the chat server (+ app menu entry, + background service)
#   - the Omarchy shell plugin: an orb in the bar and a full-page chat overlay
#   - a Super+Ctrl+M shortcut to open the chat
set -e
cd "$(dirname "$0")"

PLUGIN_ID=bsarer.slm-test
APP_DIR=~/.local/share/slm-test
PLUGIN_DIR=~/.config/omarchy/plugins/$PLUGIN_ID
BINDINGS=~/.config/hypr/bindings.lua
MARK_BEGIN="-- >>> slm-test >>>"
MARK_END="-- <<< slm-test <<<"

# 1. Chat server + app menu entry
mkdir -p "$APP_DIR" ~/.local/bin ~/.local/share/applications ~/.local/state/slm-test
install -m 755 slm-test "$APP_DIR/slm-test"
install -m 644 index.html "$APP_DIR/index.html"
ln -sf "$APP_DIR/slm-test" ~/.local/bin/slm-test

cat > ~/.local/share/applications/slm-test.desktop <<EOF
[Desktop Entry]
Name=SLM Test
Comment=Local chat with Ollama
Exec=$HOME/.local/bin/slm-test
Icon=internet-chat
Terminal=false
Type=Application
Categories=Utility;
EOF

# 2. Background service, so the orb answers instantly
mkdir -p ~/.config/systemd/user
install -m 644 slm-test.service ~/.config/systemd/user/slm-test.service
systemctl --user daemon-reload
systemctl --user enable slm-test.service >/dev/null 2>&1
systemctl --user restart slm-test.service

# 3. Omarchy shell plugin (orb + overlay)
mkdir -p "$PLUGIN_DIR"
install -m 644 orb/manifest.json orb/Orb.qml orb/Chat.qml "$PLUGIN_DIR/"
omarchy-shell -q shell rescanPlugins
if ! omarchy plugin list --json | python3 -c "
import sys, json
sys.exit(0 if any(p['id'] == '$PLUGIN_ID' and p['enabled'] for p in json.load(sys.stdin)) else 1)"; then
  omarchy plugin enable "$PLUGIN_ID" --section center
fi

# 4. Keyboard shortcut (Super+Ctrl+M)
if ! grep -qF -- "$MARK_BEGIN" "$BINDINGS"; then
  cp "$BINDINGS" "$BINDINGS.bak.$(date +%s)"
  cat >> "$BINDINGS" <<EOF

$MARK_BEGIN
o.bind("SUPER + CTRL + M", "SLM Test chat", "systemctl --user start slm-test.service; omarchy-shell shell toggle $PLUGIN_ID '{}'")
$MARK_END
EOF
fi
hyprctl reload >/dev/null
errors=$(hyprctl configerrors)
if [[ -n "$errors" && "$errors" != *"no errors"* ]]; then
  echo "Hyprland reported config errors:" >&2
  echo "$errors" >&2
fi

echo "Installed. Click the orb in the bar or press Super + Ctrl + M to chat."
