local world = require("src.core.world")
local config = require("src.data.config_entities")
local requirements = require("src.core.entity_requirements")

local M = {}
local FOOD_UNIT_HUNGER_RECOVER = 50

local function eat_personal_food(e)
    if not (e and (e.personal_food or 0) > 0 and (e.hunger or 0) < 100) then
        return 0
    end
    local eaten = 1
    e.personal_food = math.max(0, math.floor(e.personal_food or 0) - eaten)
    if eaten <= 0 then
        return 0
    end
    e.hunger = math.min(100, (e.hunger or 0) + eaten * FOOD_UNIT_HUNGER_RECOVER)
    local max_hp = (e.dna and e.dna.max_health) or 100
    e.health = math.min(max_hp, (e.health or 0) + eaten * (config.HEALTH_RECOVER_FROM_FOOD))
    return eaten
end

function M.update(w, e, dt)
    local step_dt = math.max(0, dt or 0)
    local trigger = config.EAT_TRIGGER_HUNGER
    local personal_capacity = math.max(0, math.floor(config.PERSONAL_FOOD_CAPACITY))
    local personal_food = math.floor(e.personal_food or 0)
    local hunger = e.hunger or 0

    if hunger < 100 and eat_personal_food(e) > 0 then
        e.state = "EatStoredFood"
        return true
    end

    hunger = e.hunger or hunger
    personal_food = math.floor(e.personal_food or personal_food)

    if not e.food_seek_active then
        if hunger <= trigger and personal_food <= 0 then
            e.food_seek_active = true
        else
            return false
        end
    end

    if hunger >= 100 and personal_food >= personal_capacity then
        e.food_seek_active = false
        return false
    end

    local vr = math.max(1, math.floor((e.dna and e.dna.view_distance) or 4))
    local cx = math.floor(e.x or 1)
    local cy = math.floor(e.y or 1)
    local map_w = w.width
    local map_h = w.height
    local best_idx
    local best_food = 0
    local function search_food(radius)
        for gy = math.max(1, cy - radius), math.min(map_h, cy + radius) do
            for gx = math.max(1, cx - radius), math.min(map_w, cx + radius) do
                local tile, idx = world.get_tile(w, gx, gy)
                local fruit = (tile and tile.apple_fruit) or 0
                if fruit > best_food then
                    best_food = fruit
                    best_idx = idx
                end
            end
        end
    end
    search_food(vr)
    if (not best_idx) and (e.hunger or 0) <= (trigger - 10) then
        search_food(math.max(vr * 3, 18))
    end

    if not best_idx then
        return false
    end

    local tx, ty = world.to_grid(w, best_idx)
    local dx = tx - (e.x or 0)
    local dy = ty - (e.y or 0)
    local d2 = (dx * dx + dy * dy)
    if d2 <= 1 then
        local tile = w.tiles[best_idx]
        if tile and (tile.apple_fruit or 0) > 0 then
            local hunger_before = e.hunger or 0
            local max_hp = (e.dna and e.dna.max_health) or 100
            local stored_now = math.floor(e.personal_food or 0)
            local personal_space = math.max(0, personal_capacity - stored_now)

            local picked = math.min(tile.apple_fruit, 1)
            tile.apple_fruit = math.max(0, (tile.apple_fruit or 0) - picked)
            if (tile.apple_fruit or 0) <= 0 then
                local res = config.RESOURCE or {}
                tile.apple_regrow_cd_days = res.APPLE_FRUIT_RESPAWN_DAYS or 3
            end
            tile.food = tile.apple_fruit

            if hunger_before < 100 then
                e.hunger = math.min(100, hunger_before + picked * FOOD_UNIT_HUNGER_RECOVER)
                e.health = math.min(max_hp, (e.health or 0) + picked * (config.HEALTH_RECOVER_FROM_FOOD))
                requirements.grant_knowledge_for_event("gather_fruit", e, picked)
                e.state = "Eat"
            elseif personal_space > 0 then
                local stored = math.min(picked, personal_space)
                e.personal_food = math.min(personal_capacity, stored_now + stored)
                if stored > 0 then
                    requirements.grant_knowledge_for_event("gather_fruit", e, stored)
                end
                e.state = "StoreFood"
            else
                e.food_seek_active = false
            end
            return true
        end
    end

    -- Not close enough yet: move toward the selected food tile this tick.
    local len = math.sqrt(d2)
    if len > 0 then
        e.vx = dx / len
        e.vy = dy / len
        local speed = (e.dna and e.dna.move_speed) or 24
        local nx = (e.x or 1) + (e.vx or 0) * speed * step_dt
        local ny = (e.y or 1) + (e.vy or 0) * speed * step_dt
        if world.in_bounds(w, math.floor(nx), math.floor(ny)) then
            e.x = math.max(1, math.min(w.width - 0.001, nx))
            e.y = math.max(1, math.min(w.height - 0.001, ny))
            e.state = "SeekFood"
            return true
        end
    end

    return false
end

return M
