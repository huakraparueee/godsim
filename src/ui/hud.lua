--[[
  Top/center title, world stats lines, selected object inspector (screen space).
]]

local entities = require("src.core.entities")
local entity_config = require("src.data.config_entities")
local selection = require("src.core.selection")
local event_log = require("src.ui.event_log")

local M = {}

function M.draw(g, w, h, f)
    local text = g.message or ""
    local tw = f:getWidth(text)
    love.graphics.setColor(0.92, 0.9, 0.85, 1)
    love.graphics.print(text, (w - tw) * 0.5, 40)

    if not g.world then
        return
    end

    local total, male, female = entities.count_by_sex(g.world)
    local total_build, shelter_build, others_build = selection.summarize_buildings(g.world)
    local units_text = string.format("Units: %d  (M:%d F:%d)", total, male, female)
    local builds_text = string.format(
        "Build: %d  (Shelter:%d Others:%d)",
        total_build,
        shelter_build,
        others_build
    )
    local date_text = event_log.format_game_date(g.world)
    local units_x = w - f:getWidth(units_text) - 24
    local builds_x = w - f:getWidth(builds_text) - 24
    local date_x = w - f:getWidth(date_text) - 24
    love.graphics.print(units_text, units_x, 80)
    love.graphics.print(builds_text, builds_x, 104)
    love.graphics.print(date_text, date_x, 128)

    local selected_kind, selected = selection.get_selected_object(g)
    local sel_title = selected and "Selected Object" or "Selected Object: none"
    local sel_x = w - f:getWidth(sel_title) - 24
    love.graphics.print(sel_title, sel_x, 152)
    if selected then
        if selected_kind == "entity" then
            local line1 = string.format("%s (%s)", selected.name or "unknown", selected.sex or "unknown")
            local line2 = string.format("Age: %s  Hunger: %.2f", event_log.format_age_years(selected.age), selected.hunger or 0)
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
            local home = selection.get_home_shelter(g, selected)
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
                        local resident = g.world.entities[selected.residents[i]]
                        if resident and resident.alive and selection.is_entity_inside_home_shelter(g, resident) then
                            inside_now = inside_now + 1
                        end
                    end
                end
                local line4 = string.format("Residents: %d/%d", residents, capacity)
                local line5 = string.format("Inside now: %d", inside_now)
                local line6 = string.format("Food: %d  Wood: %d", food_units, wood_units)
                local repro = selection.get_shelter_repro_status(g, selected)
                local line7 = string.format("Repro ready M:%d F:%d", repro.male_ready, repro.female_ready)
                local resident_names = {}
                if selected.residents then
                    for i = 1, #selected.residents do
                        local resident = g.world.entities[selected.residents[i]]
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

return M
