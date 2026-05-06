--[[
  Selected object helpers, shelter queries, building summaries, reproduction HUD data.
]]

local entities = require("src.core.entities")
local entity_config = require("src.data.config_entities")
local entity_requirements = require("src.core.entity_requirements")

local M = {}

function M.get_selected_object(g)
    if not (g and g.world and g.selected_object) then
        return nil, nil
    end
    if g.selected_object.kind == "entity" then
        return "entity", entities.get_by_id(g.world, g.selected_object.id)
    end
    if g.selected_object.kind == "building" then
        local b = g.world.buildings and g.world.buildings[g.selected_object.index]
        if b then
            return "building", b
        end
    end
    return nil, nil
end

function M.get_home_shelter(g, entity)
    if not (g and g.world and entity and entity.home_shelter_id) then
        return nil
    end
    local buildings = g.world.buildings or {}
    for i = 1, #buildings do
        local b = buildings[i]
        if b and b.kind == "shelter" and b.id == entity.home_shelter_id then
            return b
        end
    end
    return nil
end

function M.is_entity_inside_home_shelter(g, entity)
    if not (g and g.world and entity and entity.home_shelter_id) then
        return false
    end
    local buildings = g.world.buildings or {}
    for i = 1, #buildings do
        local b = buildings[i]
        if b and b.kind == "shelter" and b.id == entity.home_shelter_id then
            local dx = (entity.x or 0) - (b.x or 0)
            local dy = (entity.y or 0) - (b.y or 0)
            return (dx * dx + dy * dy) <= (0.9 * 0.9)
        end
    end
    return false
end

function M.summarize_buildings(w)
    local total = 0
    local shelters = 0
    local others_build = 0
    local under_construction = 0
    local buildings = (w and w.buildings) or {}
    for i = 1, #buildings do
        local b = buildings[i]
        if b then
            total = total + 1
            if b.kind == "shelter" then
                shelters = shelters + 1
            elseif b.kind == "campfire" then
                others_build = others_build + 1
            end
            if b.under_construction then
                under_construction = under_construction + 1
            end
        end
    end
    return total, shelters, others_build, under_construction
end

function M.get_shelter_repro_status(g, shelter)
    local status = {
        male_ready = 0,
        female_ready = 0,
        male_block = nil,
        female_block = nil,
    }
    if not (g and g.world and shelter and shelter.residents) then
        return status
    end

    for i = 1, #shelter.residents do
        local resident = g.world.entities[shelter.residents[i]]
        if resident and resident.alive and resident.home_shelter_id == shelter.id then
            local rule_id = (resident.sex == "male") and "reproduce_male" or "reproduce_female"
            local ok, reason = entity_requirements.can_do(rule_id, resident)
            local cooldown = (resident.reproduction_cooldown or 0) > 0
            local age_ok = true
            if resident.sex == "female" then
                age_ok = resident.age >= entity_config.REPRO.FEMALE_MIN_AGE and resident.age <= entity_config.REPRO.FEMALE_MAX_AGE
            elseif resident.sex == "male" then
                age_ok = resident.age >= entity_config.REPRO.MALE_MIN_AGE
            end

            if resident.sex == "male" then
                if ok and (not cooldown) and age_ok then
                    status.male_ready = status.male_ready + 1
                else
                    status.male_block = status.male_block or reason or (cooldown and "cooldown") or "age"
                end
            elseif resident.sex == "female" then
                local max_hp = (resident.dna and resident.dna.max_health) or 100
                local carry_ok = (resident.hunger or 0) <= entity_config.REPRO_MAX_HUNGER
                    and (resident.health or 0) >= (max_hp * entity_config.REPRO_MIN_HEALTH_RATIO)
                if ok and (not cooldown) and age_ok and (not resident.pregnant) and carry_ok then
                    status.female_ready = status.female_ready + 1
                else
                    status.female_block = status.female_block
                        or reason
                        or (resident.pregnant and "pregnant")
                        or (cooldown and "cooldown")
                        or ((resident.hunger or 0) > entity_config.REPRO_MAX_HUNGER and "hunger")
                        or "health/age"
                end
            end
        end
    end

    return status
end

return M
