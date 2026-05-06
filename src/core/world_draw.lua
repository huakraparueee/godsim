--[[
  Map transform, tile overlays, entities, buildings, selection ring.
]]

local entity_config = require("src.data.config_entities")
local selection = require("src.core.selection")
local cam = require("src.utils.camera")

local M = {}

function M.draw(g)
    if not (g.renderer and g.camera) then
        return
    end

    local map_offset_x, map_offset_y = cam.screen_offset()
    love.graphics.push()
    love.graphics.translate(map_offset_x, map_offset_y)
    love.graphics.scale(g.camera.zoom, g.camera.zoom)
    love.graphics.translate(-g.camera.x, -g.camera.y)
    g.renderer:draw(0, 0)
    local ts = g.renderer.tile_size
    local half_ts = ts * 0.5
    local object_px = 1
    local object_offset = (ts - object_px) * 0.5
    local building_px = 4
    local building_radius = building_px * 0.5
    local selected_radius = math.max(2.0, ts * 0.75)
    local resource_cfg = entity_config.RESOURCE or {}
    local rabbit_visible_threshold = resource_cfg.WILDLIFE_MIN_TO_HUNT or 0.18
    local wolf_visible_threshold = resource_cfg.WOLF_MIN_TO_HUNT or 0.08
    for i = 1, #g.world.tiles do
        local tile = g.world.tiles[i]
        local fruit = tile.apple_fruit or 0
        local pine = tile.pine_wood or 0
        local rabbit = tile.wildlife or 0
        local wolves = tile.wolves or 0
        local tx = ((i - 1) % g.world.width) * ts
        local ty = math.floor((i - 1) / g.world.width) * ts
        if fruit > 0.01 then
            love.graphics.setColor(1.0, 0.58, 0.08, math.min(0.78, 0.42 + fruit * 0.55))
            love.graphics.circle("fill", tx + (ts * 0.72), ty + (ts * 0.24), math.max(1.2, ts * 0.2))
        end
        if pine > 0.2 then
            love.graphics.setColor(0.18, 0.62, 0.18, math.min(0.85, 0.18 + pine * 0.42))
            love.graphics.rectangle("fill", tx + (ts * 0.12), ty + (ts * 0.58), math.max(0.9, ts * 0.2), math.max(0.9, ts * 0.32))
        end
        if rabbit > rabbit_visible_threshold then
            love.graphics.setColor(1.0, 0.92, 0.12, math.min(1.0, 0.35 + rabbit * 0.65))
            love.graphics.circle("fill", tx + (ts * 0.34), ty + (ts * 0.34), math.max(0.7, ts * 0.13))
            love.graphics.rectangle("fill", tx + (ts * 0.28), ty + (ts * 0.18), math.max(0.5, ts * 0.05), math.max(0.7, ts * 0.15))
            love.graphics.rectangle("fill", tx + (ts * 0.38), ty + (ts * 0.18), math.max(0.5, ts * 0.05), math.max(0.7, ts * 0.15))
        end
        if wolves > wolf_visible_threshold then
            love.graphics.setColor(0.95, 0.08, 0.08, math.min(1.0, 0.45 + wolves * 1.4))
            love.graphics.rectangle("fill", tx + (ts * 0.52), ty + (ts * 0.52), math.max(0.9, ts * 0.24), math.max(0.7, ts * 0.16))
            love.graphics.polygon(
                "fill",
                tx + (ts * 0.76), ty + (ts * 0.52),
                tx + (ts * 0.90), ty + (ts * 0.46),
                tx + (ts * 0.84), ty + (ts * 0.62)
            )
        end
    end
    for _, e in pairs(g.world.entities) do
        if e and e.alive then
            if selection.is_entity_inside_home_shelter(g, e) then
                goto continue_entity_draw
            end
            if e.sex == "male" then
                love.graphics.setColor(0.32, 0.7, 1, 1)
            elseif e.sex == "female" then
                love.graphics.setColor(1, 0.45, 0.75, 1)
            else
                love.graphics.setColor(1, 0.92, 0.32, 1)
            end
            love.graphics.rectangle("fill", (e.x - 1) * ts + object_offset, (e.y - 1) * ts + object_offset, object_px, object_px)
        end
        ::continue_entity_draw::
    end
    local buildings = g.world.buildings or {}
    for i = 1, #buildings do
        local b = buildings[i]
        if b and b.kind == "campfire" then
            if b.under_construction then
                love.graphics.setColor(0.75, 0.45, 0.18, 0.55)
            else
                love.graphics.setColor(1.0, 0.45, 0.08, 0.95)
            end
            love.graphics.circle("fill", (b.x - 1) * ts + half_ts, (b.y - 1) * ts + half_ts, building_radius)
        elseif b and b.kind == "shelter" then
            if b.under_construction then
                love.graphics.setColor(0.62, 0.52, 0.38, 0.55)
            else
                love.graphics.setColor(0.78, 0.62, 0.42, 0.95)
            end
            love.graphics.circle("fill", (b.x - 1) * ts + half_ts, (b.y - 1) * ts + half_ts, building_radius)
        end
    end
    local _sk, selected = selection.get_selected_object(g)
    if selected then
        love.graphics.setColor(1, 1, 1, 0.95)
        love.graphics.circle("line", (selected.x - 1) * ts + half_ts, (selected.y - 1) * ts + half_ts, selected_radius)
    end
    love.graphics.pop()
end

return M
