local spawn = require("src.core.entities.spawn")
local update = require("src.core.entities.update")
local build = require("src.core.entities.build")
local reproduce = require("src.core.entities.reproduce")
local world = require("src.core.world")
local entity_events = require("src.core.entities_events")

local M = {}

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

function M.spawn(...)
    return spawn.spawn(...)
end

function M.update(w, dt)
    local cal = w and w.calendar
    if not cal then
        return
    end

    local current_day = math.floor(cal.total_days or 1)
    local last_day = w._entities_last_processed_day
    if not last_day then
        w._entities_last_processed_day = current_day
        return
    end

    local game_day_delta = math.max(0, current_day - last_day)
    if game_day_delta > 0 then
        w._entities_last_processed_day = current_day
    else
        game_day_delta = 0
    end
    reproduce.update_pregnancies(w, dt, spawn.spawn)
    return update.update(w, game_day_delta, dt, M.kill)
end

function M.kill(...)
    local w, id, reason = ...
    local e = w and w.entities and w.entities[id]
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

function M.try_reproduce(w, dt)
    return reproduce.try_reproduce(w, dt)
end

function M.try_build_campfires(w, dt)
    local cal = w and w.calendar
    local seconds_per_day = (cal and cal.seconds_per_day) or 1
    if seconds_per_day <= 0 then
        seconds_per_day = 1
    end
    local game_day_delta = (dt or 0) / seconds_per_day
    return build.try_build_campfires(w, game_day_delta)
end

function M.try_build_shelters(w, dt)
    local cal = w and w.calendar
    local seconds_per_day = (cal and cal.seconds_per_day) or 1
    if seconds_per_day <= 0 then
        seconds_per_day = 1
    end
    local game_day_delta = (dt or 0) / seconds_per_day
    return build.try_build_shelters(w, game_day_delta)
end

function M.get_by_id(w, id)
    if not w or not w.entities then
        return nil
    end
    return w.entities[id]
end

function M.count_by_sex(w)
    local male, female, other, total = 0, 0, 0, 0
    for _, e in pairs((w and w.entities) or {}) do
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

function M.find_spawn_site(w, seed, preferred_x, preferred_y)
    local rng = make_rng(seed or (w and w.seed))
    local center_x = preferred_x or ((w and w.width or 2) / 2)
    local center_y = preferred_y or ((w and w.height or 2) / 2)
    local best_x, best_y = center_x, center_y
    local best_d2 = math.huge
    for _ = 1, 120 do
        local gx = rng(2, math.max(2, (w.width or 2) - 1))
        local gy = rng(2, math.max(2, (w.height or 2) - 1))
        local tile = world.get_tile(w, gx, gy)
        local def = tile and world.get_tile_def(tile.type_id)
        if def and def.walkable then
            local dx = gx - center_x
            local dy = gy - center_y
            local d2 = (dx * dx + dy * dy)
            if d2 < best_d2 then
                best_d2 = d2
                best_x, best_y = gx, gy
            end
        end
    end
    return best_x + 0.5, best_y + 0.5
end

function M.seed_random(w, count, seed)
    local rng = make_rng(seed or (w and w.seed))
    for i = 1, (count or 0) do
        local sx, sy = M.find_spawn_site(w, (seed or w.seed) + (i * 97))
        local sex = (rng() < 0.5) and "male" or "female"
        M.spawn(w, sx + ((rng() - 0.5) * 0.8), sy + ((rng() - 0.5) * 0.8), nil, sex)
    end
end

return M
