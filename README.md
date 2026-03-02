# Binding Windows CLI

Lua CLI + Hammerspoon module for local window layout state and hotkey-driven apply.

## Requirements

- macOS
- Hammerspoon
- Lua on `PATH`

```bash
brew install --cask hammerspoon
brew install lua
```

## Setup

```bash
./binding-windows init
./binding-windows doctor
```

Bootstrap creates:

- `~/.hammerspoon/binding-windows-layouts.lua`
- `~/.hammerspoon/binding_windows.lua`
- `require("binding_windows")` in `~/.hammerspoon/init.lua` (if missing)

## CLI quick examples

```bash
# health / listing
./binding-windows doctor
./binding-windows debug-target two-up
./binding-windows list
./binding-windows list --json

# create + bind + apply
./binding-windows create quadrants
./binding-windows bind 1 quadrants
./binding-windows apply quadrants

# rule management
./binding-windows rule-list quadrants
./binding-windows rule-set quadrants top_left pattern "infinity$"
./binding-windows rule-auto quadrants pattern "infinity$" "infinity%-1$" "infinity%-2$" "infinity%-3$"

# advanced JSON override
./binding-windows rule-set-json quadrants @./rules.json

# config backup
./binding-windows export ./binding-windows-layouts.backup.lua
./binding-windows import ./binding-windows-layouts.backup.lua
```

## Notes

- Hotkeys are fixed to `ctrl + option(alt) + cmd + <1-9>`.
- Layout defaults are generic; no hardcoded title rules.
- Screen targeting defaults to the focused/clicked window's display (`screen = "focused"`).
- This is Lua-only; no long-running CLI process.
