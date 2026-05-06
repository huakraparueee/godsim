--[[
  Play scene (god-game loop). Hot-reloads with lurker under src/.
  Prefer require("src.<folder>.<file>") for new modules under src/.
]]

local M = {}

local scenarios = require("src.data.scenarios")
local sim = require("src.core.sim")
local cam = require("src.utils.camera")
local pick = require("src.utils.pick")
local session = require("src.core.session")
local terraform = require("src.core.terraform")
local ui_menus = require("src.ui.menus")
local event_log = require("src.ui.event_log")
local world_draw = require("src.core.world_draw")
local world_visual_sync = require("src.core.world_visual_sync")
local hud = require("src.ui.hud")

local function clamp_time_scale(scale)
    local s = math.floor((scale or 1) + 0.5)
    if s < 1 then
        return 1
    end
    if s > 4 then
        return 4
    end
    return s
end

local function apply_adaptive_sim_profile(g)
    if not g.sim then
        return
    end
    local scale = clamp_time_scale(g.time_scale)
    if g._adaptive_last_scale == scale then
        return
    end

    local profiles = {
        [1] = { stats_stride = 2, max_steps_per_frame = 8 },
        [2] = { stats_stride = 4, max_steps_per_frame = 6 },
        [3] = { stats_stride = 8, max_steps_per_frame = 4 },
        [4] = { stats_stride = 16, max_steps_per_frame = 2 },
    }
    local p = profiles[scale] or profiles[1]
    g.sim.eco_slices = 6
    g.sim.stats_stride = p.stats_stride
    g.sim.max_steps_per_frame = p.max_steps_per_frame
    g.sim.max_accumulator = g.sim.step_dt * (g.sim.max_steps_per_frame + 1)
    g.time_scale = scale
    g._adaptive_last_scale = scale
end

local function update_visual_lod_state(g)
    if not (g and g.camera) then
        return
    end
    local z = g.camera.zoom or 1
    -- L0 = coarse only, L1 = low detail, L2 = full detail.
    local prev_lod = g.visual_lod
    local lod = prev_lod
    if lod == nil then
        if z < 1.02 then
            lod = 0
        elseif z < 1.22 then
            lod = 1
        else
            lod = 2
        end
    end

    if lod == 2 then
        if z < 1.14 then
            lod = 1
        end
    elseif lod == 1 then
        if z >= 1.26 then
            lod = 2
        elseif z < 0.98 then
            lod = 0
        end
    else
        if z >= 1.06 then
            lod = 1
        end
    end

    local prev_block = g.visual_coarse_block_tiles
    local prev_target = g.visual_coarse_target_px
    local coarse_target_px = (lod == 0) and 4 or 16
    local next_block = world_visual_sync.compute_coarse_block_tiles(g, coarse_target_px)
    g.visual_lod = lod
    g.visual_coarse_target_px = coarse_target_px
    g.visual_coarse_block_tiles = next_block

    if prev_lod ~= lod or prev_target ~= coarse_target_px or prev_block ~= next_block then
        world_visual_sync.invalidate(g)
    end
end

function M.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    M.scenario_id = "balanced"
    session.reset(M)
    M.camera = {
        x = 0,
        y = 0,
        zoom = 2.0,
        min_zoom = 1.0,
        max_zoom = 4.0,
        pan_speed = 420,
    }
    M.drag_pan = {
        active = false,
    }
    M.brush = {
        radius = 2,
        min_radius = 1,
        max_radius = 24,
        type_id = "forest",
        enabled = false,
        painting = false,
    }
    M.ui = ui_menus.build_brush_menu()
    M.sim_ui = ui_menus.build_sim_control_menu()
    M.speed_ui = ui_menus.build_speed_menu()
    M.scenario_ui = ui_menus.build_scenario_menu()
    M.sim_running = true
    M.time_scale = 1
    M.debug = {
        frame_ms = 0,
        update_ms = 0,
        render_ms = 0,
        sim_ms = 0,
        sim_steps = 0,
        fps = 0,
        gc_kb = 0,
    }
    M._adaptive_last_scale = nil
    apply_adaptive_sim_profile(M)
    cam.center_on_map(M)
    update_visual_lod_state(M)
end

function M.update(dt)
    local update_start = love.timer.getTime()
    apply_adaptive_sim_profile(M)
    local sim_dt = dt * (M.time_scale or 1)

    if not M.camera then
        return
    end

    local move_x = 0
    local move_y = 0

    if love.keyboard.isDown("left", "a") then
        move_x = move_x - 1
    end
    if love.keyboard.isDown("right", "d") then
        move_x = move_x + 1
    end
    if love.keyboard.isDown("up", "w") then
        move_y = move_y - 1
    end
    if love.keyboard.isDown("down", "s") then
        move_y = move_y + 1
    end

    local speed = M.camera.pan_speed / M.camera.zoom
    M.camera.x = M.camera.x + move_x * speed * dt
    M.camera.y = M.camera.y + move_y * speed * dt
    cam.update_bounds(M)
    update_visual_lod_state(M)

    if M.brush.painting and not M.drag_pan.active then
        terraform.apply_brush_at_mouse(M)
    end
    if M.sim_running then
        local sim_start = love.timer.getTime()
        M.debug.sim_steps = sim.update(M.sim, M.world, sim_dt)
        M.debug.sim_ms = (love.timer.getTime() - sim_start) * 1000
    else
        M.debug.sim_steps = 0
        M.debug.sim_ms = 0
    end

    world_visual_sync.maybe_sync(M)

    local update_elapsed_ms = (love.timer.getTime() - update_start) * 1000
    M.debug.frame_ms = dt * 1000
    M.debug.update_ms = update_elapsed_ms
    M.debug.fps = love.timer.getFPS()
    M.debug.gc_kb = collectgarbage("count")
end

function M.draw()
    local render_start = love.timer.getTime()
    love.graphics.clear(0.08, 0.09, 0.12, 1)
    local w = love.graphics.getWidth()
    local h = love.graphics.getHeight()
    local f = love.graphics.getFont()

    world_draw.draw(M)
    hud.draw(M, w, h, f)

    ui_menus.draw_sim_control_menu(M)
    ui_menus.draw_brush_menu(M)
    ui_menus.draw_speed_menu(M)
    ui_menus.draw_scenario_menu(M)
    event_log.draw_panel(M, w, h)
    love.graphics.setColor(1, 1, 1, 1)
    if M.debug then
        M.debug.render_ms = (love.timer.getTime() - render_start) * 1000
        hud.draw_debug_overlay(M, w, h, f)
    end
end

function M.keypressed(key, _scancode, _isrepeat)
    if key == "escape" then
        love.event.quit()
    end
    if key == "q" then
        M.camera.zoom = cam.clamp(M.camera.zoom * 0.9, M.camera.min_zoom, M.camera.max_zoom)
        cam.update_bounds(M)
        update_visual_lod_state(M)
    elseif key == "e" then
        M.camera.zoom = cam.clamp(M.camera.zoom * 1.1, M.camera.min_zoom, M.camera.max_zoom)
        cam.update_bounds(M)
        update_visual_lod_state(M)
    elseif key == "n" then
        session.reset(M)
        M._adaptive_last_scale = nil
        apply_adaptive_sim_profile(M)
        cam.center_on_map(M)
        update_visual_lod_state(M)
    elseif key == "f2" then
        local ids = scenarios.list_ids()
        local idx = 1
        for i = 1, #ids do
            if ids[i] == M.scenario_id then
                idx = i
                break
            end
        end
        idx = (idx % #ids) + 1
        M.scenario_id = ids[idx]
        session.reset(M)
        M._adaptive_last_scale = nil
        apply_adaptive_sim_profile(M)
        cam.center_on_map(M)
        update_visual_lod_state(M)
    end
end

function M.wheelmoved(_x, y)
    if not M.camera or y == 0 then
        return
    end
    local factor = (y > 0) and 1.1 or 0.9
    M.camera.zoom = cam.clamp(M.camera.zoom * factor, M.camera.min_zoom, M.camera.max_zoom)
    cam.update_bounds(M)
    update_visual_lod_state(M)
end

function M.resize(_w, _h)
    if M.camera then
        cam.update_bounds(M)
    end
end

function M.mousepressed(x, y, button, _istouch, _presses)
    if button == 3 and M.drag_pan then
        M.drag_pan.active = true
    elseif button == 1 and M.brush then
        local mx, my = x, y
        if ui_menus.handle_sim_control_click(M, mx, my) then
            return
        end
        if ui_menus.handle_brush_menu_click(M, mx, my) then
            return
        end
        if ui_menus.handle_speed_menu_click(M, mx, my) then
            return
        end
        if ui_menus.handle_scenario_menu_click(M, mx, my) then
            return
        end
        local picked_building_index = pick.building_index_at_screen(M, mx, my)
        if picked_building_index then
            M.selected_object = { kind = "building", index = picked_building_index }
            return
        end
        local picked_entity = pick.entity_at_screen(M, mx, my)
        if picked_entity then
            M.selected_object = { kind = "entity", id = picked_entity.id }
            return
        end
        if M.brush.enabled then
            M.brush.painting = true
            terraform.apply_brush_at_mouse(M)
        else
            M.selected_object = nil
        end
    end
end

function M.mousereleased(_x, _y, button)
    if button == 3 and M.drag_pan then
        M.drag_pan.active = false
    elseif button == 1 and M.brush then
        M.brush.painting = false
    end
end

function M.mousemoved(_x, _y, dx, dy)
    if not (M.camera and M.drag_pan and M.drag_pan.active) then
        return
    end
    M.camera.x = M.camera.x - (dx / M.camera.zoom)
    M.camera.y = M.camera.y - (dy / M.camera.zoom)
    cam.update_bounds(M)
end

return M
