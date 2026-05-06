--[[
  New game / scenario application / world reset (mutates game state table `g`).
]]

local world = require("src.core.world")
local map_renderer = require("src.core.map_renderer")
local entities = require("src.core.entities")
local sim = require("src.core.sim")
local scenarios = require("src.data.scenarios")

local M = {}

function M.apply_scenario_to_world(w, scenario)
    local m = scenario.modifiers or {}
    w.environment.fertility_mult = m.fertility or 1.0
    w.environment.rainfall_mult = m.rainfall or 1.0
    w.environment.heat_mult = m.heat or 1.0
end

function M.make_new_seed()
    local base = os.time()
    if love and love.timer and love.timer.getTime then
        base = base + math.floor(love.timer.getTime() * 1000)
    end
    return base
end

function M.reset(g)
    local scenario = scenarios.get(g.scenario_id)
    local map_size_tiles = world.DEFAULT_MAP_TILES or 256
    g.world = world.new(map_size_tiles, map_size_tiles, M.make_new_seed())
    M.apply_scenario_to_world(g.world, scenario)

    local mid_x = g.world.width * 0.5
    local mid_y = g.world.height * 0.5
    local start_x, start_y = entities.find_spawn_site(g.world, g.world.seed + 13, mid_x, mid_y)
    local spawns = scenario.spawns or {}

    for i = 1, (spawns.male or 1) do
        entities.spawn(g.world, start_x - 0.5 - (i * 0.2), start_y, nil, "male")
    end
    for i = 1, (spawns.female or 1) do
        entities.spawn(g.world, start_x + 0.5 + (i * 0.2), start_y, nil, "female")
    end
    if (spawns.random or 0) > 0 then
        entities.seed_random(g.world, spawns.random, g.world.seed + 77)
    end

    g.renderer = map_renderer.new(4, g.world.width * g.world.height)
    g.renderer:rebuild(g.world)
    g.sim = sim.new({
        step_dt = 1 / 20,
        max_steps_per_frame = 8,
        eco_slices = 3,
        stats_stride = 3,
    })
    g.selected_object = nil
    g.message = string.format("GodSim — %s", scenario.name)
    g.overlay_canvas = nil
    g.overlay_canvas_coarse = nil
    g.vis_overlay_dirty = true
    g.vis_overlay_coarse_dirty = true
    g._overlay_tick_cadence = 0
end

return M
