#!/bin/bash
# Builds the place and type-checks every script (needs Rojo + luau-lsp; paths below are this PC's).
cd "$(dirname "$0")/.."
R="$LOCALAPPDATA/Programs/Rojo/rojo.exe"
L=/c/Users/aweso/2-player-obby/.tools
"$R" sourcemap default.project.json -o sourcemap.json >/dev/null
"$R" build -o build.rbxl | tail -1
$L/luau-lsp/luau-lsp.exe analyze --platform=roblox --sourcemap=sourcemap.json --definitions=@roblox=$L/globalTypes.d.luau src 2>&1 | grep -v -E "^\[(INFO|WARN)\]|^$"
