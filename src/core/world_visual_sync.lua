--[[
  Build tile resource overlays off-screen during update(); draw phase only blits Canvas.
  Skips rebuild when simulation did not advance and terraform did not touch tiles.
]]

local entity_config = require("src.data.config_entities")

local M = {}

function M.invalidate(g)
    if g then
        g.vis_overlay_dirty = true
        g.vis_overlay_coarse_dirty = true
        g._overlay_tick_cadence = 0
    end
end

function M.compute_coarse_block_tiles(g, target_screen_px)
    if not (g and g.camera and g.renderer) then
        return 2
    end
    local ts = g.renderer.tile_size or 4
    local zoom = g.camera.zoom or 1
    local tile_screen_px = ts * zoom
    if tile_screen_px <= 0 then
        return 2
    end
    local desired_screen_px = target_screen_px or 4
    local block_tiles = math.ceil(desired_screen_px / tile_screen_px)
    if block_tiles < 1 then
        block_tiles = 1
    elseif block_tiles > 12 then
        block_tiles = 12
    end
    return block_tiles
end

local function ensure_canvas(g)
    local ts = g.renderer.tile_size
    local w_px = g.world.width * ts
    local h_px = g.world.height * ts
    if not g.overlay_canvas or g.overlay_canvas:getWidth() ~= w_px or g.overlay_canvas:getHeight() ~= h_px then
        g.overlay_canvas = love.graphics.newCanvas(w_px, h_px)
        g.overlay_canvas:setFilter("nearest", "nearest")
        g.vis_overlay_dirty = true
    end
end

local function ensure_coarse_canvas(g)
    local ts = g.renderer.tile_size
    local w_px = g.world.width * ts
    local h_px = g.world.height * ts
    if not g.overlay_canvas_coarse or g.overlay_canvas_coarse:getWidth() ~= w_px or g.overlay_canvas_coarse:getHeight() ~= h_px then
        g.overlay_canvas_coarse = love.graphics.newCanvas(w_px, h_px)
        g.overlay_canvas_coarse:setFilter("nearest", "nearest")
        g.vis_overlay_coarse_dirty = true
    end
end

local function repaint_tile_overlays(g)
    local w = g.world
    local ts = g.renderer.tile_size
    local tiles = w.tiles
    local tile_w = w.width
    local resource_cfg = entity_config.RESOURCE or {}
    local rabbit_visible_threshold = resource_cfg.WILDLIFE_MIN_TO_HUNT or 0.18
    local wolf_visible_threshold = resource_cfg.WOLF_MIN_TO_HUNT or 0.08

    for i = 1, #tiles do
        local tile = tiles[i]
        local fruit = tile.apple_fruit or 0
        local pine = tile.pine_wood or 0
        local rabbit = tile.wildlife or 0
        local wolves = tile.wolves or 0
        local tx = ((i - 1) % tile_w) * ts
        local ty = math.floor((i - 1) / tile_w) * ts
        if fruit > 0.01 then
            love.graphics.setColor(1.0, 0.58, 0.08, math.min(0.78, 0.42 + fruit * 0.55))
            local r = math.max(1.2, ts * 0.2)
            local fx = tx + (ts * 0.72) - r
            local fy = ty + (ts * 0.24) - r
            love.graphics.rectangle("fill", fx, fy, r * 2, r * 2)
        end
        if pine > 0.2 then
            love.graphics.setColor(0.18, 0.62, 0.18, math.min(0.85, 0.18 + pine * 0.42))
            love.graphics.rectangle("fill", tx + (ts * 0.12), ty + (ts * 0.58), math.max(0.9, ts * 0.2), math.max(0.9, ts * 0.32))
        end
        if rabbit > rabbit_visible_threshold then
            love.graphics.setColor(1.0, 0.92, 0.12, math.min(1.0, 0.35 + rabbit * 0.65))
            local br = math.max(0.7, ts * 0.13)
            local rbx = tx + (ts * 0.34) - br
            local rby = ty + (ts * 0.34) - br
            love.graphics.rectangle("fill", rbx, rby, br * 2, br * 2)
            love.graphics.rectangle("fill", tx + (ts * 0.28), ty + (ts * 0.18), math.max(0.5, ts * 0.05), math.max(0.7, ts * 0.15))
            love.graphics.rectangle("fill", tx + (ts * 0.38), ty + (ts * 0.18), math.max(0.5, ts * 0.05), math.max(0.7, ts * 0.15))
        end
        if wolves > wolf_visible_threshold then
            love.graphics.setColor(0.95, 0.08, 0.08, math.min(1.0, 0.45 + wolves * 1.4))
            love.graphics.rectangle("fill", tx + (ts * 0.52), ty + (ts * 0.52), math.max(0.9, ts * 0.24), math.max(0.7, ts * 0.16))
            love.graphics.rectangle("fill", tx + (ts * 0.72), ty + (ts * 0.44), math.max(0.6, ts * 0.18), math.max(0.5, ts * 0.14))
        end
    end
end

local BIOME_COLORS = {
    deep_water = { 0.08, 0.2, 0.45 },
    shallow_water = { 0.15, 0.4, 0.7 },
    sand = { 0.78, 0.72, 0.44 },
    grass = { 0.3, 0.56, 0.26 },
    forest = { 0.14, 0.42, 0.16 },
    mountain = { 0.5, 0.5, 0.52 },
}

local function repaint_coarse_overlay(g)
    local w = g.world
    local ts = g.renderer.tile_size
    local tiles = w.tiles
    local block = g.visual_coarse_block_tiles or M.compute_coarse_block_tiles(g, g.visual_coarse_target_px or 4)
    local block_px = ts * block
    local width = w.width
    local height = w.height
    for gy = 1, height, block do
        for gx = 1, width, block do
            local counts = {}
            local fruit_sum = 0
            local pine_sum = 0
            local wildlife_sum = 0
            local wolves_sum = 0
            local sample_count = 0
            for by = gy, math.min(height, gy + block - 1) do
                local row = (by - 1) * width
                for bx = gx, math.min(width, gx + block - 1) do
                    local idx = row + bx
                    local tile = tiles[idx]
                    if tile then
                        local type_id = tile.type_id or "grass"
                        counts[type_id] = (counts[type_id] or 0) + 1
                        fruit_sum = fruit_sum + (tile.apple_fruit or 0)
                        pine_sum = pine_sum + (tile.pine_wood or 0)
                        wildlife_sum = wildlife_sum + (tile.wildlife or 0)
                        wolves_sum = wolves_sum + (tile.wolves or 0)
                        sample_count = sample_count + 1
                    end
                end
            end
            local dominant = "grass"
            local dominant_count = 0
            for type_id, c in pairs(counts) do
                if c > dominant_count then
                    dominant = type_id
                    dominant_count = c
                end
            end
            local base = BIOME_COLORS[dominant] or BIOME_COLORS.grass
            local fruit = (sample_count > 0) and (fruit_sum / sample_count) or 0
            local pine = (sample_count > 0) and (pine_sum / sample_count) or 0
            local wildlife = (sample_count > 0) and (wildlife_sum / sample_count) or 0
            local wolves = (sample_count > 0) and (wolves_sum / sample_count) or 0
            local r = math.min(1, base[1] + (fruit * 0.35))
            local gch = math.min(1, base[2] + (pine * 0.18) + (wildlife * 0.1))
            local b = math.min(1, base[3] + (wolves * 0.35))
            love.graphics.setColor(r, gch, b, 1)
            love.graphics.rectangle("fill", (gx - 1) * ts, (gy - 1) * ts, block_px, block_px)
        end
    end
end

-- Overlay refresh stride by time_scale (cheap vs sim every frame when speed > x1).
local OVERLAY_STRIDE = {
    [1] = 1,
    [2] = 2,
    [3] = 3,
    [4] = 4,
}

function M.maybe_sync(g)
    local steps = (g.debug and g.debug.sim_steps) or 0
    if not (g.vis_overlay_dirty or g.vis_overlay_coarse_dirty or steps > 0) then
        return
    end
    if not (g.world and g.renderer and love.graphics) then
        return
    end

    local ts = math.floor((g.time_scale or 1) + 1e-6)
    if ts > 4 then
        ts = 4
    end
    if ts < 1 then
        ts = 1
    end

    local stride = OVERLAY_STRIDE[ts] or 1
    if (not g.vis_overlay_dirty) and (not g.vis_overlay_coarse_dirty) and stride > 1 then
        g._overlay_tick_cadence = (g._overlay_tick_cadence or 0) + 1
        if (g._overlay_tick_cadence % stride) ~= 0 then
            return
        end
    end

    local lod = g.visual_lod or 1
    if lod <= 0 then
        ensure_coarse_canvas(g)
    else
        ensure_canvas(g)
    end

    love.graphics.push("all")
    if lod <= 0 then
        love.graphics.setCanvas(g.overlay_canvas_coarse)
    else
        love.graphics.setCanvas(g.overlay_canvas)
    end
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setBlendMode("alpha")
    if lod <= 0 then
        repaint_coarse_overlay(g)
    else
        repaint_tile_overlays(g)
    end
    love.graphics.setCanvas()
    love.graphics.pop("all")

    love.graphics.setColor(1, 1, 1, 1)
    if lod <= 0 then
        g.vis_overlay_coarse_dirty = false
    else
        g.vis_overlay_dirty = false
    end
end

return M
