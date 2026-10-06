#!/bin/bash
# Removes everything install.sh added.
PLUGIN_ID=bsarer.slm-test
BINDINGS=~/.config/hypr/bindings.lua

# Shortcut
if grep -qF -- "-- >>> slm-test >>>" "$BINDINGS" 2>/dev/null; then
  cp "$BINDINGS" "$BINDINGS.bak.$(date +%s)"
  sed -i '/^-- >>> slm-test >>>$/,/^-- <<< slm-test <<<$/d' "$BINDINGS"
  hyprctl reload >/dev/null
fi

# Shell plugin
omarchy-shell -q shell hide "$PLUGIN_ID"
omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1
rm -rf ~/.config/omarchy/plugins/$PLUGIN_ID
omarchy-shell -q shell rescanPlugins

# Service
systemctl --user disable --now slm-test.service >/dev/null 2>&1
rm -f ~/.config/systemd/user/slm-test.service
systemctl --user daemon-reload

# App
rm -rf ~/.local/share/slm-test ~/.local/state/slm-test
rm -f ~/.local/bin/slm-test ~/.local/share/applications/slm-test.desktop

echo "SLM Test removed."
