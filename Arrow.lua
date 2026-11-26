-- Earthmother's Guide: built-in waypoint arrow (no TomTom needed).
-- Copyright (C) 2026 Vard Ruun. Licensed under GPL-3.0-only; see LICENSE and NOTICE.md.
-- Works out the direction and distance from the player to the current step's coordinates;
-- the guide panel draws it as an arrowhead. Works across zones on the same continent.

local ADDON, ns = ...
ns = ns or _G.EarthmothersGuide

local TEXTURE = "Interface\\AddOns\\EarthmothersGuide\\Media\\Arrow"
local ARRIVE_YARDS = 8
local TWO_PI = math.pi * 2

local target         -- { m, x, y, title, step }

----------------------------------------------------------------------------------------------
-- Math (pure, tested offline)
----------------------------------------------------------------------------------------------
-- WoW world coordinates: x grows north, y grows west. Facing is radians counter-clockwise from
-- north. Returns distance in yards and the angle to draw the arrow at (0 = straight ahead,
-- counter-clockwise positive), or nil when the angle is unknown.
function ns.ArrowMath(px, py, tx, ty, facing)
  local dNorth, dWest = tx - px, ty - py
  local dist = math.sqrt(dNorth * dNorth + dWest * dWest)
  if not facing then return dist, nil end
  local bearing = math.atan2(dWest, dNorth)        -- counter-clockwise from north
  local rel = (bearing - facing) % TWO_PI          -- 0..2pi
  return dist, rel
end

-- Green when ahead, yellow to the side, red behind.
function ns.ArrowColor(rel)
  if not rel then return 0.7, 0.7, 0.7 end
  local off = rel > math.pi and (TWO_PI - rel) or rel   -- 0 (ahead) .. pi (behind)
  local t = off / math.pi
  if t < 0.5 then
    local k = t / 0.5
    return 0.56 + 0.44 * k, 0.75 + 0.15 * k, 0.35 - 0.15 * k   -- plains green -> wheat yellow
  end
  local k = (t - 0.5) / 0.5
  return 1.0, 0.9 - 0.55 * k, 0.2 - 0.05 * k                   -- wheat yellow -> clay red
end

----------------------------------------------------------------------------------------------
-- Positions
----------------------------------------------------------------------------------------------
-- Map position -> world position. Uses each map's world rectangle, measured once per map from
-- two corners, so the 20-times-a-second arrow update does plain maths without creating tables.
local rects = {}
local function mapRect(mapID)
  local r = rects[mapID]
  if r then return r end
  -- a failed lookup (e.g. while loading) is retried after a few seconds, not cached for good
  if r == false and (GetTime and GetTime() or 0) < (rects["retry" .. mapID] or 0) then return nil end
  r = false
  if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
    -- measured from the top-left corner and the centre: the far corner (1,1) is translated
    -- inaccurately on some maps
    local ok1, c1, p1 = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0, 0))
    local ok2, c2, p2 = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0.5, 0.5))
    if ok1 and ok2 and p1 and p2 and c1 == c2 then
      r = { c = c1, x0 = p1.x, y0 = p1.y, dx = 2 * (p2.x - p1.x), dy = 2 * (p2.y - p1.y) }
    end
  end
  rects[mapID] = r
  if not r then rects["retry" .. mapID] = (GetTime and GetTime() or 0) + 5 end
  return r or nil
end

local function worldPos(mapID, x, y)
  local r = mapRect(mapID)
  if not r then return nil end
  -- map x runs west->east, map y north->south; both map linearly onto world coordinates
  return r.c, r.x0 + r.dx * y, r.y0 + r.dy * x
end
ns.WorldPos = worldPos

local function playerWorldPos()
  local mapID, x, y = ns.PlayerMapPosition()
  if not mapID or not x then return nil end
  return worldPos(mapID, x, y)
end

local function facing()
  if not GetPlayerFacing then return nil end
  local ok, f = pcall(GetPlayerFacing)
  if ok and type(f) == "number" and not ns.IsSecret(f) then return f end
  return nil
end

local function formatDistance(yards)
  if yards >= 1000 then return ("%.1f km"):format(yards * 0.9144 / 1000) end
  return ("%d yd"):format(math.floor(yards + 0.5))
end

----------------------------------------------------------------------------------------------
-- Target and reading (drawn by the guide panel in UI.lua)
----------------------------------------------------------------------------------------------
ns.ARROW_TEXTURE = TEXTURE

-- What the panel should draw right now:
--   state "point": rel (radians), r, g, b, text (distance)
--   state "here":  you are at the target
--   state "far":   target on another continent / position unknown; text names the zone
--   nil            no target
-- Candidate points for the current target. A batch step has one point per quest; only quests
-- in your log that are not finished yet count. Falls back to the step's own point.
-- Candidate points for the current target. A batch step has one point per quest; only quests
-- in your log that are not finished yet count. Falls back to the step's own point.
-- Cached until the guide state changes (quest accepted/finished), not rebuilt every frame.
local cache, cacheValid = {}, false
local function candidates()
  if cacheValid then return cache end
  for k in pairs(cache) do cache[k] = nil end
  local st = target.step
  if st and st.t == "complete" and st.pts then
    for _, q in ipairs(st.q or {}) do
      local p = st.pts[q]
      if p and ns.IsQuestInLog(q) and not ns.IsQuestReady(q) then
        cache[#cache + 1] = { m = p.m, x = p.x, y = p.y, q = q }
      end
    end
  end
  if #cache == 0 and target.m then cache[1] = { m = target.m, x = target.x, y = target.y } end
  cacheValid = true
  return cache
end
ns.OnChange(function() cacheValid = false end)

-- Picks the nearest candidate to the player (same continent). Returns point, distance.
function ns.NearestPoint(points, pc, px, py)
  local best, bestDist
  for _, p in ipairs(points) do
    local tc, tx, ty = worldPos(p.m, p.x / 100, p.y / 100)
    if tc and tc == pc then
      local d = math.sqrt((tx - px) ^ 2 + (ty - py) ^ 2)
      if not bestDist or d < bestDist then best, bestDist = p, d end
    end
  end
  return best, bestDist
end

-- Only switch to another quest when it is clearly closer, so the arrow and map pin do not
-- flip back and forth between two objectives at about the same distance.
local SWITCH_YARDS = 25
local current        -- the point the arrow is on
local reading = {}   -- reused every frame

local function distanceTo(p, pc, px, py)
  local tc, tx, ty = worldPos(p.m, p.x / 100, p.y / 100)
  if not tc or tc ~= pc then return nil end
  return math.sqrt((tx - px) ^ 2 + (ty - py) ^ 2)
end

function ns.ArrowReading()
  if not target then return nil end
  local points = candidates()
  if #points == 0 then return nil end
  local pc, px, py = playerWorldPos()
  local best, bestDist = nil, nil
  if pc then best, bestDist = ns.NearestPoint(points, pc, px, py) end
  if best and current and current.q ~= best.q then
    -- the candidate list is rebuilt on quest updates, so find the current target by quest
    local still
    for _, p in ipairs(points) do if p.q == current.q then still = p break end end
    local curDist = still and distanceTo(still, pc, px, py)
    if curDist and curDist - bestDist < SWITCH_YARDS then best, bestDist = still, curDist end
  end
  current = best
  if not best then
    reading.state, reading.r, reading.g, reading.b, reading.rel = "far", 0.55, 0.5, 0.45, 0
    reading.text, reading.q = target.zone or "", points[1].q
    return reading
  end
  local _, tx, ty = worldPos(best.m, best.x / 100, best.y / 100)
  local dist, rel = ns.ArrowMath(px, py, tx, ty, facing())
  reading.q = best.q
  if dist <= ARRIVE_YARDS then
    reading.state, reading.r, reading.g, reading.b, reading.rel, reading.text = "here", 0.56, 0.75, 0.35, 0, "here"
    return reading
  end
  reading.state, reading.rel, reading.text = "point", rel or 0, formatDistance(dist)
  reading.r, reading.g, reading.b = ns.ArrowColor(rel)
  return reading
end
ns.UpdateArrow = ns.ArrowReading

function ns.SetArrow(step)
  if not ns.Setting("arrow") or not step or not ((step.m and step.x) or step.pts) then
    ns.ClearArrow()
    return false
  end
  target = { m = step.m, x = step.x, y = step.y, zone = step.zone, step = step }
  cacheValid, current = false, nil
  return true
end

function ns.ClearArrow()
  target = nil
end

function ns.ArrowTarget() return target end
