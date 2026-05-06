local world = require("src.core.world")
local config = require("src.data.config_entities")
local requirements = require("src.core.entity_requirements")
local entity_events = require("src.core.entities_events")
local blackboard = require("src.core.blackboard")

local M = {}

local function next_building_uid(w)
    w.stats.next_building_uid = (w.stats.next_building_uid or 0) + 1
    return w.stats.next_building_uid
end

local function ensure_job_queue(w)
    local board = blackboard.get(w)
    w.jobs = (board and board.jobs) or w.jobs or {}
    if board then
        board.jobs = w.jobs
    end
    w.stats.next_job_id = (w.stats and w.stats.next_job_id) or 0
end

local function next_job_id(w)
    ensure_job_queue(w)
    w.stats.next_job_id = (w.stats.next_job_id or 0) + 1
    return w.stats.next_job_id
end

local function enqueue_construction_job(w, building)
    if not (building and building.uid) then
        return
    end
    ensure_job_queue(w)
    for i = 1, #w.jobs do
        local job = w.jobs[i]
        if job and job.kind == "deliver_wood_construction" and job.target_uid == building.uid then
            return
        end
    end
    local priority = 100
    if building.kind == "shelter" then
        priority = 120
    elseif building.kind == "campfire" then
        priority = 90
    end
    blackboard.add_job(w, {
        id = next_job_id(w),
        kind = "deliver_wood_construction",
        target_uid = building.uid,
        x = building.x,
        y = building.y,
        priority = priority,
        claimed_by = nil,
        claim_expires_tick = nil,
    })
end

local function has_job(w, kind, target_uid)
    for i = 1, #w.jobs do
        local job = w.jobs[i]
        if job and job.kind == kind and job.target_uid == target_uid then
            return true
        end
    end
    return false
end

local function enqueue_shelter_food_jobs(w)
    ensure_job_queue(w)
    local buildings = w.buildings or {}
    local build_cfg = config.BUILD
    local trigger_stock = build_cfg.SHELTER_SUPPORT_TRIGGER_STOCK
    local max_food_stock = build_cfg.SHELTER_MAX_FOOD_STOCK
    for i = 1, #buildings do
        local b = buildings[i]
        if b and b.kind == "shelter" and (not b.under_construction) then
            b.food_stock = b.food_stock or 0
            if b.food_stock < trigger_stock and b.food_stock < max_food_stock then
                if not has_job(w, "deliver_food_shelter", b.uid) then
                    blackboard.add_job(w, {
                        id = next_job_id(w),
                        kind = "deliver_food_shelter",
                        target_uid = b.uid,
                        x = b.x,
                        y = b.y,
                        priority = 80,
                        claimed_by = nil,
                        claim_expires_tick = nil,
                    })
                end
            end
        end
    end
end

local function has_nearby_building(w, x, y, min_spacing, kind_filter)
    local min_d2 = min_spacing * min_spacing
    local buildings = w.buildings or {}
    for i = 1, #buildings do
        local b = buildings[i]
        if b and ((not kind_filter) or b.kind == kind_filter) then
            local dx = (x or 0) - (b.x or 0)
            local dy = (y or 0) - (b.y or 0)
            if (dx * dx + dy * dy) <= min_d2 then
                return true
            end
        end
    end
    return false
end

local function count_homeless_entities(w)
    local buildings = w.buildings or {}
    local shelter_capacity = config.BUILD.SHELTER_CAPACITY
    local shelters = {}

    for i = 1, #buildings do
        local b = buildings[i]
        if b and b.kind == "shelter" and (not b.under_construction) then
            b.residents = {}
            shelters[b.id] = b
        end
    end

    for _, e in pairs(w.entities or {}) do
        if e and e.alive and e.home_shelter_id then
            local home = shelters[e.home_shelter_id]
            if home and #home.residents < shelter_capacity then
                home.residents[#home.residents + 1] = e.id
            else
                e.home_shelter_id = nil
            end
        end
    end

    for _, e in pairs(w.entities or {}) do
        if e and e.alive and not e.home_shelter_id then
            local best
            local best_d2 = math.huge
            for _, shelter in pairs(shelters) do
                if shelter and #shelter.residents < shelter_capacity then
                    local dx = (e.x or 0) - (shelter.x or 0)
                    local dy = (e.y or 0) - (shelter.y or 0)
                    local d2 = dx * dx + dy * dy
                    if d2 < best_d2 then
                        best = shelter
                        best_d2 = d2
                    end
                end
            end
            if best then
                e.home_shelter_id = best.id
                best.residents[#best.residents + 1] = e.id
            end
        end
    end

    local homeless = 0
    for _, e in pairs(w.entities or {}) do
        if e and e.alive and not e.home_shelter_id then
            homeless = homeless + 1
        end
    end
    return homeless
end

local function get_pending_shelter_capacity(w)
    local buildings = w.buildings or {}
    local pending_capacity = 0
    local default_capacity = config.BUILD.SHELTER_CAPACITY
    for i = 1, #buildings do
        local b = buildings[i]
        if b and b.kind == "shelter" and b.under_construction then
            pending_capacity = pending_capacity + (b.capacity or default_capacity)
        end
    end
    return pending_capacity
end

local function find_nearest_campfire(w, e, max_range, completed_only)
    local buildings = w.buildings or {}
    local best
    local best_d2 = math.huge
    local max_d2 = max_range and (max_range * max_range) or math.huge
    for i = 1, #buildings do
        local b = buildings[i]
        if b and b.kind == "campfire" and ((not completed_only) or not b.under_construction) then
            local dx = (e.x or 0) - (b.x or 0)
            local dy = (e.y or 0) - (b.y or 0)
            local d2 = dx * dx + dy * dy
            if d2 <= max_d2 and d2 < best_d2 then
                best = b
                best_d2 = d2
            end
        end
    end
    return best
end

local function is_walkable_build_site(w, x, y)
    local gx = math.floor(x)
    local gy = math.floor(y)
    local tile = world.get_tile(w, gx, gy)
    local def = tile and world.get_tile_def(tile.type_id)
    return def and def.walkable
end

local function find_shelter_build_site(w, e, min_spacing)
    if not (w and e) then
        return nil, nil
    end

    if is_walkable_build_site(w, e.x, e.y) and (not has_nearby_building(w, e.x, e.y, min_spacing)) then
        return e.x, e.y
    end

    local cx = math.floor(e.x)
    local cy = math.floor(e.y)
    local search_radius = math.max(math.ceil(min_spacing) + 3, 10)
    local best_x
    local best_y
    local best_d2 = math.huge

    for gy = math.max(1, cy - search_radius), math.min(w.height, cy + search_radius) do
        for gx = math.max(1, cx - search_radius), math.min(w.width, cx + search_radius) do
            local x = gx + 0.5
            local y = gy + 0.5
            if is_walkable_build_site(w, x, y) and (not has_nearby_building(w, x, y, min_spacing)) then
                local dx = x - e.x
                local dy = y - e.y
                local d2 = dx * dx + dy * dy
                if d2 < best_d2 then
                    best_d2 = d2
                    best_x = x
                    best_y = y
                end
            end
        end
    end

    return best_x, best_y
end

function M.try_build_campfires(w, game_day_delta)
    local day_delta = math.max(0, game_day_delta or 0)
    local build_cfg = config.BUILD or {}
    local built = 0
    local max_per_step = math.max(1, build_cfg.CAMPFIRE_MAX_PER_STEP)
    local min_spacing = build_cfg.CAMPFIRE_MIN_SPACING
    enqueue_shelter_food_jobs(w)
    local homeless_count = count_homeless_entities(w)
    if homeless_count <= 0 then
        return 0
    end

    for _, e in pairs(w.entities or {}) do
        if built >= max_per_step then
            break
        end
        if e and e.alive then
            e.build_cooldown = math.max(0, (e.build_cooldown or 0) - day_delta)
            local can_build = requirements.can_do("build_campfire", e)
            if can_build and (e.build_cooldown or 0) <= 0 then
                local hunger_ok = (e.hunger or 0) >= build_cfg.CAMPFIRE_MAX_HUNGER
                local health_ok = (e.health or 0) >= build_cfg.CAMPFIRE_MIN_HEALTH
                local nearby_campfire = find_nearest_campfire(w, e, build_cfg.CAMPFIRE_NEED_RANGE, false)
                if hunger_ok and health_ok and (not nearby_campfire) and (not has_nearby_building(w, e.x, e.y, min_spacing)) then
                    local b = {
                        uid = next_building_uid(w),
                        kind = "campfire",
                        x = e.x,
                        y = e.y,
                        built_day = (w.calendar and w.calendar.total_days) or 1,
                        builder_id = e.id,
                        under_construction = true,
                        required_wood = build_cfg.CAMPFIRE_WOOD_REQUIRED,
                        construction_wood = 0,
                    }
                    w.buildings[#w.buildings + 1] = b
                    enqueue_construction_job(w, b)
                    e.build_cooldown = build_cfg.CAMPFIRE_COOLDOWN
                    e.state = "PlaceCampfireFrame"
                    requirements.grant_knowledge_for_event("build_campfire", e)
                    built = built + 1
                end
            end
        end
    end

    return built
end

function M.try_build_shelters(w, game_day_delta)
    local day_delta = math.max(0, game_day_delta or 0)
    local build_cfg = config.BUILD or {}
    local built = 0
    local max_per_step = math.max(1, build_cfg.SHELTER_MAX_PER_STEP)
    local min_spacing = build_cfg.SHELTER_MIN_SPACING
    local shelter_capacity = build_cfg.SHELTER_CAPACITY
    enqueue_shelter_food_jobs(w)
    local homeless_count = count_homeless_entities(w)
    local pending_capacity = get_pending_shelter_capacity(w)
    local homeless_need = math.max(0, homeless_count - pending_capacity)
    if homeless_need <= 0 then
        return 0
    end

    for _, e in pairs(w.entities or {}) do
        if built >= max_per_step then
            break
        end
        if e and e.alive then
            e.shelter_cooldown = math.max(0, (e.shelter_cooldown or 0) - day_delta)
            local can_build = requirements.can_do("build_shelter", e)
            if can_build and (e.shelter_cooldown or 0) <= 0 and homeless_need > 0 then
                local hunger_ok = (e.hunger or 0) >= build_cfg.SHELTER_MAX_HUNGER
                local health_ok = (e.health or 0) >= build_cfg.SHELTER_MIN_HEALTH
                local build_x, build_y = find_shelter_build_site(w, e, min_spacing)
                if hunger_ok and health_ok and build_x and build_y then
                    local b = {
                        uid = next_building_uid(w),
                        id = #w.buildings + 1,
                        kind = "shelter",
                        x = build_x,
                        y = build_y,
                        built_day = (w.calendar and w.calendar.total_days) or 1,
                        builder_id = e.id,
                        capacity = shelter_capacity,
                        residents = {},
                        food_stock = 0,
                        wood_stock = 0,
                        under_construction = true,
                        required_wood = build_cfg.SHELTER_WOOD_REQUIRED,
                        construction_wood = 0,
                    }
                    w.buildings[#w.buildings + 1] = b
                    enqueue_construction_job(w, b)
                    e.shelter_cooldown = build_cfg.SHELTER_COOLDOWN
                    homeless_need = math.max(0, homeless_need - (b.capacity or shelter_capacity))
                    e.state = "PlaceShelterFrame"
                    requirements.grant_knowledge_for_event("build_shelter", e)
                    built = built + 1
                end
            end
        end
    end

    return built
end

return M
