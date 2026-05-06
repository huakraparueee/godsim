--[[
  Fixed-step simulation skeleton.
  Owns accumulator and calls subsystem updates at stable step size.
]]

local entities = require("src.core.entities")
local world = require("src.core.world")
local entity_events = require("src.core.entities_events")
local entities_cfg = require("src.data.config_entities")

local sim = {}

local function rand01()
    if love and love.math and love.math.random then
        return love.math.random()
    end
    return math.random()
end

local function get_seasonal_factor(w)
    local cal = w.calendar
    if not cal then
        return 1.0
    end
    local day_of_year = cal.day_of_year or 1
    local days_per_year = (cal.days_per_month or 30) * (cal.months_per_year or 12)
    local phase = (day_of_year / math.max(1, days_per_year)) * math.pi * 2
    return 0.85 + (math.sin(phase) * 0.15)
end

local function update_calendar(w, dt)
    local cal = w.calendar
    if not cal then
        return
    end

    local seconds_per_day = cal.seconds_per_day or 1
    if seconds_per_day <= 0 then
        seconds_per_day = 1
    end

    cal.day_progress = (cal.day_progress or 0) + dt
    while cal.day_progress >= seconds_per_day do
        cal.day_progress = cal.day_progress - seconds_per_day
        cal.day = (cal.day or 1) + 1
        cal.day_of_year = (cal.day_of_year or 1) + 1
        cal.total_days = (cal.total_days or 1) + 1

        local days_per_month = cal.days_per_month or 30
        local months_per_year = cal.months_per_year or 12
        if cal.day > days_per_month then
            cal.day = 1
            cal.month = (cal.month or 1) + 1
            if cal.month > months_per_year then
                cal.month = 1
                cal.year = (cal.year or 1) + 1
            end
        end

        local days_per_year = days_per_month * months_per_year
        if cal.day_of_year > days_per_year then
            cal.day_of_year = 1
        end
    end
end

function sim.new(config)
    config = config or {}
    return {
        step_dt = config.step_dt or (1 / 20),
        max_steps_per_frame = config.max_steps_per_frame or 8,
        max_accumulator = config.max_accumulator or ((config.step_dt or (1 / 20)) * ((config.max_steps_per_frame or 8) + 1)),
        eco_slices = config.eco_slices or 2,
        stats_stride = config.stats_stride or 2,
        accumulator = 0,
        tick = 0,
        eco_phase = 0,
    }
end

function sim.step(state, w, dt)
    w.elapsed_time = (w.elapsed_time or 0) + dt
    update_calendar(w, dt)

    local total_food = 0
    local total_apples = 0
    local total_wood = 0
    local total_wildlife = 0
    local total_wolves = 0
    local fruit_spawned = 0
    local tile_count = #w.tiles
    local env = w.environment or {}
    local fertility_mult = env.fertility_mult or 1.0
    local rainfall_mult = env.rainfall_mult or 1.0
    local heat_mult = env.heat_mult or 1.0
    local seasonal = get_seasonal_factor(w)
    local rabbit_spread = {}
    local resources = entities_cfg.RESOURCE or {}
    local eco_slices = math.max(1, math.floor(state.eco_slices or 1))
    local eco_phase = math.floor(state.eco_phase or 0) % eco_slices
    local eco_dt = dt * eco_slices

    local campfire_tile_boost = {}
    local buildings = w.buildings or {}
    local avoid_range = resources.WOLF_CAMPFIRE_AVOID_RANGE or 5.0
    local avoid_range_i = math.max(1, math.floor(avoid_range + 0.5))
    local avoid_range2 = avoid_range * avoid_range
    for bi = 1, #buildings do
        local b = buildings[bi]
        if b and b.kind == "campfire" and (not b.under_construction) then
            local cx = math.floor(b.x or 0)
            local cy = math.floor(b.y or 0)
            local min_y = math.max(1, cy - avoid_range_i)
            local max_y = math.min(w.height, cy + avoid_range_i)
            local min_x = math.max(1, cx - avoid_range_i)
            local max_x = math.min(w.width, cx + avoid_range_i)
            for gy = min_y, max_y do
                for gx = min_x, max_x do
                    local dx = gx - (b.x or gx)
                    local dy = gy - (b.y or gy)
                    if (dx * dx + dy * dy) <= avoid_range2 then
                        local idx = world.to_index(w, gx, gy)
                        if idx then
                            campfire_tile_boost[idx] = true
                        end
                    end
                end
            end
        end
    end

    for i = 1 + eco_phase, tile_count, eco_slices do
        local tile = w.tiles[i]
        local def = world.get_tile_def(tile.type_id)
        local fertility = (def and def.fertility) or 0
        local moisture = tile.moisture or 0.5
        local moisture_target = 0.45 * rainfall_mult
        moisture = moisture + ((moisture_target - moisture) * 0.22 * eco_dt)
        tile.moisture = math.max(0.05, math.min(1.0, moisture))
        local moisture_effect = 0.6 + tile.moisture * 0.9
        local heat_penalty = 1.0 - math.max(0, (heat_mult - 1.0) * 0.25)
        local fruit_growth = ((resources.APPLE_FRUIT_GROWTH or 0.005) + fertility * 0.006) * fertility_mult * seasonal * moisture_effect * heat_penalty * eco_dt
        local apple_wood_growth = ((resources.APPLE_WOOD_GROWTH or 0.0015) + fertility * 0.0012) * fertility_mult * seasonal * moisture_effect * eco_dt
        local pine_wood_growth = ((resources.PINE_WOOD_GROWTH or 0.0022) + fertility * 0.0018) * rainfall_mult * eco_dt
        local fruit_max = resources.APPLE_FRUIT_MAX or 1.0
        local apple_wood_max = resources.APPLE_WOOD_MAX or 0.8
        local pine_wood_max = resources.PINE_WOOD_MAX or 1.2
        local wildlife_max = resources.WILDLIFE_MAX or 1.0

        local before_fruit = tile.apple_fruit or 0
        if tile.type_id == "forest" and tile.has_apple_tree == nil then
            tile.has_apple_tree = (tile.apple_fruit or 0) > 0 or (tile.apple_wood or 0) > 0
        end
        if tile.type_id == "forest" and tile.has_apple_tree then
            tile.apple_fruit = math.min(fruit_max, before_fruit + fruit_growth)
            tile.apple_wood = math.min(apple_wood_max, (tile.apple_wood or 0) + apple_wood_growth)
        else
            tile.apple_fruit = 0
            tile.apple_wood = 0
        end

        if tile.type_id == "grass" or tile.type_id == "forest" then
            if (not tile.rabbit_young) and (not tile.rabbit_adult) and (not tile.rabbit_old) and (tile.wildlife or 0) > 0 then
                tile.rabbit_young = (tile.wildlife or 0) * 0.20
                tile.rabbit_adult = (tile.wildlife or 0) * 0.70
                tile.rabbit_old = (tile.wildlife or 0) * 0.10
            end
            local young = tile.rabbit_young or 0
            local adult = tile.rabbit_adult or 0
            local old = tile.rabbit_old or 0
            local current_rabbits = young + adult + old
            local habitat_capacity = wildlife_max
            if tile.type_id == "forest" then
                habitat_capacity = wildlife_max * 0.65
            end
            local breeding_season = math.max(0.05, (seasonal - 0.70) / 0.30)
            local habitat_quality = fertility_mult * moisture_effect * heat_penalty
            local reproduction = adult
                * (resources.WILDLIFE_REPRO_RATE or 0.012)
                * breeding_season
                * habitat_quality
                * math.max(0, 1 - (current_rabbits / math.max(0.001, habitat_capacity)))
                * eco_dt
            local mature = math.min(young, young / math.max(1, resources.WILDLIFE_YOUNG_DAYS or 45) * eco_dt)
            local aging = math.min(adult, adult / math.max(1, resources.WILDLIFE_ADULT_DAYS or 420) * eco_dt)
            local old_age_death = math.min(old, old / math.max(1, resources.WILDLIFE_OLD_DAYS or 120) * eco_dt)
            local ambient_death = current_rabbits
                * (resources.WILDLIFE_MORTALITY_RATE or 0.0035)
                * (1 + math.max(0, heat_mult - 1.0) * 0.35)
                * eco_dt
            local young_share = current_rabbits > 0 and (young / current_rabbits) or 0
            local adult_share = current_rabbits > 0 and (adult / current_rabbits) or 0
            local old_share = current_rabbits > 0 and (old / current_rabbits) or 0
            young = math.max(0, young + reproduction - mature - (ambient_death * young_share))
            adult = math.max(0, adult + mature - aging - (ambient_death * adult_share))
            old = math.max(0, old + aging - old_age_death - (ambient_death * old_share))
            local next_rabbits = young + adult + old
            if next_rabbits > habitat_capacity then
                local scale = habitat_capacity / math.max(0.001, next_rabbits)
                young = young * scale
                adult = adult * scale
                old = old * scale
                next_rabbits = habitat_capacity
            end
            if adult <= 0 and next_rabbits > 0 and next_rabbits < (resources.WILDLIFE_EXTINCTION_THRESHOLD or 0.035) then
                local extinction_chance = (resources.WILDLIFE_EXTINCTION_CHANCE or 0.04) * eco_dt
                if rand01() < extinction_chance then
                    young = 0
                    adult = 0
                    old = 0
                    next_rabbits = 0
                end
            end
            tile.rabbit_young = young
            tile.rabbit_adult = adult
            tile.rabbit_old = old
            tile.wildlife = next_rabbits

            local dispersal_threshold = resources.WILDLIFE_DISPERSAL_THRESHOLD or 0.34
            if next_rabbits > dispersal_threshold then
                local gx, gy = world.to_grid(w, i)
                local targets = {}
                local dirs = {
                    { 1, 0 },
                    { -1, 0 },
                    { 0, 1 },
                    { 0, -1 },
                }
                for d = 1, #dirs do
                    local nx = gx + dirs[d][1]
                    local ny = gy + dirs[d][2]
                    local neighbor, neighbor_idx = world.get_tile(w, nx, ny)
                    if neighbor and (neighbor.type_id == "grass" or neighbor.type_id == "forest") then
                        local neighbor_capacity = wildlife_max * ((neighbor.type_id == "forest") and 0.65 or 1.0)
                        if (neighbor.wildlife or 0) < neighbor_capacity then
                            targets[#targets + 1] = {
                                idx = neighbor_idx,
                                capacity = neighbor_capacity,
                            }
                        end
                    end
                end
                if #targets > 0 then
                    local leaving = math.min(next_rabbits - dispersal_threshold, next_rabbits * (resources.WILDLIFE_DISPERSAL_RATE or 0.025) * eco_dt)
                    if leaving > 0 then
                        local leaving_adult = math.min(adult, leaving * 0.75)
                        local leaving_young = math.min(young, leaving - leaving_adult)
                        local leaving_total = leaving_adult + leaving_young
                        rabbit_spread[i] = rabbit_spread[i] or { young = 0, adult = 0, old = 0 }
                        rabbit_spread[i].young = rabbit_spread[i].young - leaving_young
                        rabbit_spread[i].adult = rabbit_spread[i].adult - leaving_adult
                        local share = leaving_total / #targets
                        local young_share_move = leaving_total > 0 and (leaving_young / leaving_total) or 0
                        local adult_share_move = leaving_total > 0 and (leaving_adult / leaving_total) or 0
                        for t = 1, #targets do
                            local target = targets[t]
                            local neighbor = w.tiles[target.idx]
                            local space = math.max(0, target.capacity - (neighbor.wildlife or 0))
                            local moved = math.min(share, space)
                            rabbit_spread[target.idx] = rabbit_spread[target.idx] or { young = 0, adult = 0, old = 0 }
                            rabbit_spread[target.idx].young = rabbit_spread[target.idx].young + (moved * young_share_move)
                            rabbit_spread[target.idx].adult = rabbit_spread[target.idx].adult + (moved * adult_share_move)
                        end
                    end
                end
            end
            fruit_spawned = fruit_spawned + math.max(0, (tile.apple_fruit or 0) - before_fruit)
        else
            local decay = 0.02 * eco_dt
            tile.rabbit_young = math.max(0, (tile.rabbit_young or 0) - ((tile.rabbit_young or 0) * decay))
            tile.rabbit_adult = math.max(0, (tile.rabbit_adult or 0) - ((tile.rabbit_adult or 0) * decay))
            tile.rabbit_old = math.max(0, (tile.rabbit_old or 0) - ((tile.rabbit_old or 0) * decay))
            tile.wildlife = (tile.rabbit_young or 0) + (tile.rabbit_adult or 0) + (tile.rabbit_old or 0)
        end
        if tile.type_id == "grass" or tile.type_id == "forest" then
            local wolf_capacity = (resources.WOLF_MAX or 0.28) * ((tile.type_id == "forest") and 1.0 or 0.55)
            local current_wolves = tile.wolves or 0
            local prey_factor = math.min(1.4, 0.45 + ((tile.wildlife or 0) / math.max(0.001, wildlife_max)))
            local wolf_repro = current_wolves
                * (resources.WOLF_REPRO_RATE or 0.0025)
                * prey_factor
                * math.max(0, 1 - (current_wolves / math.max(0.001, wolf_capacity)))
                * eco_dt
            local wolf_mortality = current_wolves
                * (resources.WOLF_MORTALITY_RATE or 0.002)
                * (1.2 - math.min(0.7, prey_factor * 0.35))
                * eco_dt
            if campfire_tile_boost[i] then
                wolf_mortality = wolf_mortality + (current_wolves * 0.10 * eco_dt)
            end
            tile.wolves = math.max(0, math.min(wolf_capacity, current_wolves + wolf_repro - wolf_mortality))
        else
            tile.wolves = math.max(0, (tile.wolves or 0) - ((tile.wolves or 0) * 0.04 * eco_dt))
        end
        if tile.type_id == "forest" then
            tile.pine_wood = math.min(pine_wood_max, (tile.pine_wood or 0) + pine_wood_growth)
        end

    end
    for idx, delta in pairs(rabbit_spread) do
        local tile = w.tiles[idx]
        if tile then
            local cap = ((entities_cfg.RESOURCE or {}).WILDLIFE_MAX or 1.0) * ((tile.type_id == "forest") and 0.65 or 1.0)
            tile.rabbit_young = math.max(0, (tile.rabbit_young or 0) + (delta.young or 0))
            tile.rabbit_adult = math.max(0, (tile.rabbit_adult or 0) + (delta.adult or 0))
            tile.rabbit_old = math.max(0, (tile.rabbit_old or 0) + (delta.old or 0))
            local total_rabbits = (tile.rabbit_young or 0) + (tile.rabbit_adult or 0) + (tile.rabbit_old or 0)
            if total_rabbits > cap then
                local scale = cap / math.max(0.001, total_rabbits)
                tile.rabbit_young = tile.rabbit_young * scale
                tile.rabbit_adult = tile.rabbit_adult * scale
                tile.rabbit_old = tile.rabbit_old * scale
                total_rabbits = cap
            end
            tile.wildlife = total_rabbits
        end
    end
    local should_refresh_stats = (state.tick % math.max(1, math.floor(state.stats_stride or 1))) == 0
    if should_refresh_stats then
        for i = 1, tile_count do
            local tile = w.tiles[i]
            tile.food = tile.apple_fruit or 0
            total_food = total_food + tile.food
            total_apples = total_apples + (tile.apple_fruit or 0)
            total_wood = total_wood + (tile.apple_wood or 0) + (tile.pine_wood or 0)
            total_wildlife = total_wildlife + (tile.wildlife or 0)
            total_wolves = total_wolves + (tile.wolves or 0)
        end
        w.stats.avg_food = (tile_count > 0) and (total_food / tile_count) or 0
        w.stats.total_apples = total_apples
        w.stats.total_wood = total_wood
        w.stats.total_wildlife = total_wildlife
        w.stats.total_wolves = total_wolves
    end

    local before_pop = w.stats.population or 0
    local before_births = w.stats.births or 0
    local before_deaths = w.stats.deaths or 0
    entities.update(w, dt)
    local born = entities.try_reproduce(w, dt)
    local built_campfires = entities.try_build_campfires(w, dt)
    local built_shelters = entities.try_build_shelters(w, dt)
    state.last_births = born
    state.last_campfires = built_campfires
    state.last_shelters = built_shelters

    local after_pop = w.stats.population or 0
    if (w.stats.peak_population or 0) < after_pop then
        w.stats.peak_population = after_pop
    end
    if (w.stats.min_population or 0) == 0 then
        w.stats.min_population = after_pop
    else
        w.stats.min_population = math.min(w.stats.min_population, after_pop)
    end

    local day_progress = (w.calendar and w.calendar.day_progress) or 0
    if day_progress < dt then
        local delta_births = (w.stats.births or 0) - before_births
        local delta_deaths = (w.stats.deaths or 0) - before_deaths
        if delta_births > 0 or delta_deaths > 0 then
            world.push_event(
                w,
                "day_summary",
                string.format("Day %d summary: +%d births / -%d deaths / pop %d", w.calendar.total_days or 1, delta_births, delta_deaths, after_pop),
                "info"
            )
        end
        if w.stats.avg_food and w.stats.avg_food < 0.22 and after_pop > before_pop then
            world.push_event(w, "warning", "Population rose during low food period; starvation risk increasing.", "warn")
        end
        if fruit_spawned > 0.2 then
            entity_events.fruit_spawn(w, fruit_spawned)
        end
    end

    state.tick = state.tick + 1
    state.eco_phase = (eco_phase + 1) % eco_slices
    w.tick = state.tick
end

function sim.update(state, w, dt)
    local max_acc = state.max_accumulator or (state.step_dt * (state.max_steps_per_frame + 1))
    state.accumulator = math.min(max_acc, state.accumulator + dt)
    local steps = 0

    while state.accumulator >= state.step_dt and steps < state.max_steps_per_frame do
        sim.step(state, w, state.step_dt)
        state.accumulator = state.accumulator - state.step_dt
        steps = steps + 1
    end

    return steps
end

return sim
