--[[
  Pathing (Phase 2+)
  Minimal grid-based pathfinder with async-shaped API:
    - pathing.request(w, from_gx, from_gy, to_gx, to_gy, opts?) -> path_id
    - pathing.poll(path_id) -> ready, path_or_err

  Current implementation computes immediately on request (stores result as a job),
  so poll() typically returns ready=true on first call.
]]

local world = require("src.core.world")

local pathing = {}

local _next_id = 0
local _jobs = {}

local function next_id()
    _next_id = _next_id + 1
    return _next_id
end

local function is_walkable(w, gx, gy)
    local tile = world.get_tile(w, gx, gy)
    if not tile then
        return false
    end
    local def = world.get_tile_def(tile.type_id)
    return def and def.walkable or false
end

local function heuristic(ax, ay, bx, by)
    -- Manhattan distance for 4-neighbor grid.
    return math.abs(ax - bx) + math.abs(ay - by)
end

local function reconstruct_path(came_from, w, goal_idx)
    local out = {}
    local idx = goal_idx
    while idx do
        local gx, gy = world.to_grid(w, idx)
        out[#out + 1] = { gx = gx, gy = gy }
        idx = came_from[idx]
    end
    -- reverse in place
    for i = 1, math.floor(#out / 2) do
        out[i], out[#out - i + 1] = out[#out - i + 1], out[i]
    end
    return out
end

local function astar(w, from_gx, from_gy, to_gx, to_gy, opts)
    opts = opts or {}
    local max_nodes = opts.max_nodes or 6000

    if not (w and w.tiles and w.width and w.height) then
        return nil, "invalid world"
    end

    from_gx = math.floor(from_gx or 0)
    from_gy = math.floor(from_gy or 0)
    to_gx = math.floor(to_gx or 0)
    to_gy = math.floor(to_gy or 0)

    if not world.in_bounds(w, from_gx, from_gy) or not world.in_bounds(w, to_gx, to_gy) then
        return nil, "out of bounds"
    end

    if (from_gx == to_gx) and (from_gy == to_gy) then
        return { { gx = from_gx, gy = from_gy } }, nil
    end

    if not is_walkable(w, to_gx, to_gy) then
        return nil, "target not walkable"
    end

    local start_idx = world.to_index(w, from_gx, from_gy)
    local goal_idx = world.to_index(w, to_gx, to_gy)
    if not start_idx or not goal_idx then
        return nil, "out of bounds"
    end

    -- Open set as simple list; selection scans for best fScore.
    -- OK for MVP; can be upgraded to binary heap if needed.
    local open = { start_idx }
    local open_set = { [start_idx] = true }

    local came_from = {}
    local g_score = { [start_idx] = 0 }
    local f_score = { [start_idx] = heuristic(from_gx, from_gy, to_gx, to_gy) }

    local expanded = 0

    while #open > 0 do
        local best_i = 1
        local best_idx = open[1]
        local best_f = f_score[best_idx] or math.huge
        for i = 2, #open do
            local idx = open[i]
            local f = f_score[idx] or math.huge
            if f < best_f then
                best_f = f
                best_i = i
                best_idx = idx
            end
        end

        -- pop best
        open[best_i] = open[#open]
        open[#open] = nil
        open_set[best_idx] = nil

        expanded = expanded + 1
        if expanded > max_nodes then
            return nil, "path search budget exceeded"
        end

        if best_idx == goal_idx then
            return reconstruct_path(came_from, w, goal_idx), nil
        end

        local cx, cy = world.to_grid(w, best_idx)
        local neighbors = {
            { cx + 1, cy },
            { cx - 1, cy },
            { cx, cy + 1 },
            { cx, cy - 1 },
        }

        for n = 1, 4 do
            local nx = neighbors[n][1]
            local ny = neighbors[n][2]
            if world.in_bounds(w, nx, ny) and is_walkable(w, nx, ny) then
                local n_idx = world.to_index(w, nx, ny)
                local tentative_g = (g_score[best_idx] or math.huge) + 1
                if tentative_g < (g_score[n_idx] or math.huge) then
                    came_from[n_idx] = best_idx
                    g_score[n_idx] = tentative_g
                    f_score[n_idx] = tentative_g + heuristic(nx, ny, to_gx, to_gy)
                    if not open_set[n_idx] then
                        open[#open + 1] = n_idx
                        open_set[n_idx] = true
                    end
                end
            end
        end
    end

    return nil, "no path"
end

function pathing.request(w, from_gx, from_gy, to_gx, to_gy, opts)
    local id = next_id()
    local path, err = astar(w, from_gx, from_gy, to_gx, to_gy, opts)
    _jobs[id] = {
        ready = true,
        path = path,
        err = err,
    }
    return id
end

function pathing.poll(path_id)
    local job = _jobs[path_id]
    if not job then
        return true, nil, "unknown path id"
    end
    if not job.ready then
        return false
    end
    if job.err then
        return true, nil, job.err
    end
    return true, job.path
end

return pathing

