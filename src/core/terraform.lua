--[[
  Terraform brush application at cursor.
]]

local world = require("src.core.world")
local cam = require("src.utils.camera")

local M = {}

function M.apply_brush_at_mouse(g)
    if not (g.world and g.renderer and g.brush) then
        return
    end

    local mx, my = love.mouse.getPosition()
    local gx, gy = cam.screen_to_grid(g, mx, my)
    local changed = world.brush(g.world, gx, gy, g.brush.radius, g.brush.type_id)
    if changed and changed > 0 then
        g.renderer:rebuild(g.world)
    end
end

return M
