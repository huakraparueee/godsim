--[[
  Lightweight GOAP planner (Phase 3 incremental rollout).
  Scope: support logistics intent selection (food vs wood).
]]

local goap = {}

local function clone_state(src)
    return {
        has_food = src.has_food or false,
        has_wood = src.has_wood or false,
        needs_food_delivery = src.needs_food_delivery or false,
        needs_wood_delivery = src.needs_wood_delivery or false,
    }
end

local function key_of_state(s)
    return table.concat({
        s.has_food and "1" or "0",
        s.has_wood and "1" or "0",
        s.needs_food_delivery and "1" or "0",
        s.needs_wood_delivery and "1" or "0",
    }, "|")
end

local function action_list(ctx)
    local food_cost = math.max(0.1, ctx.food_cost or 1.0)
    local wood_cost = math.max(0.1, ctx.wood_cost or 1.0)
    return {
        {
            id = "gather_food",
            cost = food_cost,
            pre = function(s)
                return s.needs_food_delivery and (not s.has_food)
            end,
            eff = function(s)
                s.has_food = true
            end,
        },
        {
            id = "deliver_food",
            cost = 1.0,
            pre = function(s)
                return s.needs_food_delivery and s.has_food
            end,
            eff = function(s)
                s.has_food = false
                s.needs_food_delivery = false
            end,
        },
        {
            id = "gather_wood",
            cost = wood_cost,
            pre = function(s)
                return s.needs_wood_delivery and (not s.has_wood)
            end,
            eff = function(s)
                s.has_wood = true
            end,
        },
        {
            id = "deliver_wood",
            cost = 1.0,
            pre = function(s)
                return s.needs_wood_delivery and s.has_wood
            end,
            eff = function(s)
                s.has_wood = false
                s.needs_wood_delivery = false
            end,
        },
    }
end

local function satisfies_goal(state, goal_id)
    if goal_id == "keep_food_supply" then
        return not state.needs_food_delivery
    end
    if goal_id == "keep_wood_supply" then
        return not state.needs_wood_delivery
    end
    return false
end

local function enumerate_plans(initial_state, actions, goal_id, max_depth)
    local best_cost = math.huge
    local best_plan = nil
    local seen = {}

    local function dfs(state, depth, acc_cost, steps)
        local state_key = key_of_state(state)
        local seen_cost = seen[state_key]
        if seen_cost and seen_cost <= acc_cost then
            return
        end
        seen[state_key] = acc_cost

        if satisfies_goal(state, goal_id) then
            if acc_cost < best_cost then
                best_cost = acc_cost
                best_plan = steps
            end
            return
        end
        if depth >= max_depth or acc_cost >= best_cost then
            return
        end

        for i = 1, #actions do
            local a = actions[i]
            if a.pre(state) then
                local next_state = clone_state(state)
                a.eff(next_state)
                local next_steps = {}
                for j = 1, #steps do
                    next_steps[j] = steps[j]
                end
                next_steps[#next_steps + 1] = a.id
                dfs(next_state, depth + 1, acc_cost + a.cost, next_steps)
            end
        end
    end

    dfs(clone_state(initial_state), 0, 0, {})
    return best_plan, best_cost
end

function goap.plan_support(ctx)
    if not ctx then
        return nil
    end
    local initial_state = {
        has_food = (ctx.carrying_food or 0) > 0,
        has_wood = (ctx.carrying_wood or 0) > 0,
        needs_food_delivery = ctx.needs_food_delivery or false,
        needs_wood_delivery = ctx.needs_wood_delivery or false,
    }
    local actions = action_list(ctx)
    local goals = {}
    if initial_state.needs_food_delivery then
        goals[#goals + 1] = { id = "keep_food_supply", utility = ctx.food_utility or 1.0 }
    end
    if initial_state.needs_wood_delivery then
        goals[#goals + 1] = { id = "keep_wood_supply", utility = ctx.wood_utility or 1.0 }
    end
    if #goals <= 0 then
        return nil
    end

    local best
    local best_score = -math.huge
    for i = 1, #goals do
        local goal = goals[i]
        local plan, plan_cost = enumerate_plans(initial_state, actions, goal.id, 4)
        if plan then
            local score = goal.utility - plan_cost
            if score > best_score then
                local intent = (goal.id == "keep_food_supply") and "food" or "wood"
                best = {
                    goal = goal.id,
                    intent = intent,
                    actions = plan,
                    cost = plan_cost,
                    score = score,
                }
                best_score = score
            end
        end
    end
    return best
end

return goap
