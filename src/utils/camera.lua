--[[
  Camera pan/zoom bounds and screen ↔ world/grid mapping (game state table `g`).
]]

local M = {}

function M.clamp(v, min_v, max_v)
    if v < min_v then
        return min_v
    end
    if v > max_v then
        return max_v
    end
    return v
end

function M.update_bounds(g)
    if not (g.camera and g.world and g.renderer) then
        return
    end

    local sw = love.graphics.getWidth()
    local sh = love.graphics.getHeight()
    local map_w = g.world.width * g.renderer.tile_size
    local map_h = g.world.height * g.renderer.tile_size

    local view_w = sw / g.camera.zoom
    local view_h = sh / g.camera.zoom
    local half_view_w = view_w * 0.5
    local half_view_h = view_h * 0.5
    local center_x = g.camera.x + half_view_w
    local center_y = g.camera.y + half_view_h

    center_x = M.clamp(center_x, 0, map_w)
    center_y = M.clamp(center_y, 0, map_h)

    g.camera.x = center_x - half_view_w
    g.camera.y = center_y - half_view_h
end

function M.center_on_map(g)
    if not (g.camera and g.world and g.renderer) then
        return
    end

    local sw = love.graphics.getWidth()
    local sh = love.graphics.getHeight()
    local map_w = g.world.width * g.renderer.tile_size
    local map_h = g.world.height * g.renderer.tile_size
    local view_w = sw / g.camera.zoom
    local view_h = sh / g.camera.zoom

    g.camera.x = (map_w - view_w) * 0.5
    g.camera.y = (map_h - view_h) * 0.5
    M.update_bounds(g)
end

function M.screen_offset()
    return 0, 0
end

function M.screen_to_world(g, mouse_x, mouse_y)
    local offset_x, offset_y = M.screen_offset()
    local wx = ((mouse_x - offset_x) / g.camera.zoom) + g.camera.x
    local wy = ((mouse_y - offset_y) / g.camera.zoom) + g.camera.y
    return wx, wy
end

function M.screen_to_grid(g, mouse_x, mouse_y)
    local wx, wy = M.screen_to_world(g, mouse_x, mouse_y)
    local ts = g.renderer.tile_size
    local gx = math.floor(wx / ts) + 1
    local gy = math.floor(wy / ts) + 1
    return gx, gy
end

return M
