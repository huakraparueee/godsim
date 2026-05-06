local blackboard = require("src.core.blackboard")
local goap = require("src.core.goap")
local world = require("src.core.world")
local eat = require("src.core.entities.eat")
local config = require("src.data.config_entities")
local requirements = require("src.core.entity_requirements")
local entity_events = require("src.core.entities_events")

local M = {}

local function ensure_task_id(w)
    w.stats = w.stats or {}
    w.stats.next_task_id = (w.stats.next_task_id or 0) + 1
    return w.stats.next_task_id
end

local function set_task(w, e, task)
    e.current_task = task
    blackboard.set_entity_task(w, e.id, task)
end

local function clear_task(w, e)
    e.current_task = nil
    blackboard.clear_entity_task(w, e.id)
end

local function find_job_by_id(w, job_id)
    local jobs = blackboard.jobs(w) or {}
    for i = 1, #jobs do
        local job = jobs[i]
        if job and job.id == job_id then
            return job, i
        end
    end
    return nil, nil
end

local function task_done(w, e, state)
    local t = e.current_task
    if t then
        if t.kind == "blackboard_job" then
            local job = find_job_by_id(w, t.job_id)
            if job and job.claimed_by == e.id then
                job.claimed_by = nil
                job.claim_expires_tick = nil
            end
        end
        t.status = state or "done"
        blackboard.set_entity_task(w, e.id, t)
    end
    clear_task(w, e)
end

local function remove_job_at(w, idx)
    if not idx then
        return
    end
    local jobs = blackboard.jobs(w) or {}
    table.remove(jobs, idx)
end

local function find_building_by_uid(w, uid)
    local buildings = w.buildings or {}
    for i = 1, #buildings do
        local b = buildings[i]
        if b and b.uid == uid then
            return b
        end
    end
    return nil
end

local function find_best_wood_tile(w, cx, cy, radius)
    local best_idx
    local best_kind = "pine"
    local best_wood = 0
    local min_y = math.max(1, cy - radius)
    local max_y = math.min(w.height, cy + radius)
    local min_x = math.max(1, cx - radius)
    local max_x = math.min(w.width, cx + radius)
    for gy = min_y, max_y do
        for gx = min_x, max_x do
            local tile, idx = world.get_tile(w, gx, gy)
            local pine = (tile and tile.pine_wood) or 0
            local apple_wood = (tile and tile.apple_wood) or 0
            local candidate = math.max(pine, apple_wood)
            if candidate > best_wood then
                best_wood = candidate
                best_idx = idx
                best_kind = (pine >= apple_wood) and "pine" or "apple"
            end
        end
    end
    return best_idx, best_kind, best_wood
end

local function find_best_food_tile(w, cx, cy, radius)
    local best_idx
    local best_food = 0
    local min_y = math.max(1, cy - radius)
    local max_y = math.min(w.height, cy + radius)
    local min_x = math.max(1, cx - radius)
    local max_x = math.min(w.width, cx + radius)
    for gy = min_y, max_y do
        for gx = min_x, max_x do
            local tile, idx = world.get_tile(w, gx, gy)
            local fruit = (tile and tile.apple_fruit) or 0
            if fruit > best_food then
                best_food = fruit
                best_idx = idx
            end
        end
    end
    return best_idx, best_food
end

local function choose_blackboard_job(w, e)
    local jobs = blackboard.jobs(w) or {}
    local now_tick = w.tick or 0
    local best_job
    local best_score = -math.huge
    for i = 1, #jobs do
        local job = jobs[i]
        if job and job.x and job.y and not blackboard.is_job_claimed_by_other(job, e.id, now_tick) then
            local dx = (e.x or 0) - job.x
            local dy = (e.y or 0) - job.y
            local d2 = (dx * dx + dy * dy)
            local score = (job.priority or 0) - (d2 * 0.01)
            if score > best_score then
                best_score = score
                best_job = job
            end
        end
    end
    if best_job and blackboard.claim_job(best_job, e.id, now_tick, 30) then
        return best_job
    end
    return nil
end

local function maybe_assign_task(w, e)
    if e.current_task then
        return
    end

    local trigger = config.EAT_TRIGGER_HUNGER
    local need_self_food = ((e.hunger or 0) <= trigger) or (e.food_seek_active == true)

    -- Always prioritize self tasks before world tasks.
    if need_self_food then
        set_task(w, e, {
            id = ensure_task_id(w),
            kind = "self_food",
            status = "in_progress",
            assigned_tick = w.tick or 0,
        })
        return
    end

    local has_jobs = #(blackboard.jobs(w) or {}) > 0
    local plan = goap.plan_unit_task({
        hunger = e.hunger or 0,
        eat_trigger = trigger,
        needs_self_food = need_self_food,
        has_blackboard_jobs = has_jobs,
    })

    if plan and plan.intent == "blackboard_job" then
        local job = choose_blackboard_job(w, e)
        if job then
            set_task(w, e, {
                id = ensure_task_id(w),
                kind = "blackboard_job",
                status = "in_progress",
                job_id = job.id,
                target_x = job.x,
                target_y = job.y,
                assigned_tick = w.tick or 0,
            })
            return
        end
    end

end

local function update_blackboard_job_task(w, e, task, dt)
    local job, job_idx = find_job_by_id(w, task.job_id)
    if not job then
        task_done(w, e, "cancelled")
        return false
    end
    local building = find_building_by_uid(w, job.target_uid)
    if job.kind == "deliver_food_shelter" then
        if not building or building.under_construction then
            remove_job_at(w, job_idx)
            task_done(w, e, "done")
            return false
        end
        local build_cfg = config.BUILD
        local max_food_stock = build_cfg.SHELTER_MAX_FOOD_STOCK
        if (building.food_stock or 0) >= max_food_stock then
            remove_job_at(w, job_idx)
            task_done(w, e, "done")
            return false
        end

        if (e.carrying_food or 0) <= 0 then
            local vr = math.max(1, math.floor((e.dna and e.dna.view_distance) or 4))
            local cx = math.floor(e.x or 1)
            local cy = math.floor(e.y or 1)
            local food_idx = find_best_food_tile(w, cx, cy, math.max(vr * 2, 10))
            if not food_idx then
                e.state = "NoFoodForShelter"
                return false
            end
            local fx, fy = world.to_grid(w, food_idx)
            local fdx = fx - (e.x or 0)
            local fdy = fy - (e.y or 0)
            local fd2 = (fdx * fdx + fdy * fdy)
            if fd2 <= 1.0 then
                local tile = w.tiles[food_idx]
                if tile and (tile.apple_fruit or 0) > 0 then
                    local taken = math.min(tile.apple_fruit, 1)
                    tile.apple_fruit = tile.apple_fruit - taken
                    tile.food = tile.apple_fruit
                    e.carrying_food = (e.carrying_food or 0) + taken
                    requirements.grant_knowledge_for_event("gather_fruit", e, taken)
                    e.state = "GatherFoodForShelter"
                    return true
                end
            end
            local flen = math.sqrt(fd2)
            if flen > 0 then
                e.vx = fdx / flen
                e.vy = fdy / flen
                local speed = (e.dna and e.dna.move_speed) or 24
                local nx = (e.x or 1) + (e.vx or 0) * speed * (dt or 0)
                local ny = (e.y or 1) + (e.vy or 0) * speed * (dt or 0)
                if world.in_bounds(w, math.floor(nx), math.floor(ny)) then
                    e.x = math.max(1, math.min(w.width - 0.001, nx))
                    e.y = math.max(1, math.min(w.height - 0.001, ny))
                end
            end
            e.state = "SeekFoodForShelter"
            return true
        end

        local dx = (building.x or 0) - (e.x or 0)
        local dy = (building.y or 0) - (e.y or 0)
        local d2 = dx * dx + dy * dy
        if d2 <= 1.0 then
            local space = math.max(0, max_food_stock - (building.food_stock or 0))
            local delivered = math.min(e.carrying_food or 0, 1, space)
            building.food_stock = (building.food_stock or 0) + delivered
            e.carrying_food = math.max(0, (e.carrying_food or 0) - delivered)
            if delivered > 0 then
                requirements.grant_knowledge_for_event("deliver_food", e, delivered)
            end
            e.state = "DeliverFoodToShelter"
            if delivered <= 0 or (building.food_stock or 0) >= max_food_stock then
                remove_job_at(w, job_idx)
                task_done(w, e, "done")
            end
            return true
        end

        local len = math.sqrt(d2)
        if len <= 0 then
            return false
        end
        e.vx = dx / len
        e.vy = dy / len
        local speed = (e.dna and e.dna.move_speed) or 24
        local nx = (e.x or 1) + (e.vx or 0) * speed * (dt or 0)
        local ny = (e.y or 1) + (e.vy or 0) * speed * (dt or 0)
        if world.in_bounds(w, math.floor(nx), math.floor(ny)) then
            e.x = math.max(1, math.min(w.width - 0.001, nx))
            e.y = math.max(1, math.min(w.height - 0.001, ny))
        end
        e.state = "BringFoodToShelter"
        return true
    end

    if not building or (not building.under_construction) then
        remove_job_at(w, job_idx)
        task_done(w, e, "done")
        return false
    end

    local need = math.max(0, (building.required_wood or 0) - (building.construction_wood or 0))
    if need <= 0 then
        building.under_construction = false
        building.completed_day = (w.calendar and w.calendar.total_days) or 1
        if building.kind == "campfire" then
            w.stats.campfires_built = (w.stats.campfires_built or 0) + 1
            entity_events.campfire_built(w, e.name, building.x, building.y)
        elseif building.kind == "shelter" then
            w.stats.shelters_built = (w.stats.shelters_built or 0) + 1
            entity_events.shelter_built(w, e.name, building.x, building.y)
        end
        remove_job_at(w, job_idx)
        task_done(w, e, "done")
        return true
    end

    local target_x = building.x
    local target_y = building.y
    if not (target_x and target_y) then
        task_done(w, e, "cancelled")
        return false
    end

    if (e.carrying_wood or 0) <= 0 then
        local vr = math.max(1, math.floor((e.dna and e.dna.view_distance) or 4))
        local cx = math.floor(e.x or 1)
        local cy = math.floor(e.y or 1)
        local wood_idx, wood_kind = find_best_wood_tile(w, cx, cy, math.max(vr * 2, 10))
        if not wood_idx then
            e.state = "NoWoodForBuild"
            return false
        end
        local wx, wy = world.to_grid(w, wood_idx)
        local wdx = wx - (e.x or 0)
        local wdy = wy - (e.y or 0)
        local wd2 = (wdx * wdx + wdy * wdy)
        if wd2 <= 1.0 then
            local tile = w.tiles[wood_idx]
            if tile then
                local cut = 0
                if wood_kind == "pine" and (tile.pine_wood or 0) >= 1 then
                    cut = 1
                    tile.pine_wood = tile.pine_wood - 1
                elseif (tile.apple_wood or 0) >= 1 then
                    cut = 1
                    tile.apple_wood = tile.apple_wood - 1
                end
                if cut > 0 then
                    e.carrying_wood = 1
                    requirements.grant_knowledge_for_event("cut_tree", e, 1)
                    entity_events.cut_tree(w, e.name, cut, wood_kind)
                    e.state = "CutWoodForBuild"
                    return true
                end
            end
        end
        local wlen = math.sqrt(wd2)
        if wlen > 0 then
            e.vx = wdx / wlen
            e.vy = wdy / wlen
            local speed = (e.dna and e.dna.move_speed) or 24
            local nx = (e.x or 1) + (e.vx or 0) * speed * (dt or 0)
            local ny = (e.y or 1) + (e.vy or 0) * speed * (dt or 0)
            if world.in_bounds(w, math.floor(nx), math.floor(ny)) then
                e.x = math.max(1, math.min(w.width - 0.001, nx))
                e.y = math.max(1, math.min(w.height - 0.001, ny))
            end
        end
        e.state = "SeekWoodForBuild"
        return true
    end

    local dx = target_x - (e.x or 0)
    local dy = target_y - (e.y or 0)
    local d2 = dx * dx + dy * dy
    if d2 <= 1.0 then
        local delivered = math.min(e.carrying_wood or 0, 1, need)
        building.construction_wood = (building.construction_wood or 0) + delivered
        e.carrying_wood = math.max(0, (e.carrying_wood or 0) - delivered)
        e.state = "DeliverWoodToBuild"
        if delivered <= 0 then
            task_done(w, e, "cancelled")
        end
        return true
    end

    local len = math.sqrt(d2)
    if len <= 0 then
        return false
    end
    e.vx = dx / len
    e.vy = dy / len
    local speed = (e.dna and e.dna.move_speed) or 24
    local nx = (e.x or 1) + (e.vx or 0) * speed * (dt or 0)
    local ny = (e.y or 1) + (e.vy or 0) * speed * (dt or 0)
    if world.in_bounds(w, math.floor(nx), math.floor(ny)) then
        e.x = math.max(1, math.min(w.width - 0.001, nx))
        e.y = math.max(1, math.min(w.height - 0.001, ny))
    end
    e.state = "BringWoodToBuild"
    return true
end

function M.update(w, e, dt)
    local trigger = config.EAT_TRIGGER_HUNGER
    local must_do_self_food = ((e.hunger or 0) <= trigger) or (e.food_seek_active == true)
    if must_do_self_food and e.current_task and e.current_task.kind == "blackboard_job" then
        task_done(w, e, "cancelled")
    end

    maybe_assign_task(w, e)
    local task = e.current_task
    if not task then
        return false
    end

    if task.kind == "self_food" then
        local acted = eat.update(w, e, dt)
        if not acted then
            task_done(w, e, "done")
            return false
        end
        blackboard.set_entity_task(w, e.id, task)
        return true
    end
    if task.kind == "blackboard_job" then
        return update_blackboard_job_task(w, e, task, dt)
    end

    task_done(w, e, "cancelled")
    return false
end

function M.cancel_current_task(w, e)
    if not (w and e and e.current_task) then
        return
    end
    task_done(w, e, "cancelled")
end

return M
