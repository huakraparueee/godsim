--[[
  Entry module for gameplay. Edits here hot-reload in dev (save file while the game runs).
  New files: require as "src.<name>" (e.g. require "src.world") so lurker modnames match.
]]

local M = {}
local world = require("src.world")
local map_renderer = require("src.map_renderer")
local entities = require("src.entities")
local sim = require("src.sim")
local scenarios = require("src.scenarios")
local entity_config = require("src.config_entities")
local entity_requirements = require("src.entity_requirements")
local DAYS_PER_YEAR = 365
local EVENT_LOG_MAX = 8

local function clamp(v, min_v, max_v)
    if v < min_v then
        return min_v
    end
    if v > max_v then
        return max_v
    end
    return v
end

local function update_camera_bounds()
    if not (M.camera and M.world and M.renderer) then
        return
    end

    local sw = love.graphics.getWidth()
    local sh = love.graphics.getHeight()
    local map_w = M.world.width * M.renderer.tile_size
    local map_h = M.world.height * M.renderer.tile_size

    local view_w = sw / M.camera.zoom
    local view_h = sh / M.camera.zoom
    local half_view_w = view_w * 0.5
    local half_view_h = view_h * 0.5
    local center_x = M.camera.x + half_view_w
    local center_y = M.camera.y + half_view_h

    center_x = clamp(center_x, 0, map_w)
    center_y = clamp(center_y, 0, map_h)

    M.camera.x = center_x - half_view_w
    M.camera.y = center_y - half_view_h
end

local function center_camera_on_map()
    if not (M.camera and M.world and M.renderer) then
        return
    end

    local sw = love.graphics.getWidth()
    local sh = love.graphics.getHeight()
    local map_w = M.world.width * M.renderer.tile_size
    local map_h = M.world.height * M.renderer.tile_size
    local view_w = sw / M.camera.zoom
    local view_h = sh / M.camera.zoom

    M.camera.x = (map_w - view_w) * 0.5
    M.camera.y = (map_h - view_h) * 0.5
    update_camera_bounds()
end

local function get_map_screen_offset()
    return 0, 0
end

local function screen_to_world(mouse_x, mouse_y)
    local offset_x, offset_y = get_map_screen_offset()
    local wx = ((mouse_x - offset_x) / M.camera.zoom) + M.camera.x
    local wy = ((mouse_y - offset_y) / M.camera.zoom) + M.camera.y
    return wx, wy
end

local function screen_to_grid(mouse_x, mouse_y)
    local wx, wy = screen_to_world(mouse_x, mouse_y)
    local ts = M.renderer.tile_size
    local gx = math.floor(wx / ts) + 1
    local gy = math.floor(wy / ts) + 1
    return gx, gy
end

local function apply_terraform_brush_at_mouse()
    if not (M.world and M.renderer and M.brush) then
        return
    end

    local mx, my = love.mouse.getPosition()
    local gx, gy = screen_to_grid(mx, my)
    local changed = world.brush(M.world, gx, gy, M.brush.radius, M.brush.type_id)
    if changed and changed > 0 then
        M.renderer:rebuild(M.world)
    end
end

local function pick_entity_at_screen(mouse_x, mouse_y)
    if not (M.world and M.renderer and M.camera) then
        return nil
    end
    local wx, wy = screen_to_world(mouse_x, mouse_y)
    local pick_radius = 1.25 -- in tile-space units
    local best
    local best_d2 = pick_radius * pick_radius
    for _, e in pairs(M.world.entities) do
        if e and e.alive then
            local dx = e.x - (wx / M.renderer.tile_size + 1)
            local dy = e.y - (wy / M.renderer.tile_size + 1)
            local d2 = dx * dx + dy * dy
            if d2 <= best_d2 then
                best = e
                best_d2 = d2
            end
        end
    end
    return best
end

local function pick_building_at_screen(mouse_x, mouse_y)
    if not (M.world and M.renderer and M.camera) then
        return nil
    end
    local wx, wy = screen_to_world(mouse_x, mouse_y)
    local pick_radius = 1.1 -- in tile-space units
    local best_index
    local best_d2 = pick_radius * pick_radius
    local buildings = M.world.buildings or {}
    for i = 1, #buildings do
        local b = buildings[i]
        if b then
            local dx = b.x - (wx / M.renderer.tile_size + 1)
            local dy = b.y - (wy / M.renderer.tile_size + 1)
            local d2 = dx * dx + dy * dy
            if d2 <= best_d2 then
                best_index = i
                best_d2 = d2
            end
        end
    end
    return best_index
end

local function get_selected_object()
    if not (M and M.world and M.selected_object) then
        return nil, nil
    end
    if M.selected_object.kind == "entity" then
        return "entity", entities.get_by_id(M.world, M.selected_object.id)
    end
    if M.selected_object.kind == "building" then
        local b = M.world.buildings and M.world.buildings[M.selected_object.index]
        if b then
            return "building", b
        end
    end
    return nil, nil
end

local function get_home_shelter(entity)
    if not (M and M.world and entity and entity.home_shelter_id) then
        return nil
    end
    local buildings = M.world.buildings or {}
    for i = 1, #buildings do
        local b = buildings[i]
        if b and b.kind == "shelter" and b.id == entity.home_shelter_id then
            return b
        end
    end
    return nil
end

local function is_entity_inside_home_shelter(entity)
    if not (M and M.world and entity and entity.home_shelter_id) then
        return false
    end
    local buildings = M.world.buildings or {}
    for i = 1, #buildings do
        local b = buildings[i]
        if b and b.kind == "shelter" and b.id == entity.home_shelter_id then
            local dx = (entity.x or 0) - (b.x or 0)
            local dy = (entity.y or 0) - (b.y or 0)
            return (dx * dx + dy * dy) <= (0.9 * 0.9)
        end
    end
    return false
end

local function summarize_buildings(w)
    local total = 0
    local shelters = 0
    local others_build = 0
    local under_construction = 0
    local buildings = (w and w.buildings) or {}
    for i = 1, #buildings do
        local b = buildings[i]
        if b then
            total = total + 1
            if b.kind == "shelter" then
                shelters = shelters + 1
            elseif b.kind == "campfire" then
                others_build = others_build + 1
            end
            if b.under_construction then
                under_construction = under_construction + 1
            end
        end
    end
    return total, shelters, others_build, under_construction
end

local function get_shelter_repro_status(shelter)
    local status = {
        male_ready = 0,
        female_ready = 0,
        male_block = nil,
        female_block = nil,
    }
    if not (M and M.world and shelter and shelter.residents) then
        return status
    end

    for i = 1, #shelter.residents do
        local resident = M.world.entities[shelter.residents[i]]
        if resident and resident.alive and resident.home_shelter_id == shelter.id then
            local rule_id = (resident.sex == "male") and "reproduce_male" or "reproduce_female"
            local ok, reason = entity_requirements.can_do(rule_id, resident)
            local cooldown = (resident.reproduction_cooldown or 0) > 0
            local age_ok = true
            if resident.sex == "female" then
                age_ok = resident.age >= entity_config.REPRO.FEMALE_MIN_AGE and resident.age <= entity_config.REPRO.FEMALE_MAX_AGE
            elseif resident.sex == "male" then
                age_ok = resident.age >= entity_config.REPRO.MALE_MIN_AGE
            end

            if resident.sex == "male" then
                if ok and (not cooldown) and age_ok then
                    status.male_ready = status.male_ready + 1
                else
                    status.male_block = status.male_block or reason or (cooldown and "cooldown") or "age"
                end
            elseif resident.sex == "female" then
                local max_hp = (resident.dna and resident.dna.max_health) or 100
                local carry_ok = (resident.hunger or 0) <= entity_config.REPRO_MAX_HUNGER
                    and (resident.health or 0) >= (max_hp * entity_config.REPRO_MIN_HEALTH_RATIO)
                if ok and (not cooldown) and age_ok and (not resident.pregnant) and carry_ok then
                    status.female_ready = status.female_ready + 1
                else
                    status.female_block = status.female_block
                        or reason
                        or (resident.pregnant and "pregnant")
                        or (cooldown and "cooldown")
                        or ((resident.hunger or 0) > entity_config.REPRO_MAX_HUNGER and "hunger")
                        or "health/age"
                end
            end
        end
    end

    return status
end

local function point_in_rect(px, py, r)
    return px >= r.x and px <= (r.x + r.w) and py >= r.y and py <= (r.y + r.h)
end

local function build_brush_menu()
    local ui = {
        panel = { x = 40, y = 250, w = 260, h = 220 },
        buttons = {},
    }

    ui.buttons.toggle = { x = 50, y = 280, w = 110, h = 26, action = "toggle_brush" }

    local tile_ids = {
        "deep_water", "shallow_water", "sand",
        "grass", "forest", "mountain",
    }

    local row_y = 320
    local col_x = { 50, 174 }
    for i, tile_id in ipairs(tile_ids) do
        local col = ((i - 1) % 2) + 1
        local row = math.floor((i - 1) / 2)
        ui.buttons["tile_" .. tile_id] = {
            x = col_x[col],
            y = row_y + row * 34,
            w = 110,
            h = 26,
            action = "set_tile",
            tile_id = tile_id,
        }
    end

    return ui
end

local function handle_brush_menu_click(mx, my)
    if not (M.ui and M.ui.buttons and M.brush) then
        return false
    end

    for _, button in pairs(M.ui.buttons) do
        if point_in_rect(mx, my, button) then
            if button.action == "toggle_brush" then
                M.brush.enabled = not M.brush.enabled
                M.brush.painting = false
            elseif button.action == "set_tile" then
                M.brush.type_id = button.tile_id
            end
            return true
        end
    end
    return false
end

local function build_speed_menu()
    local ui = {
        panel = { x = 40, y = 480, w = 260, h = 78 },
        buttons = {},
    }
    local scales = { 1, 7, 14, 30 }
    local x = 54
    for _, s in ipairs(scales) do
        ui.buttons["speed_" .. s] = {
            x = x,
            y = 512,
            w = 54,
            h = 28,
            action = "set_speed",
            scale = s,
        }
        x = x + 60
    end
    return ui
end

local function build_scenario_menu()
    return {
        panel = { x = 40, y = 566, w = 260, h = 116 },
        new_game_button = { x = 50, y = 598, w = 112, h = 28, action = "new_game" },
        scenario_button = { x = 174, y = 598, w = 116, h = 28, action = "next_scenario" },
    }
end

local function apply_scenario_to_world(w, scenario)
    local m = scenario.modifiers or {}
    w.environment.fertility_mult = m.fertility or 1.0
    w.environment.rainfall_mult = m.rainfall or 1.0
    w.environment.heat_mult = m.heat or 1.0
end

local function make_new_seed()
    local base = os.time()
    if love and love.timer and love.timer.getTime then
        base = base + math.floor(love.timer.getTime() * 1000)
    end
    return base
end

local function reset_world()
    local scenario = scenarios.get(M.scenario_id)
    local map_size_tiles = math.floor(world.meters_to_tiles(10000))
    M.world = world.new(map_size_tiles, map_size_tiles, make_new_seed())
    apply_scenario_to_world(M.world, scenario)

    local mid_x = M.world.width * 0.5
    local mid_y = M.world.height * 0.5
    local start_x, start_y = entities.find_spawn_site(M.world, M.world.seed + 13, mid_x, mid_y)
    local spawns = scenario.spawns or {}

    for i = 1, (spawns.male or 1) do
        entities.spawn(M.world, start_x - 0.5 - (i * 0.2), start_y, nil, "male")
    end
    for i = 1, (spawns.female or 1) do
        entities.spawn(M.world, start_x + 0.5 + (i * 0.2), start_y, nil, "female")
    end
    if (spawns.random or 0) > 0 then
        entities.seed_random(M.world, spawns.random, M.world.seed + 77)
    end

    M.renderer = map_renderer.new(4, M.world.width * M.world.height)
    M.renderer:rebuild(M.world)
    M.sim = sim.new({
        step_dt = 1 / 20,
        max_steps_per_frame = 8,
    })
    M.selected_object = nil
    M.message = string.format("GodSim — %s", scenario.name)
end

local function handle_speed_menu_click(mx, my)
    if not (M.speed_ui and M.speed_ui.buttons) then
        return false
    end
    for _, button in pairs(M.speed_ui.buttons) do
        if point_in_rect(mx, my, button) then
            if button.action == "set_speed" then
                M.time_scale = button.scale
            end
            return true
        end
    end
    return false
end

local function handle_scenario_menu_click(mx, my)
    if not M.scenario_ui then
        return false
    end
    if point_in_rect(mx, my, M.scenario_ui.new_game_button) then
        reset_world()
        center_camera_on_map()
        return true
    end
    if point_in_rect(mx, my, M.scenario_ui.scenario_button) then
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
        reset_world()
        center_camera_on_map()
        return true
    end
    return false
end

local function build_sim_control_menu()
    return {
        panel = { x = 40, y = 200, w = 260, h = 40 },
        button = { x = 50, y = 206, w = 110, h = 26, action = "toggle_sim" },
    }
end

local function handle_sim_control_click(mx, my)
    if not (M.sim_ui and M.sim_ui.button) then
        return false
    end
    if point_in_rect(mx, my, M.sim_ui.button) then
        M.sim_running = not M.sim_running
        return true
    end
    return false
end

local function draw_brush_menu()
    if not (M.ui and M.brush) then
        return
    end

    love.graphics.setColor(0.08, 0.08, 0.1, 0.88)
    love.graphics.rectangle("fill", M.ui.panel.x, M.ui.panel.y, M.ui.panel.w, M.ui.panel.h, 6, 6)
    love.graphics.setColor(0.85, 0.85, 0.9, 1)
    love.graphics.rectangle("line", M.ui.panel.x, M.ui.panel.y, M.ui.panel.w, M.ui.panel.h, 6, 6)
    love.graphics.print("Brush Menu", M.ui.panel.x + 10, M.ui.panel.y + 10)
    love.graphics.print("Radius: " .. tostring(M.brush.radius), M.ui.panel.x + 130, M.ui.panel.y + 35)

    for key, button in pairs(M.ui.buttons) do
        local active = false
        local label = key
        if button.action == "toggle_brush" then
            active = M.brush.enabled
            label = M.brush.enabled and "Brush: ON" or "Brush: OFF"
        elseif button.action == "set_tile" then
            label = button.tile_id
            active = (M.brush.type_id == button.tile_id)
        end

        if active then
            love.graphics.setColor(0.22, 0.56, 0.34, 0.95)
        else
            love.graphics.setColor(0.22, 0.22, 0.26, 0.95)
        end
        love.graphics.rectangle("fill", button.x, button.y, button.w, button.h, 4, 4)
        love.graphics.setColor(0.9, 0.9, 0.95, 1)
        love.graphics.rectangle("line", button.x, button.y, button.w, button.h, 4, 4)
        love.graphics.print(label, button.x + 8, button.y + 5)
    end
end

local function draw_sim_control_menu()
    if not M.sim_ui then
        return
    end
    local panel = M.sim_ui.panel
    local button = M.sim_ui.button
    love.graphics.setColor(0.08, 0.08, 0.1, 0.88)
    love.graphics.rectangle("fill", panel.x, panel.y, panel.w, panel.h, 6, 6)
    love.graphics.setColor(0.85, 0.85, 0.9, 1)
    love.graphics.rectangle("line", panel.x, panel.y, panel.w, panel.h, 6, 6)
    local running = M.sim_running
    if running then
        love.graphics.setColor(0.22, 0.56, 0.34, 0.95)
    else
        love.graphics.setColor(0.56, 0.22, 0.22, 0.95)
    end
    love.graphics.rectangle("fill", button.x, button.y, button.w, button.h, 4, 4)
    love.graphics.setColor(0.9, 0.9, 0.95, 1)
    love.graphics.rectangle("line", button.x, button.y, button.w, button.h, 4, 4)
    love.graphics.print(running and "Stop" or "Start", button.x + 32, button.y + 5)
    love.graphics.print("Simulation", panel.x + 170, panel.y + 12)
end

local function draw_speed_menu()
    if not M.speed_ui then
        return
    end

    love.graphics.setColor(0.08, 0.08, 0.1, 0.88)
    love.graphics.rectangle("fill", M.speed_ui.panel.x, M.speed_ui.panel.y, M.speed_ui.panel.w, M.speed_ui.panel.h, 6, 6)
    love.graphics.setColor(0.85, 0.85, 0.9, 1)
    love.graphics.rectangle("line", M.speed_ui.panel.x, M.speed_ui.panel.y, M.speed_ui.panel.w, M.speed_ui.panel.h, 6, 6)
    love.graphics.print("Time Speed", M.speed_ui.panel.x + 10, M.speed_ui.panel.y + 10)

    for _, button in pairs(M.speed_ui.buttons) do
        local active = (M.time_scale == button.scale)
        if active then
            love.graphics.setColor(0.22, 0.56, 0.34, 0.95)
        else
            love.graphics.setColor(0.22, 0.22, 0.26, 0.95)
        end
        love.graphics.rectangle("fill", button.x, button.y, button.w, button.h, 4, 4)
        love.graphics.setColor(0.9, 0.9, 0.95, 1)
        love.graphics.rectangle("line", button.x, button.y, button.w, button.h, 4, 4)
        love.graphics.print("x" .. tostring(button.scale), button.x + 14, button.y + 6)
    end
end

local function draw_scenario_menu()
    if not M.scenario_ui then
        return
    end
    local panel = M.scenario_ui.panel
    local new_game_button = M.scenario_ui.new_game_button
    local scenario_button = M.scenario_ui.scenario_button
    local scenario = scenarios.get(M.scenario_id)

    love.graphics.setColor(0.08, 0.08, 0.1, 0.88)
    love.graphics.rectangle("fill", panel.x, panel.y, panel.w, panel.h, 6, 6)
    love.graphics.setColor(0.85, 0.85, 0.9, 1)
    love.graphics.rectangle("line", panel.x, panel.y, panel.w, panel.h, 6, 6)
    love.graphics.print("Scenario", panel.x + 10, panel.y + 10)
    love.graphics.print(scenario.name, panel.x + 10, panel.y + 30)

    love.graphics.setColor(0.22, 0.56, 0.34, 0.95)
    love.graphics.rectangle("fill", new_game_button.x, new_game_button.y, new_game_button.w, new_game_button.h, 4, 4)
    love.graphics.setColor(0.9, 0.9, 0.95, 1)
    love.graphics.rectangle("line", new_game_button.x, new_game_button.y, new_game_button.w, new_game_button.h, 4, 4)
    love.graphics.print("New Game", new_game_button.x + 20, new_game_button.y + 6)

    love.graphics.setColor(0.22, 0.22, 0.26, 0.95)
    love.graphics.rectangle("fill", scenario_button.x, scenario_button.y, scenario_button.w, scenario_button.h, 4, 4)
    love.graphics.setColor(0.9, 0.9, 0.95, 1)
    love.graphics.rectangle("line", scenario_button.x, scenario_button.y, scenario_button.w, scenario_button.h, 4, 4)
    love.graphics.print("Next Scenario", scenario_button.x + 10, scenario_button.y + 6)
end

local function format_game_date(w)
    local cal = w and w.calendar
    if not cal then
        return "Day -"
    end
    local year = cal.year or 0
    local day_of_year = cal.day_of_year or 1
    return string.format("Year %d Day %d/365", year, day_of_year)
end

local function format_age_years(age_days)
    local years = (age_days or 0) / DAYS_PER_YEAR
    return string.format("%.1fy", years)
end

local function truncate_text_to_width(font, text, max_width)
    if font:getWidth(text) <= max_width then
        return text
    end

    local suffix = "..."
    local limit = math.max(0, max_width - font:getWidth(suffix))
    while #text > 0 and font:getWidth(text) > limit do
        text = text:sub(1, #text - 1)
    end
    return text .. suffix
end

local function event_log_color(event)
    if event.severity == "warn" or event.kind == "danger" or event.kind == "death" then
        return 1.0, 0.52, 0.38, 1
    end
    if event.kind == "birth" or event.kind == "build" then
        return 0.62, 0.95, 0.62, 1
    end
    if event.kind == "explore" then
        return 0.62, 0.78, 1.0, 1
    end
    return 0.86, 0.86, 0.9, 1
end

local function draw_event_log(screen_w, screen_h)
    local event_list = M.world and M.world.stats and M.world.stats.event_log
    local recent = {}
    if event_list then
        for i = #event_list, 1, -1 do
            local event = event_list[i]
            if event then
                recent[#recent + 1] = event
                if #recent >= EVENT_LOG_MAX then
                    break
                end
            end
        end
    end

    local font = love.graphics.getFont()
    local pad = 8
    local line_h = font:getHeight() + 3
    local panel_w = math.min(420, math.max(300, screen_w * 0.36))
    local panel_h = pad * 2 + line_h * (EVENT_LOG_MAX + 1)
    local x = screen_w - panel_w - 24
    local y = screen_h - panel_h - 24
    local text_w = panel_w - (pad * 2)

    love.graphics.setColor(0.04, 0.045, 0.06, 0.82)
    love.graphics.rectangle("fill", x, y, panel_w, panel_h, 6, 6)
    love.graphics.setColor(0.85, 0.85, 0.9, 0.9)
    love.graphics.rectangle("line", x, y, panel_w, panel_h, 6, 6)
    love.graphics.print("Event Log", x + pad, y + pad)

    if #recent <= 0 then
        love.graphics.setColor(0.58, 0.58, 0.64, 1)
        love.graphics.print("No important events yet", x + pad, y + pad + line_h)
        return
    end

    for i = 1, #recent do
        local event = recent[i]
        local line = string.format("D%s [%s] %s", tostring(event.day or "?"), event.kind or "event", event.message or "")
        line = truncate_text_to_width(font, line, text_w)
        love.graphics.setColor(event_log_color(event))
        love.graphics.print(line, x + pad, y + pad + (line_h * i))
    end
end

function M.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    M.scenario_id = "balanced"
    reset_world()
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
    M.ui = build_brush_menu()
    M.sim_ui = build_sim_control_menu()
    M.speed_ui = build_speed_menu()
    M.scenario_ui = build_scenario_menu()
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
    center_camera_on_map()
end

function M.update(dt)
    local update_start = love.timer.getTime()
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
    update_camera_bounds()

    if M.brush.painting and not M.drag_pan.active then
        apply_terraform_brush_at_mouse()
    end
    if M.sim_running then
        local sim_start = love.timer.getTime()
        M.debug.sim_steps = sim.update(M.sim, M.world, sim_dt)
        M.debug.sim_ms = (love.timer.getTime() - sim_start) * 1000
    else
        M.debug.sim_steps = 0
        M.debug.sim_ms = 0
    end

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
    local text = M.message or ""
    local tw = f:getWidth(text)
    if M.renderer and M.camera then
        local map_offset_x, map_offset_y = get_map_screen_offset()
        love.graphics.push()
        love.graphics.translate(map_offset_x, map_offset_y)
        love.graphics.scale(M.camera.zoom, M.camera.zoom)
        love.graphics.translate(-M.camera.x, -M.camera.y)
        M.renderer:draw(0, 0)
        local ts = M.renderer.tile_size
        local half_ts = ts * 0.5
        local object_px = 1
        local object_offset = (ts - object_px) * 0.5
        local building_px = 4
        local building_radius = building_px * 0.5
        local selected_radius = math.max(2.0, ts * 0.75)
        local resource_cfg = entity_config.RESOURCE or {}
        local rabbit_visible_threshold = resource_cfg.WILDLIFE_MIN_TO_HUNT or 0.18
        local wolf_visible_threshold = resource_cfg.WOLF_MIN_TO_HUNT or 0.08
        for i = 1, #M.world.tiles do
            local tile = M.world.tiles[i]
            local fruit = tile.apple_fruit or 0
            local pine = tile.pine_wood or 0
            local rabbit = tile.wildlife or 0
            local wolves = tile.wolves or 0
            local tx = ((i - 1) % M.world.width) * ts
            local ty = math.floor((i - 1) / M.world.width) * ts
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
        for _, e in pairs(M.world.entities) do
            if e and e.alive then
                if is_entity_inside_home_shelter(e) then
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
        local buildings = M.world.buildings or {}
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
        local selected_kind, selected = get_selected_object()
        if selected then
            love.graphics.setColor(1, 1, 1, 0.95)
            love.graphics.circle("line", (selected.x - 1) * ts + half_ts, (selected.y - 1) * ts + half_ts, selected_radius)
        end
        love.graphics.pop()
    end
    love.graphics.setColor(0.92, 0.9, 0.85, 1)
    love.graphics.print(text, (w - tw) * 0.5, 40)
    if M.world then
        local total, male, female = entities.count_by_sex(M.world)
        local total_build, shelter_build, others_build = summarize_buildings(M.world)
        local units_text = string.format("Units: %d  (M:%d F:%d)", total, male, female)
        local builds_text = string.format(
            "Build: %d  (Shelter:%d Others:%d)",
            total_build,
            shelter_build,
            others_build
        )
        local date_text = format_game_date(M.world)
        local units_x = w - f:getWidth(units_text) - 24
        local builds_x = w - f:getWidth(builds_text) - 24
        local date_x = w - f:getWidth(date_text) - 24
        love.graphics.print(units_text, units_x, 80)
        love.graphics.print(builds_text, builds_x, 104)
        love.graphics.print(date_text, date_x, 128)

        local selected_kind, selected = get_selected_object()
        local sel_title = selected and "Selected Object" or "Selected Object: none"
        local sel_x = w - f:getWidth(sel_title) - 24
        love.graphics.print(sel_title, sel_x, 152)
        if selected then
            if selected_kind == "entity" then
                local line1 = string.format("%s (%s)", selected.name or "unknown", selected.sex or "unknown")
                local line2 = string.format("Age: %s  Hunger: %.2f", format_age_years(selected.age), selected.hunger or 0)
                local line3 = string.format("HP: %.0f  Food: %d", selected.health or 0, math.floor((selected.personal_food or 0) + 0.5))
                local dna = selected.dna or {}
                local line4 = string.format(
                    "DNA spd:%.1f view:%.1f fert:%.2f",
                    dna.move_speed or 0,
                    dna.view_distance or 0,
                    dna.fertility_rate or 0
                )
                local line5 = string.format(
                    "DNA hp:%.0f mut:%.3f",
                    dna.max_health or 0,
                    dna.mutation_factor or 0
                )
                local line6 = string.format(
                    "Power STR:%.1f  KNOW:%.1f",
                    selected.strength or (dna.strength or 0),
                    selected.knowledge or (dna.knowledge or 0)
                )
                local home = get_home_shelter(selected)
                local line7 = string.format("State: %s", selected.state or "none")
                local line8
                if home then
                    line8 = string.format("Home: shelter #%s  Homeless: no", tostring(selected.home_shelter_id))
                else
                    line8 = "Home: none  Homeless: yes"
                end
                love.graphics.print(line1, w - f:getWidth(line1) - 24, 176)
                love.graphics.print(line2, w - f:getWidth(line2) - 24, 200)
                love.graphics.print(line3, w - f:getWidth(line3) - 24, 224)
                love.graphics.print(line4, w - f:getWidth(line4) - 24, 248)
                love.graphics.print(line5, w - f:getWidth(line5) - 24, 272)
                love.graphics.print(line6, w - f:getWidth(line6) - 24, 296)
                love.graphics.print(line7, w - f:getWidth(line7) - 24, 320)
                love.graphics.print(line8, w - f:getWidth(line8) - 24, 344)
            else
                local line1 = string.format("Type: %s", selected.kind or "building")
                local line2 = string.format("Pos: (%.1f, %.1f)", selected.x or 0, selected.y or 0)
                local line3 = string.format("Built day: %s", tostring(selected.built_day or "?"))
                love.graphics.print(line1, w - f:getWidth(line1) - 24, 176)
                love.graphics.print(line2, w - f:getWidth(line2) - 24, 200)
                love.graphics.print(line3, w - f:getWidth(line3) - 24, 224)
                if selected.kind == "shelter" then
                    local residents = selected.residents and #selected.residents or 0
                    local capacity = selected.capacity or 0
                    local food_units = math.floor((selected.food_stock or 0) + 0.5)
                    local wood_units = math.floor((selected.wood_stock or 0) + 0.5)
                    local inside_now = 0
                    if selected.residents then
                        for i = 1, #selected.residents do
                            local resident = M.world.entities[selected.residents[i]]
                            if resident and resident.alive and is_entity_inside_home_shelter(resident) then
                                inside_now = inside_now + 1
                            end
                        end
                    end
                    local line4 = string.format("Residents: %d/%d", residents, capacity)
                    local line5 = string.format("Inside now: %d", inside_now)
                    local line6 = string.format("Food: %d  Wood: %d", food_units, wood_units)
                    local repro = get_shelter_repro_status(selected)
                    local line7 = string.format("Repro ready M:%d F:%d", repro.male_ready, repro.female_ready)
                    local resident_names = {}
                    if selected.residents then
                        for i = 1, #selected.residents do
                            local resident = M.world.entities[selected.residents[i]]
                            if resident and resident.alive then
                                resident_names[#resident_names + 1] = resident.name or ("Unit-" .. tostring(resident.id or "?"))
                            end
                        end
                    end
                    local line8
                    if #resident_names > 0 then
                        line8 = "Residents: " .. table.concat(resident_names, ", ")
                    else
                        line8 = "Residents: none"
                    end
                    if repro.male_ready == 0 and repro.male_block then
                        line7 = line7 .. " M:" .. repro.male_block
                    end
                    if repro.female_ready == 0 and repro.female_block then
                        line7 = line7 .. " F:" .. repro.female_block
                    end
                    if selected.under_construction then
                        line6 = string.format(
                            "Frame wood: %d/%d",
                            math.floor((selected.construction_wood or 0) + 0.5),
                            math.floor((selected.required_wood or 0) + 0.5)
                        )
                    end
                    love.graphics.print(line4, w - f:getWidth(line4) - 24, 248)
                    love.graphics.print(line5, w - f:getWidth(line5) - 24, 272)
                    love.graphics.print(line6, w - f:getWidth(line6) - 24, 296)
                    love.graphics.print(line7, w - f:getWidth(line7) - 24, 320)
                    love.graphics.print(line8, w - f:getWidth(line8) - 24, 344)
                elseif selected.kind == "campfire" then
                    local build_cfg = entity_config.BUILD or {}
                    local line4
                    if selected.under_construction then
                        line4 = string.format(
                            "Frame wood: %d/%d",
                            math.floor((selected.construction_wood or 0) + 0.5),
                            math.floor((selected.required_wood or 0) + 0.5)
                        )
                    else
                        line4 = string.format("Rest radius: %.1f tiles", build_cfg.CAMPFIRE_USE_RADIUS or 3.0)
                    end
                    local line5 = string.format("Recover HP: %.1f/day", build_cfg.CAMPFIRE_HEALTH_RECOVER or 2.0)
                    local line6 = string.format("Purpose: homeless rest point")
                    love.graphics.print(line4, w - f:getWidth(line4) - 24, 248)
                    love.graphics.print(line5, w - f:getWidth(line5) - 24, 272)
                    love.graphics.print(line6, w - f:getWidth(line6) - 24, 296)
                end
            end
        end

    end
    draw_sim_control_menu()
    draw_brush_menu()
    draw_speed_menu()
    draw_scenario_menu()
    draw_event_log(w, h)
    love.graphics.setColor(1, 1, 1, 1)
    if M.debug then
        M.debug.render_ms = (love.timer.getTime() - render_start) * 1000
    end
end

function M.keypressed(key, _scancode, _isrepeat)
    if key == "escape" then
        love.event.quit()
    end
    if key == "q" then
        M.camera.zoom = clamp(M.camera.zoom * 0.9, M.camera.min_zoom, M.camera.max_zoom)
        update_camera_bounds()
    elseif key == "e" then
        M.camera.zoom = clamp(M.camera.zoom * 1.1, M.camera.min_zoom, M.camera.max_zoom)
        update_camera_bounds()
    elseif key == "n" then
        reset_world()
        center_camera_on_map()
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
        reset_world()
        center_camera_on_map()
    end
end

function M.wheelmoved(_x, y)
    if not M.camera or y == 0 then
        return
    end
    local factor = (y > 0) and 1.1 or 0.9
    M.camera.zoom = clamp(M.camera.zoom * factor, M.camera.min_zoom, M.camera.max_zoom)
    update_camera_bounds()
end

function M.resize(_w, _h)
    if M.camera then
        update_camera_bounds()
    end
end

function M.mousepressed(_x, _y, button)
    if button == 3 and M.drag_pan then
        M.drag_pan.active = true
    elseif button == 1 and M.brush then
        local mx, my = love.mouse.getPosition()
        if handle_sim_control_click(mx, my) then
            return
        end
        if handle_brush_menu_click(mx, my) then
            return
        end
        if handle_speed_menu_click(mx, my) then
            return
        end
        if handle_scenario_menu_click(mx, my) then
            return
        end
        local picked_building_index = pick_building_at_screen(mx, my)
        if picked_building_index then
            M.selected_object = { kind = "building", index = picked_building_index }
            return
        end
        local picked_entity = pick_entity_at_screen(mx, my)
        if picked_entity then
            M.selected_object = { kind = "entity", id = picked_entity.id }
            return
        end
        if M.brush.enabled then
            M.brush.painting = true
            apply_terraform_brush_at_mouse()
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
    update_camera_bounds()
end

return M
