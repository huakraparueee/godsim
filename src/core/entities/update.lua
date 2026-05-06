local config = require("src.data.config_entities")
local tasks = require("src.core.entities.tasks")
local movement = require("src.core.entities.movement")

local M = {}
local FOOD_UNIT_HUNGER_RECOVER = 50
local TODDLER_AGE_DAYS = 3 * 365

local function find_shelter_by_id(w, shelter_id)
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

local function stay_near_home(w, e, step_dt)
    local home = find_shelter_by_id(w, e.home_shelter_id)
    if not home then
        return false
    end
    local dx = (home.x or 0) - (e.x or 0)
    local dy = (home.y or 0) - (e.y or 0)
    local d2 = dx * dx + dy * dy
    if d2 <= (0.9 * 0.9) then
        e.vx = 0
        e.vy = 0
        e.state = "StayHome"
        return true
    end

    local len = math.sqrt(d2)
    if len <= 0 then
        return true
    end
    e.vx = dx / len
    e.vy = dy / len
    local speed = (e.dna and e.dna.move_speed) or 24
    local nx = (e.x or 1) + (e.vx or 0) * speed * (step_dt or 0)
    local ny = (e.y or 1) + (e.vy or 0) * speed * (step_dt or 0)
    if nx >= 1 and nx <= (w.width - 0.001) and ny >= 1 and ny <= (w.height - 0.001) then
        e.x = nx
        e.y = ny
    end
    e.state = "GoHome"
    return true
end

local function is_inside_home(e, home)
    if not (e and home) then
        return false
    end
    local dx = (home.x or 0) - (e.x or 0)
    local dy = (home.y or 0) - (e.y or 0)
    return (dx * dx + dy * dy) <= (0.9 * 0.9)
end

local function eat_from_personal_food(e)
    if not (e and (e.personal_food or 0) > 0 and (e.hunger or 0) < 100) then
        return false
    end
    e.personal_food = math.max(0, math.floor(e.personal_food or 0) - 1)
    e.hunger = math.min(100, (e.hunger or 0) + FOOD_UNIT_HUNGER_RECOVER)
    local max_hp = (e.dna and e.dna.max_health) or 100
    e.health = math.min(max_hp, (e.health or 0) + (config.HEALTH_RECOVER_FROM_FOOD))
    return true
end

local function eat_from_home_food(e, home)
    if not (e and home and (home.food_stock or 0) >= 1 and (e.hunger or 0) < 100) then
        return false
    end
    home.food_stock = math.max(0, (home.food_stock or 0) - 1)
    e.hunger = math.min(100, (e.hunger or 0) + FOOD_UNIT_HUNGER_RECOVER)
    local max_hp = (e.dna and e.dna.max_health) or 100
    e.health = math.min(max_hp, (e.health or 0) + (config.HEALTH_RECOVER_FROM_FOOD))
    return true
end

local function apply_daily_changes(w, e, game_day_delta, kill_fn)
    e.age = (e.age or 0) + game_day_delta
    e.hunger = math.max(0, (e.hunger or 0) - ((config.HUNGER_RATE) * game_day_delta))

    if e.age >= (config.MAX_AGE) then
        kill_fn(w, e.id, "old_age")
        return false
    end
    if (e.health or 0) <= 0 or e.hunger <= 0 then
        kill_fn(w, e.id, "starvation")
        return false
    end
    return true
end

local function is_toddler(e)
    if not e then
        return false
    end
    if e.age == nil then
        return false
    end
    return e.age < TODDLER_AGE_DAYS
end

local function update_toddler(w, e, step_dt)
    tasks.cancel_current_task(w, e)
    local home = find_shelter_by_id(w, e.home_shelter_id)
    local at_home = stay_near_home(w, e, step_dt)
    if not at_home then
        e.vx = 0
        e.vy = 0
        e.state = "ToddlerNoHome"
        return
    end
    if e.hunger <= config.EAT_TRIGGER_HUNGER then
        if home and is_inside_home(e, home) and eat_from_home_food(e, home) then
            e.state = "ToddlerEatHomeFood"
            return
        end
    end
    e.state = "ToddlerStayHome"
end

function M.update(w, game_day_delta, step_dt, kill_fn)
    local day_delta = math.max(0, game_day_delta or 0)
    for _, e in pairs(w.entities) do
        if e and e.alive then
            if e.sex == "female" and e.pregnant then
                local home = find_shelter_by_id(w, e.home_shelter_id)
                local at_home = stay_near_home(w, e, step_dt)
                if not at_home then
                    e.vx = 0
                    e.vy = 0
                    e.state = "PregnantNoHome"
                end
                if (e.hunger or 0) <= config.EAT_TRIGGER_HUNGER then
                    if eat_from_personal_food(e) then
                        e.state = "PregnantEatStoredFood"
                    elseif home and is_inside_home(e, home) and eat_from_home_food(e, home) then
                        e.state = "PregnantEatHomeFood"
                    end
                end
                if day_delta > 0 and e.alive then
                    apply_daily_changes(w, e, day_delta, kill_fn)
                end
                goto continue_entity_update
            end

            if is_toddler(e) then
                update_toddler(w, e, step_dt)
                if day_delta > 0 and e.alive then
                    apply_daily_changes(w, e, day_delta, kill_fn)
                end
                goto continue_entity_update
            end

            local task_acted = tasks.update(w, e, step_dt)
            if not task_acted then
                local at_home = stay_near_home(w, e, step_dt)
                if not at_home then
                    movement.update(w, e, step_dt)
                end
            end

            if day_delta > 0 and e.alive then
                apply_daily_changes(w, e, day_delta, kill_fn)
            end
        end
        ::continue_entity_update::
    end
end

return M
