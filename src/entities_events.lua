local world = require("src.world")
local events = {}
local DAYS_PER_YEAR = 365

local function push(w, kind, message, severity)
    if world and world.push_event then
        world.push_event(w, kind, message, severity)
    end
end

function events.birth(w, mother_name, count, conception_day, birth_day)
    local c_day = conception_day or "?"
    local b_day = birth_day or "?"
    push(
        w,
        "birth",
        string.format(
            "%s gave birth to %d child(ren) | conceived day %s -> birth day %s",
            mother_name or "female",
            count or 1,
            tostring(c_day),
            tostring(b_day)
        ),
        "info"
    )
end

function events.death(w, entity_name, reason, id)
    if reason == "starvation" or reason == "old_age" or reason == "wolf_attack" then
        push(w, "death", string.format("%s died from %s", entity_name or ("Unit-" .. tostring(id or "?")), reason), "info")
    end
end

function events.pregnancy(w, female_name, male_name, female_entity, male_entity)
    local f_age = (female_entity and female_entity.age or 0) / DAYS_PER_YEAR
    local f_str = female_entity and female_entity.strength or 0
    local f_knw = female_entity and female_entity.knowledge or 0
    local m_age = (male_entity and male_entity.age or 0) / DAYS_PER_YEAR
    local m_str = male_entity and male_entity.strength or 0
    local m_knw = male_entity and male_entity.knowledge or 0
    push(
        w,
        "pregnancy",
        string.format(
            "%s conceived with %s | F[a:%.1f s:%.1f k:%.1f] M[a:%.1f s:%.1f k:%.1f]",
            female_name or "female",
            male_name or "male",
            f_age,
            f_str,
            f_knw,
            m_age,
            m_str,
            m_knw
        ),
        "info"
    )
end

function events.home_invite(w, male_name, female_name, shelter_id)
    push(
        w,
        "social",
        string.format(
            "%s invited %s to live in shelter #%s",
            male_name or "male",
            female_name or "female",
            tostring(shelter_id or "?")
        ),
        "info"
    )
end

function events.campfire_built(w, builder_name, x, y)
    push(
        w,
        "build",
        string.format(
            "%s built a campfire at (%.1f, %.1f)",
            builder_name or "unit",
            x or 0,
            y or 0
        ),
        "info"
    )
end

function events.shelter_built(w, builder_name, x, y)
    push(
        w,
        "build",
        string.format(
            "%s built a shelter at (%.1f, %.1f)",
            builder_name or "unit",
            x or 0,
            y or 0
        ),
        "info"
    )
end

function events.food_delivery(w, carrier_name, shelter_id, amount)
    push(
        w,
        "support",
        string.format(
            "%s delivered %.2f food to shelter #%s",
            carrier_name or "unit",
            amount or 0,
            tostring(shelter_id or "?")
        ),
        "info"
    )
end

function events.gather_fruit(w, worker_name, amount)
    push(
        w,
        "resource",
        string.format("%s gathered apples %.2f", worker_name or "unit", amount or 0),
        "info"
    )
end

function events.hunt_wildlife(w, hunter_name, amount)
    push(
        w,
        "resource",
        string.format("%s hunted rabbit for meat %.2f", hunter_name or "unit", amount or 0),
        "info"
    )
end

function events.hunt_wolf(w, hunter_name, amount)
    push(
        w,
        "resource",
        string.format("%s hunted wolf for meat %.2f", hunter_name or "unit", amount or 0),
        "info"
    )
end

function events.wolf_attack(w, victim_name, damage)
    push(
        w,
        "danger",
        string.format("Wolf attacked %s for %.0f damage", victim_name or "unit", damage or 0),
        "warn"
    )
end

function events.explore(w, entity_name, x, y)
    push(
        w,
        "explore",
        string.format("%s explored new area near (%.1f, %.1f)", entity_name or "unit", x or 0, y or 0),
        "info"
    )
end

function events.cut_tree(w, worker_name, amount, tree_type)
    push(
        w,
        "resource",
        string.format("%s cut %s wood %.2f", worker_name or "unit", tree_type or "tree", amount or 0),
        "info"
    )
end

function events.fruit_spawn(w, amount)
    push(
        w,
        "resource",
        string.format("Apple fruit regrew +%.2f", amount or 0),
        "info"
    )
end

return events
