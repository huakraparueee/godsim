local rules = require("src.config_entity_event_requirements")
local dna_ranges = require("src.config_dna_ranges")

local requirements = {}

local function clamp(v, min_v, max_v)
    if v < min_v then
        return min_v
    end
    if v > max_v then
        return max_v
    end
    return v
end

local function get_profile(entity)
    return dna_ranges[(entity and entity.sex) or ""] or dna_ranges.fallback
end

function requirements.can_do(event_id, entity)
    local rule = rules[event_id]
    if not rule then
        return true
    end
    if not entity then
        return false, "missing entity"
    end

    if rule.min_age and (entity.age or 0) < rule.min_age then
        return false, "age too low"
    end
    if rule.max_age and (entity.age or 0) > rule.max_age then
        return false, "age too high"
    end
    if rule.min_strength and (entity.strength or 0) < rule.min_strength then
        return false, "strength too low"
    end
    if rule.min_knowledge and (entity.knowledge or 0) < rule.min_knowledge then
        return false, "knowledge too low"
    end

    return true
end

function requirements.grant_knowledge_for_event(event_id, entity, multiplier)
    local rule = rules[event_id]
    if not (rule and entity) then
        return 0
    end

    local applied_multiplier = tonumber(multiplier) or 1
    if applied_multiplier <= 0 then
        return 0
    end

    local profile = get_profile(entity)
    local knowledge_gain = (tonumber(rule.knowledge_gain) or 0) * applied_multiplier
    if knowledge_gain > 0 then
        local current = entity.knowledge or 0
        local max_knowledge = (profile.knowledge and profile.knowledge.max) or 100
        entity.knowledge = clamp(current + knowledge_gain, 0, max_knowledge)
    end

    local strength_gain = (tonumber(rule.strength_gain) or 0) * applied_multiplier
    if strength_gain > 0 then
        local current = entity.strength or 0
        local min_strength = (profile.strength and profile.strength.min) or 0
        local max_strength = (profile.strength and profile.strength.max) or 100
        entity.strength = clamp(current + strength_gain, min_strength, max_strength)
    end

    return knowledge_gain
end

return requirements
