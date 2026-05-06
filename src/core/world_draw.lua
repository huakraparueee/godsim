--[[
  Map transform, tile overlay bitmap (built in update via world_visual_sync), entities, buildings.
]]

local selection = require("src.core.selection")
local cam = require("src.utils.camera")

local M = {}
local TREE_SHEET_PATH = "src/assets/tree48x48_8frame.png"
local TREE_FRAME_SIZE = 48
local TREE_ANIM_FPS = 1
local HUMAN_M_SHEET_PATH = "src/assets/human_m_48x48_4frame_4direct_1atk_1die.png"
local HUMAN_F_SHEET_PATH = "src/assets/human_f_48x48_4frame_4direct_1atk_1die.png"
local HUMAN_FRAME_SIZE = 48
local HUMAN_ANIM_FPS = 6
local SHELTER_SHEET_PATH = "src/assets/shelter48x48_4frame.png"
local SHELTER_FRAME_SIZE = 48
local SHELTER_ANIM_FPS = 2
local RABBIT_SHEET_PATH = "src/assets/rabbit48x48_4frame.png"
local RABBIT_FRAME_SIZE = 48
local RABBIT_ANIM_FPS = 4
local tree_sprite = nil
local human_sprites = {}
local shelter_sprite = nil
local rabbit_sprite = nil

local function clamp(v, min_v, max_v)
    if v < min_v then
        return min_v
    end
    if v > max_v then
        return max_v
    end
    return v
end

local function ensure_tree_sprite()
    if tree_sprite ~= nil then
        return tree_sprite
    end
    if not love.filesystem.getInfo(TREE_SHEET_PATH) then
        tree_sprite = false
        return tree_sprite
    end
    local image = love.graphics.newImage(TREE_SHEET_PATH)
    image:setFilter("nearest", "nearest")
    local iw, ih = image:getDimensions()
    local cols = math.max(1, math.floor(iw / TREE_FRAME_SIZE))
    local rows = math.max(1, math.floor(ih / TREE_FRAME_SIZE))
    local total = math.min(8, cols * rows)
    local quads = {}
    for i = 1, total do
        local idx = i - 1
        local cx = idx % cols
        local cy = math.floor(idx / cols)
        quads[i] = love.graphics.newQuad(
            cx * TREE_FRAME_SIZE,
            cy * TREE_FRAME_SIZE,
            TREE_FRAME_SIZE,
            TREE_FRAME_SIZE,
            iw,
            ih
        )
    end
    tree_sprite = { image = image, quads = quads, count = total }
    return tree_sprite
end

local function load_human_sprite(sheet_path)
    if not love.filesystem.getInfo(sheet_path) then
        return false
    end
    local image = love.graphics.newImage(sheet_path)
    image:setFilter("nearest", "nearest")
    local iw, ih = image:getDimensions()
    local cols = math.max(1, math.floor(iw / HUMAN_FRAME_SIZE))
    local rows = math.max(1, math.floor(ih / HUMAN_FRAME_SIZE))
    local frames = math.min(4, cols)
    local function build_row(row_idx)
        local row = {}
        for i = 1, frames do
            row[i] = love.graphics.newQuad(
                (i - 1) * HUMAN_FRAME_SIZE,
                row_idx * HUMAN_FRAME_SIZE,
                HUMAN_FRAME_SIZE,
                HUMAN_FRAME_SIZE,
                iw,
                ih
            )
        end
        return row
    end
    local down = build_row(math.min(0, rows - 1))
    local up = build_row(math.min(1, rows - 1))
    local left = build_row(math.min(2, rows - 1))
    local right = build_row(math.min(3, rows - 1))
    local atk = build_row(math.min(4, rows - 1))
    local die = build_row(math.min(5, rows - 1))
    return {
        image = image,
        frames = frames,
        rows = { up = up, down = down, left = left, right = right, attack = atk, die = die },
    }
end

local function ensure_human_sprite(sex)
    local key = (sex == "female") and "female" or "male"
    if human_sprites[key] ~= nil then
        return human_sprites[key]
    end
    local primary_path = (key == "female") and HUMAN_F_SHEET_PATH or HUMAN_M_SHEET_PATH
    local fallback_path = (key == "female") and HUMAN_M_SHEET_PATH or HUMAN_F_SHEET_PATH
    local sprite = load_human_sprite(primary_path)
    if sprite == false then
        sprite = load_human_sprite(fallback_path)
    end
    human_sprites[key] = sprite
    return sprite
end

local function ensure_shelter_sprite()
    if shelter_sprite ~= nil then
        return shelter_sprite
    end
    if not love.filesystem.getInfo(SHELTER_SHEET_PATH) then
        shelter_sprite = false
        return shelter_sprite
    end
    local image = love.graphics.newImage(SHELTER_SHEET_PATH)
    image:setFilter("nearest", "nearest")
    local iw, ih = image:getDimensions()
    local cols = math.max(1, math.floor(iw / SHELTER_FRAME_SIZE))
    local frames = math.min(4, cols)
    local quads = {}
    for i = 1, frames do
        quads[i] = love.graphics.newQuad(
            (i - 1) * SHELTER_FRAME_SIZE,
            0,
            SHELTER_FRAME_SIZE,
            SHELTER_FRAME_SIZE,
            iw,
            ih
        )
    end
    shelter_sprite = { image = image, quads = quads, frames = frames }
    return shelter_sprite
end

local function ensure_rabbit_sprite()
    if rabbit_sprite ~= nil then
        return rabbit_sprite
    end
    if not love.filesystem.getInfo(RABBIT_SHEET_PATH) then
        rabbit_sprite = false
        return rabbit_sprite
    end
    local image = love.graphics.newImage(RABBIT_SHEET_PATH)
    image:setFilter("nearest", "nearest")
    local iw, ih = image:getDimensions()
    local cols = math.max(1, math.floor(iw / RABBIT_FRAME_SIZE))
    local frames = math.min(4, cols)
    local quads = {}
    for i = 1, frames do
        quads[i] = love.graphics.newQuad(
            (i - 1) * RABBIT_FRAME_SIZE,
            0,
            RABBIT_FRAME_SIZE,
            RABBIT_FRAME_SIZE,
            iw,
            ih
        )
    end
    rabbit_sprite = { image = image, quads = quads, frames = frames }
    return rabbit_sprite
end

local function resolve_entity_dir(e)
    local vx = e.vx or 0
    local vy = e.vy or 0
    if math.abs(vx) > math.abs(vy) then
        if vx >= 0.01 then
            return "right"
        elseif vx <= -0.01 then
            return "left"
        end
    else
        if vy >= 0.01 then
            return "down"
        elseif vy <= -0.01 then
            return "up"
        end
    end
    return e._sprite_dir or "down"
end

local function draw_entity_layer(g, ts)
    local male_sprite = ensure_human_sprite("male")
    local female_sprite = ensure_human_sprite("female")
    if (male_sprite and male_sprite ~= false and male_sprite.frames > 0) or (female_sprite and female_sprite ~= false and female_sprite.frames > 0) then
        local t = love.timer.getTime()
        local human_px = math.max(14, ts * 3.5)
        local scale = human_px / HUMAN_FRAME_SIZE
        for _, e in pairs(g.world.entities) do
            if e and e.alive then
                if selection.is_entity_inside_home_shelter(g, e) then
                    goto continue_entity_sprite_draw
                end
                local dir = resolve_entity_dir(e)
                e._sprite_dir = dir
                local state = string.lower(e.state or "")
                local moving = (math.abs(e.vx or 0) + math.abs(e.vy or 0)) > 0.02
                local row_key = dir
                if state:find("attack", 1, true) then
                    row_key = "attack"
                elseif state:find("die", 1, true) or state:find("dead", 1, true) then
                    row_key = "die"
                end
                local sprite = (e.sex == "female") and female_sprite or male_sprite
                if sprite == false or not sprite or sprite.frames <= 0 then
                    sprite = male_sprite
                end
                if sprite == false or not sprite or sprite.frames <= 0 then
                    goto continue_entity_sprite_draw
                end
                local row = sprite.rows[row_key] or sprite.rows.down
                local phase = (e.id or 0) % sprite.frames
                local frame = 1
                if row_key == "attack" or row_key == "die" or moving then
                    frame = (math.floor(t * HUMAN_ANIM_FPS + phase) % sprite.frames) + 1
                end
                love.graphics.setColor(1, 1, 1, 1)
                local x = (e.x - 1) * ts + (ts * 0.5) - (human_px * 0.5)
                local y = (e.y - 1) * ts + ts - human_px
                love.graphics.draw(sprite.image, row[frame], x, y, 0, scale, scale)
            end
            ::continue_entity_sprite_draw::
        end
        love.graphics.setColor(1, 1, 1, 1)
        return
    end

    -- Fallback when sprite sheet is missing/invalid.
    local object_px = 1
    local object_offset = (ts - object_px) * 0.5
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
end

local function tree_hash(gx, gy, seed)
    return (gx * 73856093 + gy * 19349663 + seed * 83492791) % 1000003
end

local function tree_candidate_score(gx, gy, seed)
    return tree_hash(gx, gy, seed) % 1000
end

local function should_draw_tree_at(w, gx, gy, seed)
    local center = tree_candidate_score(gx, gy, seed)
    if center >= 700 then
        return false
    end
    -- Keep nearest-neighbor spacing: this tile wins only if it has
    -- the best score among 8-connected neighbors.
    for ny = math.max(1, gy - 1), math.min(w.height, gy + 1) do
        for nx = math.max(1, gx - 1), math.min(w.width, gx + 1) do
            if not (nx == gx and ny == gy) then
                local neighbor = tree_candidate_score(nx, ny, seed)
                if neighbor < center then
                    return false
                end
            end
        end
    end
    return true
end

local function draw_tree_layer(g, ts)
    local sprite = ensure_tree_sprite()
    if not sprite or sprite == false or sprite.count == 0 then
        return
    end
    local w = g.world
    local zoom = g.camera.zoom or 1
    local sw = love.graphics.getWidth()
    local sh = love.graphics.getHeight()
    local view_w = sw / zoom
    local view_h = sh / zoom
    local x0 = g.camera.x
    local y0 = g.camera.y
    local x1 = x0 + view_w
    local y1 = y0 + view_h
    local gx0 = clamp(math.floor(x0 / ts), 0, w.width - 1) + 1
    local gy0 = clamp(math.floor(y0 / ts), 0, w.height - 1) + 1
    local gx1 = clamp(math.floor(x1 / ts), 0, w.width - 1) + 1
    local gy1 = clamp(math.floor(y1 / ts), 0, w.height - 1) + 1
    local visible_tiles = (gx1 - gx0 + 1) * (gy1 - gy0 + 1)
    local stride = 1
    if visible_tiles > 40000 then
        stride = 3
    elseif visible_tiles > 18000 then
        stride = 2
    end
    local tree_px = math.max(16, ts * 4)
    local scale = tree_px / TREE_FRAME_SIZE
    local seed = g.world.seed or 1
    local anim_t = love.timer.getTime() * TREE_ANIM_FPS
    love.graphics.setColor(1, 1, 1, 0.95)
    for gy = gy0, gy1, stride do
        local row = (gy - 1) * w.width
        for gx = gx0, gx1, stride do
            local tile = w.tiles[row + gx]
            if tile and tile.type_id == "forest" then
                local pine = tile.pine_wood or 0
                if tile.has_apple_tree or pine > 0.45 then
                    if should_draw_tree_at(w, gx, gy, seed) then
                        local hash = tree_candidate_score(gx, gy, seed)
                        local phase = hash % sprite.count
                        local frame = (math.floor(anim_t + phase) % sprite.count) + 1
                        local x = (gx - 1) * ts + (ts * 0.5) - (tree_px * 0.5)
                        local y = (gy - 1) * ts + ts - tree_px
                        love.graphics.draw(sprite.image, sprite.quads[frame], x, y, 0, scale, scale)
                    end
                end
            end
        end
    end
end

local function draw_shelter_sprite(b, ts)
    local sprite = ensure_shelter_sprite()
    if not sprite or sprite == false or sprite.frames <= 0 then
        return false
    end
    local t = love.timer.getTime()
    local phase = (math.floor((b.uid or 0)) % sprite.frames)
    local frame = (math.floor(t * SHELTER_ANIM_FPS + phase) % sprite.frames) + 1
    local shelter_px = math.max(18, ts * 5)
    local scale = shelter_px / SHELTER_FRAME_SIZE
    local x = (b.x - 1) * ts + (ts * 0.5) - (shelter_px * 0.5)
    local y = (b.y - 1) * ts + ts - shelter_px
    if b.under_construction then
        love.graphics.setColor(1, 1, 1, 0.6)
    else
        love.graphics.setColor(1, 1, 1, 1)
    end
    love.graphics.draw(sprite.image, sprite.quads[frame], x, y, 0, scale, scale)
    return true
end

local function rabbit_candidate_score(gx, gy, seed)
    return (gx * 92837111 + gy * 689287499 + seed * 283923481) % 1000003
end

local function should_draw_rabbit_tile(w, gx, gy, seed, radius)
    local r = radius or 1
    local center = rabbit_candidate_score(gx, gy, seed)
    for ny = math.max(1, gy - r), math.min(w.height, gy + r) do
        for nx = math.max(1, gx - r), math.min(w.width, gx + r) do
            if not (nx == gx and ny == gy) then
                local n = rabbit_candidate_score(nx, ny, seed)
                if n < center then
                    return false
                end
            end
        end
    end
    return true
end

local function draw_rabbit_layer(g, ts)
    local sprite = ensure_rabbit_sprite()
    if not sprite or sprite == false or sprite.frames <= 0 then
        return
    end
    local w = g.world
    local zoom = g.camera.zoom or 1
    local sw = love.graphics.getWidth()
    local sh = love.graphics.getHeight()
    local view_w = sw / zoom
    local view_h = sh / zoom
    local x0 = g.camera.x
    local y0 = g.camera.y
    local x1 = x0 + view_w
    local y1 = y0 + view_h
    local gx0 = clamp(math.floor(x0 / ts), 0, w.width - 1) + 1
    local gy0 = clamp(math.floor(y0 / ts), 0, w.height - 1) + 1
    local gx1 = clamp(math.floor(x1 / ts), 0, w.width - 1) + 1
    local gy1 = clamp(math.floor(y1 / ts), 0, w.height - 1) + 1
    local t = love.timer.getTime()
    local rabbit_px = math.max(10, ts * 2.8)
    local scale = rabbit_px / RABBIT_FRAME_SIZE
    for gy = gy0, gy1 do
        local row = (gy - 1) * w.width
        for gx = gx0, gx1 do
            local tile = w.tiles[row + gx]
            local rabbit_pop = tile and (tile.wildlife or 0) or 0
            if rabbit_pop > 0.16 then
                local seed = w.seed or 1
                local hash = rabbit_candidate_score(gx, gy, seed)
                local score01 = (hash % 1000) / 999
                -- Wildlife drives visibility probability directly.
                local show_chance = clamp((rabbit_pop - 0.16) / 0.6, 0, 1)
                if score01 <= show_chance and should_draw_rabbit_tile(w, gx, gy, seed, 1) then
                    local density = 1
                    -- Very high wildlife can show 2 rabbits, but only on wider spacing winners.
                    if rabbit_pop > 0.62 and should_draw_rabbit_tile(w, gx, gy, seed + 17, 2) then
                        local second_chance = clamp((rabbit_pop - 0.62) / 0.38, 0, 1) * 0.5
                        if (((hash + 211) % 1000) / 999) <= second_chance then
                            density = 2
                        end
                    end
                    for i = 1, density do
                        local phase = (hash + (i * 37)) % sprite.frames
                        local frame = (math.floor(t * RABBIT_ANIM_FPS + phase) % sprite.frames) + 1
                        local ox = (((hash + i * 97) % 100) / 100 - 0.5) * (ts * 0.55)
                        local oy = (((hash + i * 53) % 100) / 100 - 0.5) * (ts * 0.35)
                        local x = (gx - 1) * ts + (ts * 0.5) - (rabbit_px * 0.5) + ox
                        local y = (gy - 1) * ts + ts - rabbit_px + oy
                        love.graphics.setColor(1, 1, 1, 0.95)
                        love.graphics.draw(sprite.image, sprite.quads[frame], x, y, 0, scale, scale)
                    end
                end
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function M.draw(g)
    if not (g.renderer and g.camera) then
        return
    end

    local map_offset_x, map_offset_y = cam.screen_offset()
    love.graphics.push()
    love.graphics.translate(map_offset_x, map_offset_y)
    love.graphics.scale(g.camera.zoom, g.camera.zoom)
    love.graphics.translate(-g.camera.x, -g.camera.y)
    local lod = g.visual_lod or 1
    if lod <= 0 then
        if g.overlay_canvas_coarse then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(g.overlay_canvas_coarse, 0, 0)
        else
            -- Fallback when coarse canvas has not been built yet.
            g.renderer:draw(0, 0)
        end
    else
        g.renderer:draw(0, 0)
        if g.overlay_canvas then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(g.overlay_canvas, 0, 0)
        end
    end
    if lod <= 0 then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.pop()
        return
    end
    local ts = g.renderer.tile_size
    local half_ts = ts * 0.5
    if lod >= 2 then
        draw_tree_layer(g, ts)
        draw_rabbit_layer(g, ts)
    end
    local building_px = 4
    local building_radius = building_px * 0.5
    local selected_radius = math.max(2.0, ts * 0.75)
    if lod >= 2 then
        draw_entity_layer(g, ts)
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
            local drew_sprite = false
            if lod >= 2 then
                drew_sprite = draw_shelter_sprite(b, ts)
            end
            if not drew_sprite then
                if b.under_construction then
                    love.graphics.setColor(0.62, 0.52, 0.38, 0.55)
                else
                    love.graphics.setColor(0.78, 0.62, 0.42, 0.95)
                end
                love.graphics.circle("fill", (b.x - 1) * ts + half_ts, (b.y - 1) * ts + half_ts, building_radius)
            end
        end
    end
    local _sk, selected = selection.get_selected_object(g)
    if selected and lod >= 2 then
        love.graphics.setColor(1, 1, 1, 0.95)
        love.graphics.circle("line", (selected.x - 1) * ts + half_ts, (selected.y - 1) * ts + half_ts, selected_radius)
    end
    love.graphics.pop()
end

return M
