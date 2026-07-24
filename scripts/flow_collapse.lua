-- ===========================================================================
-- THE FLOW COLLAPSES
-- Scenario event script for "The Interdependency" map
-- Sins of a Solar Empire II, based on John Scalzi's Collapsing Empire trilogy
-- ===========================================================================
-- What this does:
--   * At semi-random intervals, a Flow stream (wormhole lane) destabilises.
--     Players get a warning ("Flow shoal instability detected"), a grace
--     period, then the stream collapses and the lane is removed.
--   * Occasionally a collapsed or dormant stream OPENS somewhere else,
--     modelling the Flow shifting rather than simply dying (the Dalasysla
--     event from The Consuming Fire).
--   * The end state trends towards total network collapse. Last connected
--     empire standing, or whoever fortified End, wins the long game.
--
-- HOW TO WIRE THIS UP:
--   The engine binding names below (see the BINDINGS section) must match
--   the current Sins 2 scenario Lua API. Check them against:
--     https://wiki.sinsofasolarempire2.com/space/SSEFW/3170238513/Lua+Event+Tutorial
--   and the example scripts shipped with the game / modding tools.
--   Everything above the BINDINGS section is engine-agnostic logic and
--   should not need touching.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- CONFIG
-- ---------------------------------------------------------------------------
local CONFIG = {
    first_event_delay_s   = 1800,   -- 30 min of peace before the Flow stirs
    min_interval_s        = 900,    -- then an event every 15 to 25 minutes
    max_interval_s        = 1500,
    warning_lead_time_s   = 300,    -- 5 min warning before a collapse lands
    reopen_chance         = 0.35,   -- chance an event opens a stream instead
    protect_last_stream_s = 5400,   -- never fully isolate a home system
                                    -- before the 90 minute mark
    -- Evacuation window (The Last Emperox): when a collapse would isolate
    -- a player's home system, they get a much longer, personal countdown.
    evacuation_lead_time_s = 1200,  -- 20 min to get everything out
    evacuation_notice_s    = 600,   -- one-time "eligible" notice, this long
                                    -- after protection expires at the earliest
    -- Flow Physics research line: how much earlier each tier learns of an
    -- event, as a multiplier on the base warning lead. Tier 0 is everyone.
    -- Tier 3 hears about the collapse the moment the Flow decides.
    flow_physics_lead_mult = { [0] = 1.0, [1] = 1.5, [2] = 2.0, [3] = 3.0 },
    -- Scarcity: the Interdependency's supply chains die with the network.
    -- Every collapsed stream raises ship build prices for everyone; every
    -- reopened stream relieves it slightly.
    scarcity_pct_per_collapse = 6,   -- +6% ship cost per collapse
    scarcity_pct_cap          = 48,  -- runaway inflation, but not infinite
    throne_tax_interval_s     = 300, -- 5 minutes between imperial tax payouts
    throne_tax_credits        = 2500,-- Credits granted to the Emperox
    rng_seed              = nil,    -- set a number for reproducible games
}

local flow_metadata = nil
pcall(function() flow_metadata = dofile("scripts/flow_data.lua") end)

-- Streams at game start. Loaded dynamically from generate_map.py's output.
local ACTIVE_STREAMS = flow_metadata and flow_metadata.active_streams or {}

-- Dormant streams the Flow can shift into.
local DORMANT_STREAMS = {}
if flow_metadata and flow_metadata.dormant_streams then
    for _, s in ipairs(flow_metadata.dormant_streams) do
        table.insert(DORMANT_STREAMS, s.id)
    end
end

-- Collapse weighting: the outer streams are the least stable, as in the
-- books, where End's connection is the first modern casualty.
local COLLAPSE_WEIGHT = {
    terhathum_end   = 4,
    hub_terhathum   = 3,
    kivu_melacrion  = 2,
    ikoyi_bremen    = 2,
    hub_kivu        = 1,
    hub_melacrion   = 1,
    hub_ikoyi       = 1,
    hub_bremen      = 1,
    bremen_dalasysla = 2,
    melacrion_earth  = 3,
}

-- Optional one-way behaviour (books canon: streams are directional).
-- The engine's wormhole lanes are two-way, so we approximate: when a
-- stream is flagged here, traversal in the reverse direction triggers a
-- notification. Set enforce = true only if the API exposes per-direction
-- travel blocking; otherwise leave as flavour.
local ONE_WAY_STREAMS = {
    -- terhathum_end = { from = "terhathum", to = "end", enforce = false },
}

-- ---------------------------------------------------------------------------
-- STATE (kept in a single table for save/load friendliness)
-- ---------------------------------------------------------------------------
local state = {
    active   = {},   -- stream_id -> true
    dormant  = {},   -- stream_id -> true
    dead     = {},   -- stream_id -> true (fully collapsed, cannot reopen)
    pending  = nil,  -- { stream_id, fire_time, kind = "collapse"|"open",
                     --   evacuation = true|nil, notified = {player->true},
                     --   public_notified = bool, evac_notified = bool }
    next_event_time = nil,
    next_tax_time = CONFIG.throne_tax_interval_s,
    eligibility_announced = {},  -- player_index -> true (one-time notice sent)
    scarcity_level = 0,          -- net collapses, drives ship price inflation
}

for _, id in ipairs(ACTIVE_STREAMS)  do state.active[id]  = true end
for _, id in ipairs(DORMANT_STREAMS) do state.dormant[id] = true end

-- ---------------------------------------------------------------------------
-- LOGIC (engine-agnostic)
-- ---------------------------------------------------------------------------
local function weighted_pick(candidates)
    local total = 0
    for _, id in ipairs(candidates) do
        total = total + (COLLAPSE_WEIGHT[id] or 1)
    end
    if total == 0 then return nil end
    local roll = math.random() * total
    for _, id in ipairs(candidates) do
        roll = roll - (COLLAPSE_WEIGHT[id] or 1)
        if roll <= 0 then return id end
    end
    return candidates[#candidates]
end

local function active_list()
    local t = {}
    for id in pairs(state.active) do t[#t + 1] = id end
    table.sort(t)
    return t
end

local function dormant_list()
    local t = {}
    for id in pairs(state.dormant) do t[#t + 1] = id end
    table.sort(t)
    return t
end

-- Streams safe to collapse: never sever the final link of a system that
-- still hosts a player home world before protect_last_stream_s.
local function collapsible_streams(now)
    local candidates = active_list()
    if now >= CONFIG.protect_last_stream_s then
        return candidates
    end
    local filtered = {}
    for _, id in ipairs(candidates) do
        if #Bindings.players_isolated_by(id, state.active) == 0 then
            filtered[#filtered + 1] = id
        end
    end
    return filtered
end

local function schedule_next(now)
    local spread = CONFIG.max_interval_s - CONFIG.min_interval_s
    state.next_event_time = now + CONFIG.min_interval_s + math.random() * spread
end

-- One-time eligibility notice (The Last Emperox): once home-system
-- protection has expired, any player whose home hangs on a single
-- remaining stream gets a personal, once-only warning that their stream
-- is now on the collapse list. Not a countdown, just the dread.
local function announce_eligibility(now)
    if now < CONFIG.protect_last_stream_s + CONFIG.evacuation_notice_s then
        return
    end
    for _, player_index in ipairs(Bindings.all_player_indices()) do
        if not state.eligibility_announced[player_index] then
            local last = Bindings.sole_home_stream(player_index, state.active)
            if last ~= nil then
                state.eligibility_announced[player_index] = true
                Bindings.notify_player(player_index,
                    ("FLOW PHYSICS BULLETIN: your home system now depends on " ..
                     "a single stream (%s), and Imperial protection of core " ..
                     "routes has lapsed. It is now eligible for collapse. " ..
                     "You will receive an evacuation window when it " ..
                     "destabilises. Plan accordingly."):format(
                        Bindings.stream_display_name(last)))
            end
        end
    end
end

-- The Flow "decides" here, silently. fire_time sits a full tier 3 horizon
-- away; who learns when is handled by deliver_notices below.
local function begin_event(now)
    local mults = CONFIG.flow_physics_lead_mult
    local max_mult = mults[3]

    local open_roll = math.random() < CONFIG.reopen_chance
    if open_roll and next(state.dormant) ~= nil then
        local id = weighted_pick(dormant_list())
        state.pending = {
            stream_id = id, kind = "open",
            fire_time = now + CONFIG.warning_lead_time_s * max_mult,
            base_lead = CONFIG.warning_lead_time_s,
            notified = {},
        }
        return
    end

    local candidates = collapsible_streams(now)
    if #candidates == 0 then
        schedule_next(now)
        return
    end
    local id = weighted_pick(candidates)

    -- Evacuation window: if this collapse severs the last stream of one or
    -- more home systems, the base countdown is much longer and the affected
    -- players are told directly when the public notice lands.
    local trapped = Bindings.players_isolated_by(id, state.active)
    local is_evacuation = #trapped > 0
    local base_lead = is_evacuation and CONFIG.evacuation_lead_time_s
                                    or CONFIG.warning_lead_time_s
    state.pending = {
        stream_id = id, kind = "collapse",
        fire_time = now + base_lead * max_mult,
        base_lead = base_lead,
        evacuation = is_evacuation or nil,
        trapped = trapped,
        notified = {},
    }
end

local function tier_message(p, tier)
    local name = Bindings.stream_display_name(p.stream_id)
    if p.kind == "open" then
        return ("FLOW MODEL FORECAST: your physicists predict a shoal will " ..
                "form near %s. Position early; no one else knows yet."):format(name)
    end
    if tier == 3 then
        return ("RACHELA'S PROPHECY: The equations of Rachela I confirm the %s stream is doomed. " ..
                "The public is still blind. Use the head start."):format(name)
    end
    return ("FLOW MODEL FORECAST: your physicists predict the %s stream " ..
            "will collapse. The public bulletin has not gone out. " ..
            "Use the head start."):format(name)
end

-- Drip the information out by Flow Physics tier. A player's notice time is
-- fire_time minus base_lead scaled by their tier multiplier, so researching
-- mid-countdown genuinely buys earlier warning on the NEXT check.
local function deliver_notices(now)
    local p = state.pending
    local mults = CONFIG.flow_physics_lead_mult

    for _, player_index in ipairs(Bindings.all_player_indices()) do
        if not p.notified[player_index] then
            local tier = Bindings.player_flow_physics_tier(player_index)
            if tier > 0 and now >= p.fire_time - p.base_lead * mults[tier] then
                p.notified[player_index] = true
                Bindings.notify_player(player_index, tier_message(p, tier))
            end
        end
    end

    if not p.public_notified and now >= p.fire_time - p.base_lead then
        p.public_notified = true
        local name = Bindings.stream_display_name(p.stream_id)
        local mins = math.floor(p.base_lead / 60)
        if p.kind == "open" then
            Bindings.notify_all(
                ("FLOW SHIFT DETECTED: shoal formation predicted near %s. " ..
                 "A new stream may open in %d minutes."):format(name, mins))
        else
            Bindings.notify_all(
                ("FLOW INSTABILITY: the %s stream is destabilising. " ..
                 "Estimated collapse in %d minutes. Anything in transit " ..
                 "when it goes will not be coming back."):format(name, mins))
            Bindings.play_warning_effects(p.stream_id)
        end
        if p.evacuation and not p.evac_notified then
            p.evac_notified = true
            for _, player_index in ipairs(p.trapped) do
                Bindings.notify_player(player_index,
                    ("EVACUATION WINDOW: when the %s stream collapses, your " ..
                     "home system will be cut off from the Flow entirely. " ..
                     "You have %d minutes. What is not through the shoal by " ..
                     "then stays forever. The Interdependency thanks you " ..
                     "for your service."):format(name, mins))
            end
        end
    end
end

-- Scarcity: net collapses drive ship price inflation across all empires.
local function scarcity_pct()
    return math.min(state.scarcity_level * CONFIG.scarcity_pct_per_collapse,
                    CONFIG.scarcity_pct_cap)
end

local function update_scarcity(delta)
    state.scarcity_level = math.max(0, state.scarcity_level + delta)
    local pct = scarcity_pct()
    Bindings.apply_scarcity_level(state.scarcity_level, pct)
    if delta > 0 then
        Bindings.notify_all(
            ("INTERDEPENDENCY MARKETS: another supply route is gone. " ..
             "Shipyard prices rise to +%d%% above pre-collapse rates."):format(pct))
    elseif state.scarcity_level >= 0 then
        Bindings.notify_all(
            ("INTERDEPENDENCY MARKETS: restored trade eases shortages. " ..
             "Shipyard prices settle at +%d%%."):format(pct))
    end
end

local function resolve_pending(now)
    local p = state.pending
    state.pending = nil

    if p.kind == "collapse" then
        state.active[p.stream_id] = nil
        state.dead[p.stream_id] = true
        Bindings.remove_stream_lane(p.stream_id)
        if p.evacuation then
            Bindings.notify_all(
                ("THE FLOW HAS COLLAPSED: the %s stream is gone, and a home " ..
                 "system has gone silent with it. Whatever they got out is " ..
                 "all they have now."):format(
                    Bindings.stream_display_name(p.stream_id)))
        else
            Bindings.notify_all(
                ("THE FLOW HAS COLLAPSED: the %s stream is gone. " ..
                 "The Interdependency grows smaller."):format(
                    Bindings.stream_display_name(p.stream_id)))
        end
        update_scarcity(1)
    else
        state.dormant[p.stream_id] = nil
        state.active[p.stream_id] = true
        Bindings.create_stream_lane(p.stream_id)
        
        -- Flicker Stream mechanic: assign a random strict lifespan
        local lifespan = 600 + math.random(600) -- 10 to 20 minutes
        Bindings.notify_all(
            ("A FLICKER STREAM HAS OPENED: %s is reachable. " ..
             "Physics models predict it will collapse in exactly %d minutes. " ..
             "Raid window is open. Do not get trapped."):format(
                Bindings.stream_display_name(p.stream_id), math.floor(lifespan / 60)))
        
        -- Override the standard random event loop to force a collapse of this stream
        state.pending = {
            stream_id = p.stream_id, kind = "collapse",
            fire_time = now + lifespan,
            base_lead = CONFIG.warning_lead_time_s,
            notified = {},
        }
        state.next_event_time = nil -- clear random timer
        update_scarcity(-1)
        return -- skip schedule_next so the forced collapse happens next
    end
    schedule_next(now)
end

-- Called every tick / on a repeating timer.
local function on_update(now)
    if state.next_event_time == nil then
        state.next_event_time = CONFIG.first_event_delay_s
    end
    announce_eligibility(now)
    if state.pending ~= nil then
        deliver_notices(now)
        if now >= state.pending.fire_time then resolve_pending(now) end
        return
    end
    if now >= state.next_event_time then begin_event(now) end

    -- Task 2: The Throne at Xi'an
    if now >= state.next_tax_time then
        state.next_tax_time = now + CONFIG.throne_tax_interval_s
        local xian_node = flow_metadata and flow_metadata.xian_node_id
        if xian_node then
            local owner = Bindings.get_planet_owner(xian_node)
            if owner and owner >= 0 and owner <= 5 then
                Bindings.add_player_credits(owner, CONFIG.throne_tax_credits)
                Bindings.notify_all(("IMPERIAL DECREE: The Emperox at Xi'an (Player %d) has collected %d credits in imperial taxes from the Interdependency."):format(owner, CONFIG.throne_tax_credits))
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- BINDINGS: align these with the official Lua Event Tutorial
-- https://wiki.sinsofasolarempire2.com/space/SSEFW/3170238513/Lua+Event+Tutorial
-- Each function documents its intent; swap the body for the real API call.
-- ---------------------------------------------------------------------------
Bindings = {}

-- Human readable name for notifications, derived from the stream id.
function Bindings.stream_display_name(stream_id)
    local a, b = stream_id:match("^(%w+)_(%w+)$")
    local function cap(s) return s:sub(1, 1):upper() .. s:sub(2) end
    if a and b then return cap(a) .. " to " .. cap(b) end
    return stream_id
end

local event_context = nil

local function get_stream_nodes(stream_id)
    if not flow_metadata then return nil, nil end
    local a, b = stream_id:match("^(%w+)_(%w+)$")
    if a and b and flow_metadata.shoal_node_ids[a] and flow_metadata.shoal_node_ids[b] then
        return flow_metadata.shoal_node_ids[a], flow_metadata.shoal_node_ids[b]
    end
    if flow_metadata.dormant_streams then
        for _, s in ipairs(flow_metadata.dormant_streams) do
            if s.id == stream_id then return s.node_a, s.node_b end
        end
    end
    return nil, nil
end

function Bindings.remove_stream_lane(stream_id)
    if not event_context then return end
    local a, b = get_stream_nodes(stream_id)
    if a and b and event_context.simulation.remove_phase_lane then
        pcall(function() event_context.simulation:remove_phase_lane(a, b) end)
    end
end

function Bindings.create_stream_lane(stream_id)
    if not event_context then return end
    local a, b = get_stream_nodes(stream_id)
    if a and b and event_context.simulation.create_phase_lane then
        pcall(function() event_context.simulation:create_phase_lane(a, b, "wormhole") end)
    end
end

function Bindings.notify_all(message)
    if event_context and event_context.simulation.display_text then
        pcall(function() event_context.simulation:display_text("timer_label", message) end)
    end
end

function Bindings.notify_player(player_index, message)
    if event_context and event_context.simulation.display_text then
        pcall(function() event_context.simulation:display_text("timer_label", "P" .. tostring(player_index) .. ": " .. message) end)
    end
end

function Bindings.all_player_indices()
    return { 0, 1, 2, 3, 4, 5 }
end

function Bindings.sole_home_stream(player_index, active_streams)
    return nil
end

function Bindings.players_isolated_by(stream_id, active_streams)
    return {}
end

function Bindings.play_warning_effects(stream_id)
end

function Bindings.player_flow_physics_tier(player_index)
    return 0
end

function Bindings.apply_scarcity_level(level, pct)
end

function Bindings.get_planet_owner(node_id)
    if event_context and event_context.simulation.get_planet_owner then
        local success, owner = pcall(function() return event_context.simulation:get_planet_owner(node_id) end)
        if success then return owner end
    end
    return nil
end

function Bindings.add_player_credits(player_index, amount)
    if event_context and event_context.simulation.add_player_credits then
        pcall(function() event_context.simulation:add_player_credits(player_index, amount) end)
    end
end



-- ---------------------------------------------------------------------------
-- ENTRY POINTS: register with whatever event hooks the tutorial specifies.
-- ---------------------------------------------------------------------------
if CONFIG.rng_seed then math.randomseed(CONFIG.rng_seed) end

function get_event_metadata()
    return {
        is_simulation_event = true,
        on_update_function = "event_on_update",
        update_interval_seconds = 1.0,
    }
end

function event_on_update(context)
    event_context = context
    on_update(context.elapsed_time)
end

return {
    get_event_metadata = get_event_metadata,
    event_on_update = event_on_update,
    on_update = on_update,
    state = state,
    config = CONFIG,
}
