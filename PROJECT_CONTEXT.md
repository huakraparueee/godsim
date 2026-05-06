# Project Context v2: God Simulator (LÖVE Engine)

เอกสารนี้คือสเปกที่ "พร้อมลงมือทำ" สำหรับโปรเจกต์ GodSim โดยเน้นให้ทีม/Agent เริ่ม Phase 1 ได้ทันทีและวัดผลได้

---

## 1) Product Vision & Pillars

### Vision

เกมแนว God Simulator แบบ Sandbox Pixel Art ผู้เล่นเป็นผู้ควบคุมโลกทางอ้อมผ่านพลังพระเจ้า แล้วดูระบบจำลองสิ่งมีชีวิตตอบสนองแบบต่อเนื่อง

### Design Pillars

1. **Systemic Sandbox**: ระบบต่าง ๆ ต้องโต้ตอบกันเองจนเกิดเหตุการณ์ใหม่
2. **Readable Chaos**: วุ่นวายได้ แต่ผู้เล่นอ่านสถานการณ์ทัน (ผ่าน UI/สี/feedback)
3. **Performance First**: รองรับจำนวนยูนิตสูงแบบลื่นไหล
4. **Meaningful Intervention**: ทุกพลังพระเจ้าต้องมีต้นทุน-ผลลัพธ์ชัด

---

## 2) Technical Baseline

- **Language**: LuaJIT (Lua 5.1 compatible)
- **Engine**: LÖVE 11.5+
- **Bootstrap**: `main.lua` + `src.game`
- **Hot Reload**: lurker + lume (watch เฉพาะ `src/**/*.lua`)
- **Architecture**: Modular (World / Sim / Entities / Powers / UI / Render)

---

## 3) Runtime & Loop Contract

### Main Loop (Target)

- `love.update(dt)` ทำงานเป็นลำดับ:
  1. input
  2. simulation tick
  3. entity updates
  4. events/powers resolution
  5. render prep
- `love.draw()` วาดแบบ read-only จาก state ปัจจุบัน (ไม่แก้ logic state ใน draw)

### Time Model

- ใช้ **hybrid timestep**:
  - simulation หลัก: fixed step (`sim_dt = 1/20`)
  - rendering / camera / interpolation: variable `dt`
- มี speed control ขั้นต่ำ: pause / 1x / 2x / 4x

---

## 4) Data Contracts (MVP)

### TileDef (ค่าคงที่ตามชนิดพื้น)

```lua
TileDef = {
  id = "grass",
  walkable = true,
  speed_mult = 1.0,
  fertility = 0.8,
  flammable = 0.2
}
```

### TileInstance (ต่อช่องในแผนที่)

```lua
Tile = {
  type_id = "grass",
  temp = 24.0,
  moisture = 0.5,
  food = 0.3,
  fire = 0.0
}
```

### DNA

```lua
DNA = {
  move_speed = 1.0,
  view_distance = 6.0,
  fertility_rate = 0.3,
  max_health = 100,
  mutation_factor = 0.05
}
```

### Entity

```lua
Entity = {
  id = 1,
  kind = "creature",
  alive = true,
  x = 0, y = 0,
  vx = 0, vy = 0,
  age = 0,
  hunger = 0,
  health = 100,
  state = "Wander",
  dna = DNA
}
```

### WorldState

```lua
WorldState = {
  seed = 12345,
  tick = 0,
  width = 256, height = 256,
  tiles = {},           -- 1D array preferred for perf
  entities = {},        -- dense array
  free_entity_slots = {}, -- object pool support
  stats = {}
}
```

---

## 5) Module API Contracts (ต้องมีก่อนเขียนจริง)

### `src/world.lua`

- `world.new(width, height, seed) -> WorldState`
- `world.get_tile(world, gx, gy) -> Tile`
- `world.set_tile_type(world, gx, gy, type_id)`
- `world.brush(world, cx, cy, radius, painter_fn)`

### `src/entities.lua`

- `entities.spawn(world, x, y, dna?) -> entity_id`
- `entities.kill(world, entity_id, reason?)`
- `entities.update(world, dt)`

### `src/sim.lua`

- `sim.update(world, dt)` (internal fixed-step accumulator)
- `sim.step(world, sim_dt)` (food grow, fire spread, reproduction checks)

### `src/powers.lua`

- `powers.cast(world, power_id, gx, gy, params?) -> ok, err`

### `src/pathing.lua` (Phase 2+)

- `pathing.request(world, from_gx, from_gy, to_gx, to_gy) -> path_id`
- `pathing.poll(path_id) -> ready, result`

---

## 6) AI/FSM Contract (MVP)

Priority จากมากไปน้อย:

1. **Critical**: `Flee` หรือ `Eat` (hunger > 0.8)
2. **Social**: `Mating` (อายุถึงเกณฑ์ + เงื่อนไขพร้อม)
3. **Default**: `Wander`

กติกา:

- state transition ทำเฉพาะใน update logic
- state ทุกตัวต้องมี `enter`, `update`, `exit` (จะเป็น no-op ได้)
- ห้ามยิง pathfinding ใหม่ทุกเฟรม (ใช้ cooldown / cache)

---

## 7) God Powers (MVP Scope)

1. **Spawn**: เกิดยูนิต 1 ตัว/กลุ่มเล็ก
2. **Rain**: เพิ่ม moisture ลด fire ในรัศมี
3. **Smite**: ดาเมจจุดเดียว + knockback เล็กน้อย

ทุกพลังต้องมี:

- `cost_faith`
- `cooldown_sec`
- `cast_radius`
- visual feedback ขั้นต่ำ 1 อย่าง

---

## 8) Performance Budget & Profiling

### Target Machine (baseline)

เครื่อง dev หลัก + บันทึกสเปก CPU/GPU/RAM ใน README (เพิ่มภายหลังได้)

### Frame Budget (60 FPS)

- total frame <= 16.6ms
- simulation <= 6ms
- entities <= 5ms
- render <= 5ms

### Hard Constraints

- หลีกเลี่ยงการสร้าง table ใหม่ใน loop ร้อน (`love.update`, `sim.step`)
- tile map ใช้ 1D array และ index function
- render map ด้วย `SpriteBatch`
- ใช้ object pooling สำหรับ entity lifecycle

### Debug Overlay (ต้องมีตั้งแต่ Phase 1)

- FPS
- entity count
- sim step ms
- render ms
- GC memory (`collectgarbage("count")`)

---

## 9) Save/Load Strategy (Phase 4)

- Format เริ่มต้น: Lua table serialization (เร็ว, ง่ายต่อดีบัก)
- Save file ต้องมี `schema_version`
- มี migration function อย่างน้อย:
  - `migrate_v1_to_v2(data)`
- auto-backup ล่าสุด 1 ไฟล์ก่อน overwrite

---

## 10) Milestones + Definition of Done

| Phase | Deliverables                      | Definition of Done                                                  |
| ----- | --------------------------------- | ------------------------------------------------------------------- |
| 1     | Grid map + zoom/pan + brush       | 256x256 tiles, 60 FPS เฉลี่ย >= 55, terraform brush ใช้งานได้       |
| 2     | Entities + DNA + movement/pathing | spawn 500 entities ได้, state เปลี่ยนตามเงื่อนไข, ไม่ crash 10 นาที |
| 3     | Ecosystem loop                    | food growth + eat + reproduce ครบ                                   |
| 4     | Save/Load                         | save/load world เดิมได้, schema_version ใช้งานจริง                  |
| 5     | God powers UI + stats             | เลือกพลัง/กดใช้ได้ครบ MVP, overlay สถิติอ่านง่าย                    |

---

## 11) Phase 1 Task Breakdown (เริ่มทำทันที)

1. [x] สร้าง `src/world.lua` + tile defs + world.new
2. [x] ทำระบบ index/grid utility (1D array indexing)
3. [x] ทำ renderer แผนที่ด้วย `SpriteBatch`
4. [x] ทำ camera: pan/zoom + bounds clamp
5. [x] ทำ terraform brush (เปลี่ยน type tile แบบ radius)
6. [x] เพิ่ม debug overlay + frame timings
7. [x] ทำ smoke test: run 5 นาที ไม่มี error *(ยืนยันแบบใช้มือกับ `love .` + สถานการณ์ Stress 500; ไม่มี automated soak ใน repo)*

---

## 12) Engineering Rules (Strict)

1. **Performance First**: no temporary allocations ใน hot paths
2. **Deterministic Optional**: ระบบที่ต้อง replay/debug ได้ต้องผูกกับ seed
3. **Headless-ready Logic**: แยก sim logic ออกจาก render เสมอ
4. **Coordinate Consistency**: ฟังก์ชันแปลง grid<->world ต้องมีแหล่งจริงจุดเดียว
5. **Data-driven**: constants/gameplay tuning อยู่ใน data tables ไม่ hardcode กระจัดกระจาย

---

## 13) Decisions Locked (Phase 2 Baseline)

- **Pathfinding (target)**: แผนใช้ `A* + Steering` — ในโค้ดปัจจุบันเป็น **steering ไปยังเป้าหมาย + สแกนไทล์รอบตัว**; ยังไม่มีโมดูล `pathing.lua` แบบ request/poll ตามสเปก §5
- **Map Boundary**: ใช้ `Bounded Map` (ไม่มี world wrap)
- **Reproduction Model**: ใช้ `Stochastic`
- **UI Approach**: ใช้ `Immediate Mode UI` (lightweight, pure LÖVE compatible)

---

## 14) Phase 1–3 closure (verified & closed)

| Phase | สถานะ | หมายเหตุการยืนยัน |
| ----- | ----- | ------------------ |
| **1** | ปิดแล้ว | แผนที่เริ่มต้น **256×256** (`world.DEFAULT_MAP_TILES`), `SpriteBatch` ผ่าน `map_renderer`, camera pan/zoom (`play` + `camera`), terraform brush (`terraform` + `world.brush`), overlay มุมซ้ายล่าง (FPS, entities, sim/render ms, GC) |
| **2** | ปิดแล้ว | Entities + DNA + อัปเดต/`spawn`/`kill` ใน `entities.lua`; state machine หลายโหมด; สถานการณ์ **`stress_500`** = 500 ยูนิตสำหรับ soak; เส้นทาง = steering ไม่ใช่ไฟล์ `pathing.lua` แยก |
| **3** | ปิดแล้ว | ห่วงนิเวศใน `sim.step` (โตของอาหาร/ทรัพยากรไทล์) + กินหลายช่องทาง + `try_reproduce` ใน `entities.lua` |

ความละเอียด Phase 1 DoD เรื่อง “60 FPS เฉลี่ย ≥ 55” ขึ้นกับเครื่อง — ใช้ overlay วัดขณะเล่นได้

---

## 15) Current Status

- [x] Bootstrap (`main.lua`, `conf.lua`)
- [x] Hot reload (`lurker`, `lume`)
- [x] Phase 1 grid / camera / brush / debug overlay
- [x] Phase 2 entities + scenarios รวม soak `stress_500`
- [x] Phase 3 ecosystem loop (food ↔ eat ↔ reproduce) ใน `sim` + `entities`
- [ ] Phase 4 Save/Load (ถัดไปตาม §9)
