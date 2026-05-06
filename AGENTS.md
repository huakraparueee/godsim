# GodSim — agent notes

Brief (TH): โปรเจกต์ LÖVE นี้มี `main.lua` ที่รากโปรเจกต์ (บูตสตรัป) และโค้ดเกมใต้ `src/` — ในโหมด dev มี hot-reload ด้วย **lurker** (สแกน `src/` แบบ recursive); แก้ `main.lua` / `conf.lua` แล้วต้องรันเกมใหม่

## Stack

- **Engine**: [LÖVE](https://love2d.org/) (`conf.lua` sets `t.version` minimum; raise it when using newer APIs).
- **Hot reload**: [lurker](https://github.com/rxi/lurker) + [lume](https://github.com/rxi/lume) in `src/libraries/` (MIT). `lurker.path = "src"` in root `main.lua`.

## Layout

| Path | Role |
|------|------|
| `main.lua` | `love.filesystem.setRequirePath`, optional lurker, forwards callbacks to `src.main`. |
| `conf.lua` | `love.conf`: window, identity, version. |
| `src/main.lua` | Returns gameplay module `require("src.scenes.play")` (จุดเชื่อมฝั่ง `src/`). |
| `src/libraries/` | Vendored libs: `lume`, `lurker` (อย่าแก้เพื่อฟีเจอร์เกม; อัปเกรดจาก upstream). |
| `src/core/` | โลก, ซิม, entities, renderer, session/selection/terraform/world-draw. |
| `src/data/` | ตาราง config + `scenarios`. |
| `src/scenes/` | ฉากเกม (ตอนนี้ `play.lua` = loop หลัก). |
| `src/ui/` | เมนู, HUD, event log. |
| `src/utils/` | เช่น camera, picking. |
| `src/assets/` | ว่างไว้สำหรับรูป / เสียง / ฟอนต์ (.gitkeep). |
| `src/ecs/` | โครงว่างไว้หากใช้ ECS (`components/`, `systems/`). |
| `src/services/` | ว่างไว้สำหรับเช่น audio / save (.gitkeep). |

## Conventions for hot reload

- โมดูลอยู่ใต้ `src/` แบบจุด: ไฟล์ `src/core/world.lua` → `require("src.core.world")`. lurker map path `src/core/world.lua` → `src.core.world`.
- **State**: `lume.hotswap` merges tables; references to gameplay table จาก play scene มักยังชี้ instance เดิมได้. Full reset dev: **F5** (`package.loaded` ที่ขึ้นต้นด้วย `src.` ถูกเคลียร์ แล้ว `game.load` ใหม่).
- **Globals**: เลี่ยง side effect global ตอน reload; เก็บ state ใน table จากโมดูล.
- **Release**: `DEV = false` ในราก `main.lua`; เก็บ `src/libraries/` ถ้ายังใช้ lume ตอนรัน.

## Editor / run

- VS Code: Love path อาจตั้งใน `.vscode/settings.json`. รันจากโฟลเดอร์โปรเจกต์ (ที่มี `main.lua`): `love .`

## What not to automate

- Do not edit vendored `src/libraries/lurker.lua` / `lume.lua` for game features; upgrade from upstream if needed.
- Agents should not strip MIT license comments from vendored `src/libraries/*` files.
