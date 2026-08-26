# roblox-slice-tycoon

Slice Tycoon — тайтл фабрики Roblox-игр, заведён из
[`roblox-game-template`](https://github.com/DaniilMurai/roblox-game-template).
Логика живёт в ядре `core/robloxcore`; здесь только `configs/main.json` и `src/`.

## Проверки

```bash
rokit install
git submodule update --init --recursive
wally install
lune run tests/run.luau
selene src
stylua --check src tests
rojo build -o build.rbxl
```

## Выкат

```bash
export ROBLOX_API_KEY=... ROBLOX_UNIVERSE_ID=... ROBLOX_PLACE_ID=...
./tools/publish.sh Published
```
