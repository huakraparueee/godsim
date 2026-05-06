local config = require("src.data.config_entities")
local dna_ranges = require("src.data.config_dna_ranges")

local M = {}

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
    return (rand01() < 0.5) and "male" or "female"
end

function M.spawn(w, x, y, dna, sex, initial_age)
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
        hunger = 100,
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
        current_task = nil,
        explore_target_x = nil,
        explore_target_y = nil,
        explore_event_cooldown = 0,
    }

    if type(initial_age) == "number" then
        w.entities[id].age = math.max(0, initial_age)
    else
        local min_age = config.INITIAL_AGE_MIN
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

return M
