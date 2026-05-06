--[[
  Screen-space picking for entities and buildings.
]]

local cam = require("src.utils.camera")

local M = {}

function M.entity_at_screen(g, mouse_x, mouse_y)
    if not (g.world and g.renderer and g.camera) then
        return nil
    end
    local wx, wy = cam.screen_to_world(g, mouse_x, mouse_y)
    local pick_radius = 1.25
    local best
    local best_d2 = pick_radius * pick_radius
    for _, e in pairs(g.world.entities) do
        if e and e.alive then
            local dx = e.x - (wx / g.renderer.tile_size + 1)
            local dy = e.y - (wy / g.renderer.tile_size + 1)
            local d2 = dx * dx + dy * dy
            if d2 <= best_d2 then
                best = e
                best_d2 = d2
            end
        end
    end
    return best
end

function M.building_index_at_screen(g, mouse_x, mouse_y)
    if not (g.world and g.renderer and g.camera) then
        return nil
    end
    local wx, wy = cam.screen_to_world(g, mouse_x, mouse_y)
    local pick_radius = 1.1
    local best_index
    local best_d2 = pick_radius * pick_radius
    local buildings = g.world.buildings or {}
    for i = 1, #buildings do
        local b = buildings[i]
        if b then
            local dx = b.x - (wx / g.renderer.tile_size + 1)
            local dy = b.y - (wy / g.renderer.tile_size + 1)
            local d2 = dx * dx + dy * dy
            if d2 <= best_d2 then
                best_index = i
                best_d2 = d2
            end
        end
    end
    return best_index
end

return M
