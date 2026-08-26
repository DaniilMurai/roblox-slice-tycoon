#!/usr/bin/env bash
# Creates a new title next to this template. Everything a title owns is its config and
# its src/; the core arrives as a submodule, exactly as it does here.
set -euo pipefail

if [ $# -ne 2 ]; then
	echo "usage: $0 <slug> \"<Display Name>\"" >&2
	exit 1
fi

slug="$1"
display_name="$2"

if ! printf '%s' "$slug" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$'; then
	# The slug becomes a directory, a repository and a Wally package name, none of which
	# tolerate spaces or capitals.
	echo "slug must be kebab-case: lowercase letters, digits and single dashes" >&2
	exit 1
fi

template_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_dir="$(dirname "$template_dir")/$slug"
core_url="$(git -C "$template_dir" config --file .gitmodules submodule.core/robloxcore.url)"

if [ -e "$target_dir" ]; then
	echo "$target_dir already exists" >&2
	exit 1
fi

mkdir -p "$target_dir"
# Build products and the submodule are re-created in the new repository, not copied: a
# stale Packages/ would hide a broken wally.toml until CI.
rsync -a \
	--exclude '.git' \
	--exclude '.gitmodules' \
	--exclude 'core' \
	--exclude 'Packages' \
	--exclude 'ServerPackages' \
	--exclude 'build.rbxl' \
	--exclude '.env' \
	--exclude 'wally.lock' \
	"$template_dir/" "$target_dir/"

cd "$target_dir"

python3 - "$slug" "$display_name" <<'PY'
import json, sys, pathlib

slug, display_name = sys.argv[1], sys.argv[2]

config = json.loads(pathlib.Path("configs/main.json").read_text())
config["slug"] = slug
config["displayName"] = display_name
pathlib.Path("configs/main.json").write_text(json.dumps(config, indent=2) + "\n")

project = json.loads(pathlib.Path("default.project.json").read_text())
project["name"] = slug
pathlib.Path("default.project.json").write_text(json.dumps(project, indent=2) + "\n")

wally = pathlib.Path("wally.toml")
wally.write_text(wally.read_text().replace("roblox-game-template", slug, 1))

checklist = pathlib.Path("STUDIO-CHECKLIST.md")
checklist.write_text(
    checklist.read_text().replace("__SLUG__", slug).replace("__DISPLAY_NAME__", display_name)
)

pathlib.Path("README.md").write_text(f"""# {slug}

{display_name} — тайтл фабрики Roblox-игр, заведён из
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
""")
PY

git init -q -b main
git submodule add -q "$core_url" core/robloxcore

# Installed before the first commit so wally.lock is part of it: a lockfile appearing as
# an untracked file right after scaffolding reads as a half-finished script.
wally install >/dev/null

git add -A
git -c commit.gpgsign=false commit -q -m "Завести тайтл $slug из шаблона"

echo "$slug ready at $target_dir"
echo "next: cd $target_dir && wally install && rojo build -o build.rbxl"
