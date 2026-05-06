--[[
  In-game calendar formatting and event log panel (bottom-right).
]]

local DAYS_PER_YEAR = 365
local EVENT_LOG_MAX = 8

local M = {}

function M.format_game_date(w)
    local cal = w and w.calendar
    if not cal then
        return "Day -"
    end
    local year = cal.year or 0
    local day_of_year = cal.day_of_year or 1
    return string.format("Year %d Day %d/365", year, day_of_year)
end

function M.format_age_years(age_days)
    local years = (age_days or 0) / DAYS_PER_YEAR
    return string.format("%.1fy", years)
end

function M.truncate_text_to_width(font, text, max_width)
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

function M.color_for_event(event)
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

function M.draw_panel(g, screen_w, screen_h)
    local event_list = g.world and g.world.stats and g.world.stats.event_log
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
        line = M.truncate_text_to_width(font, line, text_w)
        love.graphics.setColor(M.color_for_event(event))
        love.graphics.print(line, x + pad, y + pad + (line_h * i))
    end
end

return M
