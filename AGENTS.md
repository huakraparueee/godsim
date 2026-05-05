# GodSim — agent notes

Brief (TH): โปรเจกต์ LÖVE นี้แยก `main.lua` (บูตสตรัป) กับโค้ดเกมใน `src/` — ในโหมด dev มี hot-reload ด้วย **lurker** (ดูไฟล์ใน `src/`); แก้ `main.lua` / `conf.lua` แล้วต้องรันเกมใหม่

## Stack

- **Engine**: [LÖVE](https://love2d.org/) (`conf.lua` sets `t.version` minimum; raise it when using newer APIs).
- **Hot reload**: [lurker](https://github.com/rxi/lurker) + [lume](https://github.com/rxi/lume) in `lib/` (MIT). Only `src/**/*.lua` is watched (`lurker.path = "src"` in `main.lua`).

## Layout

| Path | Role |
|------|------|
| `main.lua` | `love.filesystem.setRequirePath`, optional lurker, forwards callbacks to `src.game`. |
| `conf.lua` | `love.conf`: window, identity, version. |
| `lib/lume.lua`, `lib/lurker.lua` | Hot-swap helpers (do not rely on them from game logic if you ship without them). |
| `src/game.lua` | Main game module (`require("src.game")`). Add `src/foo.lua` → `require("src.foo")` so lurker module names stay `src.*`. |

## Conventions for hot reload

- Use **dotted modules under `src/`**: file `src/world.lua` → `require("src.world")`. Lurker builds the name `src.world` from path `src/world.lua`.
- **State**: `lume.hotswap` merges tables; references to the main `src.game` table often stay valid. For a full reset in dev, press **F5** (clears `package.loaded` entries starting with `src.` and runs `game.load` again).
- **Global side effects**: avoid new globals on reload; prefer tables returned from modules.
- **Release**: set `DEV = false` in `main.lua` (or gate on a build flag) so lurker is not loaded; ship `lib/` only if you still need lume at runtime.

## Editor / run

- VS Code: Love path may be set in `.vscode/settings.json` (`lazarusoverlook.love2d.path`). Run via your Love2D extension or: `love .` from the project root (folder containing `main.lua`).

## What not to automate

- Do not edit `lib/lurker.lua` / `lib/lume.lua` for game features; upgrade them from upstream if needed.
- Agents should not strip MIT license comments from vendored `lib/*` files.
