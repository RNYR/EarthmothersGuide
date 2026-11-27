-- Offline tests: luajit tests/run.lua (from the addon folder).
-- Copyright (C) 2026 Vard Ruun. Licensed under GPL-3.0-only; see LICENSE and NOTICE.md.
-- Loads the addon files listed in the .toc against a mocked WoW API and checks the engine.

local failures, passed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failures = failures + 1; print("FAIL: " .. msg) end
end

------------------------------------------------------------------------------ mock client
local state = { level = 1, log = {}, done = {}, ready = {}, spells = {}, map = 1412, x = 0.5, y = 0.5, zone = "Mulgore" }
local waypoints = {}

function UnitLevel() return state.level end
function GetRealZoneText() return state.zone end
function IsPlayerSpell(id) return state.spells[id] == true end
C_QuestLog = {
  IsQuestFlaggedCompleted = function(id) return state.done[id] == true end,
  GetLogIndexForQuestID = function(id) return state.log[id] and 1 or nil end,
  IsComplete = function(id) return state.ready[id] == true end,
  GetQuestObjectives = function() return { { text = "0/8 Plainstrider Feathers", finished = false } } end,
}
C_Map = {
  GetBestMapForUnit = function() return state.map end,
  GetPlayerMapPosition = function() return { x = state.x, y = state.y } end,
  CanSetUserWaypointOnMap = function() return true end,
  SetUserWaypoint = function(p) waypoints[#waypoints + 1] = p end,
}
state.facing = 0
function GetPlayerFacing() return state.facing end
function CreateVector2D(x, y) return { x = x, y = y } end
-- fake world: map 1412 (Mulgore) spans 3000 yards north-south and 2000 east-west on continent 1
C_Map.GetWorldPosFromMapPos = function(m, v) return 1, { x = -v.y * 3000, y = -v.x * 2000 } end
UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m = m, x = x, y = y } end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }
C_Timer = { After = function(_, fn) fn() end }
print = print

local function newObject()
  local o = { shown = true, scripts = {}, text = "" }
  -- Like real frames: unknown methods (Capitalised) are no-ops, unknown fields are nil.
  setmetatable(o, { __index = function(t, k)
    if type(k) == "string" and k:match("^%u") then return function(self, ...) return nil end end
    return nil
  end })
  o.SetScript = function(self, k, fn) self.scripts[k] = fn end
  o.events = {}
  o.RegisterEvent = function(self, e) self.events[e] = true end
  o.CreateFontString = function() local f = newObject(); f.SetText = function(s, t) s.text = t end
    f.GetStringHeight = function() return 12 end; return f end
  o.CreateTexture = function() return newObject() end
  o.GetFontString = function() return newObject() end
  o.Show = function(self) self.shown = true end
  o.Hide = function(self) self.shown = false end
  o.IsShown = function(self) return self.shown end
  o.GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end
  return o
end
SlashCmdList = {}   -- the game provides this table
function CreateFrame(_, name) local o = newObject(); if name then _G[name] = o end; return o end
UIParent = newObject()

------------------------------------------------------------------------------ load the .toc
local ns = {}
local files = {}
for line in io.lines("EarthmothersGuide.toc") do
  if not line:match("^#") and line:match("%S") then files[#files + 1] = (line:gsub("\\", "/")) end
end
for _, f in ipairs(files) do
  local chunk, err = loadfile(f)
  check(chunk ~= nil, "load " .. f .. ": " .. tostring(err))
  if chunk then
    local ok, e = pcall(chunk, "EarthmothersGuide", ns)
    check(ok, "run " .. f .. ": " .. tostring(e))
  end
end
local frame = ns.eventFrame
local function fire(event, arg) frame.scripts.OnEvent(frame, event, arg) end

------------------------------------------------------------------------------ data checks
fire("ADDON_LOADED", "EarthmothersGuide")
local count = 0
for n = 1, 12 do
  check(ns.chapters[n] ~= nil, "chapter " .. n .. " registered")
end
local TYPES = { accept = 1, complete = 1, turnin = 1, ["goto"] = 1, level = 1, spell = 1, zone = 1, note = 1, train = 1, bind = 1 }
local seenQuest = { accept = {}, turnin = {} }
for i, s in ipairs(ns.steps) do
  count = count + 1
  check(TYPES[s.t], "step " .. i .. " has a known type: " .. tostring(s.t))
  check(type(s.text) == "string" and #s.text > 0, "step " .. i .. " has text")
  if s.t == "accept" or s.t == "complete" or s.t == "turnin" then
    check(type(s.q) == "table" and #s.q > 0, "step " .. i .. " has quest ids")
    for _, q in ipairs(s.q or {}) do
      check(s.qn and type(s.qn[q]) == "string", "step " .. i .. " names quest " .. q)
      if s.t ~= "complete" then
        check(not seenQuest[s.t][q], ("quest %d is %sed only once (step %d)"):format(q, s.t, i))
        seenQuest[s.t][q] = i
      end
    end
  end
  if s.x then check(type(s.y) == "number" and s.x >= 0 and s.x <= 100, "step " .. i .. " has sane coordinates") end
  if s.d then check(s.dmin and s.dmax and s.dmin <= s.dmax, "dungeon step " .. i .. " has a level range") end
end
-- every turn-in follows its accept
for q, ti in pairs(seenQuest.turnin) do
  local ai = seenQuest.accept[q]
  check(ai and ai < ti, ("quest %d accepted (step %s) before turn-in (step %d)"):format(q, tostring(ai), ti))
end
check(count > 1000, "guide has a full route (" .. count .. " steps)")

------------------------------------------------------------------------------ engine checks
fire("PLAYER_ENTERING_WORLD")
check(ns.index == 1, "fresh character starts at step 1 (got " .. tostring(ns.index) .. ")")
check(#waypoints >= 0, "waypoint call did not error")

-- step 1 is a note: manual. Move on.
ns.Next()
local s = ns.Current()
check(s.t == "accept", "step 2 is an accept step")
-- accept its quests -> auto advance
for _, q in ipairs(s.q) do state.log[q] = true end
fire("QUEST_ACCEPTED", s.q[1])
check(ns.Current() ~= s, "accepting the quest advances the guide")

-- complete + turn in everything up to the first manual step
local guard = 0
while guard < 400 do
  guard = guard + 1
  local cur = ns.Current()
  if not ns.VERIFIABLE[cur.t] then break end
  for _, q in ipairs(cur.q or {}) do
    if cur.t == "accept" then state.log[q] = true
    elseif cur.t == "complete" then state.ready[q] = true
    elseif cur.t == "turnin" then state.done[q] = true; state.log[q] = nil end
  end
  if cur.t == "spell" then state.spells[cur.spell] = true end
  fire("QUEST_LOG_UPDATE")
  if ns.Current() == cur then break end
end
check(ns.Current().t == "zone" or not ns.VERIFIABLE[ns.Current().t],
  "camp quests flow through to the next manual step (stopped at " .. ns.Current().t .. " #" .. ns.index .. ")")

-- zone step completes on arrival
local zoneStep = ns.Current()
if zoneStep.t == "zone" then
  state.map = zoneStep.m; state.zone = zoneStep.zoneName
  fire("ZONE_CHANGED_NEW_AREA")
  check(ns.Current() ~= zoneStep, "zone step completes when you arrive")
end

-- manual Prev does not snap forward until the next game event
local here = ns.index
ns.Prev()
check(ns.index == here - 1, "prev moves back one step")
ns.Refresh()
check(ns.index == here - 1, "manual move is respected by Refresh")
fire("QUEST_LOG_UPDATE")
check(ns.index == here - 1, "a quest log update does not undo a manual move")
fire("QUEST_TURNED_IN")
check(ns.index >= here, "real progress (a hand-in) resumes auto-advance")

-- resume from quest log when saved position is missing
local resume = ns.FindResumeIndex()
check(resume >= here - 1, "resume index follows completed quests (" .. resume .. ")")

-- dungeon filter
local dstep
for _, st in ipairs(ns.steps) do if st.d then dstep = st break end end
check(dstep ~= nil, "route has dungeon steps")
state.level = 10
check(not ns.IsFiltered(dstep), "dungeon step shown when in range")
ns.SetSetting("dungeons", false)   -- an old saved setting from 1.0.x must not hide dungeons
check(not ns.IsFiltered(dstep), "dungeon steps cannot be switched off")
state.level = dstep.dmax + 1
check(ns.IsFiltered(dstep), "dungeon step above the dungeon's range is skipped")
state.level = 10

-- slash commands do not error
for _, cmd in ipairs({ "", "show", "next", "prev", "chapter 4", "way", "resume", "scale 1.2", "lock", "unlock", "help" }) do
  local ok, e = pcall(SlashCmdList.EARTHMOTHERSGUIDE, cmd)
  check(ok, "/emg " .. cmd .. ": " .. tostring(e))
end
ns.GotoChapter(8)
check(ns.Current().chapter.num == 8, "chapter jump lands in chapter 8")

-- druid milestones exist in order
local function findSpell(id) for i, st in ipairs(ns.steps) do if st.t == "spell" and st.spell == id then return i end end end
local bear, aquatic, cat, travel = findSpell(5487), findSpell(1066), findSpell(768), findSpell(783)
check(bear and aquatic and cat and travel and bear < aquatic and aquatic < cat and cat < travel,
  "form milestones in order: bear < aquatic < cat < travel")

------------------------------------------------------------------------------ mid-route start
-- A level 25 character that has never used the guide and handed in nothing it lists.
state.level, state.done, state.log, state.ready, state.spells = 25, {}, {}, {}, {}
ns.InitPosition(false)
check(ns.Current().chapter.num == 5, "level 25 with no history starts in chapter 5 (got " .. ns.Current().chapter.num .. ")")
local ch2complete
for _, st in ipairs(ns.chapters[2].steps) do if st.t == "complete" and not st.cls then ch2complete = st break end end
check(ns.IsFiltered(ch2complete), "an early quest you never picked up is skipped")
state.log[ch2complete.q[1]] = true
check(not ns.IsFiltered(ch2complete), "an early quest still in your log is kept")
state.log = {}

-- grey quests: level 10 quest at level 25 is skipped, class quests never are
local grey, cls
for _, st in ipairs(ns.steps) do
  if not grey and st.t == "accept" and st.ql and st.ql <= 12 and not st.cls and not st.unlock then grey = st end
  if not cls and st.cls and st.t == "accept" then cls = st end
end
ns.startIndex = nil
check(ns.IsFiltered(grey), "grey quest skipped at level 25")
check(ns.GreyLevel(25) == 18 and ns.GreyLevel(45) == 35 and ns.GreyLevel(60) == 51, "the game's grey rule")
ns.SetSetting("grayLevels", 0)
check(not ns.IsFiltered(grey), "grey skipping can be turned off")
ns.SetSetting("grayLevels", 24)
check(not ns.IsFiltered(grey), "a fixed level gap can be set")
ns.SetSetting("grayLevels", -1)
check(not ns.IsFiltered(cls), "class quests are never skipped as grey")

-- missing forms
local names = {}
for _, f in ipairs(ns.MissingForms()) do names[#names + 1] = f.name end
check(table.concat(names, ",") == "Bear Form,Aquatic Form,Cat Form", "level 25 without forms is told about Bear, Aquatic, Cat (" .. table.concat(names, ",") .. ")")
state.spells[5487] = true
check(#ns.MissingForms() == 2, "learning Bear Form removes it from the warning")

-- quests done far ahead of your level do not throw you forward...
local marked = 0
for _, st in ipairs(ns.chapters[7].steps) do
  if st.t == "turnin" and marked < 10 then
    for _, q in ipairs(st.q) do state.done[q] = true end
    marked = marked + 1
  end
end
ns.InitPosition(false)
check(ns.Current().chapter.num <= 6, "level 25: chapter 7 quests done early do not move the start past your level (got " .. ns.Current().chapter.num .. ")")
-- ...but at the right level, quest history beats level and moves the start there
state.level = ns.chapters[7].levels[1]
ns.InitPosition(false)
check(ns.Current().chapter.num >= 7, "at chapter 7's level: finished chapter 7 quests move the start there (got " .. ns.Current().chapter.num .. ")")
state.level = 25
for _, cmd in ipairs({ "status", "gray 4", "gray grey", "resume", "check 6128", "check" }) do
  local ok, e = pcall(SlashCmdList.EARTHMOTHERSGUIDE, cmd)
  check(ok, "/emg " .. cmd .. ": " .. tostring(e))
end

-- the in-game case: level 15, the Cure Poison quest (6128) in the log, later Barrens quests done
state.level, state.done, state.log, state.ready, state.spells = 15, {}, {}, {}, { [5487] = true }
for _, q in ipairs({ 5926, 5922, 5930, 5932, 6002, 6126, 6127, 855 }) do state.done[q] = true end
state.log[6128] = true
ns.InitPosition(false)
local cur = ns.Current()
check(cur.t == "complete" and cur.q[1] == 6128,
  "a class quest in your log is not jumped over (at " .. cur.t .. " " .. tostring(cur.q and cur.q[1]) .. ")")

------------------------------------------------------------------------------ arrow
local function near(a, b) return a and b and math.abs(a - b) < 1e-6 end
local d, rel = ns.ArrowMath(0, 0, 10, 0, 0)
check(near(d, 10) and near(rel, 0), "target north while facing north: straight ahead")
d, rel = ns.ArrowMath(0, 0, 0, 10, 0)
check(near(rel, math.pi / 2), "target west while facing north: arrow points left")
d, rel = ns.ArrowMath(0, 0, 0, -10, 0)
check(near(rel, 3 * math.pi / 2), "target east while facing north: arrow points right")
d, rel = ns.ArrowMath(0, 0, 10, 0, math.pi / 2)
check(near(rel, 3 * math.pi / 2), "facing west, target north: arrow points right")
d, rel = ns.ArrowMath(0, 0, 3, 4, nil)
check(near(d, 5) and rel == nil, "no facing: distance only")
local r, g = ns.ArrowColor(0)
check(g > r, "ahead is green")
r, g = ns.ArrowColor(math.pi)
check(r > g, "behind is red")

-- live arrow follows the current step
state.map, state.x, state.y, state.facing = 1412, 0.40, 0.70, 0
local wstep
for _, st in ipairs(ns.steps) do if st.m == 1412 and st.x then wstep = st break end end
check(ns.SetWaypoint(wstep), "waypoint set for a step with coordinates")
check(ns.ArrowTarget() and ns.ArrowTarget().step == wstep, "arrow targets the step")
check(pcall(ns.UpdateArrow), "arrow update runs")
ns.SetWaypoint({ t = "note", text = "x" })
check(ns.ArrowTarget() == nil, "arrow hides on a step without coordinates")
for _, cmd in ipairs({ "arrow off", "arrow on" }) do
  local ok, e = pcall(SlashCmdList.EARTHMOTHERSGUIDE, cmd)
  check(ok, "/emg " .. cmd .. ": " .. tostring(e))
end
check(ns.Setting("arrow") == true, "arrow setting toggles back on")

------------------------------------------------------------------------------ batch checklist
ns.startIndex = nil
ns.logReady = true
state.level, state.done, state.log, state.ready = 3, {}, {}, {}
local batchStep, acceptBefore
for _, st in ipairs(ns.chapters[2].steps) do
  if st.t == "complete" and st.q and #st.q >= 3 and st.pts then batchStep = st break end
end
check(batchStep ~= nil, "chapter 2 has a multi-quest batch step")
check(batchStep.text:match("^Do these %d+ quests"), "batch step says how many quests: " .. tostring(batchStep.text))
local qa, qb, qc = batchStep.q[1], batchStep.q[2], batchStep.q[3]
state.level = 13
for _, q in ipairs(batchStep.q) do state.log[q] = true end
check(not ns.IsStepDone(batchStep), "batch not done while quests are open")
for _, q in ipairs(batchStep.q) do if q ~= qa then state.ready[q] = true end end
check(not ns.IsStepDone(batchStep), "batch waits for the last quest")
state.log[qa] = nil
check(ns.IsStepDone(batchStep), "a quest you dropped does not hold the batch up")
ns.logReady = false
check(not ns.IsStepDone(batchStep), "before the quest log loads, missing quests still count as open")
ns.logReady = true

-- nearest objective
state.ready, state.log = {}, {}
for _, q in ipairs(batchStep.q) do state.log[q] = true end
ns.SetIndex(batchStep.index, true)
ns.SetWaypoint(batchStep)
local pb = batchStep.pts[qb]
state.map, state.x, state.y = pb.m, pb.x / 100, pb.y / 100
local reading = ns.ArrowReading()
check(reading and reading.q == qb, "arrow leads to the nearest unfinished quest (" .. tostring(reading and reading.q) .. " vs " .. qb .. ")")
state.ready[qb] = true
ns.Fire()   -- the game sends quest log events; the guide refreshes
reading = ns.ArrowReading()
check(reading and reading.q ~= qb, "finished quest is no longer an arrow target")

-- carried quests and pickup preview
state.ready = {}
local other
for _, st in ipairs(ns.chapters[2].steps) do
  if st.t == "complete" and st ~= batchStep and st.q and not st.cls then other = st break end
end
state.log[other.q[1]] = true
ns.Fire()   -- in game, every quest log change triggers a refresh
local carried = ns.Carrying()
local found = false
for _, e in ipairs(carried) do if e.id == other.q[1] then found = true end end
check(found, "quests from other batches you carry are listed")
for _, e in ipairs(carried) do check(e.id ~= qa, "the current batch is not repeated under carried quests") end
local acc
for i = batchStep.index - 1, 1, -1 do if ns.steps[i].t == "accept" then acc = ns.steps[i] break end end
for _, q in ipairs(batchStep.q) do state.log[q] = nil end
ns.SetIndex(acc.index, true)
check(ns.ComingUp == nil, "the \"Coming up\" section is gone")

-- compact mode and item button render without errors
GetQuestLogSpecialItemInfo = function() return "|Hitem:5880|h[Lunardust]|h", 134400 end
InCombatLockdown = function() return false end
state.log[qa] = true
ns.SetIndex(batchStep.index, true)
ns.SetSetting("compact", true)
check(pcall(ns.Fire), "compact checklist renders")
ns.SetSetting("compact", false)
-- give the mock panel real positions: rows stacked from y=500 down, the visible area 520..300
do
  local pf = _G.EarthmothersGuideFrame
  pf.scroll.GetTop = function() return 520 end
  pf.scroll.GetBottom = function() return 300 end
  local y = 500
  for _, row in ipairs(pf.rows) do
    local top = y
    row.GetTop = function() return top end
    row.GetRight = function() return 310 end
    y = y - 40
  end
  ns.UpdateItemButtons()
  local b = _G.EarthmothersGuideItemButton1
  check(b and b:IsShown(), "a quest with a usable item gets a button beside its row")
  local itemRow
  for _, row in ipairs(pf.rows) do if row.used and row.spec and row.spec.item then itemRow = row break end end
  check(itemRow ~= nil, "the row of that quest makes room for the button")
  -- a row scrolled out of view has no button
  for _, row in ipairs(pf.rows) do row.GetTop = function() return 900 end end
  ns.UpdateItemButtons()
  check(not (b and b:IsShown()), "no item button for a row scrolled out of view")
  for _, row in ipairs(pf.rows) do row.GetTop = function() return 500 end end
  ns.SetSetting("itemButton", false)
  ns.Fire()
  check(not (b and b:IsShown()), "quest item buttons can be switched off")
  ns.SetSetting("itemButton", true)
  -- the panel never grows past "Panel max height": it scrolls instead
  ns.SetSetting("maxHeight", 150)
  ns.Fire()
  check((pf.scrollMax or 0) >= 0, "scroll range is worked out")
  local before = pf.scrollAt or 0
  ns.ScrollPanel(10000)
  check((pf.scrollAt or 0) == (pf.scrollMax or 0), "scrolling stops at the end")
  ns.ScrollPanel(-10000)
  check((pf.scrollAt or 0) == 0, "scrolling stops at the top")
  check(pcall(ns.PreviewMaxHeight), "the max height preview shows without errors")
  -- panel width: set, kept within 260-520, and the panel lays out at that width
  local widths = {}
  pf.SetWidth = function(_, w) widths[#widths + 1] = w end
  SlashCmdList.EARTHMOTHERSGUIDE("width 420")
  check(ns.Setting("panelWidth") == 420, "/emg width sets the panel width")
  ns.Fire()
  check(widths[#widths] == 420, "the panel is laid out at the chosen width")
  SlashCmdList.EARTHMOTHERSGUIDE("width 2000")
  check(ns.Setting("panelWidth") == 420, "a width outside 260-520 is refused")
  ns.SetSetting("panelWidth", 100)
  ns.Fire()
  check(widths[#widths] == 260, "the panel never gets narrower than 260")
  ns.SetSetting("panelWidth", 350)
  ns.Fire()
  ns.SetSetting("maxHeight", 450)
  ns.Fire()
end
------------------------------------------------------------------------------ hand-ins and professions
-- dungeon quests are picked up near the dungeon, not in faraway cities (no Undercity pickup for RFC)
for _, st in ipairs(ns.steps) do
  if st.d == "Ragefire Chasm" and st.t == "accept" then
    check(st.zone ~= "Undercity", "Ragefire Chasm quests are not picked up in Undercity (" .. tostring(st.npc) .. ")")
  end
end

-- ready to hand in: only finished quests of the batch you are on, with who takes them and where
do
  local bstep
  for _, st in ipairs(ns.steps) do
    if st.t == "complete" and st.q and #st.q >= 3 and not st.d then
      local ok = true
      for _, q in ipairs(st.q) do if not ns.turninIndex[q] or ns.turninIndex[q] < st.index then ok = false end end
      if ok then bstep = st break end
    end
  end
  check(bstep ~= nil, "found a batch with hand-ins after it")
  local q1, q2 = bstep.q[1], bstep.q[2]
  local t1 = ns.steps[ns.turninIndex[q1]]
  -- someone else's finished quest, from another chapter, is in your log too
  local other
  for q, ti in pairs(ns.turninIndex) do if ns.steps[ti].chapter ~= bstep.chapter then other = q break end end
  state.log, state.ready, state.done = { [q1] = true, [q2] = true, [other] = true }, { [q1] = true, [q2] = true, [other] = true }, {}
  ns.SetIndex(t1.index, true)
  local ready = ns.ReadyToHandIn()
  local has2, hasOther = false, false
  for _, e in ipairs(ready) do
    if e.id == q2 then has2 = e end
    if e.id == other then hasOther = true end
  end
  check(has2 and has2.npc == ns.steps[ns.turninIndex[q2]].npc, "a finished quest of this batch is listed with who takes it")
  check(not hasOther, "finished quests from outside the batch are not listed")
  check(pcall(ns.Fire), "panel renders the ready list")
  state.log, state.ready = {}, {}
end

-- profession quests
local profStep, profQ
for _, st in ipairs(ns.steps) do
  if st.prof and st.t == "accept" then profStep = st; profQ = next(st.prof) break end
end
check(profStep ~= nil, "route tags profession quests (" .. tostring(profQ) .. ")")
state.log, state.ready = {}, {}
ns.SetSetting("professions", false)
check(ns.QuestHidden(profStep, profQ), "profession quest hidden when the option is off")
local visible = ns.StepQuests(profStep)
for _, q in ipairs(visible) do check(q ~= profQ, "hidden profession quest not listed in its step") end
if #profStep.q == 1 then check(ns.IsFiltered(profStep), "a step with only a profession quest is skipped") end
state.log[profQ] = true
check(not ns.QuestHidden(profStep, profQ), "a profession quest already in your log stays")
state.log = {}
ns.SetSetting("professions", true)
check(not ns.QuestHidden(profStep, profQ), "profession quests shown when the option is on")

------------------------------------------------------------------------------ hearthstone and travel
local binds, hearthTips, detours, moonTrain = 0, 0, 0, 0
local firstBind
for _, st in ipairs(ns.steps) do
  if st.t == "bind" then binds = binds + 1; firstBind = firstBind or st end
  if st.tip and st.tip:match("Use your hearthstone") then hearthTips = hearthTips + 1 end
  if st.t == "zone" and st.text:match("^Detour to") then detours = detours + 1 end
  if st.t == "train" and st.tip and st.tip:match("Teleport: Moonglade.*hearth back") then moonTrain = moonTrain + 1 end
end
check(binds >= 15, "route sets the hearthstone at each new hub (" .. binds .. ")")
check(hearthTips >= 3, "travel steps suggest the hearthstone when it is set there (" .. hearthTips .. ")")
check(detours >= 1, "long-waiting city hand-ins get a detour (" .. detours .. ")")
check(moonTrain >= 10, "training steps suggest Teleport: Moonglade and hearthing back (" .. moonTrain .. ")")
check(firstBind.bind == "Bloodhoof Village" and firstBind.x, "first hearth is Bloodhoof Village, with the innkeeper's location")
GetBindLocation = function() return "Bloodhoof Village" end
check(ns.IsStepDone(firstBind), "set-hearth step completes when the game reports the new hearth")
GetBindLocation = function() return "Camp Narache" end
check(not ns.IsStepDone(firstBind), "set-hearth step waits while the hearth is elsewhere")
local cross
for _, st in ipairs(ns.steps) do if st.t == "bind" and st.bind == "The Crossroads" then cross = st break end end
GetBindLocation = function() return "Crossroads" end
check(ns.IsStepDone(cross), "hearth names match loosely (Crossroads = The Crossroads)")
-- a detour hands in only quests that waited too long, at least MAX levels below the route
for i, st in ipairs(ns.steps) do
  if st.t == "zone" and st.text:match("^Detour to") then
    local nxt = ns.steps[i + 1]
    check(nxt and nxt.t == "turnin", "a detour is followed by its hand-ins (" .. st.text .. ")")
  end
end

------------------------------------------------------------------------------ Timbermaw tunnel tip
local felwoodTravel, wsTravel
for _, st in ipairs(ns.steps) do
  if st.t == "zone" and st.tipRep and st.zone == "Felwood" then felwoodTravel = st end
  if st.t == "zone" and st.tipRep and st.zone == "Winterspring" then wsTravel = st end
end
check(felwoodTravel and wsTravel, "Felwood and Winterspring travel steps carry the tunnel tip")
local rep = 2
C_Reputation = { GetFactionDataByID = function(id) if id == 576 then return { reaction = rep } end end }
check(not ns.StepTip(wsTravel):match("Teleport: Moonglade"), "while Timbermaw is Hostile the tunnel shortcut is not suggested")
check(ns.StepTip(wsTravel):match("run straight through"), "Hostile: tells you to run through, not fight")
rep = 3
check(ns.StepTip(wsTravel):match("Teleport: Moonglade"), "at Unfriendly the Moonglade tunnel shortcut is suggested")
C_Reputation = nil
check(ns.StepTip(felwoodTravel) == felwoodTravel.tip, "without reputation data the safe tip is shown")

check(ns.IsManual({ t = "note" }) and not ns.IsManual({ t = "accept" }), "notes are clicked through, quest steps are not")
check(ns.optionsPage ~= nil, "settings page built")
check(pcall(ns.optionsPage.Refresh, ns.optionsPage, true), "settings page refresh runs")
check(pcall(ns.OpenOptions), "opening settings runs")
for _, cmd in ipairs({ "options" }) do
  local ok, e = pcall(SlashCmdList.EARTHMOTHERSGUIDE, cmd)
  check(ok, "/emg " .. cmd .. ": " .. tostring(e))
end

------------------------------------------------------------------------------ review fixes
ns.startIndex = nil; ns.logReady = true
state.level, state.log, state.ready, state.done, state.spells = 8, {}, {}, {}, {}
-- a turn-in step does not block on a quest you never took or abandoned
local two
for _, st in ipairs(ns.chapters[1].steps) do if st.t == "turnin" and #st.q >= 2 then two = st break end end
check(two ~= nil, "chapter 1 has a turn-in step with two quests")
if two then
  ns.SetIndex(two.index, true)
  state.done[two.q[1]] = true            -- handed in one, never took the other
  check(ns.IsStepDone(two), "turn-in step finishes when the other quest was never taken")
  state.log[two.q[2]] = true             -- but if you carry it, it waits
  check(not ns.IsStepDone(two), "turn-in step waits for a quest you still carry")
  state.log = {}
end

-- resume ignores learned spells (they come with level, not with quests)
state.done, state.spells = {}, { [18960] = true, [5487] = true }
local lastProof
for i, st in ipairs(ns.steps) do
  if st.t == "turnin" and st.chapter.num == 1 and i < 40 then lastProof = i; for _, q in ipairs(st.q) do state.done[q] = true end end
end
local r = ns.FindResumeIndex()
check(r <= lastProof + 1, ("knowing Teleport: Moonglade does not push the start forward (%d vs %d)"):format(r, lastProof + 1))

-- dungeon steps stay for quests you carry, even outlevelled or with dungeons off
local dstep2
for _, st in ipairs(ns.steps) do if st.d and st.t == "turnin" and not st.unlock then dstep2 = st break end end
state.level = (dstep2.dmax or 20) + 5
state.log[dstep2.q[1]] = true
check(not ns.IsFiltered(dstep2), "outlevelled dungeon turn-in kept while the quest is in your log")
state.log = {}
check(ns.IsFiltered(dstep2), "outlevelled dungeon step without the quest is skipped")

-- continuing a note does not stop on a step that is already done
local note
for i, st in ipairs(ns.steps) do
  if st.t == "note" and ns.steps[i + 1] and ns.steps[i + 1].t == "bind" then note = st break end
end
if note then
  state.level = 5
  GetBindLocation = function() return ns.steps[note.index + 1].bind end
  ns.SetIndex(note.index, true)
  ns.Next()
  check(ns.index > note.index + 1, "Next from a note skips a hearth step that is already set")
end

-- the map pin is cleared on steps without a location
ns.pinSet = true
local cleared = false
C_Map.ClearUserWaypoint = function() cleared = true end
ns.SetWaypoint({ t = "note", text = "x" })
check(cleared, "map pin cleared on a step without a location")

-- secret values never reach the maths
issecretvalue = function(v) return v == "secret" end
GetPlayerFacing = function() return "secret" end
check(pcall(ns.ArrowReading), "hidden facing value does not break the arrow")
issecretvalue = nil
GetPlayerFacing = function() return state.facing end

-- route data: no exclusive pairs together, no reputation-gated quests, Krol'dok and Shen'dralas filled
local inRoute = {}
for _, st in ipairs(ns.steps) do for _, q in ipairs(st.q or {}) do inRoute[q] = true end end
for _, pair in ipairs({ {9121, 9122}, {5093, 5094}, {5093, 5095}, {6541, 6542}, {1370, 1369} }) do
  check(not (inRoute[pair[1]] and inRoute[pair[2]]), ("exclusive quests %d and %d are not both routed"):format(pair[1], pair[2]))
end
for _, q in ipairs({ 9121, 9124, 5513, 5517, 6031, 1370, 1369 }) do
  check(not inRoute[q], "raid or reputation-gated quest " .. q .. " is not routed")
end
local krol, shen = 0, 0
for _, st in ipairs(ns.steps) do
  if st.d == "Krol'dok Stronghold" and st.q then krol = krol + #st.q end
  if st.zone == "Shen'dralas" and st.t == "accept" then shen = shen + #st.q end
end
check(krol > 0, "Krol'dok Stronghold has quests (" .. krol .. ")")
check(shen >= 8, "Shen'dralas has its quests (" .. shen .. ")")

-- training below level 10 does not suggest Teleport: Moonglade
for _, st in ipairs(ns.steps) do
  if st.t == "train" and (st.lvl or 99) < 10 then
    check(not (st.tip or ""):match("Teleport"), "level " .. st.lvl .. " training does not suggest a spell you lack")
  end
end

------------------------------------------------------------------------------ second review: engine
-- clicking the last note does not error
ns.SetIndex(#ns.steps, true)
check(pcall(ns.Next), "clicking the final note does not error")
check(ns.index == #ns.steps, "the guide stays on the final step")

-- after a note, the guide keeps advancing on its own when the next step finishes
ns.startIndex = nil; ns.logReady = true
state.level, state.log, state.ready, state.done = 12, {}, {}, {}
local noteThenDo
for i, st in ipairs(ns.steps) do
  local nx = ns.steps[i + 1]
  if ns.IsManual(st) and st.t ~= "bind" and nx and nx.t == "complete" and nx.q and #nx.q == 1 then noteThenDo = st break end
end
if noteThenDo then
  local dostep = ns.steps[noteThenDo.index + 1]
  state.log[dostep.q[1]] = true
  ns.SetIndex(noteThenDo.index, true)
  ns.Next()
  check(ns.index == dostep.index and not ns.manualMove, "continuing a note is not a manual move")
  state.ready[dostep.q[1]] = true
  fire("QUEST_LOG_UPDATE")
  check(ns.index > dostep.index, "finishing the objectives moves the guide on after a note")
  state.log, state.ready = {}, {}
end

-- a hand-picked step that becomes finished moves on, without any special event
local doStep
for _, st in ipairs(ns.chapters[2].steps) do if st.t == "complete" and #st.q == 1 and not st.cls then doStep = st break end end
state.log[doStep.q[1]] = true
ns.SetIndex(doStep.index, true)
state.ready[doStep.q[1]] = true
fire("QUEST_LOG_UPDATE")
check(ns.index > doStep.index, "a step you picked by hand moves on once you finish it")
state.log, state.ready = {}, {}

-- the modern "spell learned" event counts as progress
local evs = ns.eventFrame.events
check(evs.LEARNED_SPELL_IN_SKILL_LINE, "registers LEARNED_SPELL_IN_SKILL_LINE")

-- catch-up after login stays near the saved chapter and respects a manual save
state.level = 15
state.done = {}
for _, st in ipairs(ns.chapters[9].steps) do
  if st.t == "turnin" then for _, q in ipairs(st.q) do state.done[q] = true end end
end
local cur2 = ns.chapters[2].steps[10]
local r2 = ns.FindResumeIndex(ns.chapters[2].steps[1].index, ns.chapters[3].steps[#ns.chapters[3].steps].index)
check(r2 <= ns.chapters[3].steps[#ns.chapters[3].steps].index + 1, "catch-up never leaves the current and next chapter")
check(ns.FindResumeIndex() <= ns.LevelCapIndex() + 1, "quests done far ahead do not move a level-15 character to chapter 9")
state.done = {}

------------------------------------------------------------------------------ second review: route data
do
  local log, peak = {}, 0
  local n = 0
  for _, st in ipairs(ns.steps) do
    if st.t == "accept" then for _, q in ipairs(st.q) do if not log[q] then log[q] = true; n = n + 1 end end
    elseif st.t == "turnin" then for _, q in ipairs(st.q) do if log[q] then log[q] = nil; n = n - 1 end end end
    if n > peak then peak = n end
  end
  check(peak <= 20, "the quest log never holds more than 20 quests (" .. peak .. ")")
end
local routed = {}
for _, st in ipairs(ns.steps) do for _, q in ipairs(st.q or {}) do routed[q] = true end end
for q = 81786, 81874 do check(not routed[q], "Season of Discovery mission " .. q .. " not routed") end
for _, q in ipairs({ 78132, 78133, 78134, 81570, 5401, 92842, 91882, 9272, 1367 }) do
  check(not routed[q], "quest " .. q .. " (SoD / Alliance / reputation-gated) not routed")
end
for _, st in ipairs(ns.steps) do
  check(not (st.npc == "Argent Officer Pureheart" or st.npc == "Quintus Wainworth" or st.npc == "Sefira Everbright"),
    "no Alliance quest NPCs in the route")
end
-- Ragefire Chasm: the follow-up inside the dungeon comes before the hand-ins outside
local maurIn, outside
for i, st in ipairs(ns.steps) do
  if st.d == "Ragefire Chasm" then
    if st.t == "turnin" and st.npc == "Maur Grimtotem" then maurIn = maurIn or i end
    if st.t == "turnin" and (st.zone == "Orgrimmar" or st.zone == "Thunder Bluff") then outside = outside or i end
  end
end
check(maurIn and outside and maurIn < outside, "RFC: hand in inside the dungeon before the city hand-ins")
-- druid steps have their places
for _, st in ipairs(ns.steps) do
  if st.cls and st.t == "complete" and (st.q[1] == 6002 or st.q[1] == 6127) then
    check(st.x and st.m, "druid step for quest " .. st.q[1] .. " has a location")
  end
end

------------------------------------------------------------------------------ second review: arrow and pin
do
  ns.SetSetting("arrow", true)
  state.log = { [900001] = true, [900002] = true }
  state.ready = {}
  local fake = { t = "complete", q = { 900001, 900002 }, pts = { [900001] = { m = 1412, x = 40, y = 70 }, [900002] = { m = 1412, x = 42, y = 70 } } }
  ns.SetArrow(fake)
  state.map, state.x, state.y = 1412, 0.400, 0.700      -- standing at quest 1
  check(ns.ArrowReading().q == 900001, "arrow starts on the nearest quest")
  state.x = 0.4105                                        -- a little closer to quest 2, but not by 25 yards
  ns.Fire()                                               -- quest log update rebuilds the candidates
  check(ns.ArrowReading().q == 900001, "arrow keeps its target through a quest log update")
  state.x = 0.42                                          -- now clearly at quest 2
  check(ns.ArrowReading().q == 900002, "arrow switches once another quest is clearly closer")
  state.log = {}
end
-- turning the map pin off clears it at once
do
  local cleared = false
  C_Map.ClearUserWaypoint = function() cleared = true end
  ns.pinSet = true
  SlashCmdList.EARTHMOTHERSGUIDE("waypoints off")
  check(cleared, "turning the map pin off removes it straight away")
  SlashCmdList.EARTHMOTHERSGUIDE("waypoints on")
end

------------------------------------------------------------------------------ Blizzard tracker replacement
do
  local t = { alpha = 1, shown = true, hooks = {}, protected = true }
  function t:SetAlpha(a) self.alpha = a end
  function t:Hide() self.shown = false end
  function t:Show() self.shown = true; for _, f in ipairs(self.hooks) do f() end end
  function t:IsProtected() return self.protected end
  function t:HookScript(_, f) self.hooks[#self.hooks + 1] = f end
  ObjectiveTrackerFrame = t
  local combat = false
  InCombatLockdown = function() return combat end
  ns.SetSetting("hideTracker", true)
  ns.UpdateBlizzardTracker()
  check(t.alpha == 0 and not t.shown, "Blizzard's tracker is hidden while the guide replaces it")
  combat = true
  t:Show()                                   -- Blizzard re-shows it during combat
  check(t.alpha == 0, "re-shown in combat: made invisible at once (alpha only)")
  combat = false
  ns.eventFrame.scripts.OnEvent(ns.eventFrame, "PLAYER_REGEN_ENABLED")   -- harmless for the engine
  SlashCmdList.EARTHMOTHERSGUIDE("tracker on")
  check(t.alpha == 1 and t.shown, "/emg tracker on gives Blizzard's tracker back")
  SlashCmdList.EARTHMOTHERSGUIDE("tracker off")
  check(t.alpha == 0 and not t.shown, "/emg tracker off hides it again")
  ns.ShowPanel(false)
  check(t.shown, "hiding the guide panel brings Blizzard's tracker back")
  ns.ShowPanel(true)
  check(not t.shown, "showing the guide panel replaces it again")
  -- giving it back in combat: shown at once when the game allows it (not protected) ...
  t.protected = false
  combat = true
  SlashCmdList.EARTHMOTHERSGUIDE("tracker on")
  check(t.alpha == 1 and t.shown, "an unprotected tracker comes back at once, even in combat")
  combat = false
  SlashCmdList.EARTHMOTHERSGUIDE("tracker off")
  -- ... and once combat ends when it is protected
  t.protected = true
  combat = true
  SlashCmdList.EARTHMOTHERSGUIDE("tracker on")
  check(not t.shown, "a protected tracker waits for the end of combat")
  combat = false
  InCombatLockdown = function() return false end
  SlashCmdList.EARTHMOTHERSGUIDE("tracker off")
end

------------------------------------------------------------------------------ optional item-started quests
do
  ns.startIndex = nil; ns.logReady = true
  state.level, state.log, state.ready, state.done = 30, {}, {}, {}
  local opt
  for _, st in ipairs(ns.steps) do if st.opt and st.t == "accept" and st.zone then opt = st break end end
  check(opt ~= nil, "route has optional item-started pickups")
  local q = opt.q[1]
  state.level = math.max(1, (opt.ql or 10))
  check(ns.IsFiltered(opt), "an optional pickup is skipped while you don't have the quest")
  local later = {}
  for _, st in ipairs(ns.steps) do
    if st.index > opt.index and st.q then for _, x in ipairs(st.q) do if x == q then later[#later + 1] = st end end end
  end
  for _, st in ipairs(later) do
    ns.SetIndex(st.index, true)   -- standing on that later step
    check(ns.IsFiltered(st) or ns.IsStepDone(st), "a step for an item quest you never looted never blocks (" .. st.t .. ")")
  end
  -- standing in its zone, it is listed under "Look out for"
  for i = opt.index, 1, -1 do
    local st = ns.steps[i]
    if not st.opt and st.zone == opt.zone and st.chapter == opt.chapter then ns.SetIndex(i, true) break end
  end
  local found = false
  for _, e in ipairs(ns.LookOutFor()) do if e.id == q then found = true end end
  check(found, "optional pickup listed under Look out for in its zone (" .. tostring(opt.npc) .. ")")
  state.log[q] = true
  ns.Fire()
  check(not ns.IsFiltered(opt), "once looted (quest in log), the pickup is part of the route")
  local gone = true
  for _, e in ipairs(ns.LookOutFor()) do if e.id == q then gone = false end end
  check(gone, "and it leaves the Look out for list")
  state.log = {}
end

------------------------------------------------------------------------------ level pacing
do
  -- chapters follow each other without level gaps, and the route ends at 60
  for n = 2, 12 do
    check(ns.chapters[n].levels[1] <= ns.chapters[n - 1].levels[2] + 1, "chapter " .. n .. " starts where chapter " .. (n - 1) .. " ends")
  end
  check(ns.chapters[12].levels[2] == 60, "the route reaches level 60")
  local grinds = 0
  for _, st in ipairs(ns.steps) do
    if st.t == "level" and st.text:match("^Grind to level") then
      grinds = grinds + 1
      check(st.lvl >= st.chapter.levels[1] - 1 and st.lvl <= st.chapter.levels[2] + 1,
        "grind to " .. st.lvl .. " fits chapter " .. st.chapter.num)
    end
  end
  check(grinds > 0 and grinds < 20, "a handful of short grinds where quests run out (" .. grinds .. ")")
end

------------------------------------------------------------------------------ per-quest skip checkboxes
do
  local panel = _G.EarthmothersGuideFrame
  ns.logReady = true; ns.startIndex = nil
  state.level, state.log, state.ready, state.done = 14, {}, {}, {}
  local batch
  for _, st in ipairs(ns.chapters[2].steps) do if st.t == "complete" and #st.q >= 3 then batch = st break end end
  for _, q in ipairs(batch.q) do state.log[q] = true end
  ns.SetIndex(batch.index, true)
  local rows = {}
  for _, r in ipairs(panel.rows) do if r.used and r.spec.q then rows[#rows + 1] = r end end
  check(#rows == #batch.q, ("one checkbox row per quest in the batch (%d of %d)"):format(#rows, #batch.q))
  -- finish all but one quest, then skip that one with its checkbox
  for i = 2, #batch.q do state.ready[batch.q[i]] = true end
  check(not ns.IsStepDone(batch), "batch waits for the last open quest")
  local last = rows[1]
  last.check.GetChecked = function() return true end
  last.check.scripts.OnClick(last.check)
  check(ns.IsSkipped(batch.q[1]), "ticking the box skips that quest")
  check(ns.IsStepDone(batch), "the batch no longer waits for the skipped quest")
  check(ns.index > batch.index, "the guide moves on")
  -- its hand-in no longer waits either
  for _, st in ipairs(ns.steps) do
    if st.t == "turnin" and st.index > batch.index then
      for _, q in ipairs(st.q) do
        if q == batch.q[1] then
          ns.SetIndex(st.index, true)
          check(ns.IsFiltered(st) or ns.IsStepDone(st), "the skipped quest's hand-in step does not wait for it")
        end
      end
    end
  end
  -- untick brings it back; /emg unskip clears all
  ns.SetSkipped(batch.q[1], false)
  check(not ns.IsSkipped(batch.q[1]), "unticking puts the quest back")
  ns.SetSkipped(batch.q[2], true)
  SlashCmdList.EARTHMOTHERSGUIDE("unskip")
  check(not ns.IsSkipped(batch.q[2]), "/emg unskip clears every skip")
  state.log, state.ready = {}, {}
end

------------------------------------------------------------------------------ third review: engine
do
  -- listener (render) errors are recorded, not swallowed
  ns.lastError = nil
  ns.SetIndex(ns.chapters[3].steps[5].index, true)
  check(ns.lastError == nil, "rendering raised no error: " .. tostring(ns.lastError))

  -- clicking the panel: real cursor positions, left-click continues a note, right-click opens settings
  local cx, cy = 400, 300
  GetCursorPosition = function() return cx, cy end
  local panel = _G.EarthmothersGuideFrame
  local note
  for _, st in ipairs(ns.steps) do if st.t == "note" and st.index < #ns.steps then note = st break end end
  ns.logReady = true
  ns.SetIndex(note.index, true)
  local ok1, e1 = pcall(panel.scripts.OnMouseDown, panel, "LeftButton")
  local ok2, e2 = pcall(panel.scripts.OnMouseUp, panel, "LeftButton")
  check(ok1 and ok2, "clicking the panel does not error: " .. tostring(e1 or e2))
  check(ns.index == note.index, "a plain click on the panel no longer moves the guide")
  -- the Done checkbox continues a note
  local row = panel.rows[1]
  check(row and row.used and row.spec and row.spec.done, "a note shows a Done checkbox")
  row.check.scripts.OnClick(row.check)
  check(ns.index > note.index, "ticking Done continues the note")
  local opened = false
  local realOpen = ns.OpenOptions
  ns.OpenOptions = function() opened = true end
  panel.scripts.OnMouseDown(panel, "RightButton")
  panel.scripts.OnMouseUp(panel, "RightButton")
  check(opened, "right-click opens the settings")
  -- a drag is not a click
  ns.SetIndex(note.index, true)
  panel.scripts.OnMouseDown(panel, "LeftButton")
  cx = cx + 40
  panel.scripts.OnMouseUp(panel, "LeftButton")
  check(ns.index == note.index, "dragging the panel does not continue the note")
  ns.OpenOptions = realOpen
  GetCursorPosition = nil

  -- before the quest log has loaded, the guide never moves forward
  state.level, state.log, state.ready, state.done = 21, {}, {}, {}
  local ti
  for _, st in ipairs(ns.chapters[2].steps) do if st.t == "turnin" and not st.cls then ti = st break end end
  ns.logReady = false
  ns.SetIndex(ti.index, false)
  ns.Advance()
  check(ns.index == ti.index, "with the quest log not loaded yet, the guide stays put")
  ns.logReady = true

  -- login catch-up does not jump over an open batch because of a quest picked up early
  local batch
  for _, st in ipairs(ns.chapters[2].steps) do if st.t == "complete" and #st.q >= 3 then batch = st break end end
  local laterAcc
  for _, st in ipairs(ns.chapters[2].steps) do
    if st.t == "accept" and st.index > batch.index + 10 and not st.opt then laterAcc = st break end
  end
  state.level = 14
  state.log = {}
  for _, q in ipairs(batch.q) do state.log[q] = true end
  for _, q in ipairs(laterAcc.q) do state.log[q] = true end
  local r = ns.FindResumeIndex(ns.chapters[2].steps[1].index, ns.chapters[3].steps[#ns.chapters[3].steps].index, true)
  r = ns.StepBackToCarried(batch.index, r)
  check(r <= batch.index, ("catch-up stays on the open batch (%d vs batch %d)"):format(r, batch.index))
  state.log = {}

  -- a pickup whose prerequisite can no longer happen is skipped
  local follow, preStep
  for _, st in ipairs(ns.steps) do
    if st.t == "accept" and st.pre and not st.opt then
      for q, pre in pairs(st.pre) do
        local ai = ns.acceptIndex[pre[1]]
        if ai and ai < st.index and #st.q == 1 then follow, preStep = st, ns.steps[ai] break end
      end
    end
    if follow then break end
  end
  check(follow ~= nil, "found a follow-up pickup with a prerequisite")
  state.level = follow.ql or 20
  state.done, state.log = {}, {}
  ns.SetIndex(follow.index, true)
  check(ns.IsFiltered(follow), "follow-up skipped when its prerequisite was never done (" .. follow.text .. ")")
  for _, p in ipairs(follow.pre[follow.q[1]]) do state.done[p] = true end
  check(not ns.IsFiltered(follow), "follow-up offered once its prerequisite is done")
  state.done = {}
end

------------------------------------------------------------------------------ third review: lower items
do
  ns.logReady = true; ns.startIndex = nil
  state.level, state.log, state.ready, state.done = 20, {}, {}, {}
  -- "Skip this step" from a pickup never lands on a step that is already finished
  local acc
  for _, st in ipairs(ns.chapters[2].steps) do
    local nx = ns.steps[st.index + 1]
    if st.t == "accept" and nx and nx.t == "complete" and not st.cls and not st.opt then acc = st break end
  end
  ns.SetIndex(acc.index, true)
  ns.Next()
  check(not ns.IsStepDone(ns.Current()), "Skip lands on a step that still has something to do (" .. ns.Current().t .. ")")

  -- after jumping back a chapter, old travel/training/note steps are skipped
  state.level = 25
  for _, st in ipairs(ns.steps) do
    if st.chapter.num <= 4 and st.t == "turnin" then for _, q in ipairs(st.q) do state.done[q] = true end end
  end
  ns.questGen = (ns.questGen or 0) + 1
  ns.GotoChapter(1)
  local stops, nonQuest = 0, 0
  local guard = 0
  while ns.Current().chapter.num < 5 and guard < 400 do
    guard = guard + 1
    local cur = ns.Current()
    if not ns.IsFiltered(cur) and not ns.IsStepDone(cur) then
      stops = stops + 1
      if not cur.q then nonQuest = nonQuest + 1 end
    end
    ns.SetIndex(ns.index + 1, true)
  end
  check(nonQuest <= 3, "jumping back to chapter 1 does not stop on old travel/training steps (" .. nonQuest .. ")")
  state.done = {}
  ns.questGen = ns.questGen + 1

  -- a delivery quest (no objectives) counts as ready once you have it
  local realN = C_QuestLog.GetNumQuestObjectives
  C_QuestLog.GetNumQuestObjectives = function() return 0 end
  state.log[777777] = true
  check(ns.IsQuestReady(777777), "a delivery quest in your log is ready to hand in")
  C_QuestLog.GetNumQuestObjectives = realN
  state.log = {}

  -- the guide never clears a map pin you set yourself
  local cleared = false
  C_Map.ClearUserWaypoint = function() cleared = true end
  EarthmothersGuideCharDB.pinSet = true
  EarthmothersGuideCharDB.pinAt = { 1412, 0.40, 0.70 }
  C_Map.GetUserWaypoint = function() return { uiMapID = 1413, position = { x = 0.5, y = 0.5 } } end
  ns.ClearMapPin()
  check(not cleared, "a map pin you placed yourself is left alone")
  EarthmothersGuideCharDB.pinSet = true
  EarthmothersGuideCharDB.pinAt = { 1412, 0.40, 0.70 }
  C_Map.GetUserWaypoint = function() return { uiMapID = 1412, position = { x = 0.40, y = 0.70 } } end
  ns.ClearMapPin()
  check(cleared, "the guide's own pin is cleared")
  C_Map.GetUserWaypoint = nil

  -- level-up is noticed at once (PLAYER_LEVEL_UP carries the new level)
  state.level = 17
  fire("PLAYER_LEVEL_UP", 18)
  check(ns.PlayerLevel() == 18, "level-up is noticed before UnitLevel catches up")
  ns.levelUp = nil
end

------------------------------------------------------------------------------ 1.0.2 route rules
do
  ns.logReady = true; ns.startIndex = nil
  state.log, state.ready, state.done = {}, {}, {}
  -- a pickup that needs ALL of several quests is lost as soon as one of them can't happen
  local st, q
  for _, s in ipairs(ns.steps) do
    if s.preAll then for k, v in pairs(s.preAll) do if #v >= 2 then st, q = s, k break end end end
    if st then break end
  end
  check(st ~= nil, "route has a pickup that needs all of several quests")
  if st then
    local all = st.preAll[q]
    ns.SetIndex(st.index, true)
    for _, p in ipairs(all) do state.done[p] = true end
    check(not ns.PrereqLost(st, q), "all prerequisites done: the pickup stays")
    state.done[all[1]] = nil
    local ai = ns.acceptIndex[all[1]]
    if ai and ai < st.index then
      check(ns.PrereqLost(st, q), "one of all-of prerequisites missed: the pickup is dropped")
    end
    state.done = {}
  end
  -- grey quests are judged one by one: a grey chain start stays only while a quest it unlocks
  -- is still worth doing ("The Ravaged Caravan" must not stay when "The Venture Co." is grey)
  local starter, follow
  for _, s in ipairs(ns.steps) do
    if s.t == "accept" and not s.cls then
      for _, q in ipairs(s.q) do
        local deps = ns.dependents[q]
        if deps and #deps == 1 and not (ns.dependents[deps[1]]) and ns.questLevel[deps[1]]
            and ns.questLevel[q] and ns.questLevel[deps[1]] >= ns.questLevel[q] + 3 then
          starter, follow = q, deps[1]
        end
      end
    end
    if starter then break end
  end
  check(starter ~= nil, "route has a chain start with a higher follow-up")
  if starter then
    state.log, state.done = {}, {}
    ns.Setting("grayLevels")
    -- the starter is grey, the follow-up is not: the starter is kept
    local lvS, lvF = ns.questLevel[starter], ns.questLevel[follow]
    local lvl
    for L = lvS + 1, 60 do if ns.GreyLevel(L) >= lvS and ns.GreyLevel(L) < lvF then lvl = L break end end
    if lvl then
      state.level = lvl
      ns.questGen = (ns.questGen or 0) + 1
      check(ns.QuestWorthDoing(starter), ("grey chain start %d kept while its follow-up %d is not grey (level %d)"):format(starter, follow, lvl))
    end
    -- both grey: the starter goes too
    for L = lvF + 1, 60 do if ns.GreyLevel(L) >= lvF then lvl = L break end end
    state.level = lvl
    ns.questGen = (ns.questGen or 0) + 1
    check(not ns.QuestWorthDoing(starter), ("grey chain start %d dropped once its follow-up %d is grey too (level %d)"):format(starter, follow, lvl))
    local st = ns.steps[ns.acceptIndex[starter]]
    check(ns.QuestHidden(st, starter), "a grey quest leading to nothing worth doing is left out of its step")
    state.level = 10
    ns.questGen = (ns.questGen or 0) + 1
  end
  -- escort and event quests have a "do" step between pickup and hand-in (Protect Kaya, Escorting Erland)
  for _, q in ipairs({ 6523, 435 }) do
    local has = false
    for _, s in ipairs(ns.steps) do
      if s.t == "complete" and s.q then for _, x in ipairs(s.q) do if x == q then has = true end end end
    end
    check(has, "escort quest " .. q .. " has a step that tells you to do it")
  end
  -- training steps follow your level: even levels, never going down
  local last = 0
  for _, s in ipairs(ns.steps) do
    if s.t == "train" then
      check(s.lvl % 2 == 0 and s.lvl > last, ("training step at level %d after %d"):format(s.lvl, last))
      last = s.lvl
    end
  end
  -- travel inside a dungeon block carries the dungeon's name, except the first trip of the block
  -- (the way in): that one stays visible even when you have outlevelled the dungeon
  local block, trips, untagged
  local function closeBlock()
    if block then check(untagged == nil or untagged == 1, ("only the way into %s is untagged"):format(block)) end
  end
  for i, s in ipairs(ns.steps) do
    if s.t == "note" and s.d then closeBlock(); block, trips, untagged = s.d, 0, nil
    elseif block and s.t == "zone" then
      trips = trips + 1
      if s.d ~= block then
        -- an untagged trip that leaves the block ends it; otherwise it must be the way in
        local j = i + 1
        while ns.steps[j] and ns.steps[j].t == "zone" do j = j + 1 end
        if ns.steps[j] and ns.steps[j].d == block then
          check(untagged == nil and trips == 1, ("travel step %d inside %s is tagged (%s)"):format(i, block, s.text))
          untagged = trips
        else closeBlock(); block = nil end
      end
    elseif block and not s.d and s.t ~= "zone" then closeBlock(); block = nil end
  end
  closeBlock()
end

------------------------------------------------------------------------------ batch text
-- "Do these 6 quests" counts only the quests you actually have to do
do
  local bs
  for _, st in ipairs(ns.steps) do
    if st.t == "complete" and st.q and #st.q >= 4 and (st.text or ""):match("^Do these") then bs = st break end
  end
  local function rowsFor(list) local r = {} for _, q in ipairs(list) do r[#r + 1] = { q = q } end return r end
  check(ns.StepText(bs, rowsFor(bs.q)) == bs.text, "all quests of the batch: the text is unchanged")
  check(ns.StepText(bs, rowsFor({ bs.q[1], bs.q[2] })):match("^Do these 2 quests"), "two of them in your log: \"Do these 2 quests\"")
  check(ns.StepText(bs, rowsFor({ bs.q[1] })):match("^Do this quest"), "one of them: \"Do this quest\"")
  local r = rowsFor({ bs.q[1], bs.q[2], bs.q[3] }); r[3].skipped = true
  check(ns.StepText(bs, r):match("^Do these 2 quests"), "a skipped quest is not counted")
end

------------------------------------------------------------------------------ side trips
-- Chen's Empty Keg (819) looted after the route passed its steps: picking it up sends the
-- guide back to it, then (with its follow-ups) back to where you were.
do
  ns.logReady = true; ns.startIndex = nil; ns.manualMove = false
  state.log, state.ready, state.done, state.level = {}, {}, {}, 16
  ns.EndSideTrip()
  local Q = 819
  local ti = ns.turninIndex[Q]
  check(ti ~= nil and ns.acceptIndex[Q] ~= nil, "Chen's Empty Keg is in the route")
  -- stand a few steps past its hand-in, in the same chapter
  local here = ti
  for i = ti + 1, #ns.steps do
    if ns.steps[i].chapter ~= ns.steps[ti].chapter then break end
    here = i
    if i >= ti + 8 then break end
  end
  -- everything before here is done
  for i = 1, here - 1 do
    local st = ns.steps[i]
    for _, q in ipairs(st.q or {}) do if q ~= Q then state.done[q] = true end end
  end
  ns.SetIndex(here, false)
  check(ns.index == here, "standing past the keg's hand-in")
  state.log[Q] = true
  local target = ns.SideTripTarget(Q)
  check(target ~= nil and target < here, "the keg's next step is behind you")
  fire("QUEST_ACCEPTED", Q)
  check(ns.index == target, ("picking up the keg goes back to it (at %d, want %d)"):format(ns.index, target))
  check(ns.InSideTrip(), "a side trip is on")
  -- finish and hand it in
  state.ready[Q] = true
  fire("QUEST_LOG_UPDATE")
  state.log[Q], state.ready[Q], state.done[Q] = nil, nil, true
  fire("QUEST_TURNED_IN", Q)
  -- either a follow-up of the keg is next, or the guide is back where you were
  local cur = ns.Current()
  local onFollowUp = false
  for _, d in ipairs(ns.dependents[Q] or {}) do if cur.q then for _, x in ipairs(cur.q) do if x == d then onFollowUp = true end end end end
  check(onFollowUp or ns.index >= here, ("after the hand-in: a follow-up or back to your place (at %d, was %d)"):format(ns.index, here))
  -- finish any follow-ups the same way; the guide ends up back at your place
  for _ = 1, 10 do
    cur = ns.Current()
    if ns.index >= here or not cur.q then break end
    for _, q in ipairs(cur.q) do
      if cur.t == "accept" then state.log[q] = true; fire("QUEST_ACCEPTED", q)
      elseif cur.t == "complete" then state.ready[q] = true; fire("QUEST_LOG_UPDATE")
      else state.log[q], state.ready[q], state.done[q] = nil, nil, true; fire("QUEST_TURNED_IN", q) end
    end
  end
  check(ns.index >= here and not ns.InSideTrip(), ("the side trip ends back at your place (at %d, was %d)"):format(ns.index, here))
  -- a quest whose hand-in is still ahead does not start a side trip
  local ahead
  for q, t in pairs(ns.turninIndex) do if t > ns.index + 5 and ns.acceptIndex[q] and ns.acceptIndex[q] < ns.index then ahead = q break end end
  if ahead then
    state.log[ahead] = true
    check(ns.SideTripTarget(ahead) == nil, "a quest the route hands in later is no reason to go back")
    state.log[ahead] = nil
  end
  state.log, state.ready, state.done = {}, {}, {}
  ns.EndSideTrip()
end

------------------------------------------------------------------------------ fresh logins
-- These load the addon again into a new namespace, so the login gate starts from scratch.
do
  local clock, queued = 100, {}
  local realAfter, realGetTime = C_Timer.After, GetTime
  GetTime = function() return clock end
  C_Timer.After = function(_, fn) queued[#queued + 1] = fn end   -- timers wait until we run them
  local function runTimers() local q = queued; queued = {}; for _, fn in ipairs(q) do fn() end end

  local function freshAddon(charDB)
    EarthmothersGuideDB, EarthmothersGuideCharDB = {}, charDB or {}
    local n2 = {}
    for _, f in ipairs(files) do
      local chunk = loadfile(f)
      if chunk then pcall(chunk, "EarthmothersGuide", n2) end
    end
    local fr = n2.eventFrame
    return n2, function(event, arg) fr.scripts.OnEvent(fr, event, arg) end
  end

  -- 1. fresh login: updates from the loading screen do not count, and the log needs two
  --    updates and two seconds after entering the world
  state.log, state.done, state.ready, state.level = {}, {}, {}, 1
  local n2, fire2 = freshAddon()
  fire2("ADDON_LOADED", "EarthmothersGuide")
  fire2("QUEST_LOG_UPDATE"); fire2("QUEST_LOG_UPDATE")
  fire2("PLAYER_ENTERING_WORLD", true)
  check(not n2.logReady, "login: quest log updates before entering the world do not count")
  fire2("QUEST_LOG_UPDATE")
  clock = 100.5
  fire2("QUEST_LOG_UPDATE")
  check(not n2.logReady, "login: two updates within two seconds are not enough")
  clock = 102.5
  fire2("QUEST_LOG_UPDATE")
  check(n2.logReady, "login: the log is trusted after two updates and two seconds")

  -- 2. /reload on a step chosen by hand that only counts as done once the log has loaded:
  --    the guide stays there
  local cIdx
  for i, st in ipairs(n2.steps) do
    if st.t == "complete" and st.q and #st.q == 1 and not st.cls and not st.d then cIdx = i break end
  end
  check(cIdx ~= nil, "found a single-quest complete step")
  clock = 200; queued = {}
  state.level = n2.steps[cIdx].ql or 10
  local n3, fire3 = freshAddon({ manual = true })
  fire3("ADDON_LOADED", "EarthmothersGuide")
  n3.index = cIdx
  fire3("PLAYER_ENTERING_WORLD", false)
  check(n3.manualMove and not n3.logReady, "reload: starts on the chosen step, log not trusted yet")
  fire3("QUEST_LOG_UPDATE")
  runTimers(); runTimers()
  check(n3.logReady, "reload: one update is enough")
  check(n3.index == cIdx, ("reload: a step chosen by hand is kept (at %d, chose %d)"):format(n3.index, cIdx))

  C_Timer.After, GetTime = realAfter, realGetTime
end

print(("%d passed, %d failed, %d steps"):format(passed, failures, count))
os.exit(failures == 0 and 0 or 1)
