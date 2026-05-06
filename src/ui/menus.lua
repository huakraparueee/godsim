--[[
  Left panel UI: brush, sim toggle, time speed, scenario controls.
]]

local scenarios = require("src.data.scenarios")
local session = require("src.core.session")
local cam = require("src.utils.camera")

local function point_in_rect(px, py, r)
    return px >= r.x and px <= (r.x + r.w) and py >= r.y and py <= (r.y + r.h)
end

local M = {}

function M.build_brush_menu()
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

function M.handle_brush_menu_click(g, mx, my)
    if not (g.ui and g.ui.buttons and g.brush) then
        return false
    end

    for _, button in pairs(g.ui.buttons) do
        if point_in_rect(mx, my, button) then
            if button.action == "toggle_brush" then
                g.brush.enabled = not g.brush.enabled
                g.brush.painting = false
            elseif button.action == "set_tile" then
                g.brush.type_id = button.tile_id
            end
            return true
        end
    end
    return false
end

function M.build_speed_menu()
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

function M.build_scenario_menu()
    return {
        panel = { x = 40, y = 566, w = 260, h = 116 },
        new_game_button = { x = 50, y = 598, w = 112, h = 28, action = "new_game" },
        scenario_button = { x = 174, y = 598, w = 116, h = 28, action = "next_scenario" },
    }
end

function M.handle_speed_menu_click(g, mx, my)
    if not (g.speed_ui and g.speed_ui.buttons) then
        return false
    end
    for _, button in pairs(g.speed_ui.buttons) do
        if point_in_rect(mx, my, button) then
            if button.action == "set_speed" then
                g.time_scale = button.scale
            end
            return true
        end
    end
    return false
end

function M.handle_scenario_menu_click(g, mx, my)
    if not g.scenario_ui then
        return false
    end
    if point_in_rect(mx, my, g.scenario_ui.new_game_button) then
        session.reset(g)
        cam.center_on_map(g)
        return true
    end
    if point_in_rect(mx, my, g.scenario_ui.scenario_button) then
        local ids = scenarios.list_ids()
        local idx = 1
        for i = 1, #ids do
            if ids[i] == g.scenario_id then
                idx = i
                break
            end
        end
        idx = (idx % #ids) + 1
        g.scenario_id = ids[idx]
        session.reset(g)
        cam.center_on_map(g)
        return true
    end
    return false
end

function M.build_sim_control_menu()
    return {
        panel = { x = 40, y = 200, w = 260, h = 40 },
        button = { x = 50, y = 206, w = 110, h = 26, action = "toggle_sim" },
    }
end

function M.handle_sim_control_click(g, mx, my)
    if not (g.sim_ui and g.sim_ui.button) then
        return false
    end
    if point_in_rect(mx, my, g.sim_ui.button) then
        g.sim_running = not g.sim_running
        return true
    end
    return false
end

function M.draw_brush_menu(g)
    if not (g.ui and g.brush) then
        return
    end

    love.graphics.setColor(0.08, 0.08, 0.1, 0.88)
    love.graphics.rectangle("fill", g.ui.panel.x, g.ui.panel.y, g.ui.panel.w, g.ui.panel.h, 6, 6)
    love.graphics.setColor(0.85, 0.85, 0.9, 1)
    love.graphics.rectangle("line", g.ui.panel.x, g.ui.panel.y, g.ui.panel.w, g.ui.panel.h, 6, 6)
    love.graphics.print("Brush Menu", g.ui.panel.x + 10, g.ui.panel.y + 10)
    love.graphics.print("Radius: " .. tostring(g.brush.radius), g.ui.panel.x + 130, g.ui.panel.y + 35)

    for key, button in pairs(g.ui.buttons) do
        local active = false
        local label = key
        if button.action == "toggle_brush" then
            active = g.brush.enabled
            label = g.brush.enabled and "Brush: ON" or "Brush: OFF"
        elseif button.action == "set_tile" then
            label = button.tile_id
            active = (g.brush.type_id == button.tile_id)
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

function M.draw_sim_control_menu(g)
    if not g.sim_ui then
        return
    end
    local panel = g.sim_ui.panel
    local button = g.sim_ui.button
    love.graphics.setColor(0.08, 0.08, 0.1, 0.88)
    love.graphics.rectangle("fill", panel.x, panel.y, panel.w, panel.h, 6, 6)
    love.graphics.setColor(0.85, 0.85, 0.9, 1)
    love.graphics.rectangle("line", panel.x, panel.y, panel.w, panel.h, 6, 6)
    local running = g.sim_running
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

function M.draw_speed_menu(g)
    if not g.speed_ui then
        return
    end

    love.graphics.setColor(0.08, 0.08, 0.1, 0.88)
    love.graphics.rectangle("fill", g.speed_ui.panel.x, g.speed_ui.panel.y, g.speed_ui.panel.w, g.speed_ui.panel.h, 6, 6)
    love.graphics.setColor(0.85, 0.85, 0.9, 1)
    love.graphics.rectangle("line", g.speed_ui.panel.x, g.speed_ui.panel.y, g.speed_ui.panel.w, g.speed_ui.panel.h, 6, 6)
    love.graphics.print("Time Speed", g.speed_ui.panel.x + 10, g.speed_ui.panel.y + 10)

    for _, button in pairs(g.speed_ui.buttons) do
        local active = (g.time_scale == button.scale)
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

function M.draw_scenario_menu(g)
    if not g.scenario_ui then
        return
    end
    local panel = g.scenario_ui.panel
    local new_game_button = g.scenario_ui.new_game_button
    local scenario_button = g.scenario_ui.scenario_button
    local scenario = scenarios.get(g.scenario_id)

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

return M
