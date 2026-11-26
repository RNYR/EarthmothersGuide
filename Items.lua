-- Earthmother's Guide: quest item buttons.
-- Copyright (C) 2026 Vard Ruun. Licensed under GPL-3.0-only; see LICENSE and NOTICE.md.
-- A quest on the panel that has a usable quest item (the kind Blizzard's quest tracker shows a
-- button for) gets a small button with the item's icon at the right end of its row. Click it
-- to use the item.
--
-- The buttons are secure, so they can only be shown, moved or changed out of combat. They are
-- anchored to UIParent, not to the panel, so the panel itself stays free to move and grow in
-- combat; if it does, the buttons catch up as soon as combat ends.

local ADDON, ns = ...
ns = ns or _G.EarthmothersGuide

local pool = {}
local pending = false
local ICON = 22

local function call(fn, ...)
  if not fn then return nil end
  local ok, a, b, c = pcall(fn, ...)
  if ok then return a, b, c end
end

local function inCombat() return InCombatLockdown and InCombatLockdown() end

-- Item link, icon and count for a quest's special item, or nil.
local function questItem(questID)
  local idx = C_QuestLog and call(C_QuestLog.GetLogIndexForQuestID, questID)
  if not idx or idx <= 0 then return nil end
  local link, icon = call(GetQuestLogSpecialItemInfo, idx)
  if not link then return nil end
  -- the quest log can name an item you no longer carry (used up, not looted yet)
  local id = tonumber(link:match("item:(%d+)"))
  local count = id and (call(C_Item and C_Item.GetItemCount, id) or call(GetItemCount, id))
  if count ~= nil and count <= 0 then return nil end
  return link, icon, count
end
ns.QuestItem = questItem

local function newButton(i)
  local b = CreateFrame("Button", "EarthmothersGuideItemButton" .. i, UIParent,
    "SecureActionButtonTemplate,BackdropTemplate")
  b:SetSize(ICON, ICON)
  b:SetFrameStrata("MEDIUM")
  b:RegisterForClicks("AnyUp", "AnyDown")
  if b.SetBackdrop then
    b:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8 })
    b:SetBackdropBorderColor(0.55, 0.42, 0.24, 1)
  end
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("TOPLEFT", 2, -2)
  b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
  b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  b.count:SetPoint("BOTTOMRIGHT", -1, 1)
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:SetScript("OnEnter", function(self)
    if self.link and GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  b:Hide()
  pool[i] = b
  return b
end

-- Put a button beside every visible quest row that has an item; hide the rest.
function ns.UpdateItemButtons()
  if inCombat() then pending = true return end
  pending = false
  local panel = _G.EarthmothersGuideFrame
  local used = 0
  if panel and panel:IsShown() and ns.Setting("shown") ~= false and ns.Setting("itemButton") and panel.rows then
    local viewTop = panel.scroll and panel.scroll:GetTop()
    local viewBottom = panel.scroll and panel.scroll:GetBottom()
    for _, row in ipairs(panel.rows) do
      local spec = row.used and row.spec
      if spec and spec.q and spec.item and row:IsShown() then
        local link, icon, count = questItem(spec.q)
        local top, right = row:GetTop(), row:GetRight()
        -- only rows you can see: a row scrolled out of view has no button
        local visible = top and right and (not viewTop or (top <= viewTop + 1 and top - ICON >= (viewBottom or 0) - 1))
        if link and visible then
          used = used + 1
          local b = pool[used] or newButton(used)
          b.link = link
          b:SetAttribute("type", "item")
          b:SetAttribute("item", link)
          b.icon:SetTexture(icon)
          b.count:SetText((count and count > 1) and count or "")
          b:SetScale((panel:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1))
          b:ClearAllPoints()
          -- same units as the row (the button has the panel's scale): its top-right corner
          b:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right, top)
          b:SetFrameLevel((panel:GetFrameLevel() or 0) + 10)
          b:Show()
        end
      end
    end
  end
  for i = used + 1, #pool do pool[i]:Hide() end
end
-- older names, still used by settings and tests
ns.UpdateItemButton = ns.UpdateItemButtons
ns.PlaceItemButton = ns.UpdateItemButtons

ns.OnChange(function() ns.UpdateItemButtons() end)

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_ENABLED" then
    if pending then ns.UpdateItemButtons() end
  else
    ns.UpdateItemButtons()   -- item counts changed
  end
end)
