-- Earthmother's Guide: quest item button.
-- Copyright (C) 2026 Vard Ruun. Licensed under GPL-3.0-or-later; see LICENSE and NOTICE.md.
-- When a quest in the current step has a usable quest item (the kind the quest log shows a
-- button for), a button appears under the guide panel. Click it to use the item.
-- It is a secure button, so it can only be shown, moved or changed out of combat; changes
-- wait until combat ends.

local ADDON, ns = ...
ns = ns or _G.EarthmothersGuide

local btn
local pending = false

local function call(fn, ...)
  if not fn then return nil end
  local ok, a, b, c = pcall(fn, ...)
  if ok then return a, b, c end
end

local function inCombat() return InCombatLockdown and InCombatLockdown() end

-- Item link and icon for a quest's special item, or nil.
local function questItem(questID)
  local idx = C_QuestLog and call(C_QuestLog.GetLogIndexForQuestID, questID)
  if not idx or idx <= 0 then return nil end
  local link, icon = call(GetQuestLogSpecialItemInfo, idx)
  if not link then return nil end
  -- the quest log can name an item you no longer carry (used up, not looted yet)
  local id = tonumber(link:match("item:(%d+)"))
  local count = id and (call(C_Item and C_Item.GetItemCount, id) or call(GetItemCount, id))
  if count ~= nil and count <= 0 then return nil end
  return link, icon
end
ns.QuestItem = questItem

local function create()
  btn = CreateFrame("Button", "EarthmothersGuideItemButton", UIParent, "SecureActionButtonTemplate,BackdropTemplate")
  btn:SetSize(32, 32)
  btn:SetClampedToScreen(true)
  btn:RegisterForClicks("AnyUp", "AnyDown")
  if btn.SetBackdrop then
    btn:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 })
    btn:SetBackdropBorderColor(0.55, 0.42, 0.24, 1)
  end
  btn.icon = btn:CreateTexture(nil, "ARTWORK")
  btn.icon:SetPoint("TOPLEFT", 3, -3)
  btn.icon:SetPoint("BOTTOMRIGHT", -3, 3)
  btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  btn.label:SetPoint("LEFT", btn, "RIGHT", 5, 0)
  btn:SetScript("OnEnter", function(self)
    if self.link and GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
      GameTooltip:Show()
    end
  end)
  btn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  btn:Hide()
end

-- Place the button just under the guide panel's bottom-left corner. Anchored to UIParent (not
-- the panel) so the panel stays freely movable in combat.
local function place()
  local panel = _G.EarthmothersGuideFrame
  if not panel or not panel.GetLeft or not panel:GetLeft() then return end
  local s = panel:GetEffectiveScale() / UIParent:GetEffectiveScale()
  local left, bottom, top = panel:GetLeft() * s, panel:GetBottom() * s, panel:GetTop() * s
  btn:ClearAllPoints()
  if bottom - 40 < 0 then
    -- panel sits at the bottom of the screen: put the button above it instead
    btn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, top + 4)
  else
    btn:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, bottom - 4)
  end
end

function ns.PlaceItemButton()
  if btn and btn:IsShown() and not inCombat() then place() end
end

function ns.UpdateItemButton()
  if inCombat() then pending = true return end
  pending = false
  if not btn then create() end
  local step = ns.Current()
  local link, icon, quest
  local panel = _G.EarthmothersGuideFrame
  local panelShown = panel and panel:IsShown() and ns.Setting("shown") ~= false
  if ns.Setting("itemButton") and panelShown and step and step.q then
    for _, q in ipairs(step.q) do
      if ns.IsQuestInLog(q) and not ns.IsQuestReady(q) then
        link, icon = questItem(q)
        if link then quest = q break end
      end
    end
  end
  if not link then
    btn:Hide()
    return
  end
  btn.link = link
  btn:SetAttribute("type", "item")
  btn:SetAttribute("item", link)
  btn.icon:SetTexture(icon)
  btn.label:SetText("|cffd9b77a" .. ((step.qn and step.qn[quest]) or "") .. "|r")
  place()
  btn:Show()
end

ns.OnChange(function() ns.UpdateItemButton() end)

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function() if pending then ns.UpdateItemButton() end end)
