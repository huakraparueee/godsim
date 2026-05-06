local scenarios = {}

scenarios.definitions = {
    balanced = {
        id = "balanced",
        name = "Balanced Era",
        description = "Moderate fertility and stable rainfall.",
        modifiers = {
            fertility = 1.0,
            rainfall = 1.0,
            heat = 1.0,
        },
        spawns = {
            male = 2,
            female = 2,
            random = 4,
        },
    },
    lush_age = {
        id = "lush_age",
        name = "Lush Age",
        description = "Food-rich land with rapid population growth.",
        modifiers = {
            fertility = 1.25,
            rainfall = 1.2,
            heat = 0.95,
        },
        spawns = {
            male = 2,
            female = 2,
            random = 12,
        },
    },
    arid_age = {
        id = "arid_age",
        name = "Arid Age",
        description = "Dry climate and high starvation pressure.",
        modifiers = {
            fertility = 0.72,
            rainfall = 0.65,
            heat = 1.15,
        },
        spawns = {
            male = 1,
            female = 1,
            random = 4,
        },
    },
    -- Phase 2 DoD helper: soak test with ~500 units (FPS will vary by machine).
    stress_500 = {
        id = "stress_500",
        name = "Stress (500 entities)",
        description = "Population soak; monitor debug overlay.",
        modifiers = {
            fertility = 1.0,
            rainfall = 1.0,
            heat = 1.0,
        },
        spawns = {
            male = 25,
            female = 25,
            random = 450,
        },
    },
}

function scenarios.get(id)
    return scenarios.definitions[id] or scenarios.definitions.balanced
end

function scenarios.list_ids()
    return { "balanced", "lush_age", "arid_age", "stress_500" }
end

return scenarios
