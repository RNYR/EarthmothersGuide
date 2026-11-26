-- Earthmother's Guide: hides Blizzard's quest tracker (under the minimap) while the guide is the
-- primary quest list. Setting "Replace Blizzard's quest tracker" (on by default).
-- Copyright (C) 2026 Vard Ruun. Licensed under GPL-3.0-only; see LICENSE and NOTICE.md.
--
-- On WoW: Forever the tracker (ObjectiveTrackerFrame) can be a protected frame:
--   * its alpha may be changed any time, even in combat, so it is made invisible at once;
--   * Hide()/Show() on a protected frame must wait until combat ends;
--   * it is never reparented and its Update() is never called (that taints Blizzard's layout).
-- Blizzard re-shows the tracker on its own; an OnShow hook hides it again.

local ADDON, ns = ...
ns = ns or _G.EarthmothersGuide

local hidden = false     -- what we currently want
local hooked = false
local waitFrame

local function tracker() return _G.ObjectiveTrackerFrame end

local function inCombat() return InCombatLockdown and InCombatLockdown() end

local function apply()
  local f = tracker()
  if not f then return end
  if hidden then f:SetAlpha(0) end                 -- never protected: works in combat too
  local protected = f.IsProtected and f:IsProtected()
  if inCombat() and (protected or not hidden) then
    -- finish after combat, using whatever is wanted then
    waitFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    return
  end
  waitFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
  if hidden then
    f:Hide()
  else
    f:SetAlpha(1)
    f:Show()
  end
end

waitFrame = CreateFrame("Frame")
waitFrame:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_REGEN_ENABLED" then apply() return end
  -- PLAYER_ENTERING_WORLD: the tracker exists now
  ns.UpdateBlizzardTracker()
end)
waitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Hide or restore the tracker according to the setting. Restoring only undoes our own hiding.
function ns.UpdateBlizzardTracker()
  local f = tracker()
  if not f then return end
  local want = ns.Setting("hideTracker") and ns.Setting("shown") ~= false
  if want and not hooked then
    f:HookScript("OnShow", function() if hidden then apply() end end)
    hooked = true
  end
  if want == hidden then return end
  hidden = want
  apply()
end

ns.OnChange(function() ns.UpdateBlizzardTracker() end)
