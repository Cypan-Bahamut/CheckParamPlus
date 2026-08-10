--[[
Copyright © 2018, from20020516
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
        notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
        notice, this list of conditions and the following disclaimer in the
        documentation and/or other materials provided with the distribution.
    * Neither the name of checkparam nor the
        names of its contributors may be used to endorse or promote products
        derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL from20020516 BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.]]

_addon.name = 'CheckParamPlus'
_addon.author = 'from20020516 & Kigen; Modified by Cypan (Bahamut)'
_addon.version = '2.5.4'
_addon.commands = {'cp','checkparam'}

require('logger')
res = require('resources')
extdata = require('extdata')
config = require('config')
packets = require('packets')
require('math')

defaults = {
    WAR = 'store tp|double attack|triple attack|quadruple attack|weapon skill damage',
    MNK = 'store tp|double attack|triple attack|quadruple attack|martial arts|subtle blow',
    WHM = 'cure potency|cure potency ii|fast cast|quick cast|cure spellcasting time|enmity|healing magic casting time|divine benison|damage taken|physical damage taken|magic damage taken',
    BLM = 'magic attack bonus|magic burst damage|magic burst damage ii|int|magic accuracy|magic damage|fast cast|elemental magic casting time',
    RDM = 'magic attack bonus|magic burst damage|magic burst damage ii|magic accuracy|fast cast|quick cast|enfeebling magic skill|enhancing magic skill|store tp|dual wield',
    THF = 'store tp|double attack|triple attack|quadruple attack|dual wield|critical hit rate|critical hit damage|haste|weapon skill damage|steal|sneak attack|trick attack',
    PLD = 'enmity|damage taken|physical damage taken|magic damage taken|spell interruption rate|phalanx|cure potency|fastcast',
    DRK = 'store tp|double attack|triple attack|quadruple attack|weapon skill damage',
    BST = 'pet: double attack|pet: magic attack bonus|pet: damage taken',
    BRD = 'all songs|song effect duration|fast cast|song spellcasting time|singing skill|wind skill|string skill',
    RNG = 'store tp|snapshot|rapid shot|weapon skill damage',
    SAM = 'store tp|double attack|triple attack|quadruple attack|weapon skill damage',
    NIN = 'store tp|double attack|triple attack|quadruple attack|subtle blow|dual wield|daken',
    DRG = 'store tp|double attack|triple attack|quadruple attack|weapon skill damage',
    SMN = 'physical damage taken|magic damage taken|pet: physical damage taken|pet: magic damage taken|blood pact delay|blood pact delay ii|blood pact damage|avatar perpetuation cost|pet: magic attack bonus|pet: attack|pet: double attack|pet: accuracy|pet: magic accuracy|summoning magic skill|pet: blood pact damage|pet: magic damage',
    BLU = 'physical damage taken|magic damage taken|haste|dual wield|store tp|double attack|triple attack|quadruple attack|critical hit rate|critical hit damage|weapon skill damage|fast cast|magic attack bonus|magic accuracy|cure potency',
    COR = 'physical damage taken|magic damage taken|haste|dual wield|store tp|snapshot|rapid shot|fast cast|cure potency|magic accuracy|magic attack bonus|magic damage|weapon skill damage',
    PUP = 'pet: hp|pet: damage taken|pet: regen|martial arts|store tp|double attack|triple attack|quadruple attack',
    DNC = 'store tp|double attack|triple attack|quadruple attack',
    SCH = 'magic attack bonus|magic burst damage|magic burst damage ii|magic accuracy|magic damage|fast cast|elemental magic casting time|cure potency|enh mag eff dur|enhancing magic effect duration',
    GEO = 'pet: regen|pet: damage taken|indicolure effect duration|fast cast|magic evasion|handbell skill|geomancy skill|geomancy',
    RUN = 'enmity|damage taken|physical damage taken|magic damage taken|spell interruption rate|phalanx|inquartata|fastcast',
    levelfilter = 99,
    debugmode = false,
    use_native = false,    -- OFF by default. When true, //cp resolves system-4 Path gear
                           -- via the client's native resolver, STAGGERED (one call at a
                           -- time, spaced out) to avoid the 16-call burst that caused OOM.
                           -- Test carefully; set false to revert to safe table-only.
    native_stagger = 0.25, -- seconds between staggered native calls. Raise (0.5, 1.0, ...)
                           -- if you still hit memory issues with use_native on.
}
settings = config.load(defaults)

tbl = {}
aug_cache = {}             -- (item_id..':'..extdata) -> resolved lines, or false
check_in_progress = false  -- guard: only one staggered resolution (//cp OR /check) at a time
check_pending = {}         -- /check equipment queued on Type 3, resolved (staggered) on Type 1
include_traits = false     -- set by //cp full for one run: add base job traits to the tally
pending_snapshot_mode = nil -- set by SELF-check paths ('cp'/'cp full'); show_results
                            -- snapshots displayed stats when set. /check never sets it.
cp_history = {}             -- {previous=snap, current=snap}; persisted to data/cp_history.lua
do
    local ok, h = pcall(dofile, windower.addon_path..'data/cp_history.lua')
    if ok and type(h) == 'table' then cp_history = h end
end

windower.register_event('addon command',function(arg,arg2)
    if arg and arg:lower() == 'augtest' then
        native_augtest(arg2)
        return
    end
    -- //cp delta : compare the two most recent //cp or //cp full snapshots.
    if arg and arg:lower() == 'delta' then
        show_delta()
        return
    end
    -- //cp full : same self-check, but also adds job traits (main + sub) from the
    -- job_traits table to the tally. main_bonus (verified merits + job point GIFTS,
    -- mastered-99 assumption) rides on the MAIN job only. Traits flagged main_only
    -- (e.g. NIN Daken) are never credited to the sub job. One-shot flag; resets after run.
    include_traits = (arg ~= nil and arg:lower() == 'full')
    if settings.use_native then
        run_check_staggered()
    else
        run_check_sync()
    end
end)

-- Original synchronous self-check: table-only (never calls the native resolver). Used
-- when use_native is off, and as the fallback when the coroutine scheduler is missing.
function run_check_sync()
    local items = windower.ffxi.get_items
    for i=0,#res.slots do
        local slot = windower.regex.replace(string.lower(res.slots[i].english),' ','_')
        local gear_set = items().equipment
        local gear = items(gear_set[slot..'_bag'],gear_set[slot])
        if gear_set[slot] > 0 then
            get_text(gear.id,gear.extdata)
        end
    end
    local my = windower.ffxi.get_player()
    pending_snapshot_mode = include_traits and 'cp full' or 'cp'
    if include_traits then
        apply_job_traits()
        include_traits = false
    end
    show_results(my.name,my.main_job,my.sub_job)
end

-- Add job trait + gift values to the tally from job_traits.lua (v2.4 structure:
-- {traits=, gifts=}). Per stat: TOTAL = max(main trait tier, sub trait tier)
--                                      + main-job merits (traits main_bonus)
--                                      + main-job gifts (mastered-99 assumption).
-- Rationale: ranked traits from main/sub do not stack (higher tier wins), but
-- main-job gifts/merits are separate mechanisms that DO stack with a sub trait
-- (e.g. DNC gift attack + /DRG Attack Bonus). main_only traits never apply on sub.
function apply_job_traits()
    local my = windower.ffxi.get_player()
    if not my then return end
    local traits = job_traits.traits or {}
    local gifts = job_traits.gifts or {}
    local totals = {}
    local merits = {}
    for _,j in ipairs({{my.main_job,my.main_job_level,true},{my.sub_job,my.sub_job_level,false}}) do
        local jt = j[1] and traits[j[1]]
        if jt and j[2] then
            for stat,def in pairs(jt) do
                if j[3] or not def.main_only then
                    local best
                    for _,t in ipairs(def.tiers or def) do
                        if j[2] >= t.lv and (not best or t.lv > best.lv) then best = t end
                    end
                    if best then totals[stat] = math.max(totals[stat] or 0, best.val) end
                    if j[3] and def.main_bonus then merits[stat] = def.main_bonus end
                end
            end
        end
    end
    for stat,v in pairs(merits) do totals[stat] = (totals[stat] or 0) + v end
    local g = my.main_job and gifts[my.main_job]
    if g then
        for stat,v in pairs(g) do totals[stat] = (totals[stat] or 0) + v end
    end
    for stat,v in pairs(totals) do
        tbl[stat] = (tbl[stat] or 0) + v
        if settings.debugmode then log('[trait] '..stat..' +'..v) end
    end
end

-- Shared staggered resolver, used by both //cp and /check. ASSUMES the caller has
-- already set check_in_progress = true and reset tbl. Walks the queue one item at a
-- time, spacing live native calls by settings.native_stagger so the 16-call burst that
-- caused OOM never happens; cached / non-Path items advance with no delay. Runs on_done
-- (typically show_results) when the queue drains, then clears the guard.
function resolve_staggered(queue, on_done)
    local delay = tonumber(settings.native_stagger) or 0.25
    local i = 1
    local function step()
        local it = queue[i]
        if not it then
            local ok2 = pcall(on_done)
            if not ok2 and settings.debugmode then log('checkparam: on_done error (staggered)') end
            check_in_progress = false
            return
        end
        i = i + 1
        local ok, made_call = pcall(get_text, it.id, it.extdata, true)
        if not ok then
            if settings.debugmode then log('checkparam: get_text error on id '..tostring(it.id)..': '..tostring(made_call)) end
            made_call = false
        end
        coroutine.schedule(step, made_call and delay or 0)
    end
    step()
end

-- Staggered self-check (//cp when use_native is on): collects equipped pieces and
-- resolves them via resolve_staggered, then displays. A guard blocks overlapping runs.
function run_check_staggered()
    if check_in_progress then
        log('checkparam: a staggered resolution is already running - please wait.')
        return
    end
    if type(coroutine) ~= 'table' or type(coroutine.schedule) ~= 'function' then
        log('checkparam: coroutine.schedule unavailable; running table-only instead.')
        run_check_sync()
        return
    end
    check_in_progress = true
    tbl = {}
    local get = windower.ffxi.get_items
    local eq = get().equipment
    local queue = {}
    for i=0,#res.slots do
        local slot = windower.regex.replace(string.lower(res.slots[i].english),' ','_')
        if eq[slot] and eq[slot] > 0 then
            local gear = get(eq[slot..'_bag'],eq[slot])
            queue[#queue+1] = {id=gear.id, extdata=gear.extdata}
        end
    end
    resolve_staggered(queue, function()
        local my = windower.ffxi.get_player()
        pending_snapshot_mode = include_traits and 'cp full' or 'cp'
        if include_traits then
            apply_job_traits()
            include_traits = false
        end
        show_results(my.name,my.main_job,my.sub_job)
    end)
end

windower.register_event('incoming chunk',function(id,data)
    -- Drop new /check (0x0C9) packets while ANY staggered resolution (//cp or a prior
    -- /check) is mid-flight, to avoid corrupting the shared tbl. No-op when use_native is
    -- off (check_in_progress is never set then), so default behaviour is unchanged.
    if check_in_progress then return end
    if id == 0x0C9 then
        local p = packets.parse('incoming',data)
        if p['Type'] == 3 then
            -- Equipment list. In native mode we only QUEUE the pieces here and resolve
            -- them (staggered) on the Type 1 packet; in table-only mode we resolve inline
            -- exactly as the original addon did. (A check sends one Type 3 packet holding
            -- all equipped pieces, so rebuilding check_pending here is correct.)
            local count = p['Count']
            if settings.use_native and type(coroutine) == 'table' and type(coroutine.schedule) == 'function' then
                check_pending = {}
                if count == 1 then
                    check_pending[1] = {id=p['Item'], extdata=p['ExtData']}
                else
                    for i=1,count do
                        check_pending[i] = {id=p['Item '..i], extdata=p['ExtData '..i]}
                    end
                end
            else
                if count == 1 then
                    get_text(p['Item'],p['ExtData'])
                else
                    for i=1,count do
                        get_text(p['Item '..i],p['ExtData '..i])
                    end
                end
            end
        elseif p['Type'] == 1 then
            local t = windower.ffxi.get_mob_by_index(p['Target Index'])
            local mjob = res.jobs[p['Main Job']].english_short
            local sjob = res.jobs[p['Sub Job']].english_short
            if p['Main Job Level'] >= settings.levelfilter then
                if settings.use_native and type(coroutine) == 'table' and type(coroutine.schedule) == 'function' then
                    -- Staggered native resolution of the queued equipment, then display.
                    local q = check_pending
                    check_pending = {}
                    local name = (t and t.name) or '?'
                    check_in_progress = true
                    tbl = {}
                    resolve_staggered(q, function()
                        show_results(name,mjob,sjob)
                    end)
                else
                    show_results(t.name,mjob,sjob)
                end
            else
                check_pending = {}
                tbl = {}
                if mjob == 'NON' then
                    error('The target is in /anon state.')
                end
            end
        end
    end
end)

function get_text(id,data,allow_native)
    config.reload(settings)
    local descriptions = res.item_descriptions[id]
    local helptext = descriptions and descriptions.english or '' --for 'vanilla' items. e.g. Moonshade Earring
    local stats = windower.regex.split(helptext,'(Pet|Avatar|Automaton|Wyvern|Luopan): ')
    for i,v in ipairs(windower.regex.split(stats[1],'\n')) do
        split_text(id,v)
    end
    if stats[2] then
        stats[2] = stats[2]:trim()
        split_text(id,stats[2],'pet: ')
    end
    local ext = extdata.decode({id=id,extdata=data})
    if ext.augments then
        for i,v in ipairs(ext.augments) do
            local stats = windower.regex.split(v,'(Pet|Avatar|Automaton|Wyvern|Luopan): ')
            -- A single augment can carry several stats. extdata gives each pet stat its
            -- own "Pet: "/"Avatar: " prefix (e.g. "Pet: Accuracy+5 Pet: Rng. Acc.+5"),
            -- so the split yields stats[1]=leading non-pet text (usually empty) and
            -- stats[2..n]=one segment per pet stat. The original code only read stats[2],
            -- silently dropping every additional pet stat. Process all segments.
            if stats[1] and stats[1]:trim() ~= '' then
                split_text(id,stats[1]:trim())
            end
            for j=2,#stats do
                split_text(id,stats[j]:trim(),'pet: ')
            end
        end
    end
    -- System-4 "Path" gear (Dynamis-D / Odyssey / Limbus / Unity reinforcement):
    -- extdata returns only {'Path: X'} and never decodes the stats. handle_path_augments
    -- supplies them from the native resolver (when allow_native, staggered + cached) or
    -- the verified max-rank table. It returns true iff it made a LIVE native call.
    local made_native_call = false
    if ext and ext.augment_system == 4 then
        made_native_call = handle_path_augments(id,ext,data,allow_native)
    end
    if enhanced[id] then
        local stats = enhanced[id]:gsub('([+-:][0-9]+)',',%1'):split(',')
        tbl[stats[1]] = tonumber(stats[2]) + (tbl[stats[1]] or 0)
        if settings.debugmode then
            log(id,res.items[id].english,stats[1],stats[2],tbl[stats[1]])
        end
    end
    tbl.sets = tbl.sets or {}
    table.insert(tbl.sets,id)
    return made_native_call
end

function split_text(id,text,arg)
    for key,value in string.gmatch(text,'/?([%D]-):?([%+%-]?[0-9]+)%%?%s?') do
        local key = windower.regex.replace(string.lower(key),'(\\"|\\.|\\s$)','')
        local key = integrate[key] or key
        local key = arg and arg..key or key
        if key == "blood pact damage" then
            key = "pet: blood pact damage"
        elseif key == "pet: damage taken" then
            tbl['pet: physical damage taken'] = tonumber(value)+(tbl['pet: physical damage taken'] or 0)
            tbl['pet: magic damage taken'] = tonumber(value)+(tbl['pet: magic damage taken'] or 0)
        elseif key == "damage taken" then
            tbl['physical damage taken'] = tonumber(value)+(tbl['physical damage taken'] or 0)
            tbl['magic damage taken'] = tonumber(value)+(tbl['magic damage taken'] or 0)
            -- NOTE: generic DT- does reduce breath damage in-game, but per user
            -- preference 'breath damage taken' tallies ONLY from explicit breath
            -- gear, so it is intentionally excluded from this fan-out.
        else
            tbl[key] = tonumber(value)+(tbl[key] or 0)
        end
        if settings.debugmode then
            log(id,res.items[id].english,key,value,tbl[key])
        end
    end
end

-- //cp augtest <slot> : SINGLE-call diagnostic for windower.ffxi.get_item_augments.
-- Calls the native resolver exactly ONCE, on the item in the named slot (default neck),
-- with no loop. Writes flushed markers to data/checkparam_augtest.txt so that if the call
-- runs the client out of memory, the file still shows how far it got.
-- Purpose: distinguish "a single call OOMs" (native route dead) from "only the 16-call
-- loop OOMed" (route viable with a cache-once design).
-- WARNING: this calls the function that OOM'd before; pcall may NOT catch a hard OOM.
-- Run once, when you can afford to restart. Normal //cp never touches this.
function native_augtest(slotname)
    local files = require('files')
    local f = files.new('data/checkparam_augtest.txt',true)
    local function w(s)
        pcall(function() f:append(tostring(s)..'\n',true) end) -- flush=true: durable before the call
        log(s)
    end
    w('--- augtest start ---')
    local fn = windower.ffxi and windower.ffxi.get_item_augments
    if type(fn) ~= 'function' then
        w('get_item_augments NOT present on this Windower build')
        w('--- done ---')
        return
    end
    w('get_item_augments present')
    slotname = (slotname or 'neck'):lower()
    local get = windower.ffxi.get_items
    local eq = get().equipment
    local idx = eq[slotname]
    if not idx or idx == 0 then
        w('no item equipped in slot: '..slotname..' (try: neck, sub, waist, left_ear, right_ear, ...)')
        w('--- done ---')
        return
    end
    local gear = get(eq[slotname..'_bag'],idx)
    w('target slot='..slotname..' item_id='..tostring(gear.id))
    w('BEFORE call (if the file ends on this line, the single call ran you out of memory)')
    local ok,nat = pcall(fn,gear.id,gear.extdata)
    w('AFTER call ok='..tostring(ok))
    if ok and type(nat) == 'table' then
        w('rank='..tostring(nat.rank)..' path='..tostring(nat.path)..' max_rank='..tostring(nat.max_rank))
        if type(nat.augments) == 'table' then
            for ai,a in ipairs(nat.augments) do
                w('  aug['..ai..'] id='..tostring(a and a.id)..' pot='..tostring(a and a.potency))
            end
        else
            w('  (no augments table in result)')
        end
    else
        w('result (not a table): '..tostring(nat))
    end
    w('--- augtest done ---')
end

-- Native augment resolution via windower.ffxi.get_item_augments (Windower ~2026-06).
-- ONE call per invocation; run_check_staggered spaces these out (the 16-call burst is
-- what OOM'd; a single call is confirmed safe). Returns "StatName+Value" display lines,
-- or nil (function absent, not rank gear, or res.augments unavailable to name the ids).
-- KNOWN LIMIT: stats the client fuses onto one line as fragments ("STR/AGI+15") may not
-- split into separate keys - does not affect simple single-stat Path gear.
function try_native_augments(id,ext_raw)
    local fn = windower.ffxi and windower.ffxi.get_item_augments
    if type(fn) ~= 'function' or type(ext_raw) ~= 'string' then return nil end
    local ok,nat = pcall(fn,id,ext_raw)
    if not ok or type(nat) ~= 'table' then return nil end
    if type(nat.augments) ~= 'table' or not next(nat.augments) then return nil end
    if not res.augments then return nil end
    local function fmt(a)
        local e = a and res.augments[a.id]
        local tmpl = e and (e.en or e.english)
        if not tmpl then return nil end
        local okf,txt = pcall(string.format,tmpl,a.potency or 0)
        return okf and txt or nil
    end
    local lines = {}
    local idx = 1
    if type(nat.line_counts) == 'table' then
        local li = 1
        while nat.line_counts[li] do
            local parts = {}
            for _=1,nat.line_counts[li] do
                local t = fmt(nat.augments[idx])
                if t then parts[#parts+1] = t end
                idx = idx + 1
            end
            if #parts > 0 then lines[#lines+1] = (table.concat(parts):gsub('%s+$','')) end
            li = li + 1
        end
    end
    while nat.augments[idx] do
        local t = fmt(nat.augments[idx])
        if t then lines[#lines+1] = (t:gsub('%s+$','')) end
        idx = idx + 1
    end
    if #lines == 0 then return nil end
    return lines
end

-- Resolve stats for system-4 "Path" gear (extdata gives only {'Path: X'}). When
-- allow_native (staggered //cp) and settings.use_native: use the client's native
-- resolver, cached by (id, extdata) so each unique item is called at most once, and
-- fall back to the verified max-rank table if it returns nothing. Otherwise use the
-- table directly. Returns true iff a LIVE native call was made this invocation, so the
-- staggered runner knows to space out the next step.
function handle_path_augments(id,ext,data,allow_native)
    local nm = (res.items[id] and res.items[id].english) or tostring(id)
    local function use_table()
        local entry = path_augments[id]
        if not entry then
            if settings.debugmode then log('[path] '..nm..' id='..id..' path='..tostring(ext.path)..' rank='..tostring(ext.rank)..' - not in path_augments table') end
            return
        end
        if ext.rank and entry.max and ext.rank < entry.max then
            if settings.debugmode then log('[path] '..nm..' rank '..tostring(ext.rank)..'/'..tostring(entry.max)..' - below max, augments not applied') end
            return
        end
        local aug = entry.paths and ext.path and entry.paths[ext.path]
        if not aug then
            if settings.debugmode then log('[path] '..nm..' path '..tostring(ext.path)..' not present in table entry') end
            return
        end
        local segs = windower.regex.split(aug,'(Pet|Avatar|Automaton|Wyvern|Luopan): ')
        if segs[1] and segs[1]:trim() ~= '' then split_text(id,segs[1]:trim()) end
        for j=2,#segs do split_text(id,segs[j]:trim(),'pet: ') end
    end

    -- No native path -> straight to the verified table.
    if not (allow_native and settings.use_native) then
        use_table()
        return false
    end
    -- Cache hit -> reuse, no live call.
    local key = tostring(id)..':'..tostring(data)
    local cached = aug_cache[key]
    if cached ~= nil then
        if cached then
            for _,l in ipairs(cached) do split_text(id,l) end
        else
            use_table()
        end
        return false
    end
    -- Cache miss -> exactly ONE native call, then cache the outcome.
    local lines = try_native_augments(id,data)
    aug_cache[key] = lines or false
    if lines then
        for _,l in ipairs(lines) do split_text(id,l) end
    else
        use_table()
    end
    return true
end

-- Damage-taken family: displayed sign-flipped so reduction reads as positive
-- progress toward the cap (raw -42% -> "42/50"); gear that INCREASES damage
-- taken reads negative ("-10/50"). Raw tally storage is unchanged; snapshots
-- store the flipped value so //cp delta matches what is displayed.
local dt_display_flip = {
    ['physical damage taken'] = true, ['magic damage taken'] = true,
    ['breath damage taken'] = true,
    ['pet: physical damage taken'] = true, ['pet: magic damage taken'] = true,
}

function show_results(name,mjob,sjob)
    local count = {}
    for key,value in pairs(combination) do
        for _,id in pairs(tbl.sets) do
            if value.item[id] then
                count[key] = (count[key] or 0)+1
            end
        end
        if count[key] and count[key] > 1 then
            for stat,multi in pairs(value.stats) do
                tbl[stat] = (tbl[stat] or 0)+multi*math.min((count[key]+value.type),5)
            end
        end
    end
    local stats = settings[mjob]
    -- Snapshot (for //cp delta): capture EXACTLY the displayed stats - after the
    -- combination set-bonus loop above, filtered by this job's watch list below.
    -- Only self-checks set pending_snapshot_mode; /check never snapshots.
    local snap_mode = pending_snapshot_mode
    pending_snapshot_mode = nil
    local snap
    if snap_mode then
        snap = {mode=snap_mode, time=os.date('%Y-%m-%d %H:%M:%S'), name=name,
                mjob=mjob, sjob=sjob or '', order={}, stats={}}
    end
    local head = '<'..mjob..'/'..(sjob or '')..'>'
    windower.add_to_chat(160,string.color(name,1,160)..': '..string.color(head,160,160))
    for index,key in ipairs(windower.regex.split(stats,'[|]')) do
        -- WA for blood pact damage showing when it is converted to pet: blood pact damage
        -- WA for damage taken showing when it is converted to physical/magic damage taken
        key = string.lower(key)
        -- Stats with no tallied value are omitted entirely (no line, no snapshot
        -- entry) so the master watch list stays extensive without nil noise.
        if key ~= 'blood pact damage' and key ~= 'damage taken' and tbl[key] ~= nil then
            local value = tbl[key]
            if dt_display_flip[key] then value = -value end
            if snap then
                snap.order[#snap.order+1] = key
                snap.stats[key] = value
            end
            local color = {value and 1 or 160,value and 166 or 160, 106, 205, 61}
            local stat_cap = caps[key]
            if dt_display_flip[key] and stat_cap then stat_cap = -stat_cap end
            local output_string = ' ['..string.color(key,color[1],160)..']'
            if stat_cap == nil or value == nil then
                output_string = output_string..' '..string.color(tostring(value),color[2],160)
            elseif value == stat_cap then
                output_string = output_string..' '..string.color(tostring(value),color[3],160)..'/'..string.color(tostring(stat_cap),155,160)
            elseif math.abs(value) > math.abs(stat_cap) then
                output_string = output_string..' '..string.color(tostring(value),color[4],160)..'/'..string.color(tostring(stat_cap),155,160)
            else
                output_string = output_string..' '..string.color(tostring(value),color[5],160)..'/'..string.color(tostring(stat_cap),155,160)
            end
            windower.add_to_chat(160,output_string)
        end
    end
    if snap then
        cp_history.previous = cp_history.current
        cp_history.current = snap
        local ok_save, err = pcall(save_cp_history)
        if not ok_save and settings.debugmode then
            log('checkparam: history save failed: '..tostring(err))
        end
    end
    tbl = {}
end

-- Persist the last two //cp snapshots to data/cp_history.lua (loaded on addon start).
function save_cp_history()
    local files = require('files')
    local parts = {'-- auto-generated by checkparam (//cp snapshot history). Do not edit.', 'return {'}
    for _,slot in ipairs({'previous','current'}) do
        local s = cp_history[slot]
        if s then
            parts[#parts+1] = slot..' = {'
            parts[#parts+1] = string.format('    mode=%q, time=%q, name=%q, mjob=%q, sjob=%q,',
                s.mode, s.time, s.name, s.mjob, s.sjob or '')
            parts[#parts+1] = '    order={'
            for _,k in ipairs(s.order) do parts[#parts+1] = string.format('        %q,', k) end
            parts[#parts+1] = '    },'
            parts[#parts+1] = '    stats={'
            for _,k in ipairs(s.order) do
                if type(s.stats[k]) == 'number' then
                    parts[#parts+1] = string.format('        [%q]=%s,', k, tostring(s.stats[k]))
                end
            end
            parts[#parts+1] = '    },'
            parts[#parts+1] = '},'
        end
    end
    parts[#parts+1] = '}'
    local f = files.new('data/cp_history.lua', true)
    f:write(table.concat(parts,'\n'), true)
end

-- //cp delta : compare the two most recent self-check snapshots (//cp or //cp full).
-- Shows previous -> current with a signed delta per stat; nil is treated as 0 for
-- the arithmetic but displayed as nil so gained/lost stats are visible. Union of
-- both watch lists (current order first) covers job or mode changes between runs.
function show_delta()
    local cur, prev = cp_history.current, cp_history.previous
    if not (cur and prev) then
        log('checkparam: //cp delta needs two recorded runs; '..(cur and 'only one snapshot stored so far.' or 'no snapshots stored yet.')..' Run //cp or //cp full '..(cur and 'once more.' or 'twice.'))
        return
    end
    windower.add_to_chat(160, string.color('cp delta',1,160)..string.color(
        ': ['..prev.mode..' '..prev.time..' <'..prev.mjob..'/'..prev.sjob..'>] -> ['
        ..cur.mode..' '..cur.time..' <'..cur.mjob..'/'..cur.sjob..'>]',160,160))
    local keys, seen = {}, {}
    for _,k in ipairs(cur.order) do keys[#keys+1]=k; seen[k]=true end
    for _,k in ipairs(prev.order or {}) do if not seen[k] then keys[#keys+1]=k end end
    for _,k in ipairs(keys) do
        local c, p = cur.stats[k], prev.stats[k]
        local d = (c or 0) - (p or 0)
        -- Zero-delta stats are omitted: the delta shows changes only.
        if d ~= 0 then
            local dstr = string.format('%+d', d)
            local dcolor = (d > 0 and 158 or 167)
            windower.add_to_chat(160, ' ['..string.color(k, 1, 160)..'] '
                ..string.color(dstr,dcolor,160))
        end
    end
end

integrate = {
    --[[integrate same property.information needed for development. @from20020516]]
    ['quad atk'] = 'quadruple attack',
    ['quad attack'] = 'quadruple attack',
    ['triple atk'] = 'triple attack',
    ['double atk'] = 'double attack',
    ['dblatk'] = 'double attack',
    ['blood pact ability delay'] = 'blood pact delay',
    ['blood pact ability delay ii'] = 'blood pact delay ii',
    ['blood pact ab del ii'] = 'blood pact delay ii',
    ['blood pact recast time ii'] = 'blood pact delay ii',
    ['blood pact dmg'] = 'blood pact damage',
    ['enhancing magic duration'] = 'enhancing magic effect duration',
    ['eva'] = 'evasion',
    ['indicolure spell duration'] = 'indicolure effect duration',
    ['indi eff dur'] = 'indicolure effect duration',
    ['mag eva'] = 'magic evasion',
    ['magic eva'] = 'magic evasion',
    ['magic atk bonus'] = 'magic attack bonus',
    ['magatkbns'] = 'magic attack bonus',
    ['mag atk bonus'] = 'magic attack bonus',
    ['mag acc'] = 'magic accuracy',
    ['m acc'] = 'magic accuracy',
    ['r acc'] = 'ranged accuracy',
    ['magic burst dmg'] = 'magic burst damage',
    ['mag dmg'] = 'magic damage',
    ['crithit rate'] = 'critical hit rate',
    ['phys dmg taken'] = 'physical damage taken',
    ['occ. quickens spellcasting']="quick cast",
    ['occassionally quickens spellcasting']="quick cast",
    ['song duration']="song effect duration",
}
enhanced = {
    [10392] = 'cursna+10', --Malison Medallion
    [10393] = 'cursna+15', --Debilis Medallion
    [10394] = 'fast cast+5', --Orunmila's Torque
    [10469] = 'fast cast+10', --Eirene's Manteel
    [10752] = 'fast cast+2', --Prolix Ring
    [10790] = 'cursna+10', --Ephedra Ring
    [10791] = 'cursna+15', --Haoma's Ring
    [10802] = 'fast cast+5', --Majorelle Shield
    [10806] = 'potency of cure effects received+15', --Adamas
    [10826] = 'fast cast+3', --Witful Belt
    [10838] = 'dual wield+5', --Patentia Sash
    [11000] = 'fast cast+3', --Swith Cape
    [11001] = 'fast cast+4', --Swith Cape +1
    [11037] = 'stoneskin+10', --Earthcry Earring
    [11051] = 'increases resistance to all status ailments+5', --Hearty Earring
    [11544] = 'fast cast+1', --Veela Cape
    [11602] = 'martial arts+10', --Cirque Necklace
    [11603] = 'dual wield+3', --Charis Necklace
    [11615] = 'fast cast+5', --Orison Locket
    [11707] = 'fast cast+2', --Estq. Earring
    [11711] = 'rewards+2', --Ferine Earring
    [11715] = 'dual wield+1', --Iga Mimikazari
    [11722] = 'sublimation+1', --Savant's Earring
    [11732] = 'dual wield+5', --Nusku's Sash
    [11734] = 'martial arts+10', --Shaolin Belt
    [11735] = 'snapshot+3', --Impulse Belt
    [11753] = 'aquaveil+1', --Emphatikos Rope
    [11775] = 'occult acumen+20', --Oneiros Rope
    [11856] = 'fast cast+10', --Anhur Robe
    [13177] = 'stoneskin+30', --Stone Gorget
    [14739] = 'dual wield+5', --Suppanomimi
    [14812] = 'fast cast+2', --Loquac. Earring
    [14813] = 'double attack+5', --Brutal Earring
    [15857] = 'drain and aspir potency+5', --Excelsis Ring
    [15960] = 'stoneskin+20', --Siegel Sash
    [15962] = 'magic burst damage+5', --Static Earring
    [16209] = 'snapshot+5', --Navarch's Mantle
    [19062] = 'divine benison+1', --Yagrush80
    [19082] = 'divine benison+2', --Yagrush85
    [19260] = 'dual wield+3', --Raider's Bmrng.
    [19614] = 'divine benison+3', --Yagrush90
    [19712] = 'divine benison+3', --Yagrush95
    [19821] = 'divine benison+3', --Yagrush99
    [19950] = 'divine benison+3', --Yagrush99+
    [20509] = 'counter+14', --Spharai119AG
    [20511] = 'martial arts+55', --Kenkonken119AG
    [21062] = 'divine benison+3', --Yagrush119
    [21063] = 'divine benison+3', --Yagrush119+
    [21078] = 'divine benison+3', --Yagrush119AG
    [21201] = 'fast cast+2', --Atinian Staff +1
    [27279] = 'physical damage taken-6', --Eri. Leg Guards
    [27280] = 'physical damage taken-7', --Eri. Leg Guards +1
    [21699] = 'potency of cure effects received+10', --Nibiru Faussar
    [27768] = 'fast cast+5', --Cizin Helm
    [27775] = 'fast cast+10', --Nahtirah Hat
    [28054] = 'fast cast+7', --Gendewitha Gages
    [28058] = 'snapshot+4', --Manibozho Gloves
    [28184] = 'fast cast+5', --Orvail Pants +1
    [28197] = 'snapshot+9', --Nahtirah Trousers
    [28206] = 'fast cast+10', --Geomancy Pants
    [28335] = 'cursna+10', --Gende. Galoshes
    [28459] = 'potency of cure effects received+5', --Chuq'aba Belt
    [28484] = 'cure potency+3', --Nourish Earring
    [28485] = 'cure potency+5', --Nourish Earring +1
    [28577] = 'potency of cure effects received+5', --Kunaji Ring
    [28582] = 'magic burst damage+5', --Locus Ring
    [28619] = 'cursna+15', --Mending Cape
    [28631] = 'elemental siphon+30', --Conveyance Cape
    [28637] = 'fast cast+7', --Lifestream Cape
    [11618] = 'song effect duration+10', -- Aoidos' Matinee
    [20629] = 'song effect duration+5', -- Legato Dagger
}
-- ===========================================================================
-- Path / Reinforcement-Point gear (extdata "augment_system 4").
-- extdata only returns {'Path: X'} for these items and never decodes the stat
-- augments (they are implied by item + path + rank and looked up client-side),
-- so the stats are supplied here. Applied ONLY when the item's current rank == max,
-- because per-rank scaling is not reliably published; sub-max items are flagged
-- (see handle_path_augments) rather than shown with guessed numbers.
-- Format: [item_id] = { max = <max rank>, paths = { [path_letter] = '<augment string @ max rank>' } }
-- Every value below is the documented MAX-RANK augment set. Sources cited per entry.
-- To extend: capture an unmapped item with settings.debugmode on, look up its
-- max-rank augments on bg-wiki, and append a row in the same format.
-- ===========================================================================
path_augments = {
    -- Ninja Nodowa +2 | Dynamis-D JSE neck | single path | max rank 25
    -- Source: FFXIclopedia "Max Rank (25) Augments"; BG-Wiki JSE Necks category
    [25491] = { max = 25, paths = { ['A'] = 'DEX+15 AGI+15 Daken+25 Physical damage limit+10%' } },
    -- Alabaster Earring | Limbus (Temenos Furnace) | max rank 30
    -- Source: FFXIclopedia/BG-Wiki "Max Rank Augments (30)"
    [26119] = { max = 30, paths = { ['A'] = 'Accuracy+15 Ranged Accuracy+15 Magic Accuracy+15 All Attributes+10 Store TP+5' } },
    -- Sailfi Belt +1 | Unity accessory (Lustreless Scales) | max rank 15
    -- Source: FFXIclopedia "Max rank augments shown"
    [28428] = { max = 15, paths = { ['A'] = 'STR+15 Double Attack+5%' } },
    -- Tatenashi Haidate +1 | Unity accessory (Lustreless Wings) | max rank 15
    -- Source: FFXIclopedia "Max rank augments shown"
    [25856] = { max = 15, paths = { ['A'] = 'Accuracy+40 All Attributes+10 Triple Attack+4%' } },
    -- Tatenashi Sune-Ate +1 | Unity accessory (Lustreless Wings) | max rank 15
    -- Source: FFXIclopedia "Max rank augments shown"
    [25924] = { max = 15, paths = { ['A'] = 'Accuracy+60 All Attributes+10 Triple Attack+3%' } },
    -- Kunimitsu | Odyssey Sheol:Gaol weapon (Pilgrim Moogle) | max rank 30 | THREE paths (A/B/C)
    -- Your capture showed Path A @ rank 14 (NOT max). Per-rank values are not published,
    -- so rank-14 is intentionally omitted (would be a guess). When you reach rank 30 on a
    -- given path, add the verified rank-30 augment string for that path here, e.g.:
    -- [21925] = { max = 30, paths = { ['A'] = '<verified rank-30 Path A string>' } },
}
-- ===========================================================================
-- Job traits for //cp full live in the supporting resource file job_traits.lua
-- (same folder as this addon). See that file for structure, sources, and the
-- verification policy. Loaded here; failure to load leaves //cp full trait-less
-- (gear-only) with a chat warning rather than erroring.
-- ===========================================================================
do
    local ok, jt = pcall(dofile, windower.addon_path..'job_traits.lua')
    if ok and type(jt) == 'table' and type(jt.traits) == 'table' then
        job_traits = jt
    else
        job_traits = {traits={},gifts={}}
        log('checkparam: could not load job_traits.lua (v2.4 format) ('..tostring(jt)..') - //cp full will add no traits.')
    end
end

combination={
    ['af']={item=S{
        23040,23041,23042,23043,23044,23045,23046,23047,23048,23049,23050,23051,23052,23053,23055,23056,23057,23058,23059,23060,23061,23062,
        23107,23108,23109,23110,23111,23112,23113,23114,23115,23116,23117,23118,23119,23120,23122,23123,23124,23125,23126,23127,23128,23129,
        23174,23175,23176,23177,23178,23179,23180,23181,23182,23183,23184,23185,23186,23187,23189,23190,23191,23192,23193,23194,23195,23196,
        23241,23242,23243,23244,23245,23246,23247,23248,23249,23250,23251,23252,23253,23254,23256,23257,23258,23259,23260,23261,23262,23263,
        23308,23309,23310,23311,23312,23313,23314,23315,23316,23317,23318,23319,23320,23321,23323,23324,23325,23326,23327,23328,23329,23330,
        23375,23376,23377,23378,23379,23380,23381,23382,23383,23384,23385,23386,23387,23388,23390,23391,23392,23393,23394,23395,23396,23397,
        23442,23443,23444,23445,23446,23447,23448,23449,23450,23451,23452,23453,23454,23455,23457,23458,23459,23460,23461,23462,23463,23464,
        23509,23510,23511,23512,23513,23514,23515,23516,23517,23518,23519,23520,23521,23522,23524,23525,23526,23527,23528,23529,23530,23531,
        23576,23577,23578,23579,23580,23581,23582,23583,23584,23585,23586,23587,23588,23589,23591,23592,23593,23594,23595,23596,23597,23598,
        23643,23644,23645,23646,23647,23648,23649,23650,23651,23652,23653,23654,23655,23656,23658,23659,23660,23661,23662,23663,23664,23665,
        26085,26191},stats={['accuracy']=15,['magic accuracy']=15,['ranged accuracy']=15},type=-1},
    ['af_smn']={item=S{23054,23121,23188,23255,23322,23389,23456,23523,23590,23657,26342},
        stats={['pet: accuracy']=15,['pet: magic accuracy']=15,['pet: ranged accuracy']=15},type=-1},
    ['adhemar']={item=S{25614,25687,27118,27303,27474},stats={['critical hit rate']=2},type=0},
    ['amalric']={item=S{25616,25689,27120,27305,27476},stats={['magic attack bonus']=10},type=0},
    ['apogee']={item=S{26677,26853,27029,27205,27381},stats={['pet: blood pact damage']=2},type=0},
    ['argosy']={item=S{26673,26849,27025,27201,27377},stats={['double attack']=2},type=0},
    ['emicho']={item=S{25610,25683,27114,27299,27470},stats={['double attack']=2},type=0},
    ['carmine']={item=S{26679,26855,27031,27207,27383},stats={['accuracy']=10},type=0},
    ['kaykaus']={item=S{25618,25691,27122,27307,27478},stats={['cure potency ii']=2},type=0},
    ['lustratio']={item=S{26669,26845,27021,27197,27373},stats={['weapon skill damage']=2},type=0},
    ['rao']={item=S{26675,26851,27027,27203,27379},stats={['matial arts']=2},type=0},
    ['ryuo']={item=S{25612,25685,27116,27301,27472},stats={['attack']=10},type=0},
    ['souveran']={item=S{26671,26847,27023,27199,27375},stats={['damage taken']=2},type=0},
    ['ayanmo']={item=S{25572,25795,25833,25884,25951},stats={['str']=8,['vit']=8,['mnd']=8},type=-1},
    ['flamma']={item=S{25569,25797,25835,25886,25953},stats={['str']=8,['dex']=8,['vit']=8},type=-1},
    ['mallquis']={item=S{25571,25799,25837,25888,25955},stats={['vit']=8,['int']=8,['mnd']=8},type=-1},
    ['Mummu']={item=S{25570,25798,25836,25887,25954},stats={['dex']=8,['agi']=8,['chr']=8},type=-1},
    ['tali\'ah']={item=S{25573,25796,25834,25885,25952},stats={['vit']=8,['dex']=8,['chr']=8},type=-1},
    ['Hizamaru']={item=S{25576,25792,25830,25881,25948},stats={['counter']=2},type=-1},
    ['Inyanga']={item=S{25577,25793,25831,25882,25949},stats={['refresh']=1},type=-1},
    ['jhakri']={item=S{25578,25794,25832,25883,25950},stats={['fast cast']=3},type=-1},
    ['meghanada']={item=S{25575,25791,25829,25880,25947},stats={['regen']=3},type=-1},
    ['Sulevia\'s']={item=S{25574,25790,25828,25879,25946},stats={['subtle blow']=5},type=-1},
    ['BladeFlashEarrings']={item=S{28520,28521},stats={['double attack']=7},type=-1},
    ['HeartDudgeonEarrings']={item=S{28522,28523},stats={['dual wield']=7},type=-1}
}

caps={
    ['haste']=25,
    ['subtle blow']=50,
    ['cure potency']=50,
    ['potency of cure effects received']=30,
    ['quick cast']=10,
    ['physical damage taken']=-50,
    ['magic damage taken']=-50,
    ['breath damage taken']=-50,
    ['pet: physical damage taken']=-87.5,
    ['pet: magic damage taken']=-87.5,
    ['pet: haste']=25,
    ['magic burst damage']=40,
    ['blood pact delay']=-15,
    ['blood pact delay ii']=-15,
    ['save tp']=500,
    ['fast cast']=80,
    ['reward']=50
}
