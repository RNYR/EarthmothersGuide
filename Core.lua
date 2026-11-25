-- Earthmother's Guide: step engine.
-- Copyright (C) 2026 Vard Ruun. Licensed under GPL-3.0-or-later; see LICENSE and NOTICE.md.
-- Chapters register their steps with ns.AddChapter(). The engine tracks the current step,
-- checks completion against the live quest log, and advances automatically.

local ADDON, ns = ...
ns = ns or {}
_G.EarthmothersGuide = ns

ns.chapters = {}
ns.steps = {}        -- flattened list of all steps, in route order
ns.listeners = {}    -- callbacks fired when the current step or its state changes

local DEFAULTS = { dungeons = true, scale = 1, locked = false, shown = true,
                   waypoints = true, arrow = true, grayLevels = 6,
                   compact = false, showCarried = true, itemButton = true, professions = true }

-- Druid forms and where their quests live, for the catch-up warning when starting mid-route.
ns.FORMS = {
  { name = "Bear Form", spell = 5487, level = 10, chapter = 1 },
  { name = "Aquatic Form", spell = 1066, level = 16, chapter = 3 },
  { name = "Cat Form", spell = 768, level = 20, chapter = 4 },
  { name = "Travel Form", spell = 783, level = 30, chapter = 6 },
  { name = "Dire Bear Form", spell = 9634, level = 40, chapter = 8 },
}

----------------------------------------------------------------------------------------------
-- Client API wrappers (pcall-guarded so a missing function never breaks the addon)
----------------------------------------------------------------------------------------------
local function call(fn, ...)
  if not fn then return nil end
  local ok, a, b, c = pcall(fn, ...)
  if ok then return a, b, c end
  return nil
end

local QL = C_QuestLog or {}

function ns.IsQuestTurnedIn(id)
  if QL.IsQuestFlaggedCompleted then return call(QL.IsQuestFlaggedCompleted, id) == true end
  if IsQuestFlaggedCompleted then return call(IsQuestFlaggedCompleted, id) == true end
  return false
end

function ns.IsQuestInLog(id)
  local idx = call(QL.GetLogIndexForQuestID, id)
  return idx ~= nil and idx > 0
end

function ns.IsQuestReady(id)
  return ns.IsQuestInLog(id) and call(QL.IsComplete, id) == true
end

function ns.GetObjectives(id)
  local list = call(QL.GetQuestObjectives, id)
  return type(list) == "table" and list or {}
end

function ns.PlayerLevel()
  return (UnitLevel and UnitLevel("player")) or 1
end

function ns.KnowsSpell(spellID)
  if IsPlayerSpell then return call(IsPlayerSpell, spellID) == true end
  if IsSpellKnown then return call(IsSpellKnown, spellID) == true end
  return false
end

-- True when the client hands out a hidden ("secret") value we must not do maths on.
function ns.IsSecret(v)
  return issecretvalue ~= nil and v ~= nil and issecretvalue(v) == true
end

function ns.PlayerMapPosition()
  if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local mapID = call(C_Map.GetBestMapForUnit, "player")
  if not mapID or ns.IsSecret(mapID) then return nil end
  local pos = call(C_Map.GetPlayerMapPosition, mapID, "player")
  if not pos then return mapID end
  local x, y = pos.x, pos.y
  if pos.GetXY then x, y = pos:GetXY() end
  if ns.IsSecret(x) or ns.IsSecret(y) then return mapID end
  return mapID, x, y
end

----------------------------------------------------------------------------------------------
-- Chapters and steps
----------------------------------------------------------------------------------------------
-- step fields:
--   t      "accept" | "complete" | "turnin" | "goto" | "level" | "spell" | "zone" | "note" | "train"
--   q      { questID, ... }  for accept / complete / turnin
--   qn     { [questID] = "Quest name" }
--   text   instruction text;  tip  optional druid tip
--   npc    NPC or object name; m uiMapID; x, y map coordinates in 0-100; zone display name
--   lvl    level for "level";  spell spellID for "spell";  zoneName / m for "zone"
--   d      dungeon name (marks the step as a dungeon step);  dmin, dmax  dungeon level range
function ns.AddChapter(num, chapter)
  chapter.num = num
  ns.chapters[num] = chapter
end

function ns.Build()
  for k in pairs(ns.steps) do ns.steps[k] = nil end
  local nums = {}
  for num in pairs(ns.chapters) do nums[#nums + 1] = num end
  table.sort(nums)
  for _, num in ipairs(nums) do
    local ch = ns.chapters[num]
    for i, step in ipairs(ch.steps) do
      step.chapter = ch
      step.chapterIndex = i
      ns.steps[#ns.steps + 1] = step
      step.index = #ns.steps
    end
  end
  -- fingerprint of this guide build: a saved position is only trusted for the same build
  local h = #ns.steps
  for i, step in ipairs(ns.steps) do
    h = (h * 31 + i * ((step.q and step.q[1]) or #(step.t or ""))) % 2147483647
  end
  ns.guideHash = tostring(h)
  -- quest ID -> index of the step where the guide picks it up / hands it in
  ns.acceptIndex, ns.turninIndex = {}, {}
  for i, step in ipairs(ns.steps) do
    if step.t == "accept" and step.q then
      for _, q in ipairs(step.q) do ns.acceptIndex[q] = ns.acceptIndex[q] or i end
    elseif step.t == "turnin" and step.q then
      for _, q in ipairs(step.q) do ns.turninIndex[q] = ns.turninIndex[q] or i end
    end
  end
end

local function db() return EarthmothersGuideDB end
local function cdb() return EarthmothersGuideCharDB end

function ns.Setting(key)
  local s = db()
  if s and s[key] ~= nil then return s[key] end
  return DEFAULTS[key]
end

function ns.SetSetting(key, value)
  EarthmothersGuideDB = EarthmothersGuideDB or {}
  EarthmothersGuideDB[key] = value
  ns.Refresh()
end

-- A step is filtered out (skipped automatically) when it is a dungeon step and dungeon steps are
-- off, or the player has outlevelled that dungeon.
--
-- Quest steps are also filtered when none of their quests are in your log and either
--   * the quests are grey for you (quest level <= your level - grayLevels), or
--   * the guide would have picked them up before the point where you started using it.
-- Quests already in your log are never filtered, so nothing you are carrying gets lost.
local QUEST_STEP = { accept = true, complete = true, turnin = true }

local function anyInLog(step)
  for _, q in ipairs(step.q or {}) do
    if ns.IsQuestInLog(q) then return true end
  end
  return false
end

local function skippedBeforeStart(step)
  local start = ns.startIndex
  if not start or step.t == "accept" then return false end
  for _, q in ipairs(step.q or {}) do
    local ai = ns.acceptIndex and ns.acceptIndex[q]
    if not ai or ai >= start or ns.IsQuestTurnedIn(q) then return false end
  end
  return true
end

function ns.IsFiltered(step)
  local level = ns.PlayerLevel()
  if step.d and not anyInLog(step) then
    -- dungeon steps for quests you still carry stay, even when dungeons are off or outlevelled
    if not ns.Setting("dungeons") then return true end
    if step.dmax and level > step.dmax then
      return true
    end
  end
  if QUEST_STEP[step.t] and step.q and #ns.StepQuests(step) == 0 then return true end
  if QUEST_STEP[step.t] and step.q and not step.cls and not anyInLog(step) then
    local gray = ns.Setting("grayLevels")
    if gray and gray > 0 and step.ql and step.ql > 0 and step.ql <= level - gray then return true end
    if skippedBeforeStart(step) then return true end
  end
  return false
end

-- A profession quest is left out of the route when "Include profession quests" is off,
-- unless you already have it in your log.
function ns.QuestHidden(step, q)
  if not (step.prof and step.prof[q]) or ns.Setting("professions") then return false end
  return not ns.IsQuestInLog(q)
end

-- Quests of a step that are part of the route for you right now.
function ns.StepQuests(step)
  local out = {}
  for _, q in ipairs(step.q or {}) do
    if not ns.QuestHidden(step, q) then out[#out + 1] = q end
  end
  return out
end

local function allQuests(step, pred)
  if not step.q or #step.q == 0 then return false end
  local any = false
  for _, id in ipairs(step.q) do
    if not ns.QuestHidden(step, id) then
      any = true
      if not pred(id) then return false end
    end
  end
  return any
end

-- Returns true when the game state shows the step is finished.
-- "Verifiable" steps can be checked from game state; manual ones (note, train) never auto-complete.
function ns.IsStepDone(step)
  local t = step.t
  if t == "accept" then
    return allQuests(step, function(id) return ns.IsQuestInLog(id) or ns.IsQuestTurnedIn(id) end)
  elseif t == "complete" then
    -- A batch is done when every quest in it is finished or handed in. Quests you never picked
    -- up (skipped, or grey) do not hold it up - once the quest log has loaded.
    return allQuests(step, function(id)
      if ns.IsQuestTurnedIn(id) or ns.IsQuestReady(id) then return true end
      return ns.logReady and not ns.IsQuestInLog(id)
    end)
  elseif t == "turnin" then
    -- handed in, or (once the log has loaded) a quest you never took or abandoned, whose
    -- pickup step is already behind you
    return allQuests(step, function(id)
      if ns.IsQuestTurnedIn(id) then return true end
      local ai = ns.acceptIndex and ns.acceptIndex[id]
      return ns.logReady and not ns.IsQuestInLog(id) and ai ~= nil and ai < (step.index or 0)
        and ai < (ns.index or 1)
    end)
  elseif t == "level" then
    return ns.PlayerLevel() >= (step.lvl or 1)
  elseif t == "spell" then
    return step.spell ~= nil and ns.KnowsSpell(step.spell)
  elseif t == "zone" then
    local mapID = ns.PlayerMapPosition()
    if step.m and mapID == step.m then return true end
    local zt = GetRealZoneText and GetRealZoneText()
    return step.zoneName ~= nil and zt == step.zoneName
  elseif t == "bind" then
    -- done once the hearthstone is set at that inn (names compared loosely: "The Crossroads")
    if not (GetBindLocation and step.bind) then return false end
    local ok, here = pcall(GetBindLocation)
    local function norm(x) return (x or ""):lower():gsub("^the ", ""):gsub("[^%a]", "") end
    return ok and here ~= nil and norm(here) == norm(step.bind)
  elseif t == "goto" then
    if not (step.m and step.x) then return false end
    local mapID, x, y = ns.PlayerMapPosition()
    if mapID ~= step.m or not x then return false end
    local dx, dy = x * 100 - step.x, y * 100 - step.y
    return (dx * dx + dy * dy) <= (step.radius or 1.5) ^ 2
  end
  return false
end

local VERIFIABLE = { accept = true, complete = true, turnin = true, spell = true }
ns.VERIFIABLE = VERIFIABLE

-- A finished step only shows how far you got if you actually did something there: a batch
-- whose quests are simply absent from your log proves nothing.
function ns.ProvesProgress(step)
  if step.t == "accept" then
    for _, q in ipairs(step.q or {}) do
      if ns.IsQuestTurnedIn(q) or ns.IsQuestInLog(q) then return true end
    end
    return false
  end
  if step.t == "complete" or step.t == "turnin" then
    for _, q in ipairs(step.q or {}) do
      if ns.IsQuestTurnedIn(q) or (step.t == "complete" and ns.IsQuestReady(q)) then return true end
    end
    return false
  end
  return false   -- spells, zones and levels say nothing about which quests you did
end

-- Where to resume when there is no saved position (or SavedVariables did not load):
-- just after the last step the game state proves is done.
-- Last step of the latest chapter your level fits (a chapter starting at most one level above
-- you). Quest history never moves you past it: a quest done far ahead of the route says
-- nothing about where the rest of your route stands.
function ns.LevelCapIndex()
  local level, cap = ns.PlayerLevel(), nil
  for num = 1, 99 do
    local ch = ns.chapters[num]
    if not ch then break end
    if ch.levels[1] <= level + 1 and ch.steps[#ch.steps] then cap = ch.steps[#ch.steps].index end
  end
  return cap or #ns.steps
end

-- Where your quest history says you are: just after the last step it proves, within
-- [from, to] (default: the whole route up to the level cap).
function ns.FindResumeIndex(from, to)
  from = from or 1
  to = math.min(to or #ns.steps, ns.LevelCapIndex())
  local last = from - 1
  for i = from, to do
    local step = ns.steps[i]
    if VERIFIABLE[step.t] and ns.IsStepDone(step) and ns.ProvesProgress(step) then last = i end
  end
  return math.min(math.max(last + 1, from), math.max(#ns.steps, 1))
end

-- First step of the chapter that fits the character's level (earliest chapter whose range holds it).
function ns.LevelStartIndex()
  local level = ns.PlayerLevel()
  local best
  for num = 1, 99 do
    local ch = ns.chapters[num]
    if not ch then break end
    if level >= ch.levels[1] and ch.steps[1] then
      best = ch.steps[1].index
      if level <= ch.levels[2] then break end
    end
  end
  return best or 1
end

-- Druid forms the character should have by now but does not know.
function ns.MissingForms()
  local missing, level = {}, ns.PlayerLevel()
  for _, f in ipairs(ns.FORMS) do
    if level >= f.level and not ns.KnowsSpell(f.spell) then missing[#missing + 1] = f end
  end
  return missing
end

-- Work out where this character is: the later of "just after the last quest step you have done"
-- and "start of the chapter for your level". Steps before that point whose quests you never
-- picked up are skipped; quests you still carry stay in the route.
function ns.InitPosition(announce)
  local byQuests = ns.FindResumeIndex()
  local byLevel = ns.LevelStartIndex()
  local start = math.max(byQuests, byLevel)
  -- Step back to the earliest unfinished quest you are carrying in the same chapter, so a quest
  -- already in your log (e.g. a class quest you started) is not jumped over.
  local first = ns.steps[start] and ns.steps[start].chapter.steps[1].index or start
  for i = first, start - 1 do
    local st = ns.steps[i]
    if (st.t == "complete" or st.t == "turnin") and st.q and not ns.IsStepDone(st) then
      local carrying = false
      for _, q in ipairs(st.q) do
        if ns.IsQuestInLog(q) then carrying = true break end
      end
      if carrying then start = i break end
    end
  end
  ns.startIndex = start
  EarthmothersGuideCharDB = EarthmothersGuideCharDB or {}
  EarthmothersGuideCharDB.startIndex = start
  ns.manualMove = false
  ns.SetIndex(start)
  ns.Advance()
  if announce and print then
    local cur = ns.Current()
    print(("|cff8fbf5aEarthmother's Guide|r: level %d - starting at chapter %d, step %d/%d."):format(
      ns.PlayerLevel(), cur and cur.chapter.num or 0, ns.index or 0, #ns.steps))
    for _, f in ipairs(ns.MissingForms()) do
      print(("|cff8fbf5aEarthmother's Guide|r: you have not learned %s yet - its quest is in chapter %d (|cffd9b77a/emg chapter %d|r)."):format(
        f.name, f.chapter, f.chapter))
    end
  end
end

-- Your standing with a faction: 1 Hated, 2 Hostile, 3 Unfriendly, 4 Neutral ... 8 Exalted.
function ns.FactionStanding(factionID)
  if C_Reputation and C_Reputation.GetFactionDataByID then
    local ok, data = pcall(C_Reputation.GetFactionDataByID, factionID)
    if ok and type(data) == "table" and data.reaction then return data.reaction end
  end
  if GetFactionInfoByID then
    local ok, _, _, standing = pcall(GetFactionInfoByID, factionID)
    if ok and standing then return standing end
  end
  return nil
end

-- The tip to show for a step: a reputation-gated tip replaces the normal one once you have
-- the standing (e.g. the Timbermaw tunnel shortcut once Timbermaw Hold is Unfriendly).
function ns.StepTip(step)
  local r = step.tipRep
  if r then
    local standing = ns.FactionStanding(r.faction)
    if standing and standing >= r.standing then return r.text end
  end
  return step.tip
end

-- Steps the player continues by hand (clicking the panel).
function ns.IsManual(step)
  return step ~= nil and (step.t == "note" or step.t == "train" or step.t == "bind")
end

-- Quests you carry from this chapter that are not part of the current step and not finished:
-- shown pinned under the step so nothing in your log is forgotten. No limit.
function ns.Carrying()
  local out, seen = {}, {}
  local cur = ns.Current()
  if not cur then return out end
  for _, q in ipairs(cur.q or {}) do seen[q] = true end
  local last = cur.chapter.steps[#cur.chapter.steps].index
  for i = 1, last do
    local st = ns.steps[i]
    if (st.t == "complete") and st.q and not ns.IsFiltered(st) then
      for _, q in ipairs(st.q) do
        if not seen[q] and ns.IsQuestInLog(q) and not ns.IsQuestReady(q) then
          seen[q] = true
          out[#out + 1] = { id = q, name = (st.qn and st.qn[q]) or ("Quest " .. q), step = st }
        end
      end
    end
  end
  return out
end
ns.AlsoHere = ns.Carrying

-- Finished quests in your log waiting to be handed in (other than the current step's), with
-- who takes them and where, from the guide's turn-in steps. Nothing ready is ever invisible.
function ns.ReadyToHandIn()
  local out, seen = {}, {}
  local cur = ns.Current()
  for _, q in ipairs(cur and cur.q or {}) do seen[q] = true end
  local ids = {}
  local QLx = C_QuestLog or {}
  local n = QLx.GetNumQuestLogEntries and select(1, QLx.GetNumQuestLogEntries())
  if n and QLx.GetInfo then
    for i = 1, n do
      local ok, info = pcall(QLx.GetInfo, i)
      if ok and info and not info.isHeader and info.questID then ids[#ids + 1] = info.questID end
    end
  else
    for q in pairs(ns.turninIndex or {}) do ids[#ids + 1] = q end
  end
  for _, q in ipairs(ids) do
    if not seen[q] and ns.IsQuestReady(q) then
      seen[q] = true
      local st = ns.turninIndex and ns.turninIndex[q] and ns.steps[ns.turninIndex[q]]
      local title = st and st.qn and st.qn[q]
      if not title and QLx.GetTitleForQuestID then
        local ok, t = pcall(QLx.GetTitleForQuestID, q)
        if ok then title = t end
      end
      title = title or ("Quest " .. q)
      out[#out + 1] = { id = q, name = title, npc = st and st.npc, zone = st and st.zone, step = st }
    end
  end
  table.sort(out, function(a, b) return (a.step and a.step.index or 1e9) < (b.step and b.step.index or 1e9) end)
  return out
end

-- On a pickup step: the quests of the batch that follows, so you can see what you are about
-- to do. Only quests not in your log yet.
function ns.ComingUp()
  local out = {}
  local cur = ns.Current()
  if not cur or cur.t ~= "accept" then return out end
  local i = (ns.index or 1) + 1
  while ns.steps[i] and ns.steps[i].chapter == cur.chapter and ns.steps[i].t == "accept" do i = i + 1 end
  local st = ns.steps[i]
  if st and st.chapter == cur.chapter and st.t == "complete" and st.q then
    for _, q in ipairs(st.q) do
      if not ns.IsQuestInLog(q) and not ns.IsQuestTurnedIn(q) and not ns.QuestHidden(st, q) then
        out[#out + 1] = { id = q, name = (st.qn and st.qn[q]) or ("Quest " .. q) }
      end
    end
  end
  return out
end

function ns.Current()
  return ns.steps[ns.index or 1]
end

function ns.SetIndex(i, manual)
  if #ns.steps == 0 then return end
  i = math.max(1, math.min(i, #ns.steps))
  ns.index = i
  EarthmothersGuideCharDB = EarthmothersGuideCharDB or {}
  EarthmothersGuideCharDB.index = i
  EarthmothersGuideCharDB.guideHash = ns.guideHash
  ns.manualMove = manual
  EarthmothersGuideCharDB.manual = manual and true or nil
  -- remember whether the step was already done when you moved onto it by hand; if it becomes
  -- done later, that is progress and the guide moves on again
  ns.manualStepDone = manual and ns.IsStepDone(ns.steps[i]) or false
  ns.Fire()
end

-- Moves forward past finished or filtered steps. Never stops on a filtered step; stops on
-- manual steps (note/train) so the player can read them.
function ns.Advance()
  local i = ns.index or 1
  local moved = false
  while i <= #ns.steps do
    local step = ns.steps[i]
    if ns.IsFiltered(step) or ns.IsStepDone(step) then
      if i == #ns.steps then break end
      i = i + 1
      moved = true
    else
      break
    end
  end
  if moved then ns.SetIndex(i) else ns.Fire() end
end

function ns.Next()
  if (ns.index or 1) >= #ns.steps then return end   -- the last step has nothing after it
  local fromManual = ns.IsManual(ns.Current())
  local i = (ns.index or 1) + 1
  while i < #ns.steps and ns.IsFiltered(ns.steps[i]) do i = i + 1 end
  if fromManual then
    -- continuing a note or training step is normal progress, not a manual jump: the guide
    -- keeps advancing on its own (and skips steps that are already finished)
    ns.SetIndex(i, false)
    ns.Advance()
  else
    ns.SetIndex(i, true)
  end
end

function ns.Prev()
  local i = (ns.index or 1) - 1
  while i > 1 and ns.IsFiltered(ns.steps[i]) do i = i - 1 end
  ns.SetIndex(i, true)
end

function ns.GotoChapter(num)
  local ch = ns.chapters[num]
  if ch and ch.steps[1] then ns.SetIndex(ch.steps[1].index, true) end
end

function ns.OnChange(fn) ns.listeners[#ns.listeners + 1] = fn end

function ns.Fire()
  for _, fn in ipairs(ns.listeners) do pcall(fn, ns.Current()) end
end

function ns.Refresh()
  -- After a manual move, do not jump forward again until the player acts in the game.
  if ns.manualMove then ns.Fire() return end
  ns.Advance()
end

----------------------------------------------------------------------------------------------
-- Waypoints: the built-in arrow (Arrow.lua) plus the Blizzard map pin.
----------------------------------------------------------------------------------------------
function ns.SetWaypoint(step)
  if not step or not ((step.m and step.x) or step.pts) then
    if ns.ClearArrow then ns.ClearArrow() end
    ns.ClearMapPin()
    return false
  end
  local shown = ns.SetArrow and ns.SetArrow(step) or false
  if not ns.Setting("waypoints") or not (step.m and step.x) then return shown end
  return ns.SetMapPin(step.m, step.x, step.y) or shown
end

-- Remove the Blizzard map pin the guide set (if any).
function ns.ClearMapPin()
  -- also clears a pin the guide left in a previous session (remembered per character)
  local db = EarthmothersGuideCharDB
  if (ns.pinSet or (db and db.pinSet)) and C_Map and C_Map.ClearUserWaypoint then call(C_Map.ClearUserWaypoint) end
  ns.pinSet = false
  if db then db.pinSet = nil end
end

-- Blizzard map pin (user waypoint) at map coordinates 0-100.
function ns.SetMapPin(m, x, y)
  if not ns.Setting("waypoints") or not (m and x and y) then ns.ClearMapPin() return false end
  if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
    if C_Map.CanSetUserWaypointOnMap and not call(C_Map.CanSetUserWaypointOnMap, m) then return false end
    local point = call(UiMapPoint.CreateFromCoordinates, m, x / 100, y / 100)
    if point then
      call(C_Map.SetUserWaypoint, point)
      ns.pinSet = true
      EarthmothersGuideCharDB = EarthmothersGuideCharDB or {}
      EarthmothersGuideCharDB.pinSet = true
      -- don't take super-tracking away from a quest you chose to track yourself
      local tracked = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and call(C_SuperTrack.GetSuperTrackedQuestID)
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint and not (tracked and tracked ~= 0) then
        call(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
      end
      return true
    end
  end
  return false
end

----------------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------------
local frame = CreateFrame and CreateFrame("Frame") or nil
ns.eventFrame = frame

-- Events that mean you made progress; only these end a manual move ("Back one step",
-- clicking a step in the route browser). Frequent events (quest log updates, subzones) only
-- refresh the panel.
local PROGRESS = {
  QUEST_ACCEPTED = true, QUEST_TURNED_IN = true, QUEST_REMOVED = true, PLAYER_LEVEL_UP = true,
  HEARTHSTONE_BOUND = true, LEARNED_SPELL_IN_TAB = true, LEARNED_SPELL_IN_SKILL_LINE = true,
  ZONE_CHANGED_NEW_AREA = true,
}
local pending, clearManual = false, false
local function schedule(event)
  if event and PROGRESS[event] then clearManual = true end
  if pending then return end
  pending = true
  local run = function()
    pending = false
    if clearManual then ns.manualMove = false end
    clearManual = false
    -- the step you moved to by hand has just been finished: that is progress too
    local cur = ns.Current()
    if ns.manualMove and cur and not ns.manualStepDone and ns.IsStepDone(cur) then ns.manualMove = false end
    ns.Refresh()
  end
  if C_Timer and C_Timer.After then C_Timer.After(0.3, run) else run() end
end
ns.schedule = schedule

local events = {
  "PLAYER_ENTERING_WORLD", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_LOG_UPDATE",
  "UNIT_QUEST_LOG_CHANGED", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED",
  "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE", "SPELLS_CHANGED", "HEARTHSTONE_BOUND",
}

-- The quest log is only trusted once it has really loaded: the first update after login can
-- still hold stale data, so wait for a second update at least two seconds after entering the
-- world (or ten seconds at most). Until then, a quest missing from the log never counts as done.
local enteredAt, logUpdates = nil, 0
local function now() return GetTime and GetTime() or 0 end
local function noteLogUpdate()
  logUpdates = logUpdates + 1
  if enteredAt and logUpdates >= 2 and now() - enteredAt >= 2 then ns.logReady = true end
end
local function whenLogReady(fn, tries)
  tries = tries or 0
  if ns.logReady or not (C_Timer and C_Timer.After) then ns.logReady = true; fn(); return end
  if tries >= 10 then ns.logReady = true; fn(); return end
  C_Timer.After(1, function() whenLogReady(fn, tries + 1) end)
end
ns.WhenLogReady = whenLogReady

function ns.OnEvent(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    EarthmothersGuideDB = EarthmothersGuideDB or {}
    EarthmothersGuideCharDB = EarthmothersGuideCharDB or {}
    ns.Build()
    local saved = EarthmothersGuideCharDB.index
    -- A saved position only means something for the same guide build; after an update that
    -- changed the steps, work the position out again from quests and level.
    if EarthmothersGuideCharDB.guideHash ~= ns.guideHash then saved = nil end
    ns.index = (saved and ns.steps[saved]) and saved or nil
    ns.startIndex = EarthmothersGuideCharDB.startIndex
    return
  end
  if event == "PLAYER_ENTERING_WORLD" and not ns.started then
    ns.started = true
    enteredAt = now()
    if ns.index then
      local manualSave = EarthmothersGuideCharDB.manual
      ns.SetIndex(ns.index, manualSave)
      -- a stale save (crash, no SavedVariables write) must not hold you back: once the quest
      -- log has loaded, move forward if your quests prove you are further along - but only
      -- within this chapter and the next, and never over a place you chose by hand
      whenLogReady(function()
        if manualSave then return end
        local cur = ns.Current()
        local nextCh = cur and (ns.chapters[cur.chapter.num + 1] or cur.chapter)
        local r = ns.FindResumeIndex(cur and cur.chapter.steps[1].index or 1, nextCh and nextCh.steps[#nextCh.steps].index)
        if r > (ns.index or 1) then ns.SetIndex(r); ns.Advance() end
      end)
    else
      -- First run on this character (or saved data was lost): read quest history and level
      -- once the quest log has loaded.
      ns.index = 1
      whenLogReady(function() ns.InitPosition(true) end)
      return
    end
  end
  if event == "UNIT_QUEST_LOG_CHANGED" and arg1 ~= "player" then return end
  if event == "QUEST_LOG_UPDATE" then noteLogUpdate() end
  schedule(event)
end

if frame then
  frame:RegisterEvent("ADDON_LOADED")
  for _, e in ipairs(events) do pcall(frame.RegisterEvent, frame, e) end
  frame:SetScript("OnEvent", ns.OnEvent)
  -- Poll "goto" steps for arrival.
  local acc = 0
  frame:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.5 then return end
    acc = 0
    local step = ns.Current()
    if step and step.t == "goto" and ns.started and not ns.manualMove and ns.IsStepDone(step) then
      ns.manualMove = false
      ns.Advance()
    end
  end)
end
