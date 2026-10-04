local Addon = WordHunterWoW_Addon
local COLORS = Addon.COLORS
local unpack = unpack or table.unpack
local PAGE_SIZE = 40
local questsFrame
local questRows = {}
local catalog = {}

-- The catalog contains ALL installed quest records, plus this character's
-- history and current log. It is only a chooser: the existing learning panel
-- owns text, word states, the editor and optional voice buttons.
-- Keep controls in English, like the existing reader and word editor.
-- The quest text itself keeps its source language.
local L = {
  title = "QUEST LIBRARY", database = "All quests", log = "In quest log",
  completed = "Completed", history = "My history", search = "Name / ID",
  inLog = "In quest log", accepted = "Accepted", inDatabase = "In database",
  hint = "Open quest text · Click words · Audio where available.",
  note = "Database = all stored quests, not just quests currently offered by NPCs.",
  empty = "No matching quests.", prev = "< Previous", next = "Next >",
  page = "Page %d / %d  ·  %d quests", missing = "No stored text for this quest.",
}

local function questID(value)
  if type(value) ~= "number" and type(value) ~= "string" then return nil end
  local id = tonumber(value)
  if not id or id <= 0 or id == math.huge or id ~= math.floor(id) then return nil end
  return id
end

local function buildCatalog()
  local byId = {}
  local function include(id, title, titleLocale, titleSource)
    id = questID(id)
    if not id then return nil end
    local q = byId[id]
    if not q then q = { id = id, idStr = tostring(id) } byId[id] = q end
    if type(title) == "string" and title ~= "" then
      q.title, q.titleLocale, q.titleSource = title, titleLocale, titleSource
    end
    return q
  end
  local locale = Addon.GetCatalogLocale and Addon.GetCatalogLocale() or Addon.GetTargetLocale()
  local data = WordHunterWoW_QuestData
  local localized, qualified
  if Addon.GetQuestDatabase then
    local sourceFlavor
    localized, sourceFlavor, qualified = Addon.GetQuestDatabase(locale)
  else
    localized = type(data) == "table" and data[locale]
  end
  local english
  if Addon.GetQuestDatabase then english = Addon.GetQuestDatabase("enUS") else english = WordHunterWoW_QuestEN end
  if not (qualified and type(localized) == "table") then
    for id, record in pairs(type(english) == "table" and english or {}) do
      if type(record) == "table" then include(id, record.title, "enUS", "database") end
    end
  end
  if type(localized) == "table" then
    for id, record in pairs(localized) do
      if type(record) == "table" then include(id, record.title, locale, "database") end
    end
  end
  local corpus = WordHunterWoWCorpus
  local bucket = type(corpus) == "table" and type(corpus.byLocale) == "table" and corpus.byLocale[locale]
  local flavor = Addon.Compat and Addon.Compat.GameFlavor() or "retail"
  if type(bucket) == "table" then
    for _, entry in pairs(bucket) do
      if type(entry) == "table" and entry.kind ~= "word" and entry.kind ~= "gossip"
          and (entry.flavor == flavor or (entry.flavor == nil and flavor == "retail")) then
        include(entry.id, entry.kind == "title" and entry.text or nil, locale, "collected text")
      end
    end
  end
  local observed = Addon.GetObservedQuestTexts and Addon.GetObservedQuestTexts(locale)
  for id, record in pairs(type(observed) == "table" and observed or {}) do
    if type(record) == "table" then include(id, record.title, locale, "observed text") end
  end
  local history = Addon.GetCharacterQuestHistory and Addon.GetCharacterQuestHistory() or {}
  for id, record in pairs(history) do
    if type(record) == "table" then
      local q = include(id)
      if q then
        if not q.title or (q.titleLocale ~= locale and (record.titleLocale == locale or not record.titleLocale)) then
          include(id, record.title, record.titleLocale, "quest history")
        end
        q.completed, q.accepted = record.completed == true, record.accepted == true
      end
    end
  end
  local Compat = Addon.Compat
  for _, entry in ipairs(Compat and Compat.QuestLogEntries and Compat.QuestLogEntries() or {}) do
    local q = include(entry.id)
    if q and (not q.title or Addon.TextLocale() == locale) then
      include(entry.id, entry.title, Addon.TextLocale(), "quest log")
    end
    if q then q.inLog = true end
  end
  local out = {}
  for _, q in pairs(byId) do
    q.title = q.title or ("Quest " .. q.idStr)
    q.sortKey = Addon.utf8Lower(q.title)
    out[#out + 1] = q
  end
  table.sort(out, function(a, b)
    if a.sortKey == b.sortKey then return a.id < b.id end
    return a.sortKey < b.sortKey
  end)
  return out
end
Addon.CollectQuestCatalog = buildCatalog

local function matchesFilter(q, filter)
  if filter == "log" then return q.inLog end
  if filter == "completed" then return q.completed end
  if filter == "history" then return q.inLog or q.accepted or q.completed end
  return true
end

local function paintRows()
  local f = questsFrame
  for _, row in ipairs(questRows) do row:Hide() end
  local width = math.max(300, f:GetWidth() - 62)
  f.questContent:SetWidth(width)
  local y = 0
  local first = (f.page - 1) * PAGE_SIZE + 1
  local last = math.min(#f.filtered, first + PAGE_SIZE - 1)
  for index = first, last do
    local poolIndex = index - first + 1
    local row = questRows[poolIndex]
    if not row then
      row = CreateFrame("Button", nil, f.questContent)
      row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "BLEND")
      row:GetHighlightTexture():SetVertexColor(0.30, 0.42, 0.55, 0.20)
      row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      Addon.ApplyFontRole(row.name, "body")
      row.name:SetPoint("TOPLEFT", 8, -6)
      row.name:SetJustifyH("LEFT")
      row.name:SetJustifyV("TOP")
      row.name:SetMaxLines(2)
      row.name:SetWordWrap(true)
      row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      row.meta:SetPoint("TOPRIGHT", -8, -6)
      row.meta:SetWidth(140)
      row.meta:SetJustifyH("RIGHT")
      row.meta:SetJustifyV("TOP")
      row.meta:SetMaxLines(2)
      row.meta:SetWordWrap(true)
      row:SetScript("OnClick", function(self)
        if Addon.OpenCatalogQuest and Addon.OpenCatalogQuest(self.item.id, Addon.GetCatalogLocale and Addon.GetCatalogLocale()) then
          f:Hide()
        else
          f.note:SetText(L.missing .. "  #" .. self.item.idStr)
        end
      end)
      row:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.item.title)
        if self.item.titleSource == "quest history" and not self.item.titleLocale then
          GameTooltip:AddLine("Saved title; language not recorded.", 0.8, 0.82, 0.88, true)
        end
        GameTooltip:AddLine("#" .. self.item.idStr .. "  ·  " .. L.hint, 0.8, 0.82, 0.88, true)
        GameTooltip:Show()
      end)
      row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
      questRows[poolIndex] = row
    end
    local q = f.filtered[index]
    row.item = q
    row.name:SetWidth(width - 166)
    row.name:SetText(q.title)
    row.name:SetTextColor(unpack(COLORS.text))
    local state = q.inLog and L.inLog or q.completed and L.completed or q.accepted and L.accepted or L.inDatabase
    local locale = Addon.GetCatalogLocale and Addon.GetCatalogLocale() or Addon.GetTargetLocale()
    local language = q.titleLocale and q.titleLocale ~= locale and " · " .. string.upper(Addon.WH_LANGUAGE_MAP[q.titleLocale] or q.titleLocale) or ""
    row.meta:SetText("#" .. q.idStr .. language .. "  ·  " .. state)
    row.meta:SetTextColor(unpack(q.completed and COLORS.known or q.inLog and COLORS.new or COLORS.muted))
    local h = math.max(28, row.name:GetStringHeight() + 12, row.meta:GetStringHeight() + 12)
    row:SetSize(width, h)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -y)
    row:Show()
    y = y + h + 3
  end
  f.questContent:SetHeight(math.max(1, y))
  f.questScroll:UpdateScrollChildRect()
  f.pageLabel:SetText(string.format(L.page, f.page, f.pageCount, f.resultCount))
  f.prevPage:SetEnabled(f.page > 1)
  f.nextPage:SetEnabled(f.page < f.pageCount)
  f.empty:SetText(L.empty)
  if f.resultCount == 0 then f.empty:Show() else f.empty:Hide() end
  f.rows = questRows
end

local function refreshView(resetPage)
  local f = questsFrame
  if not f or not f:IsShown() then return end
  local query = Addon.utf8Lower(Addon.trim(f.search:GetText()))
  f.filtered = {}
  for _, q in ipairs(catalog) do
    if matchesFilter(q, f.filter) and (query == "" or q.sortKey:find(query, 1, true) or q.idStr:find(query, 1, true)) then
      f.filtered[#f.filtered + 1] = q
    end
  end
  f.resultCount = #f.filtered
  f.pageCount = math.max(1, math.ceil(f.resultCount / PAGE_SIZE))
  f.page = resetPage and 1 or math.max(1, math.min(f.page or 1, f.pageCount))
  for name, button in pairs(f.filterButtons) do
    Addon.styleFlatButton(button, COLORS.new, name == f.filter)
  end
  f.note:SetText(L.note)
  f.questScroll:SetVerticalScroll(0)
  paintRows()
end

function Addon.refreshQuestBrowser()
  if not questsFrame or not questsFrame:IsShown() then return end
  catalog = buildCatalog()
  Addon.RefreshCatalogLanguageControls()
  refreshView(false)
end

function Addon.SetQuestCatalogFilter(filter)
  if not questsFrame or not questsFrame.filterButtons[filter] then return end
  questsFrame.filter = filter
  refreshView(true)
end

local function layout()
  local f = questsFrame
  local tabWidth = (f:GetWidth() - 54) / 4
  for index, name in ipairs({ "database", "log", "completed", "history" }) do
    local button = f.filterButtons[name]
    button:SetSize(tabWidth, 26)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", 18 + (index - 1) * (tabWidth + 6), -60)
  end
  if f:IsShown() then paintRows() end
end

function Addon.toggleQuestBrowser()
  if not questsFrame then
    local f = CreateFrame("Frame", "WordHunterWoWQuests", UIParent, "BackdropTemplate")
    questsFrame, Addon.questsFrame = f, f
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(22)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      Addon.SaveFramePosition(self, Addon.LayoutKey("quests"))
    end)
    Addon.setBackdrop(f)
    Addon.SetupEscapeClose(f)
    Addon.PlaceFrame(f, "quests")
    Addon.ApplyWindowScale("listScale")
    Addon.MakeResizable(f, "quests", 560, 350, 1000, 800)
    f:Hide()
    f.filter, f.page, f.filterButtons = "database", 1, {}
    f.filtered, f.resultCount, f.pageCount = {}, 0, 1
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 18, -14)
    title:SetPoint("TOPRIGHT", -162, -14)
    title:SetText(L.title)
    local language = Addon.CreateCatalogLanguageButton(f)
    language:SetPoint("TOPRIGHT", -36, -12)
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 18, -37)
    hint:SetPoint("TOPRIGHT", -30, -37)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.hint)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Hide() end)
    for _, name in ipairs({ "database", "log", "completed", "history" }) do
      local key = name
      local b = Addon.createFlatButton(f, L[name], COLORS.new)
      b:SetScript("OnClick", function() Addon.SetQuestCatalogFilter(key) end)
      b:SetScript("OnLeave", function() Addon.styleFlatButton(b, COLORS.new, f.filter == key) end)
      f.filterButtons[name] = b
    end
    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 18, -100)
    label:SetText(L.search)
    f.search = Addon.createEditBox(f)
    f.search:SetPoint("TOPLEFT", 110, -93)
    f.search:SetPoint("TOPRIGHT", -20, -93)
    f.search:SetText("")
    local searchTimer
    f.search:SetScript("OnTextChanged", function()
      if searchTimer then searchTimer:Cancel() end
      searchTimer = C_Timer.NewTimer(0.15, function() refreshView(true) end)
    end)
    f.search:SetScript("OnEscapePressed", function() f:Hide() end)
    f.questScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.questScroll:SetPoint("TOPLEFT", 18, -128)
    f.questScroll:SetPoint("BOTTOMRIGHT", -34, 72)
    if f.questScroll.SetClipsChildren then f.questScroll:SetClipsChildren(true) end
    f.questContent = CreateFrame("Frame", nil, f.questScroll)
    f.questContent:SetSize(500, 1)
    f.questScroll:SetScrollChild(f.questContent)
    f.empty = f.questContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.empty:SetPoint("TOPLEFT", 8, -10)
    f.prevPage = Addon.createActionButton(f, L.prev)
    f.prevPage:SetSize(96, 24)
    f.prevPage:SetPoint("BOTTOMLEFT", 18, 39)
    f.prevPage:SetScript("OnClick", function()
      f.page = math.max(1, f.page - 1)
      f.questScroll:SetVerticalScroll(0)
      paintRows()
    end)
    f.nextPage = Addon.createActionButton(f, L.next)
    f.nextPage:SetSize(96, 24)
    f.nextPage:SetPoint("BOTTOMRIGHT", -18, 39)
    f.nextPage:SetScript("OnClick", function()
      f.page = math.min(f.pageCount, f.page + 1)
      f.questScroll:SetVerticalScroll(0)
      paintRows()
    end)
    f.pageLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.pageLabel:SetPoint("BOTTOM", 0, 47)
    f.note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.note:SetPoint("BOTTOMLEFT", 18, 12)
    f.note:SetPoint("BOTTOMRIGHT", -18, 12)
    f.note:SetJustifyH("LEFT")
    f.note:SetWordWrap(true)
    f.note:SetMaxLines(2)
    f:HookScript("OnSizeChanged", layout)
    local function refreshLogTab()
      if Addon.RefreshQuestsLogButton then Addon.RefreshQuestsLogButton() end
    end
    f:HookScript("OnShow", refreshLogTab)
    f:HookScript("OnHide", refreshLogTab)
    layout()
  end
  if questsFrame:IsShown() then
    questsFrame:Hide()
  else
    Addon.PlaceFrame(questsFrame, "quests")
    if Addon.SyncCharacterQuestHistory then Addon.SyncCharacterQuestHistory() end
    questsFrame:Show()
    layout()
    Addon.refreshQuestBrowser()
  end
end
