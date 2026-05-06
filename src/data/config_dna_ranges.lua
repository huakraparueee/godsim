local ranges = {
    male = {
        move_speed = { min = 9, max = 40, default = 25 },
        view_distance = { min = 2, max = 12, default = 6 },
        fertility_rate = { min = 0.08, max = 0.95, default = 0.34 },
        max_health = { min = 60, max = 185, default = 108 },
        mutation_factor = { min = 0.0, max = 0.3, default = 0.05 },
        strength = { min = 6, max = 100, default = 28 },
        knowledge = { min = 0, max = 100, default = 5 },
    },
    female = {
        move_speed = { min = 8, max = 38, default = 23 },
        view_distance = { min = 2, max = 12, default = 6 },
        fertility_rate = { min = 0.1, max = 0.98, default = 0.4 },
        max_health = { min = 55, max = 175, default = 102 },
        mutation_factor = { min = 0.0, max = 0.3, default = 0.05 },
        strength = { min = 4, max = 95, default = 22 },
        knowledge = { min = 0, max = 100, default = 6 },
    },
    fallback = {
        move_speed = { min = 8, max = 40, default = 24 },
        view_distance = { min = 2, max = 12, default = 6 },
        fertility_rate = { min = 0.05, max = 0.95, default = 0.3 },
        max_health = { min = 50, max = 180, default = 100 },
        mutation_factor = { min = 0.0, max = 0.3, default = 0.05 },
        strength = { min = 1, max = 100, default = 20 },
        knowledge = { min = 0, max = 100, default = 5 },
    },
}

return ranges
