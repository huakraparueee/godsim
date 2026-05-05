--[[
  Phase 1 - Task 1 baseline world module:
  - Tile definitions
  - World construction (world.new)
]]

local world = {}
local entity_config = require("src.config_entities")
world.TILE_METERS = 100
local UI_EVENT_LOG_MAX = 8
local UI_EVENT_LOG_KINDS = {
    birth = true,
    build = true,
    danger = true,
    day_summary = true,
    death = true,
    explore = true,
    pregnancy = true,
    social = true,
    warning = true,
}

world.tile_defs = {
    deep_water = { id = "deep_water", walkable = false, speed_mult = 0.0, fertility = 0.0, flammable = 0.0 },
    shallow_water = { id = "shallow_water", walkable = false, speed_mult = 0.0, fertility = 0.0, flammable = 0.0 },
    sand = { id = "sand", walkable = true, speed_mult = 0.85, fertility = 0.15, flammable = 0.0 },
    grass = { id = "grass", walkable = true, speed_mult = 1.0, fertility = 0.8, flammable = 0.2 },
    forest = { id = "forest", walkable = true, speed_mult = 0.65, fertility = 0.65, flammable = 0.9 },
    mountain = { id = "mountain", walkable = false, speed_mult = 0.0, fertility = 0.05, flammable = 0.0 },
}

local default_tile_state = {
    temp = 24.0,
    moisture = 0.5,
    food = 0.0,
    has_apple_tree = false,
    apple_fruit = 0.0,
    apple_wood = 0.0,
    pine_wood = 0.0,
    wildlife = 0.0,
    rabbit_young = 0.0,
    rabbit_adult = 0.0,
    rabbit_old = 0.0,
    wolves = 0.0,
    fire = 0.0,
}

local function make_rng(seed)
    if love and love.math and love.math.newRandomGenerator then
        local s = tonumber(seed) or os.time()
        local rg = love.math.newRandomGenerator(s)
        return function()
            return rg:random()
        end
    end

    -- Fallback LCG when love.math is unavailable.
    local state = tonumber(seed) or os.time()
    return function()
        state = (1103515245 * state + 12345) % 2147483648
        return state / 2147483648
    end
end

local function rand01()
    if love and love.math and love.math.random then
        return love.math.random()
    end
    return math.random()
end

local function reset_tile_resources_for_type(tile, type_id)
    local resource_cfg = entity_config.RESOURCE or {}
    tile.has_apple_tree = false
    tile.apple_fruit = 0
    tile.apple_wood = 0
    tile.pine_wood = 0
    tile.food = 0

    if type_id == "forest" then
        tile.has_apple_tree = rand01() < (resource_cfg.APPLE_TREE_DENSITY or 0.70)
        if tile.has_apple_tree then
            if rand01() < (resource_cfg.APPLE_START_FRUIT_CHANCE or 0.50) then
                tile.apple_fruit = 0.12 + (rand01() * 0.2)
                tile.food = tile.apple_fruit
            end
            tile.apple_wood = 0.24 + (rand01() * 0.22)
        end
        tile.pine_wood = 0.36 + (rand01() * 0.45)
    end
end

function world.in_bounds(w, gx, gy)
    return gx >= 1 and gx <= w.width and gy >= 1 and gy <= w.height
end

function world.to_index(w, gx, gy)
    if not world.in_bounds(w, gx, gy) then
        return nil
    end
    return (gy - 1) * w.width + gx
end

function world.to_grid(w, index)
    if type(index) ~= "number" or index < 1 or index > (w.width * w.height) then
        return nil, nil
    end
    local gx = ((index - 1) % w.width) + 1
    local gy = math.floor((index - 1) / w.width) + 1
    return gx, gy
end

function world.get_tile(w, gx, gy)
    local index = world.to_index(w, gx, gy)
    if not index then
        return nil
    end
    return w.tiles[index], index
end

function world.get_tile_def(type_id)
    return world.tile_defs[type_id]
end

function world.tiles_to_meters(tiles)
    return (tiles or 0) * world.TILE_METERS
end

function world.meters_to_tiles(meters)
    return (meters or 0) / world.TILE_METERS
end

function world.set_tile_type(w, gx, gy, type_id)
    if not world.tile_defs[type_id] then
        return false, "unknown tile type"
    end
    local tile = world.get_tile(w, gx, gy)
    if not tile then
        return false, "out of bounds"
    end
    tile.type_id = type_id
    reset_tile_resources_for_type(tile, type_id)
    return true
end

function world.brush(w, cx, cy, radius, type_id)
    if not world.tile_defs[type_id] then
        return 0, "unknown tile type"
    end
    if type(radius) ~= "number" or radius < 0 then
        return 0, "invalid radius"
    end

    local changed = 0
    local r2 = radius * radius
    local min_x = math.floor(cx - radius)
    local max_x = math.floor(cx + radius)
    local min_y = math.floor(cy - radius)
    local max_y = math.floor(cy + radius)

    for gy = min_y, max_y do
        for gx = min_x, max_x do
            local dx = gx - cx
            local dy = gy - cy
            if (dx * dx + dy * dy) <= r2 then
                local tile = world.get_tile(w, gx, gy)
                if tile and tile.type_id ~= type_id then
                    tile.type_id = type_id
                    reset_tile_resources_for_type(tile, type_id)
                    changed = changed + 1
                end
            end
        end
    end

    return changed
end

local function pick_initial_tile_type(x, y, width, height, rng)
    if x == 1 or y == 1 or x == width or y == height then
        return "deep_water"
    end

    if x == 2 or y == 2 or x == (width - 1) or y == (height - 1) then
        return "shallow_water"
    end

    return "grass"
end

local function can_cluster_replace(tile)
    return tile and tile.type_id ~= "deep_water" and tile.type_id ~= "shallow_water"
end

local function paint_biome_cluster(w, cx, cy, radius, type_id, rng, strength)
    local radius2 = radius * radius
    local min_x = math.max(3, cx - radius)
    local max_x = math.min(w.width - 2, cx + radius)
    local min_y = math.max(3, cy - radius)
    local max_y = math.min(w.height - 2, cy + radius)
    local cluster_strength = strength or 0.82

    for gy = min_y, max_y do
        for gx = min_x, max_x do
            local dx = gx - cx
            local dy = gy - cy
            local d2 = dx * dx + dy * dy
            if d2 <= radius2 then
                local tile = world.get_tile(w, gx, gy)
                if can_cluster_replace(tile) then
                    local distance_ratio = math.sqrt(d2) / math.max(1, radius)
                    local edge_falloff = 1 - (distance_ratio * 0.45)
                    if rng() < (cluster_strength * edge_falloff) then
                        tile.type_id = type_id
                    end
                end
            end
        end
    end
end

local function seed_biome_clusters(w, rng)
    local total_tiles = w.width * w.height
    local scale = total_tiles / 1000
    local cluster_defs = {
        { type_id = "forest", count = math.max(2, math.floor(scale * 3.0)), min_radius = 4, max_radius = 9, strength = 0.88 },
        { type_id = "sand", count = math.max(1, math.floor(scale * 1.4)), min_radius = 3, max_radius = 7, strength = 0.82 },
        { type_id = "mountain", count = math.max(1, math.floor(scale * 1.1)), min_radius = 3, max_radius = 8, strength = 0.86 },
    }

    for i = 1, #cluster_defs do
        local def = cluster_defs[i]
        for _ = 1, def.count do
            local cx = 3 + math.floor(rng() * math.max(1, w.width - 5))
            local cy = 3 + math.floor(rng() * math.max(1, w.height - 5))
            local radius = def.min_radius + math.floor(rng() * math.max(1, def.max_radius - def.min_radius + 1))
            paint_biome_cluster(w, cx, cy, radius, def.type_id, rng, def.strength)

            -- Add a few nearby lobes so clusters look like natural patches, not perfect circles.
            local lobes = 1 + math.floor(rng() * 3)
            for _lobe = 1, lobes do
                local angle = rng() * math.pi * 2
                local dist = radius * (0.35 + rng() * 0.45)
                local lx = math.max(3, math.min(w.width - 2, math.floor(cx + math.cos(angle) * dist)))
                local ly = math.max(3, math.min(w.height - 2, math.floor(cy + math.sin(angle) * dist)))
                local lobe_radius = math.max(2, math.floor(radius * (0.45 + rng() * 0.35)))
                paint_biome_cluster(w, lx, ly, lobe_radius, def.type_id, rng, def.strength * 0.9)
            end
        end
    end
end

local function is_rabbit_habitat(tile)
    return tile and (tile.type_id == "grass" or tile.type_id == "forest")
end

local function seed_rabbit_colonies(w, rng)
    local resource_cfg = entity_config.RESOURCE or {}
    local total_tiles = w.width * w.height
    local clusters = math.max(1, math.floor((total_tiles / 1000) * (resource_cfg.WILDLIFE_START_CLUSTERS_PER_1000_TILES or 1.4)))
    local radius_min = resource_cfg.WILDLIFE_START_CLUSTER_RADIUS_MIN or 2
    local radius_max = resource_cfg.WILDLIFE_START_CLUSTER_RADIUS_MAX or 4
    local wildlife_max = resource_cfg.WILDLIFE_MAX or 0.55

    for _ = 1, clusters do
        local cx
        local cy
        for _attempt = 1, 40 do
            local x = 3 + math.floor(rng() * math.max(1, w.width - 5))
            local y = 3 + math.floor(rng() * math.max(1, w.height - 5))
            local tile = world.get_tile(w, x, y)
            if is_rabbit_habitat(tile) then
                cx = x
                cy = y
                break
            end
        end

        if cx and cy then
            local radius = radius_min + math.floor(rng() * math.max(1, radius_max - radius_min + 1))
            local radius2 = radius * radius
            for gy = math.max(1, cy - radius), math.min(w.height, cy + radius) do
                for gx = math.max(1, cx - radius), math.min(w.width, cx + radius) do
                    local dx = gx - cx
                    local dy = gy - cy
                    local d2 = dx * dx + dy * dy
                    local tile = world.get_tile(w, gx, gy)
                    if d2 <= radius2 and is_rabbit_habitat(tile) then
                        local falloff = 1 - (math.sqrt(d2) / math.max(1, radius + 1))
                        local habitat_mult = (tile.type_id == "forest") and 0.65 or 1.0
                        local colony_pop = (0.08 + rng() * 0.24) * falloff * habitat_mult
                        local added = math.min(wildlife_max * habitat_mult - (tile.wildlife or 0), colony_pop)
                        if added > 0 then
                            tile.rabbit_young = (tile.rabbit_young or 0) + (added * 0.20)
                            tile.rabbit_adult = (tile.rabbit_adult or 0) + (added * 0.70)
                            tile.rabbit_old = (tile.rabbit_old or 0) + (added * 0.10)
                            tile.wildlife = (tile.rabbit_young or 0) + (tile.rabbit_adult or 0) + (tile.rabbit_old or 0)
                        end
                    end
                end
            end
        end
    end
end

local function seed_wolf_packs(w, rng)
    local resource_cfg = entity_config.RESOURCE or {}
    local total_tiles = w.width * w.height
    local packs = math.max(1, math.floor((total_tiles / 1000) * (resource_cfg.WOLF_START_PACKS_PER_1000_TILES or 0.35)))
    local radius = resource_cfg.WOLF_START_PACK_RADIUS or 2
    local wolf_max = resource_cfg.WOLF_MAX or 0.28

    for _ = 1, packs do
        local cx
        local cy
        for _attempt = 1, 60 do
            local x = 3 + math.floor(rng() * math.max(1, w.width - 5))
            local y = 3 + math.floor(rng() * math.max(1, w.height - 5))
            local tile = world.get_tile(w, x, y)
            if tile and tile.type_id == "forest" then
                cx = x
                cy = y
                break
            end
        end

        if cx and cy then
            local radius2 = radius * radius
            for gy = math.max(1, cy - radius), math.min(w.height, cy + radius) do
                for gx = math.max(1, cx - radius), math.min(w.width, cx + radius) do
                    local dx = gx - cx
                    local dy = gy - cy
                    local d2 = dx * dx + dy * dy
                    local tile = world.get_tile(w, gx, gy)
                    if d2 <= radius2 and tile and (tile.type_id == "forest" or tile.type_id == "grass") then
                        local falloff = 1 - (math.sqrt(d2) / math.max(1, radius + 1))
                        local habitat_mult = (tile.type_id == "forest") and 1.0 or 0.55
                        tile.wolves = math.min(wolf_max * habitat_mult, (tile.wolves or 0) + ((0.04 + rng() * 0.08) * falloff * habitat_mult))
                    end
                end
            end
        end
    end
end

function world.new(width, height, seed)
    assert(type(width) == "number" and width > 0, "world.new: width must be > 0")
    assert(type(height) == "number" and height > 0, "world.new: height must be > 0")

    local w = {
        seed = seed or os.time(),
        tick = 0,
        elapsed_time = 0,
        width = width,
        height = height,
        tiles = {},
        entities = {},
        free_entity_slots = {},
        buildings = {},
        calendar = {
            day = 1,
            month = 1,
            year = 0,
            day_of_year = 1,
            total_days = 1,
            days_per_month = 30,
            months_per_year = 12,
            seconds_per_day = 1,
            day_progress = 0,
        },
        stats = {
            population = 0,
            births = 0,
            deaths = 0,
            deaths_old_age = 0,
            deaths_starvation = 0,
            avg_food = 0,
            total_apples = 0,
            total_wood = 0,
            peak_population = 0,
            min_population = 0,
            campfires_built = 0,
            shelters_built = 0,
            events = {},
            max_events = 120,
            event_log = {},
            max_event_log = UI_EVENT_LOG_MAX,
        },
        environment = {
            fertility_mult = 1.0,
            rainfall_mult = 1.0,
            heat_mult = 1.0,
        },
    }

    local rng = make_rng(w.seed)

    local total = width * height
    for i = 1, total do
        local x, y = world.to_grid(w, i)
        w.tiles[i] = {
            type_id = pick_initial_tile_type(x, y, width, height, rng),
            temp = default_tile_state.temp,
            moisture = default_tile_state.moisture,
            food = default_tile_state.food,
            has_apple_tree = default_tile_state.has_apple_tree,
            apple_fruit = default_tile_state.apple_fruit,
            apple_wood = default_tile_state.apple_wood,
            pine_wood = default_tile_state.pine_wood,
            wildlife = default_tile_state.wildlife,
            rabbit_young = default_tile_state.rabbit_young,
            rabbit_adult = default_tile_state.rabbit_adult,
            rabbit_old = default_tile_state.rabbit_old,
            wolves = default_tile_state.wolves,
            fire = default_tile_state.fire,
        }
    end

    seed_biome_clusters(w, rng)

    for i = 1, total do
        if w.tiles[i].type_id == "forest" then
            w.tiles[i].has_apple_tree = rng() < ((entity_config.RESOURCE or {}).APPLE_TREE_DENSITY or 0.70)
            if w.tiles[i].has_apple_tree then
                if rng() < ((entity_config.RESOURCE or {}).APPLE_START_FRUIT_CHANCE or 0.50) then
                    w.tiles[i].apple_fruit = 0.12 + (rng() * 0.2)
                    w.tiles[i].food = w.tiles[i].apple_fruit
                end
                w.tiles[i].apple_wood = 0.24 + (rng() * 0.22)
            end
            w.tiles[i].pine_wood = 0.36 + (rng() * 0.45)
        end
    end

    seed_rabbit_colonies(w, rng)
    seed_wolf_packs(w, rng)

    return w
end

function world.push_event(w, kind, message, severity)
    if not (w and w.stats and w.stats.events) then
        return
    end

    local event = {
        day = (w.calendar and w.calendar.total_days) or 1,
        tick = w.tick or 0,
        kind = kind or "info",
        severity = severity or "info",
        message = message or "",
    }

    local events = w.stats.events
    events[#events + 1] = event

    local max_events = w.stats.max_events or 120
    local overflow = #events - max_events
    if overflow > 0 then
        for _ = 1, overflow do
            table.remove(events, 1)
        end
    end

    if UI_EVENT_LOG_KINDS[event.kind] then
        w.stats.event_log = w.stats.event_log or {}
        local event_log = w.stats.event_log
        event_log[#event_log + 1] = event
        local max_event_log = w.stats.max_event_log or UI_EVENT_LOG_MAX
        local log_overflow = #event_log - max_event_log
        if log_overflow > 0 then
            for _ = 1, log_overflow do
                table.remove(event_log, 1)
            end
        end
    end
end

return world
