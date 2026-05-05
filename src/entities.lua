--[[
  Phase 2 starter:
  - entities.spawn
  - entities.kill
  - entities.update (basic wander movement)
]]

local entities = {}
local world = require("src.world")
local config = require("src.config_entities")
local entity_events = require("src.entities_events")
local dna_ranges = require("src.config_dna_ranges")
local requirements = require("src.entity_requirements")
local find_shelter_by_id
local CHILD_SURVIVAL_AGE_DAYS = 5 * 365
local CHILD_HUNGER_RATE_FACTOR = 0.5
local CHILD_STARVE_THRESHOLD_BONUS = 0.35
local SHELTER_CONSUME_RATE_PREGNANT = 0.08
local SHELTER_CONSUME_RATE_CHILD = 0.06
local EMERGENCY_FRUIT_RATE = 0.08
local EXPLORE_EVENT_COOLDOWN = 12

local function make_rng(seed)
    if love and love.math and love.math.newRandomGenerator then
        local rg = love.math.newRandomGenerator(seed or os.time())
        return function(min, max)
            if min and max then
                return rg:random(min, max)
            end
            return rg:random()
        end
    end

    local state = tonumber(seed) or os.time()
    return function(min, max)
        state = (1103515245 * state + 12345) % 2147483648
        local r = state / 2147483648
        if min and max then
            return math.floor(min + r * (max - min + 1))
        end
        return r
    end
end

local function default_dna()
    local fallback = dna_ranges.fallback
    return {
        move_speed = fallback.move_speed.default,
        view_distance = fallback.view_distance.default,
        fertility_rate = fallback.fertility_rate.default,
        max_health = fallback.max_health.default,
        mutation_factor = fallback.mutation_factor.default,
        strength = fallback.strength.default,
        knowledge = fallback.knowledge.default,
    }
end

local function clamp(v, min_v, max_v)
    if v < min_v then
        return min_v
    end
    if v > max_v then
        return max_v
    end
    return v
end

local function rand01()
    if love and love.math and love.math.random then
        return love.math.random()
    end
    return math.random()
end

local function rand_int(min_v, max_v)
    if max_v < min_v then
        return min_v
    end
    if love and love.math and love.math.random then
        return love.math.random(min_v, max_v)
    end
    return math.random(min_v, max_v)
end

local function is_walkable_tile(w, gx, gy)
    local tile = world.get_tile(w, gx, gy)
    local def = tile and world.get_tile_def(tile.type_id)
    return def and def.walkable
end

local function score_spawn_site(w, gx, gy, radius)
    if not is_walkable_tile(w, gx, gy) then
        return -math.huge
    end

    local score = 0.25
    local resources = config.RESOURCE or {}
    local search_radius = radius or 6
    local min_x = math.max(1, gx - search_radius)
    local max_x = math.min(w.width, gx + search_radius)
    local min_y = math.max(1, gy - search_radius)
    local max_y = math.min(w.height, gy + search_radius)

    for y = min_y, max_y do
        for x = min_x, max_x do
            local tile = world.get_tile(w, x, y)
            if tile then
                local dx = x - gx
                local dy = y - gy
                local distance = math.sqrt(dx * dx + dy * dy)
                if distance <= search_radius then
                    local weight = 1.0 / (1.0 + distance * 0.35)
                    local wood = (tile.apple_wood or 0) + (tile.pine_wood or 0)
                    score = score
                        + ((tile.apple_fruit or 0) * 4.0 * weight)
                        + ((tile.wildlife or 0) * 2.6 * weight)
                        + (wood * 0.35 * weight)
                        - ((tile.wolves or 0) * 2.0 * weight)

                    local def = world.get_tile_def(tile.type_id)
                    if def and def.walkable then
                        score = score + (0.03 * weight)
                    end
                end
            end
        end
    end

    if score < ((resources.WILDLIFE_MIN_TO_HUNT or 0.22) * 0.2) then
        score = score - 0.5
    end
    return score
end

local function find_explore_target(w, e, min_radius, max_radius)
    local cx = math.floor(e.x or 0)
    local cy = math.floor(e.y or 0)
    local best_x
    local best_y
    local best_score = -math.huge
    local tries = 36

    for _ = 1, tries do
        local angle = rand01() * math.pi * 2
        local distance = min_radius + (rand01() * math.max(1, max_radius - min_radius))
        local gx = math.floor(cx + math.cos(angle) * distance)
        local gy = math.floor(cy + math.sin(angle) * distance)
        if world.in_bounds(w, gx, gy) and is_walkable_tile(w, gx, gy) then
            local score = score_spawn_site(w, gx, gy, 5) + (distance * 0.02)
            if score > best_score then
                best_score = score
                best_x = gx + 0.5
                best_y = gy + 0.5
            end
        end
    end

    return best_x, best_y
end

local function shuffle_in_place(list)
    for i = #list, 2, -1 do
        local j = rand_int(1, i)
        list[i], list[j] = list[j], list[i]
    end
end

local function get_dna_profile(sex)
    return dna_ranges[sex] or dna_ranges.fallback
end

local function sanitize_dna(dna, sex)
    local profile = get_dna_profile(sex)
    local src = dna or default_dna()
    return {
        move_speed = clamp(src.move_speed or profile.move_speed.default, profile.move_speed.min, profile.move_speed.max),
        view_distance = clamp(src.view_distance or profile.view_distance.default, profile.view_distance.min, profile.view_distance.max),
        fertility_rate = clamp(src.fertility_rate or profile.fertility_rate.default, profile.fertility_rate.min, profile.fertility_rate.max),
        max_health = clamp(src.max_health or profile.max_health.default, profile.max_health.min, profile.max_health.max),
        mutation_factor = clamp(src.mutation_factor or profile.mutation_factor.default, profile.mutation_factor.min, profile.mutation_factor.max),
        strength = clamp(src.strength or profile.strength.default, profile.strength.min, profile.strength.max),
        knowledge = clamp(src.knowledge or profile.knowledge.default, profile.knowledge.min, profile.knowledge.max),
    }
end

local function normalize_sex(sex)
    if sex == "male" or sex == "female" then
        return sex
    end
    local r = (love and love.math and love.math.random and love.math.random()) or math.random()
    return (r < 0.5) and "male" or "female"
end

local function age_fertility_factor(e)
    if e.sex == "female" then
        if e.age < config.REPRO.FEMALE_MIN_AGE or e.age > config.REPRO.FEMALE_MAX_AGE then
            return 0
        end
        local mid = (config.REPRO.FEMALE_MIN_AGE + config.REPRO.FEMALE_MAX_AGE) * 0.5
        local span = (config.REPRO.FEMALE_MAX_AGE - config.REPRO.FEMALE_MIN_AGE) * 0.5
        local t = math.abs((e.age - mid) / math.max(0.001, span))
        return math.max(0.15, 1.0 - (t * 0.7))
    end
    if e.age < config.REPRO.MALE_MIN_AGE then
        return 0
    end
    local male_decline_start = 55 * 365
    local older_penalty = 0
    if e.age > male_decline_start then
        older_penalty = ((e.age - male_decline_start) / 365) * 0.06
    end
    return math.max(0.2, 1.0 - older_penalty)
end

local function can_mate(w, e)
    if not (e and e.alive) then
        return false
    end
    if e.sex == "male" then
        local ok = requirements.can_do("reproduce_male", e)
        if not e.home_shelter_id or not find_shelter_by_id(w, e.home_shelter_id) then
            return false
        end
        return ok and (e.reproduction_cooldown or 0) <= 0 and age_fertility_factor(e) > 0
    end
    local ok = requirements.can_do("reproduce_female", e)
    if not e.home_shelter_id or not find_shelter_by_id(w, e.home_shelter_id) then
        return false
    end
    return ok and (e.reproduction_cooldown or 0) <= 0 and not e.pregnant and age_fertility_factor(e) > 0
end

local function can_carry_pregnancy(e)
    if not (e and e.alive and e.sex == "female") then
        return false
    end
    local max_hp = (e.dna and e.dna.max_health) or 100
    return e.hunger <= config.REPRO_MAX_HUNGER and e.health >= (max_hp * config.REPRO_MIN_HEALTH_RATIO)
end

local function has_nearby_building(w, x, y, min_spacing, kind_filter)
    local min_d2 = min_spacing * min_spacing
    local buildings = w.buildings or {}
    for i = 1, #buildings do
        local b = buildings[i]
        if b and ((not kind_filter) or b.kind == kind_filter) then
            local dx = x - (b.x or 0)
            local dy = y - (b.y or 0)
            if (dx * dx + dy * dy) <= min_d2 then
                return true
            end
        end
    end
    return false
end

local function has_completed_campfire_near(w, x, y, radius)
    local radius2 = radius * radius
    local buildings = w.buildings or {}
    for i = 1, #buildings do
        local b = buildings[i]
        if b and b.kind == "campfire" and (not b.under_construction) then
            local dx = x - (b.x or 0)
            local dy = y - (b.y or 0)
            if (dx * dx + dy * dy) <= radius2 then
                return true
            end
        end
    end
    return false
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

    if is_walkable_build_site(w, e.x, e.y) and not has_nearby_building(w, e.x, e.y, min_spacing) then
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
            if is_walkable_build_site(w, x, y) and not has_nearby_building(w, x, y, min_spacing) then
                local dx = x - e.x
                local dy = y - e.y
                local d2 = dx * dx + dy * dy
                if d2 < best_d2 then
                    best_x = x
                    best_y = y
                    best_d2 = d2
                end
            end
        end
    end

    return best_x, best_y
end

local function move_towards(e, tx, ty)
    local dir_x = tx - e.x
    local dir_y = ty - e.y
    local len = math.sqrt(dir_x * dir_x + dir_y * dir_y)
    if len > 0.001 then
        e.vx = dir_x / len
        e.vy = dir_y / len
    end
    return len
end

local function ensure_job_queue(w)
    w.jobs = w.jobs or {}
    w.stats.next_job_id = (w.stats and w.stats.next_job_id) or 0
end

local function next_job_id(w)
    ensure_job_queue(w)
    w.stats.next_job_id = (w.stats.next_job_id or 0) + 1
    return w.stats.next_job_id
end

local function next_building_uid(w)
    w.stats.next_building_uid = (w.stats and w.stats.next_building_uid) or 0
    w.stats.next_building_uid = w.stats.next_building_uid + 1
    return w.stats.next_building_uid
end

local function find_building_by_uid(w, uid)
    if not uid then
        return nil
    end
    local buildings = w.buildings or {}
    for i = 1, #buildings do
        local b = buildings[i]
        if b and b.uid == uid then
            return b
        end
    end
    return nil
end

local function is_job_active(w, job)
    if not (job and job.kind == "deliver_wood_construction") then
        return false
    end
    local b = find_building_by_uid(w, job.target_uid)
    if not b then
        return false
    end
    if not b.under_construction then
        return false
    end
    return (b.construction_wood or 0) < (b.required_wood or 0)
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
    w.jobs[#w.jobs + 1] = {
        id = next_job_id(w),
        kind = "deliver_wood_construction",
        target_uid = building.uid,
        x = building.x,
        y = building.y,
    }
end

local function cleanup_jobs(w)
    ensure_job_queue(w)
    local kept = {}
    for i = 1, #w.jobs do
        local job = w.jobs[i]
        if is_job_active(w, job) then
            kept[#kept + 1] = job
        end
    end
    w.jobs = kept
end

local function find_best_construction_job_target(w, e)
    ensure_job_queue(w)
    local best
    local best_d2 = math.huge
    for i = 1, #w.jobs do
        local job = w.jobs[i]
        if is_job_active(w, job) then
            local b = find_building_by_uid(w, job.target_uid)
            if b then
                local dx = (e.x or 0) - (b.x or 0)
                local dy = (e.y or 0) - (b.y or 0)
                local d2 = dx * dx + dy * dy
                if d2 < best_d2 then
                    best = b
                    best_d2 = d2
                end
            end
        end
    end
    return best
end

local function find_best_wood_tile(w, cx, cy, radius)
    local map_w = w.width
    local map_h = w.height
    local best_idx
    local best_wood = 0
    local best_kind = "pine"
    local min_y = math.max(1, cy - radius)
    local max_y = math.min(map_h, cy + radius)
    local min_x = math.max(1, cx - radius)
    local max_x = math.min(map_w, cx + radius)
    for gy = min_y, max_y do
        for gx = min_x, max_x do
            local tile, idx = world.get_tile(w, gx, gy)
            local pine = (tile and tile.pine_wood) or 0
            local apple_wood = (tile and tile.apple_wood) or 0
            local candidate = math.max(pine, apple_wood)
            if candidate > best_wood then
                best_wood = candidate
                best_idx = idx
                best_kind = (pine >= apple_wood) and "pine" or "apple"
            end
        end
    end
    return best_idx, best_kind, best_wood
end

local function find_best_wildlife_tile(w, cx, cy, radius)
    local map_w = w.width
    local map_h = w.height
    local best_idx
    local best_wildlife = 0
    local min_y = math.max(1, cy - radius)
    local max_y = math.min(map_h, cy + radius)
    local min_x = math.max(1, cx - radius)
    local max_x = math.min(map_w, cx + radius)
    for gy = min_y, max_y do
        for gx = min_x, max_x do
            local tile, idx = world.get_tile(w, gx, gy)
            local wildlife = (tile and tile.wildlife) or 0
            if wildlife > best_wildlife then
                best_wildlife = wildlife
                best_idx = idx
            end
        end
    end
    return best_idx, best_wildlife
end

local function find_best_wolf_tile(w, cx, cy, radius)
    local map_w = w.width
    local map_h = w.height
    local best_idx
    local best_wolves = 0
    local avoid_range = ((config.RESOURCE or {}).WOLF_CAMPFIRE_AVOID_RANGE or 5.0)
    local min_y = math.max(1, cy - radius)
    local max_y = math.min(map_h, cy + radius)
    local min_x = math.max(1, cx - radius)
    local max_x = math.min(map_w, cx + radius)
    for gy = min_y, max_y do
        for gx = min_x, max_x do
            local tile, idx = world.get_tile(w, gx, gy)
            local wolves = (tile and tile.wolves) or 0
            if wolves > best_wolves and not has_completed_campfire_near(w, gx, gy, avoid_range) then
                best_wolves = wolves
                best_idx = idx
            end
        end
    end
    return best_idx, best_wolves
end

local function harvest_rabbits(tile, amount)
    if not tile or amount <= 0 then
        return 0
    end
    if (not tile.rabbit_young) and (not tile.rabbit_adult) and (not tile.rabbit_old) and (tile.wildlife or 0) > 0 then
        tile.rabbit_young = (tile.wildlife or 0) * 0.20
        tile.rabbit_adult = (tile.wildlife or 0) * 0.70
        tile.rabbit_old = (tile.wildlife or 0) * 0.10
    end

    local remaining = amount
    local taken = 0
    local from_adult = math.min(tile.rabbit_adult or 0, remaining)
    tile.rabbit_adult = math.max(0, (tile.rabbit_adult or 0) - from_adult)
    remaining = remaining - from_adult
    taken = taken + from_adult

    local from_old = math.min(tile.rabbit_old or 0, remaining)
    tile.rabbit_old = math.max(0, (tile.rabbit_old or 0) - from_old)
    remaining = remaining - from_old
    taken = taken + from_old

    local from_young = math.min(tile.rabbit_young or 0, remaining)
    tile.rabbit_young = math.max(0, (tile.rabbit_young or 0) - from_young)
    taken = taken + from_young

    tile.wildlife = (tile.rabbit_young or 0) + (tile.rabbit_adult or 0) + (tile.rabbit_old or 0)
    return taken
end

local function harvest_wolves(tile, amount)
    if not tile or amount <= 0 then
        return 0
    end
    local taken = math.min(tile.wolves or 0, amount)
    tile.wolves = math.max(0, (tile.wolves or 0) - taken)
    return taken
end

local function eat_personal_food(e)
    if not (e and (e.personal_food or 0) > 0 and (e.hunger or 0) > 0) then
        return 0
    end
    local eaten = 1
    e.personal_food = math.max(0, math.floor(e.personal_food or 0) - eaten)
    if eaten <= 0 then
        return 0
    end
    e.hunger = math.max(0, (e.hunger or 0) - eaten * (config.HUNGER_RECOVER_RATE or 1.6))
    local max_hp = (e.dna and e.dna.max_health) or 100
    e.health = math.min(max_hp, (e.health or 0) + eaten * (config.HEALTH_RECOVER_FROM_FOOD or 4.0))
    return eaten
end

find_shelter_by_id = function(w, shelter_id)
    if not shelter_id then
        return nil
    end
    local buildings = w.buildings or {}
    for i = 1, #buildings do
        local b = buildings[i]
        if b and b.kind == "shelter" and (not b.under_construction) and b.id == shelter_id then
            return b
        end
    end
    return nil
end

local function rebuild_shelter_residents(w)
    local shelters = {}
    local buildings = w.buildings or {}
    local capacity = ((config.BUILD or {}).SHELTER_CAPACITY or 4)
    local candidates_by_shelter = {}

    local function resident_priority(e)
        local score = 0
        if (e.home_lock_until_age or 0) > (e.age or 0) then
            -- Locked children must keep home assignment.
            score = score + 1000
        end
        if e.sex == "female" and e.pregnant then
            score = score + 200
        end
        score = score + ((e.age or 0) * 0.0001)
        return score
    end

    for i = 1, #buildings do
        local b = buildings[i]
        if b and b.kind == "shelter" and (not b.under_construction) then
            b.residents = {}
            b.food_stock = b.food_stock or 0
            b.wood_stock = b.wood_stock or 0
            shelters[b.id] = b
            candidates_by_shelter[b.id] = {}
        end
    end

    for _, e in pairs(w.entities) do
        if e and e.alive and e.home_shelter_id then
            if shelters[e.home_shelter_id] then
                local list = candidates_by_shelter[e.home_shelter_id]
                list[#list + 1] = e
            else
                e.home_shelter_id = nil
            end
        end
    end

    for shelter_id, list in pairs(candidates_by_shelter) do
        table.sort(list, function(a, b)
            local pa = resident_priority(a)
            local pb = resident_priority(b)
            if pa == pb then
                return (a.id or 0) < (b.id or 0)
            end
            return pa > pb
        end)
        local shelter = shelters[shelter_id]
        for i = 1, #list do
            local e = list[i]
            if i <= capacity then
                shelter.residents[#shelter.residents + 1] = e.id
            else
                e.home_shelter_id = nil
            end
        end
    end
end

local function find_nearest_shelter_with_space(w, e)
    local buildings = w.buildings or {}
    local capacity = ((config.BUILD or {}).SHELTER_CAPACITY or 4)
    local best
    local best_d2 = math.huge
    for i = 1, #buildings do
        local b = buildings[i]
        if b and b.kind == "shelter" and (not b.under_construction) and (b.residents and #b.residents < capacity) then
            local dx = e.x - b.x
            local dy = e.y - b.y
            local d2 = dx * dx + dy * dy
            if d2 < best_d2 then
                best = b
                best_d2 = d2
            end
        end
    end
    return best
end

local function shelter_sex_counts(w, shelter)
    local male = 0
    local female = 0
    if not (shelter and shelter.residents) then
        return male, female
    end
    for i = 1, #shelter.residents do
        local resident = w.entities[shelter.residents[i]]
        if resident and resident.alive then
            if resident.sex == "male" then
                male = male + 1
            elseif resident.sex == "female" then
                female = female + 1
            end
        end
    end
    return male, female
end

local function can_entity_leave_home(e)
    if not e then
        return false
    end
    local lock_age = e.home_lock_until_age or 0
    return (e.age or 0) >= lock_age
end

local function try_evict_random_resident_from_shelter(w, shelter, protected_entity_ids)
    if not (shelter and shelter.residents) then
        return nil
    end
    local protected = protected_entity_ids or {}
    local male, female = shelter_sex_counts(w, shelter)
    local candidates = {}
    for i = 1, #shelter.residents do
        local resident_id = shelter.residents[i]
        local resident = w.entities[resident_id]
        if resident and resident.alive and resident.home_shelter_id == shelter.id and not protected[resident_id] and can_entity_leave_home(resident) then
            local after_male = male - ((resident.sex == "male") and 1 or 0)
            local after_female = female - ((resident.sex == "female") and 1 or 0)
            if after_male >= 1 and after_female >= 1 then
                candidates[#candidates + 1] = resident
            end
        end
    end
    if #candidates <= 0 then
        return nil
    end
    shuffle_in_place(candidates)
    local evicted = candidates[1]
    evicted.home_shelter_id = nil
    return evicted
end

local function assign_newborn_to_mother_shelter_with_right(w, newborn, mother)
    if not (newborn and mother and mother.home_shelter_id) then
        return
    end
    local shelter = find_shelter_by_id(w, mother.home_shelter_id)
    if not shelter then
        return
    end
    local capacity = ((config.BUILD or {}).SHELTER_CAPACITY or 4)
    newborn.home_shelter_id = shelter.id
    newborn.home_lock_until_age = 3 * 365
    rebuild_shelter_residents(w)
    if shelter.residents and #shelter.residents > capacity then
        try_evict_random_resident_from_shelter(w, shelter, {
            [newborn.id] = true,
            [mother.id] = true,
        })
        rebuild_shelter_residents(w)
    end
end

local function find_best_shelter_for_entity(w, e)
    local buildings = w.buildings or {}
    local capacity = ((config.BUILD or {}).SHELTER_CAPACITY or 4)
    local best
    local best_score = math.huge
    for i = 1, #buildings do
        local b = buildings[i]
        if b and b.kind == "shelter" and (not b.under_construction) and (b.residents and #b.residents < capacity) then
            local dx = (e.x or 0) - (b.x or 0)
            local dy = (e.y or 0) - (b.y or 0)
            local d2 = dx * dx + dy * dy
            local male, female = shelter_sex_counts(w, b)
            local opposite_bonus = 1.0
            if e.sex == "male" and female > 0 then
                opposite_bonus = 0.65
            elseif e.sex == "female" and male > 0 then
                opposite_bonus = 0.65
            end
            local score = d2 * opposite_bonus
            if score < best_score then
                best = b
                best_score = score
            end
        end
    end
    return best
end

local function assign_homeless_to_available_shelters(w)
    rebuild_shelter_residents(w)
    for _, e in pairs(w.entities) do
        if e and e.alive and not e.home_shelter_id then
            local shelter = find_best_shelter_for_entity(w, e)
            if shelter then
                e.home_shelter_id = shelter.id
                shelter.residents = shelter.residents or {}
                shelter.residents[#shelter.residents + 1] = e.id
            end
        end
    end
end

local function is_entity_inside_shelter(e, shelter)
    if not (e and shelter) then
        return false
    end
    local dx = (e.x or 0) - (shelter.x or 0)
    local dy = (e.y or 0) - (shelter.y or 0)
    return (dx * dx + dy * dy) <= (0.9 * 0.9)
end

local function is_entity_outside_home(w, e)
    local home = e and find_shelter_by_id(w, e.home_shelter_id)
    if not home then
        return true
    end
    return not is_entity_inside_shelter(e, home)
end

local function try_invite_outside_home_encounters(w, dt)
    local social_cfg = config.SOCIAL or {}
    local invite_range = social_cfg.INVITE_HOME_RANGE or 1.6
    local invite_range2 = invite_range * invite_range
    local max_invites = math.max(1, social_cfg.INVITE_HOME_MAX_PER_STEP or 1)
    local cooldown = social_cfg.INVITE_HOME_COOLDOWN or 90
    local capacity = ((config.BUILD or {}).SHELTER_CAPACITY or 4)
    local invites = 0

    for _, e in pairs(w.entities) do
        if e and e.alive then
            e.invite_home_cooldown = math.max(0, (e.invite_home_cooldown or 0) - dt)
        end
    end

    for _, male in pairs(w.entities) do
        if invites >= max_invites then
            break
        end
        if male and male.alive
            and male.sex == "male"
            and (male.age or 0) >= config.REPRO.MALE_MIN_AGE
            and (male.invite_home_cooldown or 0) <= 0
            and can_entity_leave_home(male)
            and is_entity_outside_home(w, male) then
            local shelter = find_shelter_by_id(w, male.home_shelter_id)
            if shelter and shelter.residents and #shelter.residents < capacity then
                for _, female in pairs(w.entities) do
                    if female and female.alive
                        and female.sex == "female"
                        and female.home_shelter_id ~= shelter.id
                        and (female.age or 0) >= config.REPRO.FEMALE_MIN_AGE
                        and (female.invite_home_cooldown or 0) <= 0
                        and can_entity_leave_home(female)
                        and is_entity_outside_home(w, female) then
                        local dx = (male.x or 0) - (female.x or 0)
                        local dy = (male.y or 0) - (female.y or 0)
                        if (dx * dx + dy * dy) <= invite_range2 then
                            female.home_shelter_id = shelter.id
                            shelter.residents[#shelter.residents + 1] = female.id
                            male.invite_home_cooldown = cooldown
                            female.invite_home_cooldown = cooldown
                            male.state = "InviteHome"
                            female.state = "MoveIn"
                            entity_events.home_invite(w, male.name, female.name, shelter.id)
                            invites = invites + 1
                            rebuild_shelter_residents(w)
                            break
                        end
                    end
                end
            end
        end
    end

    return invites
end

local function shelter_has_pregnant_resident(w, shelter)
    if not (shelter and shelter.residents) then
        return false
    end
    for i = 1, #shelter.residents do
        local resident = w.entities[shelter.residents[i]]
        if resident and resident.alive and resident.sex == "female" and resident.pregnant then
            return true
        end
    end
    return false
end

local function find_support_target_shelter(w, e)
    local buildings = w.buildings or {}
    local trigger_stock = ((config.BUILD or {}).SHELTER_SUPPORT_TRIGGER_STOCK or 1.2)
    local best
    local best_d2 = math.huge
    for i = 1, #buildings do
        local b = buildings[i]
        if b and b.kind == "shelter" and (not b.under_construction) and (b.food_stock or 0) < trigger_stock then
            local has_resident = true
            if has_resident then
                local need_score = trigger_stock - (b.food_stock or 0)
                if shelter_has_pregnant_resident(w, b) then
                    need_score = need_score + 0.6
                end
            local dx = e.x - b.x
            local dy = e.y - b.y
            local d2 = dx * dx + dy * dy
                -- prioritize urgent shelters (pregnant resident / lower stock), then distance.
                local adjusted_d2 = d2 / math.max(0.2, need_score)
            if adjusted_d2 < best_d2 then
                best = b
                    best_d2 = adjusted_d2
                end
            end
        end
    end
    return best
end

local function find_wood_target_building(w, e)
    local buildings = w.buildings or {}
    local trigger_stock = ((config.BUILD or {}).SHELTER_WOOD_TRIGGER_STOCK or 0.9)
    local best
    local best_d2 = math.huge
    for i = 1, #buildings do
        local b = buildings[i]
        local needs_wood = false
        local need_factor = 1.0
        if b and b.under_construction and (b.construction_wood or 0) < (b.required_wood or 0) then
            needs_wood = true
            need_factor = 1.8
        elseif b and b.kind == "shelter" and (not b.under_construction) and (b.wood_stock or 0) < trigger_stock then
            needs_wood = true
        end
        if needs_wood then
            local dx = e.x - b.x
            local dy = e.y - b.y
            local d2 = dx * dx + dy * dy
            local adjusted_d2 = d2 / need_factor
            if adjusted_d2 < best_d2 then
                best = b
                best_d2 = adjusted_d2
            end
        end
    end
    return best
end

local function try_finish_construction(w, b, actor_name)
    if not (b and b.under_construction) then
        return false
    end
    local required = b.required_wood or 0
    local current = b.construction_wood or 0
    if current < required then
        return false
    end
    b.under_construction = false
    b.completed_day = (w.calendar and w.calendar.total_days) or 1
    if b.kind == "campfire" then
        w.stats.campfires_built = (w.stats.campfires_built or 0) + 1
        entity_events.campfire_built(w, actor_name or "unit", b.x, b.y)
    elseif b.kind == "shelter" then
        w.stats.shelters_built = (w.stats.shelters_built or 0) + 1
        entity_events.shelter_built(w, actor_name or "unit", b.x, b.y)
        assign_homeless_to_available_shelters(w)
    end
    cleanup_jobs(w)
    return true
end

local function count_homeless_entities(w)
    local homeless = 0
    for _, e in pairs(w.entities) do
        if e and e.alive and not e.home_shelter_id then
            homeless = homeless + 1
        end
    end
    return homeless
end

local function get_pending_shelter_capacity(w)
    local buildings = w.buildings or {}
    local pending_capacity = 0
    local active_sites = 0
    local default_capacity = ((config.BUILD or {}).SHELTER_CAPACITY or 4)
    for i = 1, #buildings do
        local b = buildings[i]
        if b and b.kind == "shelter" and b.under_construction then
            pending_capacity = pending_capacity + (b.capacity or default_capacity)
            active_sites = active_sites + 1
        end
    end
    return pending_capacity, active_sites
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
    return best, math.sqrt(best_d2)
end

local function try_rest_at_campfire(w, e, dt)
    if not (w and e and e.alive) then
        return false
    end
    if (e.hunger or 0) >= config.EAT_TRIGGER_HUNGER then
        return false
    end

    local build_cfg = config.BUILD or {}
    local max_hp = (e.dna and e.dna.max_health) or 100
    local health_ratio = (e.health or 0) / math.max(1, max_hp)
    local needs_rest = (not e.home_shelter_id) or health_ratio < (build_cfg.CAMPFIRE_REST_HEALTH_RATIO or 0.75)
    if not needs_rest then
        return false
    end

    local campfire, distance = find_nearest_campfire(w, e, build_cfg.CAMPFIRE_ATTRACT_RANGE or 12.0, true)
    if not campfire then
        return false
    end

    local use_radius = build_cfg.CAMPFIRE_USE_RADIUS or 3.0
    if distance > use_radius then
        move_towards(e, campfire.x, campfire.y)
        e.state = "SeekCampfire"
        return true
    end

    e.vx = 0
    e.vy = 0
    e.health = math.min(max_hp, (e.health or 0) + ((build_cfg.CAMPFIRE_HEALTH_RECOVER or 2.0) * dt))
    e.hunger = math.max(0, (e.hunger or 0) - ((build_cfg.CAMPFIRE_HUNGER_RECOVER or 0.025) * dt))
    local profile = get_dna_profile(e.sex)
    e.knowledge = clamp((e.knowledge or 0) + ((build_cfg.CAMPFIRE_KNOWLEDGE_GAIN or 0.03) * dt), profile.knowledge.min, profile.knowledge.max)
    e.state = "RestAtCampfire"
    return true
end

local function try_wolf_attack(w, e, dt)
    if not (w and e and e.alive) then
        return false
    end
    local resources = config.RESOURCE or {}
    local avoid_range = resources.WOLF_CAMPFIRE_AVOID_RANGE or 5.0
    if has_completed_campfire_near(w, e.x or 0, e.y or 0, avoid_range) then
        return false
    end

    local cx = math.floor(e.x or 0)
    local cy = math.floor(e.y or 0)
    local attack_range = resources.WOLF_ATTACK_RANGE or 1.6
    local best_idx, wolves = find_best_wolf_tile(w, cx, cy, math.max(1, math.ceil(attack_range)))
    if not (best_idx and wolves and wolves >= (resources.WOLF_MIN_TO_HUNT or 0.08)) then
        return false
    end
    local wx, wy = world.to_grid(w, best_idx)
    local dx = (e.x or 0) - wx
    local dy = (e.y or 0) - wy
    if (dx * dx + dy * dy) > (attack_range * attack_range) then
        return false
    end

    local chance = (resources.WOLF_ATTACK_CHANCE or 0.06) * math.max(0.25, wolves) * dt
    if rand01() >= chance then
        return false
    end

    local damage = (resources.WOLF_ATTACK_DAMAGE or 28) * math.max(0.65, math.min(1.5, wolves / math.max(0.001, resources.WOLF_MIN_TO_HUNT or 0.08)))
    e.health = math.max(0, (e.health or 0) - damage)
    e.state = "WolfAttack"
    entity_events.wolf_attack(w, e.name, damage)
    if e.health <= 0 then
        entities.kill(w, e.id, "wolf_attack")
    end
    return true
end

function entities.spawn(w, x, y, dna, sex, initial_age)
    local slot = table.remove(w.free_entity_slots)
    local id = slot or (#w.entities + 1)
    local sx = normalize_sex(sex)
    local prefix = config.NAME_PREFIX[sx] or "Unit"
    local entity_dna = sanitize_dna(dna, sx)
    w.stats.name_seq = (w.stats.name_seq or 0) + 1
    w.entities[id] = {
        id = id,
        name = string.format("%s-%03d", prefix, w.stats.name_seq),
        kind = "creature",
        alive = true,
        x = x,
        y = y,
        vx = 0,
        vy = 0,
        age = 0,
        hunger = 0,
        health = entity_dna.max_health,
        state = "Wander",
        sex = sx,
        dna = entity_dna,
        strength = entity_dna.strength,
        knowledge = entity_dna.knowledge,
        wander_timer = 0,
        reproduction_cooldown = 0,
        pregnant = false,
        gestation_timer = 0,
        pregnancy_partner = nil,
        pregnancy_start_day = nil,
        build_cooldown = 0,
        shelter_cooldown = 0,
        invite_home_cooldown = 0,
        home_shelter_id = nil,
        home_lock_until_age = 0,
        personal_food = 0,
        carrying_food = 0,
        carrying_wood = 0,
        explore_target_x = nil,
        explore_target_y = nil,
        explore_event_cooldown = 0,
    }
    if type(initial_age) == "number" then
        w.entities[id].age = math.max(0, initial_age)
    else
        local min_age = config.INITIAL_AGE_MIN or 0
        local max_age = config.INITIAL_AGE_MAX or min_age
        if max_age < min_age then
            max_age = min_age
        end
        w.entities[id].age = min_age + ((max_age - min_age) * rand01())
    end
    w.stats.population = (w.stats.population or 0) + 1
    w.stats.births = (w.stats.births or 0) + 1
    return id
end

function entities.try_build_campfires(w, dt)
    local build_cfg = config.BUILD or {}
    local built = 0
    local max_per_step = math.max(1, build_cfg.CAMPFIRE_MAX_PER_STEP or 1)
    local min_spacing = build_cfg.CAMPFIRE_MIN_SPACING or 4.0
    local homeless_count = count_homeless_entities(w)
    if homeless_count <= 0 then
        return 0
    end

    for _, e in pairs(w.entities) do
        if built >= max_per_step then
            break
        end
        if e and e.alive then
            e.build_cooldown = math.max(0, (e.build_cooldown or 0) - dt)
            local can_build = requirements.can_do("build_campfire", e)
            if can_build and (e.build_cooldown or 0) <= 0 then
                local max_hp = (e.dna and e.dna.max_health) or 100
                local health_ratio = (e.health or 0) / math.max(1, max_hp)
                local hunger_ok = (e.hunger or 0) <= (build_cfg.CAMPFIRE_MAX_HUNGER or 0.65)
                local health_ok = health_ratio >= (build_cfg.CAMPFIRE_MIN_HEALTH_RATIO or 0.4)
                local nearby_campfire = find_nearest_campfire(w, e, build_cfg.CAMPFIRE_NEED_RANGE or 12.0, false)
                if hunger_ok and health_ok and (not nearby_campfire) and not has_nearby_building(w, e.x, e.y, min_spacing) then
                    local buildings = w.buildings
                    buildings[#buildings + 1] = {
                        uid = next_building_uid(w),
                        kind = "campfire",
                        x = e.x,
                        y = e.y,
                        built_day = (w.calendar and w.calendar.total_days) or 1,
                        builder_id = e.id,
                        under_construction = true,
                        required_wood = (build_cfg.CAMPFIRE_WOOD_REQUIRED or 6),
                        construction_wood = 0,
                    }
                    enqueue_construction_job(w, buildings[#buildings])
                    e.build_cooldown = build_cfg.CAMPFIRE_COOLDOWN or 90
                    e.state = "PlaceCampfireFrame"
                    requirements.grant_knowledge_for_event("build_campfire", e)
                    built = built + 1
                end
            end
        end
    end

    return built
end

function entities.try_build_shelters(w, dt)
    local build_cfg = config.BUILD or {}
    local built = 0
    local max_per_step = math.max(1, build_cfg.SHELTER_MAX_PER_STEP or 1)
    local min_spacing = build_cfg.SHELTER_MIN_SPACING or 5.0
    local shelter_capacity = build_cfg.SHELTER_CAPACITY or 4
    local homeless_count = count_homeless_entities(w)
    local pending_capacity = get_pending_shelter_capacity(w)
    local homeless_need = math.max(0, homeless_count - pending_capacity)
    if homeless_need <= 0 then
        return 0
    end

    for _, e in pairs(w.entities) do
        if built >= max_per_step then
            break
        end
        if e and e.alive then
            e.shelter_cooldown = math.max(0, (e.shelter_cooldown or 0) - dt)
            local can_build = requirements.can_do("build_shelter", e)
            if can_build
                and (e.shelter_cooldown or 0) <= 0
                and homeless_need > 0 then
                local max_hp = (e.dna and e.dna.max_health) or 100
                local health_ratio = (e.health or 0) / math.max(1, max_hp)
                local hunger_ok = (e.hunger or 0) <= (build_cfg.SHELTER_MAX_HUNGER or 0.55)
                local health_ok = health_ratio >= (build_cfg.SHELTER_MIN_HEALTH_RATIO or 0.55)
                local build_x, build_y = find_shelter_build_site(w, e, min_spacing)
                if hunger_ok and health_ok and build_x and build_y then
                    local buildings = w.buildings
                    buildings[#buildings + 1] = {
                        uid = next_building_uid(w),
                        id = #buildings + 1,
                        kind = "shelter",
                        x = build_x,
                        y = build_y,
                        built_day = (w.calendar and w.calendar.total_days) or 1,
                        builder_id = e.id,
                        capacity = build_cfg.SHELTER_CAPACITY or 4,
                        residents = {},
                        food_stock = 0,
                        wood_stock = 0,
                        under_construction = true,
                        required_wood = (build_cfg.SHELTER_WOOD_REQUIRED or 12),
                        construction_wood = 0,
                    }
                    enqueue_construction_job(w, buildings[#buildings])
                    e.shelter_cooldown = build_cfg.SHELTER_COOLDOWN or 140
                    homeless_need = math.max(0, homeless_need - (buildings[#buildings].capacity or shelter_capacity))
                    e.state = "PlaceShelterFrame"
                    requirements.grant_knowledge_for_event("build_shelter", e)
                    built = built + 1
                end
            end
        end
    end

    return built
end

function entities.get_by_id(w, id)
    if not id then
        return nil
    end
    local e = w.entities[id]
    if e and e.alive then
        return e
    end
    return nil
end

function entities.kill(w, id, reason)
    local e = w.entities[id]
    if not e or not e.alive then
        return false
    end
    e.alive = false
    w.entities[id] = nil
    w.free_entity_slots[#w.free_entity_slots + 1] = id
    w.stats.population = math.max(0, (w.stats.population or 1) - 1)
    w.stats.deaths = (w.stats.deaths or 0) + 1
    if reason == "old_age" then
        w.stats.deaths_old_age = (w.stats.deaths_old_age or 0) + 1
    elseif reason == "starvation" then
        w.stats.deaths_starvation = (w.stats.deaths_starvation or 0) + 1
    end
    entity_events.death(w, e.name, reason, id)
    return true
end

function entities.find_spawn_site(w, seed, preferred_x, preferred_y)
    local rng = make_rng(seed or w.seed)
    local best_x
    local best_y
    local best_score = -math.huge

    local function consider(gx, gy)
        if not world.in_bounds(w, gx, gy) then
            return
        end
        local score = score_spawn_site(w, gx, gy, 6)
        if preferred_x and preferred_y then
            local dx = gx - preferred_x
            local dy = gy - preferred_y
            score = score - (math.sqrt(dx * dx + dy * dy) * 0.015)
        end
        if score > best_score then
            best_score = score
            best_x = gx
            best_y = gy
        end
    end

    if preferred_x and preferred_y then
        local cx = math.floor(preferred_x)
        local cy = math.floor(preferred_y)
        local radius = 24
        for gy = math.max(3, cy - radius), math.min(w.height - 2, cy + radius) do
            for gx = math.max(3, cx - radius), math.min(w.width - 2, cx + radius) do
                consider(gx, gy)
            end
        end
    end

    for _ = 1, 160 do
        local gx = rng(3, math.max(3, w.width - 2))
        local gy = rng(3, math.max(3, w.height - 2))
        consider(gx, gy)
    end

    if best_x and best_y then
        return best_x + 0.5, best_y + 0.5
    end

    local fallback_x = clamp(preferred_x or (w.width * 0.5), 1.0, w.width - 0.001)
    local fallback_y = clamp(preferred_y or (w.height * 0.5), 1.0, w.height - 0.001)
    return fallback_x, fallback_y
end

function entities.seed_random(w, count, seed)
    local rng = make_rng(seed or w.seed)
    for i = 1, count do
        local sx, sy = entities.find_spawn_site(w, (seed or w.seed) + (i * 97))
        local sex = (rng() < 0.5) and "male" or "female"
        entities.spawn(w, sx + ((rng() - 0.5) * 0.8), sy + ((rng() - 0.5) * 0.8), nil, sex)
    end
end

function entities.count_by_sex(w)
    local male = 0
    local female = 0
    local other = 0
    local total = 0
    for _, e in pairs(w.entities) do
        if e and e.alive then
            total = total + 1
            if e.sex == "male" then
                male = male + 1
            elseif e.sex == "female" then
                female = female + 1
            else
                other = other + 1
            end
        end
    end
    return total, male, female, other
end

function entities.try_reproduce(w, dt)
    local conceptions = 0

    assign_homeless_to_available_shelters(w)

    for _, e in pairs(w.entities) do
        if e and e.alive then
            e.reproduction_cooldown = math.max(0, (e.reproduction_cooldown or 0) - dt)
            if (not e.home_shelter_id) or (not find_shelter_by_id(w, e.home_shelter_id)) then
                local shelter = find_best_shelter_for_entity(w, e)
                if shelter then
                    e.home_shelter_id = shelter.id
                end
            end
        end
    end

    rebuild_shelter_residents(w)

    local buildings = w.buildings or {}
    for i = 1, #buildings do
        local shelter = buildings[i]
        if shelter and shelter.kind == "shelter" and (not shelter.under_construction) and shelter.residents then
            local males = {}
            local females = {}
            for j = 1, #shelter.residents do
                local resident = w.entities[shelter.residents[j]]
                if resident and resident.alive and resident.home_shelter_id == shelter.id and can_mate(w, resident) then
                    if resident.sex == "male" then
                        males[#males + 1] = resident
                    elseif resident.sex == "female" and can_carry_pregnancy(resident) then
                        females[#females + 1] = resident
                    end
                end
            end

            for j = 1, #females do
                local f = females[j]
                local chosen
                for k = 1, #males do
                    local m = males[k]
                    if m and m.alive and (m.reproduction_cooldown or 0) <= 0 then
                        chosen = m
                        break
                    end
                end

                if chosen then
                    local fertility_m = ((chosen.dna and chosen.dna.fertility_rate) or 0.3) * age_fertility_factor(chosen)
                    local fertility_f = ((f.dna and f.dna.fertility_rate) or 0.3) * age_fertility_factor(f)
                    local health_factor = math.min(1.0, math.max(0.15, (f.health / math.max(1, ((f.dna and f.dna.max_health) or 100)))))
                    local hunger_factor = 1.0 - math.min(0.7, f.hunger)
                    local chance = math.max(0.45, math.min(0.95, ((fertility_m + fertility_f) * 0.5) * health_factor * hunger_factor))
                    if rand01() <= chance then
                        f.pregnant = true
                        f.gestation_timer = config.REPRO.GESTATION_TIME
                        f.pregnancy_partner = chosen.id
                        f.pregnancy_start_day = (w.calendar and w.calendar.total_days) or 1
                        f.reproduction_cooldown = config.REPRO.COOLDOWN_FEMALE
                        chosen.reproduction_cooldown = config.REPRO.COOLDOWN_MALE
                        f.state = "Pregnant"
                        requirements.grant_knowledge_for_event("reproduce_female", f)
                        requirements.grant_knowledge_for_event("reproduce_male", chosen)
                        conceptions = conceptions + 1
                        if conceptions <= 2 then
                            entity_events.pregnancy(w, f.name, chosen.name, f, chosen)
                        end
                    end
                end
            end
        end
    end

    return conceptions
end

function entities.update(w, dt)
    local map_w = w.width
    local map_h = w.height
    cleanup_jobs(w)
    rebuild_shelter_residents(w)
    try_invite_outside_home_encounters(w, dt)

    for _, e in pairs(w.entities) do
        if e and e.alive then
            if not e.home_shelter_id then
                local shelter = find_best_shelter_for_entity(w, e)
                if shelter then
                    e.home_shelter_id = shelter.id
                end
            end
            e.age = e.age + dt
            local hunger_rate = config.HUNGER_RATE
            if (e.age or 0) < CHILD_SURVIVAL_AGE_DAYS then
                hunger_rate = hunger_rate * CHILD_HUNGER_RATE_FACTOR
            end
            e.hunger = e.hunger + (hunger_rate * dt)
            e.explore_event_cooldown = math.max(0, (e.explore_event_cooldown or 0) - dt)
            e.personal_food = math.min(config.PERSONAL_FOOD_CAPACITY or 2, math.floor(e.personal_food or 0))
            local stored_eat_trigger = e.home_shelter_id and config.EAT_TRIGGER_HUNGER or (config.HOMELESS_EAT_TRIGGER_HUNGER or config.EAT_TRIGGER_HUNGER)
            if e.hunger >= stored_eat_trigger and eat_personal_food(e) > 0 then
                e.state = "EatStoredFood"
            end
            e.wander_timer = e.wander_timer - dt

            if e.sex == "female" and e.pregnant then
                if not e.home_shelter_id then
                    local shelter = find_best_shelter_for_entity(w, e)
                    if shelter then
                        e.home_shelter_id = shelter.id
                    end
                end
                e.gestation_timer = math.max(0, (e.gestation_timer or 0) - dt)
                e.hunger = e.hunger + (config.HUNGER_RATE * 0.35 * dt)
                local home = find_shelter_by_id(w, e.home_shelter_id)
                if home then
                    local d_home = move_towards(e, home.x, home.y)
                    if d_home <= 0.9 then
                        e.vx = 0
                        e.vy = 0
                        local consume = math.min(home.food_stock or 0, SHELTER_CONSUME_RATE_PREGNANT * dt)
                        home.food_stock = math.max(0, (home.food_stock or 0) - consume)
                        -- Emergency fallback: when shelter stock is empty, let pregnant residents
                        -- consume a small amount of nearby apples without leaving home area.
                        if consume <= 0.0001 then
                            local cx = math.floor(e.x)
                            local cy = math.floor(e.y)
                            local best_idx
                            local best_fruit = 0
                            for gy = math.max(1, cy - 1), math.min(map_h, cy + 1) do
                                for gx = math.max(1, cx - 1), math.min(map_w, cx + 1) do
                                    local tile, idx = world.get_tile(w, gx, gy)
                                    local fruit = (tile and tile.apple_fruit) or 0
                                    if fruit > best_fruit then
                                        best_fruit = fruit
                                        best_idx = idx
                                    end
                                end
                            end
                            if best_idx and best_fruit > 0 then
                                local tile = w.tiles[best_idx]
                                local emergency_eat = math.min(tile.apple_fruit or 0, EMERGENCY_FRUIT_RATE * dt)
                                tile.apple_fruit = math.max(0, (tile.apple_fruit or 0) - emergency_eat)
                                tile.food = tile.apple_fruit
                                consume = consume + emergency_eat
                            end
                        end
                        e.hunger = math.max(0, e.hunger - consume * config.HUNGER_RECOVER_RATE)
                        e.state = "StayHomePregnant"
                    else
                        -- While returning home, allow small emergency fruit intake nearby.
                        local cx = math.floor(e.x)
                        local cy = math.floor(e.y)
                        local best_idx
                        local best_fruit = 0
                        for gy = math.max(1, cy - 1), math.min(map_h, cy + 1) do
                            for gx = math.max(1, cx - 1), math.min(map_w, cx + 1) do
                                local tile, idx = world.get_tile(w, gx, gy)
                                local fruit = (tile and tile.apple_fruit) or 0
                                if fruit > best_fruit then
                                    best_fruit = fruit
                                    best_idx = idx
                                end
                            end
                        end
                        if best_idx and best_fruit > 0 then
                            local tile = w.tiles[best_idx]
                            local emergency_eat = math.min(tile.apple_fruit or 0, EMERGENCY_FRUIT_RATE * dt)
                            tile.apple_fruit = math.max(0, (tile.apple_fruit or 0) - emergency_eat)
                            tile.food = tile.apple_fruit
                            e.hunger = math.max(0, e.hunger - emergency_eat * config.HUNGER_RECOVER_RATE)
                        end
                        e.state = "GoHomePregnant"
                    end
                else
                    -- No shelter available yet: keep pregnancy alive by allowing nearby foraging.
                    local cx = math.floor(e.x)
                    local cy = math.floor(e.y)
                    local best_idx
                    local best_fruit = 0
                    local vr = math.max(1, math.floor((e.dna and e.dna.view_distance) or 4))
                    local min_y = math.max(1, cy - vr)
                    local max_y = math.min(map_h, cy + vr)
                    local min_x = math.max(1, cx - vr)
                    local max_x = math.min(map_w, cx + vr)
                    for gy = min_y, max_y do
                        for gx = min_x, max_x do
                            local tile, idx = world.get_tile(w, gx, gy)
                            local fruit = (tile and tile.apple_fruit) or 0
                            if fruit > best_fruit then
                                best_fruit = fruit
                                best_idx = idx
                            end
                        end
                    end
                    if best_idx then
                        local tx, ty = world.to_grid(w, best_idx)
                        local len = move_towards(e, tx, ty)
                        local tile = w.tiles[best_idx]
                        if len < 0.9 and tile and (tile.apple_fruit or 0) > 0 then
                            local eaten = math.min(tile.apple_fruit, EMERGENCY_FRUIT_RATE * dt)
                            tile.apple_fruit = tile.apple_fruit - eaten
                            tile.food = tile.apple_fruit
                            e.hunger = math.max(0, e.hunger - eaten * config.HUNGER_RECOVER_RATE)
                            e.state = "PregnantForage"
                        else
                            e.state = "PregnantSeekFood"
                        end
                    else
                        e.state = "PregnantNoShelter"
                    end
                end
                if e.gestation_timer <= 0 then
                    local births = 1
                    local fertility = (e.dna and e.dna.fertility_rate) or 0.3
                    if fertility > 0.55 and rand01() < 0.16 then
                        births = 2
                    end
                    for _ = 1, births do
                        local sex = (rand01() < 0.5) and "male" or "female"
                        local bx = e.x + ((rand01() - 0.5) * 0.7)
                        local by = e.y + ((rand01() - 0.5) * 0.7)
                        local newborn_id = entities.spawn(w, bx, by, nil, sex, 0)
                        local newborn = w.entities[newborn_id]
                        assign_newborn_to_mother_shelter_with_right(w, newborn, e)
                    end
                    e.pregnant = false
                    e.pregnancy_partner = nil
                    e.reproduction_cooldown = config.REPRO.POSTPARTUM_COOLDOWN
                    e.state = "Postpartum"
                    requirements.grant_knowledge_for_event("give_birth", e, births)
                    entity_events.birth(w, e.name, births, e.pregnancy_start_day, (w.calendar and w.calendar.total_days) or 1)
                    e.pregnancy_start_day = nil
                end
            end

            local home_locked = not can_entity_leave_home(e)
            if home_locked then
                local locked_home = find_shelter_by_id(w, e.home_shelter_id)
                if locked_home then
                    local d_home = move_towards(e, locked_home.x, locked_home.y)
                    if d_home <= 0.9 then
                        e.vx = 0
                        e.vy = 0
                        local consume = math.min(locked_home.food_stock or 0, SHELTER_CONSUME_RATE_CHILD * dt)
                        locked_home.food_stock = math.max(0, (locked_home.food_stock or 0) - consume)
                        if consume <= 0.0001 then
                            local cx = math.floor(e.x)
                            local cy = math.floor(e.y)
                            local best_idx
                            local best_fruit = 0
                            for gy = math.max(1, cy - 1), math.min(map_h, cy + 1) do
                                for gx = math.max(1, cx - 1), math.min(map_w, cx + 1) do
                                    local tile, idx = world.get_tile(w, gx, gy)
                                    local fruit = (tile and tile.apple_fruit) or 0
                                    if fruit > best_fruit then
                                        best_fruit = fruit
                                        best_idx = idx
                                    end
                                end
                            end
                            if best_idx and best_fruit > 0 then
                                local tile = w.tiles[best_idx]
                                local emergency_eat = math.min(tile.apple_fruit or 0, EMERGENCY_FRUIT_RATE * dt)
                                tile.apple_fruit = math.max(0, (tile.apple_fruit or 0) - emergency_eat)
                                tile.food = tile.apple_fruit
                                consume = consume + emergency_eat
                            end
                        end
                        e.hunger = math.max(0, e.hunger - consume * config.HUNGER_RECOVER_RATE)
                        e.state = "StayHomeChild"
                    else
                        e.state = "GoHomeChild"
                    end
                else
                    -- If a locked child lost home assignment, try to reassign quickly.
                    local shelter = find_best_shelter_for_entity(w, e)
                    if shelter then
                        e.home_shelter_id = shelter.id
                    end
                    e.vx = 0
                    e.vy = 0
                    e.state = "ChildNeedHome"
                end
            end

            local support_shelter = nil
            local wood_shelter = nil
            local campfire_resting = false
            if not (e.sex == "female" and e.pregnant) and (not home_locked) then
                campfire_resting = try_rest_at_campfire(w, e, dt)
            end
            local doing_support = campfire_resting
            if not (e.sex == "female" and e.pregnant) and (not home_locked) and (not campfire_resting) then
                local self_eat_trigger = e.home_shelter_id and config.EAT_TRIGGER_HUNGER or (config.HOMELESS_EAT_TRIGGER_HUNGER or config.EAT_TRIGGER_HUNGER)
                local hungry_for_self = e.hunger >= self_eat_trigger
                local own_shelter = find_shelter_by_id(w, e.home_shelter_id)
                if not hungry_for_self then
                    local own_trigger_stock = ((config.BUILD or {}).SHELTER_SUPPORT_TRIGGER_STOCK or 1.2)
                    local own_max_food_stock = ((config.BUILD or {}).SHELTER_MAX_FOOD_STOCK or 100)
                    local own_max_wood_stock = ((config.BUILD or {}).SHELTER_MAX_WOOD_STOCK or 100)
                    local construction_target = find_best_construction_job_target(w, e)
                    wood_shelter = construction_target or find_wood_target_building(w, e)
                    local food_low = own_shelter and (own_shelter.food_stock or 0) < own_trigger_stock
                    local food_not_full = own_shelter and (own_shelter.food_stock or 0) < own_max_food_stock
                    local own_wood_not_full = own_shelter and (own_shelter.wood_stock or 0) < own_max_wood_stock

                    -- For non-construction periods, keep topping up own shelter wood
                    -- instead of stopping around low trigger values.
                    if (not construction_target) and own_wood_not_full then
                        wood_shelter = own_shelter
                    end

                    if own_shelter and (not construction_target) and food_not_full and own_wood_not_full then
                        -- Idle rule: keep both stocks full; choose the emptier one first.
                        local food_ratio = (own_shelter.food_stock or 0) / math.max(1, own_max_food_stock)
                        local wood_ratio = (own_shelter.wood_stock or 0) / math.max(1, own_max_wood_stock)
                        if (e.carrying_food or 0) > 0 then
                            support_shelter = own_shelter
                        elseif (e.carrying_wood or 0) > 0 then
                            wood_shelter = own_shelter
                        elseif food_ratio <= wood_ratio then
                            support_shelter = own_shelter
                            wood_shelter = nil
                        else
                            wood_shelter = own_shelter
                        end
                    elseif food_low and wood_shelter then
                        -- While both are needed, split workload to keep both moving.
                        if (e.id or 0) % 2 ~= 0 then
                            support_shelter = own_shelter
                        end
                    elseif food_low then
                        support_shelter = own_shelter
                    elseif food_not_full and (not wood_shelter) then
                        -- If there is no wood work pending, top up food to full.
                        support_shelter = own_shelter
                    end
                    if support_shelter and requirements.can_do("deliver_food", e) then
                        doing_support = true
                        if (e.carrying_food or 0) > 0 then
                            local d_shelter = move_towards(e, support_shelter.x, support_shelter.y)
                            if d_shelter <= 1.0 then
                                local max_food_stock = ((config.BUILD or {}).SHELTER_MAX_FOOD_STOCK or 100)
                                local current_food = support_shelter.food_stock or 0
                                local space_food = math.max(0, max_food_stock - current_food)
                                local delivered = math.min(e.carrying_food, 1, space_food)
                                support_shelter.food_stock = math.min(max_food_stock, current_food + delivered)
                                e.carrying_food = math.max(0, (e.carrying_food or 0) - delivered)
                                e.state = "DeliverFood"
                                if delivered > 0 then
                                    requirements.grant_knowledge_for_event("deliver_food", e)
                                    entity_events.food_delivery(w, e.name, support_shelter.id, delivered)
                                end
                            else
                                e.state = "BringFood"
                            end
                        else
                            local best_idx
                            local best_food = 0
                            local best_hunt_idx
                            local best_wildlife = 0
                            local best_wolf_idx
                            local best_wolves = 0
                            local vr = math.max(1, math.floor((e.dna and e.dna.view_distance) or 4))
                            local cx = math.floor(e.x)
                            local cy = math.floor(e.y)
                            local resources = config.RESOURCE or {}
                            local min_wildlife = resources.WILDLIFE_MIN_TO_HUNT or 0.18
                            local min_wolves = resources.WOLF_MIN_TO_HUNT or 0.08
                            local min_y = math.max(1, cy - vr)
                            local max_y = math.min(map_h, cy + vr)
                            local min_x = math.max(1, cx - vr)
                            local max_x = math.min(map_w, cx + vr)
                            for gy = min_y, max_y do
                                for gx = min_x, max_x do
                                    local tile, idx = world.get_tile(w, gx, gy)
                                    if tile and tile.apple_fruit and tile.apple_fruit > best_food then
                                        best_food = tile.apple_fruit
                                        best_idx = idx
                                    end
                                end
                            end
                            if requirements.can_do("hunt_wildlife", e) then
                                best_hunt_idx, best_wildlife = find_best_wildlife_tile(w, cx, cy, vr)
                            end
                            if requirements.can_do("hunt_wolf", e) then
                                best_wolf_idx, best_wolves = find_best_wolf_tile(w, cx, cy, vr)
                            end
                            local rabbit_value = best_wildlife * (resources.WILDLIFE_FOOD_YIELD or 2.4)
                            local wolf_value = best_wolves * (resources.WOLF_FOOD_YIELD or 5.0)
                            local use_wolf = best_wolf_idx and best_wolves >= min_wolves and wolf_value > math.max(best_food, rabbit_value)
                            local use_hunt = (not use_wolf) and best_hunt_idx and best_wildlife >= min_wildlife and rabbit_value > best_food
                            local target_idx = use_wolf and best_wolf_idx or (use_hunt and best_hunt_idx or best_idx)
                            if target_idx then
                                local tx, ty = world.to_grid(w, target_idx)
                                local len = move_towards(e, tx, ty)
                                local tile = w.tiles[target_idx]
                                if len < 0.9 and use_wolf and tile and (tile.wolves or 0) >= min_wolves then
                                    local hunted = harvest_wolves(tile, math.min(tile.wolves or 0, 0.12))
                                    local meat = hunted * (resources.WOLF_FOOD_YIELD or 5.0)
                                    e.carrying_food = (e.carrying_food or 0) + meat
                                    if meat > 0 then
                                        requirements.grant_knowledge_for_event("hunt_wolf", e)
                                        entity_events.hunt_wolf(w, e.name, meat)
                                    end
                                    e.state = "HuntWolf"
                                elseif len < 0.9 and use_hunt and tile and (tile.wildlife or 0) >= min_wildlife then
                                    local hunted = harvest_rabbits(tile, math.min(tile.wildlife or 0, 0.45))
                                    local meat = hunted * (resources.WILDLIFE_FOOD_YIELD or 2.4)
                                    e.carrying_food = (e.carrying_food or 0) + meat
                                    if meat > 0 then
                                        requirements.grant_knowledge_for_event("hunt_wildlife", e)
                                        entity_events.hunt_wildlife(w, e.name, meat)
                                    end
                                    e.state = "HuntRabbit"
                                elseif len < 0.9 and tile and tile.apple_fruit and tile.apple_fruit > 0 then
                                    local taken = math.min(tile.apple_fruit, 2)
                                    tile.apple_fruit = tile.apple_fruit - taken
                                    tile.food = tile.apple_fruit
                                    e.carrying_food = (e.carrying_food or 0) + taken
                                    if taken > 0 then
                                        requirements.grant_knowledge_for_event("gather_fruit", e)
                                        entity_events.gather_fruit(w, e.name, taken)
                                    end
                                    e.state = "CollectFood"
                                else
                                    e.state = use_wolf and "TrackWolf" or (use_hunt and "TrackRabbit" or "SeekFoodForShelter")
                                end
                            else
                                -- No reachable food candidate for shelter right now:
                                -- let this worker switch to wood in this tick.
                                doing_support = false
                            end
                        end
                    end

                    if (not doing_support) and wood_shelter and requirements.can_do("cut_tree", e) then
                        doing_support = true
                        if (e.carrying_wood or 0) > 0 then
                            local d_wood_shelter = move_towards(e, wood_shelter.x, wood_shelter.y)
                            if d_wood_shelter <= 1.0 then
                                local delivered_wood = 0
                                if wood_shelter.under_construction then
                                    local required = wood_shelter.required_wood or 0
                                    local current = wood_shelter.construction_wood or 0
                                    local need = math.max(0, required - current)
                                    delivered_wood = math.min(e.carrying_wood, 1, need)
                                    wood_shelter.construction_wood = current + delivered_wood
                                else
                                    local max_wood_stock = ((config.BUILD or {}).SHELTER_MAX_WOOD_STOCK or 100)
                                    local current_wood = wood_shelter.wood_stock or 0
                                    local space_wood = math.max(0, max_wood_stock - current_wood)
                                    delivered_wood = math.min(e.carrying_wood, 1, space_wood)
                                    wood_shelter.wood_stock = math.min(max_wood_stock, current_wood + delivered_wood)
                                end
                                e.carrying_wood = math.max(0, (e.carrying_wood or 0) - delivered_wood)
                                if wood_shelter.under_construction then
                                    if try_finish_construction(w, wood_shelter, e.name) then
                                        e.state = "CompleteBuild"
                                    else
                                        e.state = "BuildFrame"
                                    end
                                else
                                    e.state = "DeliverWood"
                                end
                            else
                                if wood_shelter.under_construction then
                                    e.state = "BringWoodToBuild"
                                else
                                    e.state = "BringWood"
                                end
                            end
                        else
                            local best_idx
                            local best_kind = "pine"
                            local vr = math.max(1, math.floor((e.dna and e.dna.view_distance) or 4))
                            local cx = math.floor(e.x)
                            local cy = math.floor(e.y)
                            best_idx, best_kind = find_best_wood_tile(w, cx, cy, vr)

                            -- If local area has no wood and there is an active construction target,
                            -- search a much wider area around the construction site.
                            if (not best_idx) and wood_shelter and wood_shelter.under_construction then
                                local tx = math.floor(wood_shelter.x or cx)
                                local ty = math.floor(wood_shelter.y or cy)
                                local wide_vr = math.max(vr * 3, 12)
                                best_idx, best_kind = find_best_wood_tile(w, tx, ty, wide_vr)
                            end
                            if best_idx then
                                local tx, ty = world.to_grid(w, best_idx)
                                local len = move_towards(e, tx, ty)
                                local tile = w.tiles[best_idx]
                                if len < 0.9 and tile then
                                    local cut = 0
                                    if best_kind == "pine" and (tile.pine_wood or 0) > 0 then
                                        cut = math.min(tile.pine_wood, 1)
                                        tile.pine_wood = tile.pine_wood - cut
                                    elseif (tile.apple_wood or 0) > 0 then
                                        cut = math.min(tile.apple_wood, 1)
                                        tile.apple_wood = tile.apple_wood - cut
                                    end
                                    if cut > 0 then
                                        e.carrying_wood = (e.carrying_wood or 0) + cut
                                        requirements.grant_knowledge_for_event("cut_tree", e)
                                        entity_events.cut_tree(w, e.name, cut, best_kind)
                                        e.state = "CutTree"
                                    else
                                        e.state = "SeekWood"
                                    end
                                else
                                    e.state = "SeekWood"
                                end
                            end
                        end
                    end
                end
            end

            -- Seek and consume food from the best nearby tile when hungry.
            local self_eat_trigger = e.home_shelter_id and config.EAT_TRIGGER_HUNGER or (config.HOMELESS_EAT_TRIGGER_HUNGER or config.EAT_TRIGGER_HUNGER)
            local wants_personal_food = (not e.home_shelter_id) and math.floor(e.personal_food or 0) < (config.PERSONAL_FOOD_CAPACITY or 2)
            if (e.hunger >= self_eat_trigger or wants_personal_food) and (not doing_support) and not (e.sex == "female" and e.pregnant) and (not home_locked) then
                local best_idx
                local best_food = 0
                local best_hunt_idx
                local best_wildlife = 0
                local best_wolf_idx
                local best_wolves = 0
                local vr = math.max(1, math.floor((e.dna and e.dna.view_distance) or 4))
                if not e.home_shelter_id then
                    vr = math.max(vr, math.floor(vr * 1.5))
                end
                local cx = math.floor(e.x)
                local cy = math.floor(e.y)
                local resources = config.RESOURCE or {}
                local min_wildlife = resources.WILDLIFE_MIN_TO_HUNT or 0.18
                local min_wolves = resources.WOLF_MIN_TO_HUNT or 0.08
                local min_y = math.max(1, cy - vr)
                local max_y = math.min(map_h, cy + vr)
                local min_x = math.max(1, cx - vr)
                local max_x = math.min(map_w, cx + vr)

                for gy = min_y, max_y do
                    for gx = min_x, max_x do
                        local tile, idx = world.get_tile(w, gx, gy)
                        if tile and tile.apple_fruit and tile.apple_fruit > best_food then
                            best_food = tile.apple_fruit
                            best_idx = idx
                        end
                    end
                end

                if requirements.can_do("hunt_wildlife", e) then
                    best_hunt_idx, best_wildlife = find_best_wildlife_tile(w, cx, cy, vr)
                end
                if requirements.can_do("hunt_wolf", e) then
                    best_wolf_idx, best_wolves = find_best_wolf_tile(w, cx, cy, vr)
                end
                local rabbit_value = best_wildlife * (resources.WILDLIFE_FOOD_YIELD or 2.4)
                local wolf_value = best_wolves * (resources.WOLF_FOOD_YIELD or 5.0)
                local use_wolf = best_wolf_idx and best_wolves >= min_wolves and wolf_value > math.max(best_food, rabbit_value)
                local use_hunt = (not use_wolf) and best_hunt_idx and best_wildlife >= min_wildlife and rabbit_value > best_food
                local target_idx = use_wolf and best_wolf_idx or (use_hunt and best_hunt_idx or best_idx)

                if target_idx then
                    e.explore_target_x = nil
                    e.explore_target_y = nil
                    local tx, ty = world.to_grid(w, target_idx)
                    local dir_x = tx - e.x
                    local dir_y = ty - e.y
                    local len = math.sqrt(dir_x * dir_x + dir_y * dir_y)
                    if len > 0.001 then
                        e.vx = dir_x / len
                        e.vy = dir_y / len
                    end

                    local tile = w.tiles[target_idx]
                    if len < 0.9 and use_wolf and tile and (tile.wolves or 0) >= min_wolves then
                        local hunted = harvest_wolves(tile, math.min(tile.wolves or 0, 0.10))
                        local meat = hunted * (resources.WOLF_FOOD_YIELD or 5.0)
                        e.hunger = math.max(0, e.hunger - meat * config.HUNGER_RECOVER_RATE)
                        local max_hp = (e.dna and e.dna.max_health) or 100
                        e.health = math.min(max_hp, e.health + meat * config.HEALTH_RECOVER_FROM_FOOD)
                        requirements.grant_knowledge_for_event("hunt_wolf", e)
                        entity_events.hunt_wolf(w, e.name, meat)
                        e.state = "EatWolfMeat"
                    elseif len < 0.9 and use_hunt and tile and (tile.wildlife or 0) >= min_wildlife then
                        local hunted = harvest_rabbits(tile, math.min(tile.wildlife or 0, 0.35))
                        local meat = hunted * (resources.WILDLIFE_FOOD_YIELD or 2.4)
                        e.hunger = math.max(0, e.hunger - meat * config.HUNGER_RECOVER_RATE)
                        local max_hp = (e.dna and e.dna.max_health) or 100
                        e.health = math.min(max_hp, e.health + meat * config.HEALTH_RECOVER_FROM_FOOD)
                        requirements.grant_knowledge_for_event("hunt_wildlife", e)
                        entity_events.hunt_wildlife(w, e.name, meat)
                        e.state = "EatMeat"
                    elseif len < 0.9 and tile and tile.apple_fruit and tile.apple_fruit > 0 then
                        local personal_capacity = config.PERSONAL_FOOD_CAPACITY or 2
                        local personal_food = math.floor(e.personal_food or 0)
                        local personal_space = math.max(0, personal_capacity - personal_food)
                        local taken = math.min(tile.apple_fruit, 1)
                        local eaten = ((e.hunger or 0) >= self_eat_trigger) and 1 or 0
                        local stored = (eaten <= 0 and personal_space > 0) and 1 or 0
                        tile.apple_fruit = tile.apple_fruit - taken
                        tile.food = tile.apple_fruit
                        e.personal_food = math.min(personal_capacity, personal_food + stored)
                        e.hunger = math.max(0, e.hunger - eaten * config.HUNGER_RECOVER_RATE)
                        local max_hp = (e.dna and e.dna.max_health) or 100
                        e.health = math.min(max_hp, e.health + eaten * config.HEALTH_RECOVER_FROM_FOOD)
                        e.state = stored > 0 and "ForageFood" or "Eat"
                    else
                        e.state = use_wolf and "TrackWolf" or (use_hunt and "TrackRabbit" or "SeekFood")
                    end
                else
                    local explore_min = vr + 3
                    local explore_max = math.max(explore_min + 2, vr * 3)
                    if not (e.explore_target_x and e.explore_target_y) then
                        e.explore_target_x, e.explore_target_y = find_explore_target(w, e, explore_min, explore_max)
                        if e.explore_target_x and (e.explore_event_cooldown or 0) <= 0 then
                            entity_events.explore(w, e.name, e.explore_target_x, e.explore_target_y)
                            e.explore_event_cooldown = EXPLORE_EVENT_COOLDOWN
                        end
                    end
                    if e.explore_target_x and e.explore_target_y then
                        local distance = move_towards(e, e.explore_target_x, e.explore_target_y)
                        if distance <= 1.0 then
                            e.explore_target_x = nil
                            e.explore_target_y = nil
                            e.state = "ExploreArrived"
                        else
                            e.state = "ExploreForFood"
                        end
                    else
                        e.state = "NoFoodExploreFailed"
                    end
                end
            end

            try_wolf_attack(w, e, dt)

            if e.hunger > 0.6 then
                local damage = (e.hunger - 0.6) * config.HEALTH_DECAY_FROM_HUNGER * dt
                e.health = math.max(0, e.health - damage)
            end

            -- Slow attribute drift: hard hunger weakens strength, living age increases knowledge.
            local profile = get_dna_profile(e.sex)
            local strength_loss = 0
            if e.hunger > 0.6 then
                strength_loss = ((e.hunger - 0.6) * 0.08 * dt)
            end
            e.strength = clamp((e.strength or ((e.dna and e.dna.strength) or profile.strength.default)) - strength_loss, profile.strength.min, profile.strength.max)
            e.knowledge = clamp((e.knowledge or ((e.dna and e.dna.knowledge) or profile.knowledge.default)) + (0.02 * dt), profile.knowledge.min, profile.knowledge.max)

            if e.wander_timer <= 0 and (not doing_support) and not (e.sex == "female" and e.pregnant) and (not home_locked) then
                local wander_roll = rand01()
                if wander_roll <= 0.05 then
                    local angle = (love.math and love.math.random and love.math.random()) or math.random()
                    angle = angle * math.pi * 2
                    e.vx = math.cos(angle)
                    e.vy = math.sin(angle)
                    e.wander_timer = 0.6 + (((love.math and love.math.random and love.math.random()) or math.random()) * 1.4)
                    if e.state ~= "Eat" and e.state ~= "SeekFood" then
                        e.state = "Wander"
                    end
                else
                    local home = find_shelter_by_id(w, e.home_shelter_id)
                    if home then
                        local d_home = move_towards(e, home.x, home.y)
                        if d_home <= 0.9 then
                            e.vx = 0
                            e.vy = 0
                            if e.state ~= "Eat" and e.state ~= "SeekFood" then
                                e.state = "StayHome"
                            end
                        else
                            if e.state ~= "Eat" and e.state ~= "SeekFood" then
                                e.state = "GoHome"
                            end
                        end
                    else
                        e.vx = 0
                        e.vy = 0
                        if e.state ~= "Eat" and e.state ~= "SeekFood" then
                            e.state = "Idle"
                        end
                    end
                    e.wander_timer = 0.4 + (((love.math and love.math.random and love.math.random()) or math.random()) * 0.8)
                end
            end

            local speed = (e.dna and e.dna.move_speed) or 24
            e.x = e.x + e.vx * speed * dt
            e.y = e.y + e.vy * speed * dt
            e.x = math.max(1.0, math.min(map_w - 0.001, e.x))
            e.y = math.max(1.0, math.min(map_h - 0.001, e.y))

            local starve_threshold = config.STARVE_THRESHOLD
            if (e.age or 0) < CHILD_SURVIVAL_AGE_DAYS then
                starve_threshold = starve_threshold + CHILD_STARVE_THRESHOLD_BONUS
            end

            if e.age >= config.MAX_AGE then
                entities.kill(w, e.id, "old_age")
            elseif e.health <= 0 then
                entities.kill(w, e.id, "starvation")
            elseif e.hunger >= starve_threshold then
                entities.kill(w, e.id, "starvation")
            end
        end
    end
end

return entities
