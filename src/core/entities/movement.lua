local world = require("src.core.world")

local M = {}

local function rand01()
    if love and love.math and love.math.random then
        return love.math.random()
    end
    return math.random()
end

local function normalize(vx, vy)
    local len = math.sqrt(vx * vx + vy * vy)
    if len <= 0 then
        return 0, 0
    end
    return vx / len, vy / len
end

function M.update(w, e, dt)
    local step_dt = math.max(0, dt or 0)
    e.wander_timer = (e.wander_timer or 0) - step_dt
    if e.wander_timer <= 0 then
        local angle = rand01() * math.pi * 2
        e.vx = math.cos(angle)
        e.vy = math.sin(angle)
        e.wander_timer = 0.8 + (rand01() * 1.2)
    end

    local speed = (e.dna and e.dna.move_speed) or 24
    local nx = (e.x or 1) + (e.vx or 0) * speed * step_dt
    local ny = (e.y or 1) + (e.vy or 0) * speed * step_dt

    if world.in_bounds(w, math.floor(nx), math.floor(ny)) then
        e.x = math.max(1, math.min(w.width - 0.001, nx))
        e.y = math.max(1, math.min(w.height - 0.001, ny))
    else
        e.vx, e.vy = normalize(-(e.vx or 0), -(e.vy or 0))
    end

    if e.state ~= "Eat" and e.state ~= "EatStoredFood" then
        e.state = "Wander"
    end
end

return M
