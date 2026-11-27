-- Earthmother's Guide: the guide panel (with the built-in arrow) and /emg commands.
-- Copyright (C) 2026 Vard Ruun. Licensed under GPL-3.0-only; see LICENSE and NOTICE.md.

local ADDON, ns = ...
ns = ns or _G.EarthmothersGuide

local COLORS = {
  bg      = { 0.16, 0.11, 0.07, 0.92 },  -- dark hide brown
  border  = { 0.55, 0.42, 0.24, 1 },     -- tanned leather
  title   = "ffd9b77a",                  -- wheat
  chapter = "ff8fbf5a",                  -- plains green
  tip     = "ff9fd47f",                  -- druid green
  dungeon = "ffe08a4a",                  -- clay orange
  dim     = "ffa89880",
}
ns.COLORS = COLORS

local TYPE_LABEL = {
  accept = "Accept", complete = "Do", turnin = "Turn in", ["goto"] = "Go to", level = "Level",
  spell = "Learn", zone = "Travel", note = "Note", train = "Train", bind = "Hearth",
}
ns.TYPE_LABEL = TYPE_LABEL

local function c(hex, text) return "|c" .. hex .. text .. "|r" end

local panel
local MIN_WIDTH, MAX_WIDTH = 260, 520   -- "Panel width" setting; 260 still fits the header
local function panelWidth()
  return math.max(MIN_WIDTH, math.min(MAX_WIDTH, ns.Setting("panelWidth") or 350))
end
local ARROW_W = 44          -- the arrow's corner (top right): arrowhead with the distance under it
local ICON = 30             -- the guide's icon (top left), as tall as the two header lines
local TEXT_X = 8 + ICON + 6 -- title and chapter line start here, lined up
local CHECK_W = 18          -- quest checkbox size
local ITEM_W = 24           -- quest item button beside a quest row (like Blizzard's quest tracker)
local PAD = 10
local HEADER = 54           -- icon, title and chapter line, arrow, and a gap; the rest scrolls
local MIN_HEIGHT = 120      -- the smallest "Panel max height" still shows the arrow and a line or two

----------------------------------------------------------------------------------------------
-- Text
----------------------------------------------------------------------------------------------
local READY = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t"

local function objectiveLines(id, indent)
  local lines = {}
  for _, o in ipairs(ns.GetObjectives(id)) do
    if o.text and o.text ~= "" and not o.finished then
      lines[#lines + 1] = indent .. c(COLORS.dim, o.text)
    end
  end
  return lines
end

-- "12/19" over all counted objectives, or the first unfinished objective's text.
local function objectiveSummary(id)
  local have, need, firstText = 0, 0, nil
  for _, o in ipairs(ns.GetObjectives(id)) do
    if o.numRequired and o.numRequired > 0 then
      have = have + math.min(o.numFulfilled or 0, o.numRequired)
      need = need + o.numRequired
    end
    if not o.finished and not firstText and o.text and o.text ~= "" then firstText = o.text end
  end
  if need > 0 then return have .. "/" .. need end
  return firstText or ""
end

local function questName(step, id) return (step.qn and step.qn[id]) or ("Quest " .. id) end

-- One line (plus objectives unless compact) for a quest you are working on.
local function activeQuestLines(lines, step, id, targeted)
  local name = questName(step, id)
  local lead = targeted and c(COLORS.title, "> ") or "- "
  if ns.Setting("compact") then
    lines[#lines + 1] = lead .. name .. "  " .. c(COLORS.dim, objectiveSummary(id))
  else
    lines[#lines + 1] = lead .. name
    for _, l in ipairs(objectiveLines(id, "    ")) do lines[#lines + 1] = l end
  end
end

-- One row per quest of the current step, each with a "skip this quest" checkbox. A row is
-- { q = questID, text = "...", skipped = bool } or, for note/training/hearth steps, a single
-- { done = true, text = "Done" } row.
local function questRows(step)
  local rows = {}
  if ns.IsManual(step) then
    rows[1] = { done = true, text = c(COLORS.dim, "Done") }
    return rows
  end
  if not step.q then return rows end
  local targeted = panel and panel.arrowQuest
  local side = ns.InSideTrip()
  for _, id in ipairs(step.q) do
    if side and not (ns.side and ns.side[id]) then
      -- on a side trip: only the quest you picked up out of order (and its follow-ups)
    else
      local name = questName(step, id)
      if ns.IsSkipped(id) then
        -- stays visible (dimmed, ticked) while its step is on screen, so a misclick is easy to undo
        rows[#rows + 1] = { q = id, skipped = true, text = c(COLORS.dim, name .. " - skipped") }
      elseif not ns.QuestHidden(step, id) then
        local lines = {}
        if step.t == "complete" then
          if ns.IsQuestTurnedIn(id) or ns.IsQuestReady(id) then
            lines[1] = READY .. " " .. c(COLORS.dim, name .. (ns.IsQuestReady(id) and " - ready" or ""))
          elseif ns.IsQuestFailed and ns.IsQuestFailed(id) then
            lines[1] = name .. c(COLORS.dungeon, " - failed: abandon it and pick it up again")
          elseif ns.IsQuestInLog(id) then
            activeQuestLines(lines, step, id, targeted == id and #step.q > 1)
            lines[1] = lines[1]:gsub("^%- ", "")
          end
        else
          local mark = ""
          if ns.IsQuestTurnedIn(id) or (step.t == "accept" and ns.IsQuestInLog(id)) then mark = " " .. READY end
          local prof = step.prof and step.prof[id]
          lines[1] = name .. (prof and c(COLORS.dim, " (" .. prof .. ")") or "") .. mark
        end
        if #lines > 0 then rows[#rows + 1] = { q = id, text = table.concat(lines, "\n") } end
      end
    end
  end
  return rows
end

-- Finished quests waiting for a turn-in somewhere else: name, who takes it and where.
local function readyLines()
  local list = ns.ReadyToHandIn()
  if #list == 0 then return nil end
  local lines = { c(COLORS.title, "Ready to hand in:") }
  for _, e in ipairs(list) do
    local who = e.npc and (e.npc .. (e.zone and (", " .. e.zone) or "")) or (e.zone or "")
    lines[#lines + 1] = READY .. " " .. e.name .. (who ~= "" and c(COLORS.dim, "  - " .. who) or "")
  end
  return table.concat(lines, "\n")
end

-- Extra section under the step: finished quests of this batch to hand in elsewhere, then (not on
-- pickups) the other unfinished quests you carry from this chapter.
local function extraLines(step)
  local parts = {}
  local ready = readyLines()
  if ready then parts[#parts + 1] = ready end
  if step.t ~= "accept" and ns.Setting("showCarried") and not ns.InSideTrip() then
    local list = ns.Carrying()
    if #list > 0 then
      local lines = { c(COLORS.title, "Also carrying:") }
      for _, e in ipairs(list) do activeQuestLines(lines, e.step, e.id, false) end
      parts[#parts + 1] = table.concat(lines, "\n")
    end
  end
  local look = ns.LookOutFor()
  if #look > 0 then
    local items = {}
    for i, e in ipairs(look) do
      if i > 4 then items[#items + 1] = ("+%d more"):format(#look - 4) break end
      items[#items + 1] = e.item .. c(COLORS.dim, " (starts " .. e.name .. ")")
    end
    parts[#parts + 1] = c(COLORS.title, "Look out for: ") .. table.concat(items, ", ")
  end
  if #parts == 0 then return nil end
  return table.concat(parts, "\n")
end

-- The step's text. A batch says how many of its quests you actually have to do: quests you
-- never picked up (or skipped) are not counted, so "Do these 6 quests" becomes "Do these 2".
function ns.StepText(step, rows)
  local text = step.text or ""
  if step.t ~= "complete" or not step.q or #step.q < 2 or not text:match("^Do these %d+ quests") then
    return text
  end
  local n = 0
  for _, spec in ipairs(rows or {}) do
    if spec.q and not spec.skipped then n = n + 1 end
  end
  if n == 0 or n == #step.q then return text end
  if n == 1 then return "Do this quest - the arrow leads to it" end
  return (text:gsub("^Do these %d+ quests", "Do these " .. n .. " quests"))
end

----------------------------------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------------------------------
local function blockHeight(fs, spacing)
  local text = fs:GetText()
  if not text or text == "" then return 0 end
  local reported = fs:GetStringHeight() or 0
  local lines = (fs.GetNumLines and fs:GetNumLines()) or 0
  local _, size = fs:GetFont()
  local computed = lines * ((size or 10) + (spacing or 0))
  return math.ceil(math.max(reported, computed, 10)) + 2
end

local function layout()
  local hasArrow = panel.arrowShown
  local left = PAD
  local PANEL_WIDTH = panelWidth()
  panel:SetWidth(PANEL_WIDTH)
  local width = PANEL_WIDTH - 2 * PAD     -- the text below the header uses the full width
  -- the chapter line sits between the icon and the arrow's corner
  panel.chapter:SetWidth(PANEL_WIDTH - TEXT_X - PAD - (hasArrow and ARROW_W or 0))
  local header = HEADER
  panel.header = header
  local y = 0                -- inside the scrolling content, under the header
  local textHeight = 0
  local function place(fs, spacing)
    fs:ClearAllPoints()
    fs:SetHeight(0)          -- let the text size itself before we measure it
    fs:SetWidth(width)
    local h = blockHeight(fs, spacing)
    if h > 0 then
      fs:SetPoint("TOPLEFT", panel.content, "TOPLEFT", left, y)
      fs:SetHeight(h)
      fs:Show()
      y = y - h - 5
      textHeight = textHeight + h + 5
    else
      fs:Hide()
    end
  end
  place(panel.body, 2)
  -- quest rows: checkbox on the left, text beside it
  for _, row in ipairs(panel.rows) do
    if row.used then
      row.text:ClearAllPoints()
      row.text:SetHeight(0)
      local itemW = (row.spec and row.spec.item) and ITEM_W or 0   -- room for the quest item button
      row.text:SetWidth(width - CHECK_W - itemW)
      local h = math.max(CHECK_W - 2, itemW > 0 and ITEM_W or 0, blockHeight(row.text, 2))
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", panel.content, "TOPLEFT", left, y)
      row:SetSize(width, h)
      row.text:SetPoint("TOPLEFT", row, "TOPLEFT", CHECK_W, -2)
      row.text:SetHeight(h)
      -- centre the checkbox on the quest's first text line (not the row), whatever the font size
      local _, size = row.text:GetFont()
      row.check:ClearAllPoints()
      row.check:SetPoint("CENTER", row, "TOPLEFT", CHECK_W / 2 - 3, -2 - math.floor((size or 10) / 2 + 0.5))
      row:Show()
      y = y - h - 2
      textHeight = textHeight + h + 2
    else
      row:Hide()
    end
  end
  place(panel.also, 0)
  place(panel.tip, 0)
  place(panel.hint, 0)
  local natural = math.max(70, header + textHeight + 6)
  local maxH = math.max(MIN_HEIGHT, ns.Setting("maxHeight") or 450)
  local height = math.min(natural, maxH)
  panel:SetHeight(height)
  panel.content:SetSize(PANEL_WIDTH, math.max(1, textHeight))
  -- longer than the maximum: scroll with the mouse wheel; a thin bar shows where you are
  local view = height - header - 6
  panel.scrollMax = math.max(0, textHeight - view)
  panel.scrollView, panel.scrollTotal = view, textHeight
  ns.ScrollPanel(0)
end

-- Scroll the panel's content by `delta` pixels (positive = down), within its range.
function ns.ScrollPanel(delta)
  if not panel then return end
  local maxS = panel.scrollMax or 0
  local cur = math.max(0, math.min(maxS, (panel.scrollAt or 0) + (delta or 0)))
  panel.scrollAt = cur
  panel.scroll:SetVerticalScroll(cur)
  if maxS > 0 then
    local view, total = panel.scrollView, panel.scrollTotal
    local thumb = math.max(12, view * view / total)
    panel.thumb:SetHeight(thumb)
    panel.thumb:ClearAllPoints()
    panel.thumb:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -3, -(panel.header or HEADER) - (view - thumb) * cur / maxS)
    panel.thumb:Show()
  else
    panel.thumb:Hide()
  end
  if ns.UpdateItemButtons then ns.UpdateItemButtons() end
end

-- Show the panel's size ("Panel width" x "Panel max height") as an outline for a few seconds,
-- while you change either setting.
local previewToken = 0
function ns.PreviewMaxHeight()
  if not panel then return end
  local h = math.max(MIN_HEIGHT, ns.Setting("maxHeight") or 450)
  panel.preview:SetSize(panelWidth(), h)
  panel.preview.label:SetText(c(COLORS.title, ("%d x %d"):format(panelWidth(), h)))
  panel.preview:Show()
  previewToken = previewToken + 1
  local mine = previewToken
  if C_Timer and C_Timer.After then
    C_Timer.After(3, function() if mine == previewToken then panel.preview:Hide() end end)
  end
  layout()
end

----------------------------------------------------------------------------------------------
-- Rendering
----------------------------------------------------------------------------------------------
local function render(step)
  if not panel then return end
  if not step then
    panel.chapter:SetText(c(COLORS.dim, "No guide steps loaded."))
    panel.body:SetText("")
    for _, row in ipairs(panel.rows) do row.used = false end
    panel.also:SetText("")
    panel.tip:SetText("")
    panel.hint:SetText("")
    panel.counter:SetText("")
    layout()
    return
  end
  local ch = step.chapter
  panel.chapter:SetText(c(COLORS.chapter, ("Ch. %d: %s (%d-%d)"):format(ch.num, ch.title, ch.levels[1], ch.levels[2])))

  local rows = questRows(step)
  local first = c(COLORS.title, (TYPE_LABEL[step.t] or "") .. ":") .. " " .. ns.StepText(step, rows)
  if step.d then
    first = c(COLORS.dungeon, ("[%s %d-%d] "):format(step.d, step.dmin or 0, step.dmax or 60)) .. first
  end
  local lines = { first }
  if step.npc and step.t ~= "goto" then
    local where = step.zone and (" - " .. step.zone) or ""
    local coords = step.x and (" (%.1f, %.1f)"):format(step.x, step.y) or ""
    lines[#lines + 1] = c(COLORS.dim, step.npc .. where .. coords)
  elseif step.x then
    lines[#lines + 1] = c(COLORS.dim, ("%s (%.1f, %.1f)"):format(step.zone or "", step.x, step.y))
  end
  panel.body:SetText(table.concat(lines, "\n"))
  for i, spec in ipairs(rows) do
    local row = panel.rows[i] or panel:NewRow()
    row.used, row.spec = true, spec
    -- a usable quest item for a quest you are working on: a button beside its row
    spec.item = nil
    if spec.q and not spec.skipped and ns.Setting("itemButton") and ns.QuestItem
        and ns.IsQuestInLog(spec.q) and not ns.IsQuestReady(spec.q) then
      spec.item = ns.QuestItem(spec.q)
    end
    row.text:SetText(spec.text)
    row.check:SetChecked(spec.skipped and true or false)
    row.tipText = spec.done and "Tick when you have done this step." or
      (spec.skipped and "Skipped: untick to put this quest back in the route." or "Skip this quest: the guide stops waiting for it.")
  end
  for i = #rows + 1, #panel.rows do panel.rows[i].used = false end
  panel.also:SetText(extraLines(step) or "")
  local tip = ns.StepTip(step)
  panel.tip:SetText(tip and c(COLORS.tip, tip) or "")
  local hint = nil
  if ns.InSideTrip() then
    hint = ("Out of route order: finish this, then the guide takes you back to step %d."):format(ns.returnIndex)
  elseif step.t == "bind" then hint = "Continues when your hearthstone is set here (or tick Done)."
  elseif ns.IsManual(step) then hint = "Tick Done to continue." end
  -- falling behind: say so instead of sending you into quests that are too hard
  local level = ns.PlayerLevel()
  if step.q and step.ql and step.ql >= level + 3 and not step.cls then
    hint = ("These quests are level %d and you are %d: group up, grind a little, or skip ahead with care."):format(step.ql, level)
  end
  panel.hint:SetText(hint and c(COLORS.dim, hint) or "")
  panel.counter:SetText(("%d / %d"):format(step.index, #ns.steps))

  if panel.lastWaypointStep ~= step then
    panel.lastWaypointStep = step
    panel.scrollAt = 0          -- a new step starts at the top
    ns.SetWaypoint(step)
  end
  panel:UpdateArrow()
  layout()
  -- Measure again once the client has laid the text out.
  if C_Timer and C_Timer.After then C_Timer.After(0, layout) end
end

----------------------------------------------------------------------------------------------
-- Panel
----------------------------------------------------------------------------------------------
local function createPanel()
  panel = CreateFrame("Frame", "EarthmothersGuideFrame", UIParent, "BackdropTemplate")
  panel:SetSize(panelWidth(), 100)
  panel:SetClampedToScreen(true)
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", function(self)
    if not ns.Setting("locked") then self.dragging = true; self:StartMoving() end
  end)
  panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    -- keep the top-left corner fixed, so the panel grows downwards when the text gets longer
    local left, top = self:GetLeft(), self:GetTop()
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    EarthmothersGuideDB = EarthmothersGuideDB or {}
    EarthmothersGuideDB.pos = { "TOPLEFT", "BOTTOMLEFT", left, top }
    if ns.UpdateItemButtons then ns.UpdateItemButtons() end
    if C_Timer and C_Timer.After then C_Timer.After(0, function() self.dragging = false end) else self.dragging = false end
  end)
  -- Left-drag moves the panel; right-click opens the settings. Steps continue via the checkboxes.
  panel:SetScript("OnMouseDown", function(self)
    self.downX, self.downY = nil, nil
    if GetCursorPosition then self.downX, self.downY = GetCursorPosition() end
  end)
  panel:SetScript("OnMouseUp", function(self, button)
    if self.dragging then return end
    if GetCursorPosition and self.downX and self.downY then
      local x, y = GetCursorPosition()
      if math.abs(x - self.downX) + math.abs(y - self.downY) > 6 then return end  -- a drag, not a click
    end
    if button == "RightButton" then
      if ns.OpenOptions then ns.OpenOptions() end
    end
  end)
  if panel.SetBackdrop then
    panel:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8x8",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    panel:SetBackdropColor(unpack(COLORS.bg))
    panel:SetBackdropBorderColor(unpack(COLORS.border))
  end

  -- header: icon on the left spanning the title and chapter lines, both lined up beside it;
  -- the arrow in the top-right corner; the step text starts under all of it at full width
  local icon = panel:CreateTexture(nil, "ARTWORK")
  icon:SetSize(ICON, ICON)
  icon:SetPoint("TOPLEFT", 8, -8)
  icon:SetTexture("Interface\\Icons\\Ability_Druid_CatForm")

  panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", TEXT_X, -9)
  panel.title:SetText(c(COLORS.title, "Earthmother's Guide"))

  -- step counter on the title line, right-aligned (left of the arrow while it is shown);
  -- the settings open with a right-click on the panel or /emg options
  panel.counter = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  panel.counter:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -10)

  panel.chapter = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.chapter:SetPoint("TOPLEFT", panel, "TOPLEFT", TEXT_X, -27)
  panel.chapter:SetWidth(panelWidth() - TEXT_X - PAD)
  panel.chapter:SetJustifyH("LEFT")
  panel.chapter:SetWordWrap(false)

  -- everything under the header scrolls when the panel is taller than "Panel max height"
  panel.scroll = CreateFrame("ScrollFrame", nil, panel)
  panel.scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -HEADER)
  panel.scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 6)
  panel.content = CreateFrame("Frame", nil, panel.scroll)
  panel.content:SetSize(panelWidth(), 1)
  panel.scroll:SetScrollChild(panel.content)
  panel:EnableMouseWheel(true)
  panel:SetScript("OnMouseWheel", function(_, delta) ns.ScrollPanel(-delta * 36) end)
  panel.thumb = panel:CreateTexture(nil, "OVERLAY")
  panel.thumb:SetWidth(3)
  panel.thumb:SetColorTexture(0.85, 0.72, 0.48, 0.6)
  panel.thumb:Hide()
  -- outline of the maximum height, shown for a moment while you change the setting
  panel.preview = CreateFrame("Frame", nil, panel, "BackdropTemplate")
  panel.preview:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
  if panel.preview.SetBackdrop then
    panel.preview:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    panel.preview:SetBackdropBorderColor(0.85, 0.72, 0.48, 0.9)
  end
  panel.preview.label = panel.preview:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.preview.label:SetPoint("BOTTOM", panel.preview, "BOTTOM", 0, 4)
  panel.preview:Hide()

  local function textBlock(spacing)
    local fs = panel.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    if spacing then fs:SetSpacing(spacing) end
    return fs
  end
  panel.body = textBlock(2)

  -- pooled quest rows: a small checkbox (skip this quest / Done) and the quest text
  panel.rows = {}
  function panel:NewRow()
    local row = CreateFrame("Frame", nil, self.content)
    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(CHECK_W, CHECK_W)
    row.check:SetPoint("TOPLEFT", row, "TOPLEFT", -3, 2)   -- re-anchored to the first text line in layout()
    row.check:SetScript("OnClick", function(cb)
      local spec = row.spec
      if not spec then return end
      if spec.done then
        cb:SetChecked(false)
        ns.Next()
      elseif spec.q then
        ns.SetSkipped(spec.q, cb:GetChecked() and true or false)
      end
    end)
    row.check:SetScript("OnEnter", function(cb)
      if GameTooltip and row.tipText then
        GameTooltip:SetOwner(cb, "ANCHOR_LEFT")
        GameTooltip:SetText(row.tipText, 1, 1, 1, 1, true)
        GameTooltip:Show()
      end
    end)
    row.check:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetJustifyH("LEFT")
    row.text:SetJustifyV("TOP")
    row.text:SetWordWrap(true)
    row.text:SetSpacing(2)
    self.rows[#self.rows + 1] = row
    return row
  end
  panel.also = textBlock()
  panel.tip = textBlock()
  panel.hint = textBlock()

  -- The arrow has the top-right corner to itself: arrowhead with the distance under it, within
  -- the height of the title and chapter lines, so the step text below is never cut short.
  -- Its right edge is the text column's right edge: the distance is right-aligned to it and the
  -- arrowhead sits centred above the distance, so both end where the step text ends.
  panel.arrowBox = CreateFrame("Frame", nil, panel)
  panel.arrowBox:SetSize(ARROW_W, 42)
  panel.arrowBox:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -5)
  panel.arrowBox:Hide()
  local ARROW_SIZE = 24
  panel.dist = panel.arrowBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.dist:SetPoint("BOTTOMRIGHT", panel.arrowBox, "BOTTOMRIGHT", 0, 2)
  panel.dist:SetJustifyH("RIGHT")
  panel.dist:SetWordWrap(false)
  panel.arrow = panel.arrowBox:CreateTexture(nil, "ARTWORK")
  panel.arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
  panel.arrow:SetPoint("BOTTOM", panel.dist, "TOP", 0, 1)
  panel.arrow:SetTexture(ns.ARROW_TEXTURE)
  -- the counter moves left of the arrow while it is shown
  function panel:PlaceHeaderRight()
    self.counter:ClearAllPoints()
    self.counter:SetPoint("TOPRIGHT", self, "TOPRIGHT", self.arrowShown and -(PAD + ARROW_W) or -PAD, -10)
  end

  function panel:UpdateArrow()
    local reading = ns.Setting("arrow") and ns.ArrowReading and ns.ArrowReading()
    local show = reading ~= nil
    if show ~= self.arrowShown then
      self.arrowShown = show
      self:PlaceHeaderRight()
      layout()
    end
    if not show then
      self.arrowBox:Hide()
      return
    end
    self.arrowBox:Show()
    if reading.q ~= self.arrowQuest then
      self.arrowQuest = reading.q
      local st = ns.Current()
      local p = st and st.pts and reading.q and st.pts[reading.q]
      if p then ns.SetMapPin(p.m, p.x, p.y) end
      if st then render(st) end
    end
    self.arrow:SetVertexColor(reading.r, reading.g, reading.b)
    self.arrow:SetRotation(reading.rel or 0)
    local label = reading.state == "here" and c(COLORS.chapter, "here")
      or reading.state == "far" and c(COLORS.dim, "far") or c(COLORS.title, reading.text)
    if label ~= self.distLabel then   -- avoid re-setting the same text 20 times a second
      self.distLabel = label
      self.dist:SetText(label)
    end
  end

  local acc = 0
  panel:SetScript("OnUpdate", function(self, elapsed)
    acc = acc + elapsed
    if acc < 0.05 then return end
    acc = 0
    self:UpdateArrow()
  end)

  local pos = EarthmothersGuideDB and EarthmothersGuideDB.pos
  if pos then
    panel:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  else
    panel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -60, -220)
  end
  panel:SetScale(ns.Setting("scale") or 1)
  if ns.Setting("shown") == false then panel:Hide() end
end

function ns.ShowPanel(show)
  if not panel then createPanel() end
  if show then panel:Show() else panel:Hide() end
  ns.SetSetting("shown", show)
  if ns.UpdateItemButtons then ns.UpdateItemButtons() end
end

function ns.ApplyScale()
  if not panel then return end
  -- keep the top-left corner where you put it: positions are in the panel's own (scaled) units
  local old = panel:GetScale() or 1
  local new = ns.Setting("scale") or 1
  local left, top = panel:GetLeft(), panel:GetTop()
  panel:SetScale(new)
  if left and top and old ~= new then
    left, top = left * old / new, top * old / new
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    EarthmothersGuideDB = EarthmothersGuideDB or {}
    EarthmothersGuideDB.pos = { "TOPLEFT", "BOTTOMLEFT", left, top }
  end
  if ns.UpdateItemButtons then ns.UpdateItemButtons() end
end

ns.OnChange(function(step)
  if not panel then createPanel() end
  render(step)
end)

----------------------------------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------------------------------
local HELP = {
  "/emg - show or hide the guide (tick the box beside a quest to skip it, Done to continue a note; right-click for settings)",
  "/emg unskip - put every skipped quest back in the route",
  "/emg options - settings and the route browser (chapters, zones, steps)",
  "/emg next | prev - move one step",
  "/emg chapter <1-12> - jump to a chapter",
  "/emg resume - work out your place again from your level and finished quests",
  "/emg status - your level, finished quests and missing druid forms",
  "/emg check <questID> - what the guide sees for one quest",
  "/emg gray grey|0-10 - skip quests when they turn grey (default), never (0), or this many levels below you",
  "/emg way - set the arrow and map pin for this step again",
  "/emg tracker on|off - show or hide Blizzard's quest tracker (hidden while the guide replaces it)",
  "/emg arrow on|off | waypoints on|off (map pin) | scale <0.6-1.6> | width <260-520> | height <150-900> | lock | unlock",
}

local function say(msg) print("|cff8fbf5aEarthmother's Guide|r: " .. msg) end
ns.say = say

SLASH_EARTHMOTHERSGUIDE1 = "/emg"
SlashCmdList.EARTHMOTHERSGUIDE = function(msg)
  local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
  if cmd == "" or cmd == "show" or cmd == "hide" or cmd == "toggle" then
    if not panel then createPanel() end
    ns.ShowPanel((cmd == "show") or (cmd ~= "hide" and not panel:IsShown()))
  elseif cmd == "options" or cmd == "config" or cmd == "settings" then
    if ns.OpenOptions then ns.OpenOptions() end
  elseif cmd == "next" or cmd == "skip" then ns.Next()
  elseif cmd == "prev" or cmd == "back" then ns.Prev()
  elseif cmd == "chapter" or cmd == "ch" then
    local n = tonumber(arg)
    if n and ns.chapters[n] then ns.GotoChapter(n) else say("chapters are 1-12") end
  elseif cmd == "arrow" then
    if arg == "on" or arg == "off" then ns.SetSetting("arrow", arg == "on") end
    if ns.Setting("arrow") then ns.SetWaypoint(ns.Current()) else ns.ClearArrow() end
    say("arrow " .. (ns.Setting("arrow") and "on" or "off"))
  elseif cmd == "waypoints" then
    if arg == "on" or arg == "off" then ns.SetSetting("waypoints", arg == "on") end
    if ns.Setting("waypoints") then ns.SetWaypoint(ns.Current()) else ns.ClearMapPin() end
    say("map pin " .. (ns.Setting("waypoints") and "on" or "off"))
  elseif cmd == "unskip" then
    ns.ClearSkips()
    say("all skipped quests are back in the route")
  elseif cmd == "tracker" then
    if arg == "on" or arg == "off" then ns.SetSetting("hideTracker", arg == "off") end
    if ns.UpdateBlizzardTracker then ns.UpdateBlizzardTracker() end
    say("Blizzard's quest tracker " .. (ns.Setting("hideTracker") and "hidden (the guide replaces it)" or "shown"))
  elseif cmd == "way" then
    if not ns.SetWaypoint(ns.Current()) then say("no waypoint for this step") end
  elseif cmd == "resume" then
    ns.InitPosition(true)
  elseif cmd == "status" then
    local done, total = 0, 0
    for q in pairs(ns.acceptIndex or {}) do
      total = total + 1
      if ns.IsQuestTurnedIn(q) then done = done + 1 end
    end
    local cur = ns.Current()
    say(("level %d, %d of %d guide quests done, at chapter %d step %d/%d"):format(ns.PlayerLevel(), done, total,
      cur and cur.chapter.num or 0, ns.index or 0, #ns.steps))
    local missing = ns.MissingForms()
    if #missing == 0 then say("all druid forms for your level learned") end
    for _, f in ipairs(missing) do say(("missing %s - /emg chapter %d"):format(f.name, f.chapter)) end
  elseif cmd == "check" then
    -- /emg check <questID>: what the guide sees for one quest (for bug reports)
    local id = tonumber(arg)
    if not id then say("usage: /emg check <questID>") return end
    local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
    say(("quest %d %s: in log=%s, objectives done=%s, handed in=%s, guide step=%s"):format(id,
      title and ("(" .. title .. ")") or "", tostring(ns.IsQuestInLog(id)), tostring(ns.IsQuestReady(id)),
      tostring(ns.IsQuestTurnedIn(id)), tostring(ns.acceptIndex and ns.acceptIndex[id])))
  elseif cmd == "gray" or cmd == "grey" then
    local n = tonumber(arg)
    if arg == "grey" or arg == "gray" or arg == "auto" then ns.SetSetting("grayLevels", -1)
    elseif n and n >= 0 and n <= 10 then ns.SetSetting("grayLevels", n) end
    local g = ns.Setting("grayLevels")
    say(g == -1 and "skipping quests once they turn grey" or g == 0 and "never skipping low quests"
      or ("skipping quests " .. g .. " or more levels below you"))
  elseif cmd == "scale" then
    local s = tonumber(arg)
    if s and s >= 0.6 and s <= 1.6 then ns.SetSetting("scale", s); ns.ApplyScale() end
  elseif cmd == "width" then
    local w = tonumber(arg)
    if w and w >= 260 and w <= 520 then ns.SetSetting("panelWidth", math.floor(w)) end
    if ns.PreviewMaxHeight then ns.PreviewMaxHeight() end
    say(("panel width %d px"):format(ns.Setting("panelWidth")))
  elseif cmd == "height" then
    local h = tonumber(arg)
    if h and h >= 150 and h <= 900 then ns.SetSetting("maxHeight", math.floor(h)) end
    if ns.PreviewMaxHeight then ns.PreviewMaxHeight() end
    say(("panel max height %d px (it scrolls when there is more)"):format(ns.Setting("maxHeight")))
  elseif cmd == "lock" or cmd == "unlock" then
    ns.SetSetting("locked", cmd == "lock")
  else
    for _, l in ipairs(HELP) do say(l) end
  end
end
