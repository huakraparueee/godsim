local requirements = {
    reproduce_male = {
        min_age = 15 * 365,
        min_strength = 4,
        min_knowledge = 0,
        knowledge_gain = 0.35,
    },
    reproduce_female = {
        min_age = 15 * 365,
        max_age = 45 * 365,
        min_strength = 4,
        min_knowledge = 0,
        knowledge_gain = 0.45,
    },
    give_birth = {
        min_age = 15 * 365,
        min_knowledge = 0,
        knowledge_gain = 0.8,
    },
    build_campfire = {
        min_age = 15 * 365,
        min_strength = 8,
        min_knowledge = 30,
        knowledge_gain = 1.2,
        strength_gain = 0.15,
    },
    build_shelter = {
        min_age = 18 * 365,
        min_strength = 12,
        min_knowledge = 8,
        knowledge_gain = 2.0,
        strength_gain = 0.35,
    },
    deliver_food = {
        min_age = 15 * 365,
        min_strength = 6,
        min_knowledge = 0,
        knowledge_gain = 0.55,
        strength_gain = 0.08,
    },
    gather_fruit = {
        min_age = 12 * 365,
        min_strength = 6,
        min_knowledge = 0,
        knowledge_gain = 0.3,
        strength_gain = 0.04,
    },
    hunt_wildlife = {
        min_age = 14 * 365,
        min_strength = 9,
        min_knowledge = 2,
        knowledge_gain = 0.7,
        strength_gain = 0.18,
    },
    hunt_wolf = {
        min_age = 16 * 365,
        min_strength = 15,
        min_knowledge = 8,
        knowledge_gain = 1.4,
        strength_gain = 0.35,
    },
    cut_tree = {
        min_age = 14 * 365,
        min_strength = 7,
        min_knowledge = 3,
        knowledge_gain = 0.45,
        strength_gain = 0.12,
    },
    fruit_spawn = {
        min_knowledge = 0,
        knowledge_gain = 0,
    },
}

return requirements
