--[[
  Centralized shared data board for AI/task systems.
  Phase 1 goal: provide a stable access layer without changing behavior.
]]

local blackboard = {}

local function ensure_table(value)
    if type(value) == "table" then
        return value
    end
    return {}
end

function blackboard.attach(w)
    if not w then
        return nil
    end

    -- Keep legacy fields as source-of-truth for now.
    w.jobs = ensure_table(w.jobs)
    w.stats = ensure_table(w.stats)
    w.stats.next_job_id = w.stats.next_job_id or 0

    local board = w.blackboard or {}
    board.world = w
    board.jobs = w.jobs
    board.entities = w.entities
    board.buildings = w.buildings
    board.stats = w.stats
    w.blackboard = board
    return board
end

function blackboard.get(w)
    if not w then
        return nil
    end
    if not w.blackboard then
        return blackboard.attach(w)
    end
    return w.blackboard
end

local function ensure_jobs_table(w)
    local board = blackboard.get(w)
    if not board then
        return nil
    end
    board.jobs = ensure_table(board.jobs)
    w.jobs = board.jobs
    return board.jobs
end

function blackboard.jobs(w)
    return ensure_jobs_table(w)
end

function blackboard.add_job(w, job)
    local jobs = ensure_jobs_table(w)
    if not jobs or type(job) ~= "table" then
        return nil
    end
    jobs[#jobs + 1] = job
    return job
end

function blackboard.cleanup_job_claims(w, current_tick)
    local jobs = ensure_jobs_table(w)
    if not jobs then
        return
    end
    local tick = math.floor(current_tick or 0)
    for i = 1, #jobs do
        local job = jobs[i]
        if job and job.claim_expires_tick and tick >= job.claim_expires_tick then
            job.claimed_by = nil
            job.claim_expires_tick = nil
        end
    end
end

function blackboard.is_job_claimed_by_other(job, entity_id, current_tick)
    if not job then
        return false
    end
    local owner = job.claimed_by
    if not owner then
        return false
    end
    if owner == entity_id then
        return false
    end
    local expires_tick = job.claim_expires_tick
    if (not expires_tick) or (math.floor(current_tick or 0) < expires_tick) then
        return true
    end
    return false
end

function blackboard.claim_job(job, entity_id, current_tick, ttl_ticks)
    if not (job and entity_id) then
        return false
    end
    local tick = math.floor(current_tick or 0)
    if blackboard.is_job_claimed_by_other(job, entity_id, tick) then
        return false
    end
    local ttl = math.max(1, math.floor(ttl_ticks or 1))
    job.claimed_by = entity_id
    job.claim_expires_tick = tick + ttl
    return true
end

return blackboard
