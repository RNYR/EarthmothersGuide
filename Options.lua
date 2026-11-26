-- Earthmother's Guide: settings page (Esc > Options > AddOns > Earthmother's Guide).
-- Copyright (C) 2026 Vard Ruun. Licensed under GPL-3.0-only; see LICENSE and NOTICE.md.
-- Options at the top, route browser below: chapters on the left, that chapter's zones and
-- steps on the right. Click a step to jump there. Mouse wheel scrolls the step list.

local ADDON, ns = ...
ns = ns or _G.EarthmothersGuide

local C = ns.COLORS or { title = "ffd9b77a", chapter = "ff8fbf5a", dungeon = "ffe08a4a", dim = "ffa89880", tip = "ff9fd47f" }
local function c(hex, text) return "|c" .. hex .. text .. "|r" end
local DONE_ICON = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t"

local page, category
local ROWS, ROW_H = 17, 16

----------------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------------
local function questNames(step)
  local names = {}
  for _, q in ipairs(step.q or {}) do
    local prof = step.prof and step.prof[q]
    local skipped = ns.IsSkipped(q) and c(C.dim, " (skipped)") or ""
    names[#names + 1] = ((step.qn and step.qn[q]) or ("Quest " .. q)) .. (prof and c(C.dim, " (" .. prof .. ")") or "") .. skipped
  end
  return table.concat(names, ", ")
end

local function stepLine(step)
  local label = (ns.TYPE_LABEL and ns.TYPE_LABEL[step.t]) or step.t
  local text
  if step.t == "accept" or step.t == "turnin" then
    text = questNames(step) .. (step.npc and c(C.dim, "  (" .. step.npc .. ")") or "")
  elseif step.t == "complete" then
    text = questNames(step)
  else
    text = step.text or ""
  end
  local tag = step.d and c(C.dungeon, "[" .. step.d .. "] ") or ""
  return tag .. c(C.title, label .. ":") .. " " .. text
end

local function chapterProgress(ch)
  local total, done = 0, 0
  for _, st in ipairs(ch.steps) do
    if st.t == "turnin" and st.q then
      for _, q in ipairs(st.q) do
        total = total + 1
        if ns.IsQuestTurnedIn(q) then done = done + 1 end
      end
    end
  end
  if total == 0 then return 0 end
  return math.floor(done * 100 / total + 0.5)
end

local function chapterZones(ch)
  local seen, list = {}, {}
  for _, st in ipairs(ch.steps) do
    if st.zone and not st.d and not seen[st.zone] then seen[st.zone] = true; list[#list + 1] = st.zone end
  end
  return list
end

local function chapterDungeons(ch)
  local seen, list = {}, {}
  for _, st in ipairs(ch.steps) do
    if st.d and not seen[st.d] then
      seen[st.d] = true
      list[#list + 1] = ("%s (%d-%d)"):format(st.d, st.dmin or 0, st.dmax or 60)
    end
  end
  return list
end

----------------------------------------------------------------------------------------------
-- Widgets
----------------------------------------------------------------------------------------------
local function label(parent, text, font)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  fs:SetJustifyH("LEFT")
  fs:SetText(text)
  return fs
end

local function checkbox(parent, text, key, onChange)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(22, 22)
  cb.label = label(parent, text)
  cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  cb:SetScript("OnClick", function(self)
    ns.SetSetting(key, self:GetChecked() and true or false)
    if onChange then onChange(self:GetChecked() and true or false) end
  end)
  cb.Refresh = function(self) self:SetChecked(ns.Setting(key) and true or false) end
  return cb
end

local function button(parent, text, w, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, 20)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

-- "Name: value  [-] [+]"
local function stepper(parent, text, get, set, fmt)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(260, 22)
  f.label = label(f, "")
  f.label:SetPoint("LEFT", f, "LEFT", 0, 0)
  local minus = button(f, "-", 22, function() set(-1); f:Refresh() end)
  local plus = button(f, "+", 22, function() set(1); f:Refresh() end)
  plus:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  minus:SetPoint("RIGHT", plus, "LEFT", -2, 0)
  f.Refresh = function() f.label:SetText(text .. ": " .. c(C.title, fmt(get()))) end
  return f
end

-- A section box in the guide's colours: dark hide fill with a tanned leather edge.
local function box(parent, x, y, w, h)
  local bg = parent:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  bg:SetSize(w, h)
  bg:SetColorTexture(0.16, 0.11, 0.07, 0.75)
  local function edge(p1, p2, ew, eh)
    local t = parent:CreateTexture(nil, "BORDER")
    t:SetColorTexture(0.55, 0.42, 0.24, 0.9)
    t:SetPoint(p1, bg, p1)
    if ew then t:SetSize(ew, 1) else t:SetSize(1, eh) end
    if p2 then t:SetPoint(p2, bg, p2) end
    return t
  end
  edge("TOPLEFT", "TOPRIGHT", w)
  edge("BOTTOMLEFT", "BOTTOMRIGHT", w)
  edge("TOPLEFT", "BOTTOMLEFT", nil, h)
  edge("TOPRIGHT", "BOTTOMRIGHT", nil, h)
  return bg
end

----------------------------------------------------------------------------------------------
-- Page
----------------------------------------------------------------------------------------------
local function buildPage(parent, name)
  local p = CreateFrame("Frame", name, parent)
  p:SetAllPoints(parent)
  p.selected = nil
  p.offset = 0

  local title = label(p, c(C.title, "Earthmother's Guide"), "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -14)
  local sub = label(p, c(C.dim, "1-60 Tauren Druid route for WoW: Forever. Tick the box beside a quest on the panel to skip it, or Done to continue a note; right-click the panel to open this page."))
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

  -- Options ------------------------------------------------------------------------------
  local PAGE_W = 664
  box(p, 12, -52, PAGE_W, 156)
  local checks = {
    checkbox(p, "Show guide panel", "shown", function(v) ns.ShowPanel(v) end),
    checkbox(p, "Include dungeon steps", "dungeons"),
    checkbox(p, "Show direction arrow", "arrow", function(v) if v then ns.SetWaypoint(ns.Current()) else ns.ClearArrow() end end),
    checkbox(p, "Set Blizzard map pin", "waypoints", function(v) if v then ns.SetWaypoint(ns.Current()) else ns.ClearMapPin() end end),
    checkbox(p, "Lock panel position", "locked"),
    checkbox(p, "Compact quest list", "compact"),
    checkbox(p, "Show carried quests", "showCarried"),
    checkbox(p, "Quest item button", "itemButton", function() ns.UpdateItemButton() end),
    checkbox(p, "Include profession quests", "professions"),
    checkbox(p, "Replace Blizzard's quest tracker", "hideTracker", function() ns.UpdateBlizzardTracker() end),
  }
  for i, cb in ipairs(checks) do
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    cb:SetPoint("TOPLEFT", p, "TOPLEFT", 20 + col * 200, -58 - row * 24)
  end
  p.checks = checks

  local scale = stepper(p, "Panel size",
    function() return ns.Setting("scale") or 1 end,
    function(d)
      local v = math.max(0.6, math.min(1.6, (ns.Setting("scale") or 1) + d * 0.1))
      ns.SetSetting("scale", math.floor(v * 10 + 0.5) / 10); ns.ApplyScale()
    end,
    function(v) return math.floor(v * 100 + 0.5) .. "%" end)
  scale:SetPoint("TOPLEFT", p, "TOPLEFT", 404, -58)
  local gray = stepper(p, "Skip quests below you by",
    function() return ns.Setting("grayLevels") or 0 end,
    function(d) ns.SetSetting("grayLevels", math.max(0, math.min(10, (ns.Setting("grayLevels") or 0) + d))) end,
    function(v) return v == 0 and "never" or (v .. " levels") end)
  gray:SetPoint("TOPLEFT", scale, "BOTTOMLEFT", 0, -2)
  p.steppers = { scale, gray }

  local find = button(p, "Find my place", 120, function() ns.InitPosition(true); p:Refresh(true) end)
  find:SetPoint("TOPLEFT", p, "TOPLEFT", 20, -180)
  local back = button(p, "Back one step", 120, function() ns.Prev(); p:Refresh(true) end)
  back:SetPoint("LEFT", find, "RIGHT", 6, 0)
  local skip = button(p, "Skip this step", 120, function() ns.Next(); p:Refresh(true) end)
  skip:SetPoint("LEFT", back, "RIGHT", 6, 0)
  p.status = label(p, "")
  p.status:SetPoint("LEFT", skip, "RIGHT", 10, 0)

  -- Route browser -----------------------------------------------------------------------
  local route = label(p, c(C.title, "Route"), "GameFontNormal")
  route:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -214)

  -- Chapter list: two lines per chapter - "3. Aquatic Form and Silverpine" and
  -- "Levels 16-21  ·  40% done" with a progress bar.
  local CH_W, CH_H = 270, 26
  local LIST_TOP = -230
  local LIST_H = 12 * (CH_H + 2) + 8
  box(p, 12, LIST_TOP, CH_W + 8, LIST_H)
  box(p, 12 + CH_W + 16, LIST_TOP, PAGE_W - CH_W - 16, LIST_H)
  p.chapterButtons = {}
  for n = 1, 12 do
    local b = CreateFrame("Button", nil, p)
    b:SetSize(CH_W, CH_H)
    b:SetPoint("TOPLEFT", p, "TOPLEFT", 16, LIST_TOP - 4 - (n - 1) * (CH_H + 2))
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0.55, 0.42, 0.24, 0.12)
    b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
    b.name = label(b, "", "GameFontNormalSmall")
    b.name:SetPoint("TOPLEFT", 6, -3)
    b.name:SetPoint("RIGHT", -96, 0)
    b.name:SetWordWrap(false)
    b.info = label(b, "")
    b.info:SetPoint("BOTTOMLEFT", 6, 4)
    b.barBg = b:CreateTexture(nil, "ARTWORK")
    b.barBg:SetSize(80, 5)
    b.barBg:SetPoint("TOPRIGHT", -8, -7)
    b.barBg:SetColorTexture(0, 0, 0, 0.5)
    b.bar = b:CreateTexture(nil, "OVERLAY")
    b.bar:SetHeight(5)
    b.bar:SetPoint("LEFT", b.barBg, "LEFT", 0, 0)
    b.bar:SetColorTexture(0.56, 0.75, 0.35, 0.9)
    b:SetScript("OnClick", function() p.selected = n; p.offset = 0; p:Refresh(false) end)
    p.chapterButtons[n] = b
  end

  local listLeft = 12 + CH_W + 16 + 8
  local listW = PAGE_W - CH_W - 16 - 16
  p.zones = label(p, "")
  p.zones:SetPoint("TOPLEFT", p, "TOPLEFT", listLeft, LIST_TOP - 8)
  p.zones:SetWidth(listW)
  p.zones:SetWordWrap(true)

  p.rows = {}
  for i = 1, ROWS do
    local r = CreateFrame("Button", nil, p)
    r:SetSize(listW, ROW_H)
    -- rows follow the chapter header directly, whatever its height
    if i == 1 then r:SetPoint("TOPLEFT", p.zones, "BOTTOMLEFT", 0, -8)
    else r:SetPoint("TOPLEFT", p.rows[i - 1], "BOTTOMLEFT", 0, 0) end
    r.stripe = r:CreateTexture(nil, "BACKGROUND")
    r.stripe:SetAllPoints()
    r.stripe:SetColorTexture(0.85, 0.72, 0.48, i % 2 == 0 and 0.06 or 0)
    r:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
    r.text = label(r, "")
    r.text:SetPoint("LEFT", 2, 0)
    r.text:SetPoint("RIGHT", -2, 0)
    r.text:SetWordWrap(false)
    r:SetScript("OnClick", function(self)
      if self.step then ns.SetIndex(self.step.index, true); p:Refresh(false) end
    end)
    p.rows[i] = r
  end
  p.scrollInfo = label(p, "")
  p.scrollInfo:SetPoint("TOPLEFT", p, "TOPLEFT", listLeft, LIST_TOP - LIST_H - 6)

  p:EnableMouseWheel(true)
  p:SetScript("OnMouseWheel", function(self, delta)
    self.offset = math.max(0, (self.offset or 0) - delta * 3)
    self:Refresh(false)
  end)

  -- Rows for the selected chapter: zone headers between steps.
  local function buildRows(ch)
    local rows, lastZone = {}, nil
    for _, st in ipairs(ch.steps) do
      if st.zone and st.zone ~= lastZone then
        rows[#rows + 1] = { header = st.zone }
        lastZone = st.zone
      end
      rows[#rows + 1] = { step = st }
    end
    return rows
  end

  function p:Refresh(followCurrent)
    for _, cb in ipairs(self.checks) do cb:Refresh() end
    for _, s in ipairs(self.steppers) do s:Refresh() end
    local cur = ns.Current()
    if followCurrent or not self.selected then
      self.selected = cur and cur.chapter.num or 1
      self.offset = nil
    end
    self.status:SetText(cur and c(C.dim, ("Level %d - chapter %d, step %d of %d"):format(
      ns.PlayerLevel(), cur.chapter.num, cur.index, #ns.steps)) or "")

    for n, b in ipairs(self.chapterButtons) do
      local ch = ns.chapters[n]
      if ch then
        local here = cur and cur.chapter.num == n
        local pct = chapterProgress(ch)
        b.name:SetText((here and c(C.chapter, "> ") or "") .. c(C.title, n .. ". ") .. ch.title)
        b.info:SetText(c(C.dim, "Levels ") .. c(C.title, ch.levels[1] .. "-" .. ch.levels[2])
          .. c(C.dim, "   " .. pct .. "% done") .. (here and c(C.chapter, "   you are here") or ""))
        b.bar:SetWidth(math.max(0.01, 80 * pct / 100))
        b.bg:SetColorTexture(0.55, 0.42, 0.24, n == self.selected and 0.40 or 0.12)
        b:Show()
      else
        b:Hide()
      end
    end

    local ch = ns.chapters[self.selected]
    if not ch then return end
    local dungeons = chapterDungeons(ch)
    self.zones:SetText(c(C.chapter, ("Ch. %d: %s - levels %d-%d"):format(ch.num, ch.title, ch.levels[1], ch.levels[2]))
      .. "\n" .. c(C.title, "Zones: ") .. table.concat(chapterZones(ch), ", ")
      .. (#dungeons > 0 and ("\n" .. c(C.dungeon, "Dungeons: ") .. table.concat(dungeons, ", ")) or ""))
    local rows = buildRows(ch)
    if self.offset == nil then
      -- open the list a few rows above the current step
      self.offset = 0
      for i, r in ipairs(rows) do
        if r.step and cur and r.step == cur then self.offset = math.max(0, i - 4) break end
      end
    end
    self.offset = math.min(self.offset, math.max(0, #rows - ROWS))
    for i, row in ipairs(self.rows) do
      local r = rows[self.offset + i]
      row.step = r and r.step or nil
      if not r then
        row.text:SetText("")
        row:Hide()
      else
        row:Show()
        if r.header then
          row.text:SetText(c(C.chapter, "-- " .. r.header .. " --"))
        else
          local st = r.step
          local prefix
          if cur and st == cur then prefix = c(C.chapter, "> ")
          elseif ns.IsStepDone(st) then prefix = DONE_ICON .. " "
          else prefix = "   " end
          local line = stepLine(st)
          if ns.IsFiltered(st) then line = c(C.dim, (line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))) end
          row.text:SetText(prefix .. line)
        end
      end
    end
    self.scrollInfo:SetText(c(C.dim, ("Rows %d-%d of %d - mouse wheel to scroll, click a step to go there."):format(
      math.min(#rows, self.offset + 1), math.min(#rows, self.offset + ROWS), #rows)))
  end

  p:SetScript("OnShow", function(self) self:Refresh(true) end)
  return p
end

----------------------------------------------------------------------------------------------
-- Registration: Blizzard Settings (modern client), old Interface Options, or own window.
----------------------------------------------------------------------------------------------
local standalone

local function makeStandalone()
  standalone = CreateFrame("Frame", "EarthmothersGuideOptionsWindow", UIParent, "BackdropTemplate")
  standalone:SetSize(700, 640)
  standalone:SetPoint("CENTER")
  standalone:SetFrameStrata("DIALOG")
  standalone:SetMovable(true)
  standalone:EnableMouse(true)
  standalone:RegisterForDrag("LeftButton")
  standalone:SetScript("OnDragStart", standalone.StartMoving)
  standalone:SetScript("OnDragStop", standalone.StopMovingOrSizing)
  if standalone.SetBackdrop then
    standalone:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8x8",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    standalone:SetBackdropColor(0.16, 0.11, 0.07, 0.97)
    standalone:SetBackdropBorderColor(0.55, 0.42, 0.24, 1)
  end
  local close = CreateFrame("Button", nil, standalone, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)
  if UISpecialFrames then table.insert(UISpecialFrames, "EarthmothersGuideOptionsWindow") end
  standalone:Hide()
  return standalone
end

local function register()
  local canvas = CreateFrame("Frame")
  canvas:SetSize(680, 640)
  page = buildPage(canvas, "EarthmothersGuideOptions")
  ns.optionsPage = page
  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, canvas, "Earthmother's Guide")
    if ok and cat then
      pcall(Settings.RegisterAddOnCategory, cat)
      category = cat
      return
    end
  end
  if InterfaceOptions_AddCategory then
    canvas.name = "Earthmother's Guide"
    pcall(InterfaceOptions_AddCategory, canvas)
    category = canvas
  end
end

function ns.OpenOptions()
  if not page then register() end
  if category and Settings and Settings.OpenToCategory then
    local id = (type(category) == "table" and (category.GetID and category:GetID() or category.ID))
    if id and pcall(Settings.OpenToCategory, id) then return end
    if InCombatLockdown and InCombatLockdown() then
      print("|cff8fbf5aEarthmother's Guide|r: the settings open after combat.")
      return
    end
  elseif category and InterfaceOptionsFrame_OpenToCategory then
    if pcall(InterfaceOptionsFrame_OpenToCategory, category) then
      pcall(InterfaceOptionsFrame_OpenToCategory, category)  -- first call only opens the frame
      return
    end
  end
  -- Fallback: show the same page in the guide's own window.
  -- Fallback window: a separate copy of the page, so the Settings canvas keeps its own.
  if not standalone then
    makeStandalone()
    standalone.page = buildPage(standalone)
  end
  standalone:Show()
  standalone.page:Refresh(true)
end

-- Keep the page current while it is open.
ns.OnChange(function()
  if page and page:IsVisible() then page:Refresh(false) end
  if standalone and standalone.page and standalone:IsShown() then standalone.page:Refresh(false) end
end)

register()
