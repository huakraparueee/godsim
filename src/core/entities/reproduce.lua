local config = require("src.data.config_entities")
local requirements = require("src.core.entity_requirements")
local entity_events = require("src.core.entities_events")

local M = {}
local TODDLER_AGE_DAYS = 3 * 365

local function rand01()
    if love and love.math and love.math.random then
        return love.math.random()
    end
    return math.random()
end

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

local function rebuild_shelter_residents(w)
    local shelters = {}
    local buildings = w.buildings or {}
    local capacity = config.BUILD.SHELTER_CAPACITY
    local toddlers_by_shelter = {}
    local others_by_shelter = {}
    for i = 1, #buildings do
        local b = buildings[i]
        if b and b.kind == "shelter" and (not b.under_construction) then
            b.residents = {}
            shelters[b.id] = b
            toddlers_by_shelter[b.id] = {}
            others_by_shelter[b.id] = {}
        end
    end
    for _, e in pairs(w.entities or {}) do
        if e and e.alive and e.home_shelter_id then
            local shelter = shelters[e.home_shelter_id]
            if not shelter then
                e.home_shelter_id = nil
            elseif e.age ~= nil and e.age < TODDLER_AGE_DAYS then
                toddlers_by_shelter[shelter.id][#toddlers_by_shelter[shelter.id] + 1] = e.id
            else
                others_by_shelter[shelter.id][#others_by_shelter[shelter.id] + 1] = e.id
            end
        end
    end
    for shelter_id, shelter in pairs(shelters) do
        local toddlers = toddlers_by_shelter[shelter_id]
        for i = 1, #toddlers do
            shelter.residents[#shelter.residents + 1] = toddlers[i]
        end
        local others = others_by_shelter[shelter_id]
        for i = 1, #others do
            if #shelter.residents < capacity then
                shelter.residents[#shelter.residents + 1] = others[i]
            else
                local evicted = w.entities[others[i]]
                if evicted and evicted.alive and evicted.home_shelter_id == shelter.id then
                    evicted.home_shelter_id = nil
                end
            end
        end
    end
end

local function find_best_shelter_for_entity(w, e)
    local buildings = w.buildings or {}
    local capacity = config.BUILD.SHELTER_CAPACITY
    local best
    local best_d2 = math.huge
    for i = 1, #buildings do
        local b = buildings[i]
        if b and b.kind == "shelter" and (not b.under_construction) and (b.residents and #b.residents < capacity) then
            local dx = (e.x or 0) - (b.x or 0)
            local dy = (e.y or 0) - (b.y or 0)
            local d2 = dx * dx + dy * dy
            if d2 < best_d2 then
                best = b
                best_d2 = d2
            end
        end
    end
    return best
end

local function assign_homeless_to_available_shelters(w)
    rebuild_shelter_residents(w)
    for _, e in pairs(w.entities or {}) do
        if e and e.alive and not e.home_shelter_id then
            local shelter = find_best_shelter_for_entity(w, e)
            if shelter then
                e.home_shelter_id = shelter.id
                shelter.residents[#shelter.residents + 1] = e.id
            end
        end
    end
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
    if not e.home_shelter_id or not find_shelter_by_id(w, e.home_shelter_id) then
        return false
    end
    if e.sex == "male" then
        local ok = requirements.can_do("reproduce_male", e)
        return ok and (e.reproduction_cooldown or 0) <= 0 and age_fertility_factor(e) > 0
    end
    local ok = requirements.can_do("reproduce_female", e)
    return ok and (e.reproduction_cooldown or 0) <= 0 and (not e.pregnant) and age_fertility_factor(e) > 0
end

local function can_carry_pregnancy(e)
    if not (e and e.alive and e.sex == "female") then
        return false
    end
    return e.hunger >= config.REPRO_MAX_HUNGER and e.health >= config.REPRO_MIN_HEALTH
end

local function assign_newborn_to_mother_shelter(w, newborn_id, mother)
    if not (newborn_id and mother and mother.home_shelter_id) then
        return
    end
    local shelter = find_shelter_by_id(w, mother.home_shelter_id)
    if not shelter then
        return
    end
    shelter.residents = shelter.residents or {}
    local newborn = w.entities[newborn_id]
    if not (newborn and newborn.alive) then
        return
    end

    local capacity = config.BUILD.SHELTER_CAPACITY
    if #shelter.residents >= capacity then
        local evict_id = nil
        for i = #shelter.residents, 1, -1 do
            local resident_id = shelter.residents[i]
            if resident_id ~= mother.id and resident_id ~= newborn.id then
                local resident = w.entities[resident_id]
                if resident and resident.alive then
                    if resident.age ~= nil and resident.age < TODDLER_AGE_DAYS then
                        -- Toddlers must keep their home.
                    else
                        evict_id = resident_id
                        table.remove(shelter.residents, i)
                        break
                    end
                end
            end
        end
        if evict_id then
            local evicted = w.entities[evict_id]
            if evicted and evicted.alive and evicted.home_shelter_id == shelter.id then
                evicted.home_shelter_id = nil
            end
        end
    end

    if #shelter.residents < capacity then
        newborn.home_shelter_id = shelter.id
        newborn.home_lock_until_age = 3 * 365
        shelter.residents[#shelter.residents + 1] = newborn.id
    end
end

function M.update_pregnancies(w, dt, spawn_fn)
    for _, e in pairs(w.entities or {}) do
        if e and e.alive and e.sex == "female" and e.pregnant then
            e.gestation_timer = math.max(0, (e.gestation_timer or 0) - dt)
            if e.gestation_timer <= 0 then
                local births = 1
                local fertility = (e.dna and e.dna.fertility_rate) or 0.3
                if fertility > 0.55 and rand01() < 0.16 then
                    births = 2
                end
                for _ = 1, births do
                    local sex = (rand01() < 0.5) and "male" or "female"
                    local bx = (e.x or 1) + ((rand01() - 0.5) * 0.7)
                    local by = (e.y or 1) + ((rand01() - 0.5) * 0.7)
                    if spawn_fn then
                        local newborn_id = spawn_fn(w, bx, by, nil, sex, 0)
                        assign_newborn_to_mother_shelter(w, newborn_id, e)
                    end
                end
                e.pregnant = false
                e.pregnancy_partner = nil
                e.state = "Postpartum"
                requirements.grant_knowledge_for_event("give_birth", e, births)
                entity_events.birth(w, e.name, births, e.pregnancy_start_day, (w.calendar and w.calendar.total_days) or 1)
                e.pregnancy_start_day = nil
            else
                e.state = "Pregnant"
            end
        end
    end
end

function M.try_reproduce(w, dt)
    local conceptions = 0
    assign_homeless_to_available_shelters(w)

    for _, e in pairs(w.entities or {}) do
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
                    local hunger_factor = math.max(0.35, math.min(1.0, (f.hunger or 0) / 100))
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

return M
