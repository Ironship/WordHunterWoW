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
  groupedPage = "Page %d / %d  ·  %d entries / %d IDs",
}

local function questID(value)
  if type(value) ~= "number" and type(value) ~= "string" then return nil end
  local id = tonumber(value)
  if not id or id <= 0 or id == math.huge or id ~= math.floor(id) then return nil end
  return id
end

local function buildCatalog(scope)
  local byId = {}
  local function include(id)
    id = questID(id)
    if not id then return end
    if not byId[id] then byId[id] = { id = id, idStr = tostring(id), titles = {} } end
    return byId[id]
  end
  local locale = Addon.GetTargetLocale()
  local localized = Addon.GetQuestDatabase and Addon.GetQuestDatabase(locale)
    or WordHunterWoW_QuestData and WordHunterWoW_QuestData[locale] or {}
  local english = Addon.GetQuestDatabase and Addon.GetQuestDatabase("enUS") or WordHunterWoW_QuestEN or {}
  local observed = Addon.GetObservedQuestTexts and Addon.GetObservedQuestTexts(locale) or {}
  local englishObserved = Addon.GetObservedQuestTexts and Addon.GetObservedQuestTexts("enUS") or {}
  local sources = Addon.GetQuestLibrarySources and Addon.GetQuestLibrarySources() or {}
  local history = Addon.GetCharacterQuestHistory and Addon.GetCharacterQuestHistory() or {}
  for id, record in pairs(history) do
    if type(record) == "table" then
      local q = include(id)
      if q then q.completed, q.accepted = record.completed == true, record.accepted == true end
    end
  end
  local log = {}
  local Compat = Addon.Compat
  for _, entry in ipairs(Compat and Compat.QuestLogEntries and Compat.QuestLogEntries() or {}) do
    local q = include(entry.id)
    if q then q.inLog = true; log[q.id] = entry end
  end
  local corpus = WordHunterWoWCorpus
  local bucket = type(corpus) == "table" and type(corpus.byLocale) == "table" and corpus.byLocale[locale]
  local flavor = Compat and Compat.GameFlavor() or "retail"
  local corpusTitles = {}
  if type(bucket) == "table" then
    for _, entry in pairs(bucket) do
      if type(entry) == "table" and (entry.kind == "title" or entry.kind == "description" or entry.kind == "objectives"
          or entry.kind == "progress" or entry.kind == "reward" or entry.kind == "completion")
          and (entry.flavor == flavor or (entry.flavor == nil and flavor == "retail")) then
        if scope ~= "my" then include(entry.id) end
        if entry.kind == "title" then corpusTitles[entry.id] = entry.text end
      end
    end
  end
  local function addRecords(rows)
    for id, record in pairs(rows or {}) do if type(record) == "table" then include(id) end end
  end
  if scope ~= "my" then
    addRecords(english); addRecords(localized); addRecords(observed); addRecords(englishObserved)
    for _, source in ipairs(sources) do
      addRecords(source.pack.locales.enUS); addRecords(source.pack.locales[locale])
    end
  end
  local function title(q, row, lang, source)
    if type(row) == "table" and type(row.title) == "string" and row.title ~= "" then
      q.titles[lang], q.titleSources = row.title, q.titleSources or {}
      q.titleSources[lang] = source
    end
  end
  local function row(rows, id) return type(rows) == "table" and (rows[id] or rows[tostring(id)]) end
  local out = {}
  for id, q in pairs(byId) do
    for _, source in ipairs(sources) do
      title(q, row(source.pack.locales.enUS, id), "enUS", "quest source")
      title(q, row(source.pack.locales[locale], id), locale, "quest source")
    end
    title(q, row(english, id), "enUS", "database")
    title(q, row(localized, id), locale, "database")
    if corpusTitles[id] then title(q, { title = corpusTitles[id] }, locale, "collected text") end
    title(q, row(englishObserved, id), "enUS", "observed text")
    title(q, row(observed, id), locale, "observed text")
    local saved = history[id] or history[tostring(id)]
    if type(saved) == "table" and saved.titleLocale and not q.titles[saved.titleLocale] then
      title(q, saved, saved.titleLocale, "quest history")
    end
    title(q, log[id], Addon.TextLocale(), "quest log")
    q.englishTitle, q.localizedTitle = q.titles.enUS or q.titles.enGB, q.titles[locale]
    local unknownTitle = type(saved) == "table" and not saved.titleLocale and saved.title
    q.title = q.localizedTitle or unknownTitle or q.englishTitle or (saved and saved.title) or ("Quest " .. q.idStr)
    q.titleLocale = q.localizedTitle and locale or (not unknownTitle and q.englishTitle and "enUS") or saved and saved.titleLocale
    q.titleSource = q.titleSources and q.titleSources[q.titleLocale] or "quest history"
    q.sortKey = Addon.utf8Lower(q.title)
    q.searchText = Addon.utf8Lower((q.englishTitle or "") .. " " .. (q.localizedTitle or "") .. " " .. q.title)
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
  if filter == "my" then return q.inLog or q.completed end
  return true
end

-- Group by both titles, not by content: variants can differ in NPCs or dialogue.
-- Keep every ID selectable, and prefer a current quest as the group's reader.
local function groupVariants(rows)
  local groups, out = {}, {}
  local function priority(q) return q.inLog and 2 or q.completed and 1 or 0 end
  for _, q in ipairs(rows) do
    local key = (q.englishTitle or q.title) .. "\031" .. (q.localizedTitle or "")
    local group = groups[key]
    if not group then
      group = { members = {}, groupKey = key }
      for field, value in pairs(q) do group[field] = value end
      groups[key], out[#out + 1] = group, group
    elseif priority(q) > priority(group) then
      for field, value in pairs(q) do group[field] = value end
      group.inLog, group.completed, group.accepted = q.inLog, q.completed, q.accepted
    end
    group.members[#group.members + 1] = q
  end
  return out
end
Addon.GroupQuestCatalogVariants = groupVariants

local function paintRows()
  local f = questsFrame
  for _, row in ipairs(questRows) do row:Hide() end
  local width = math.max(300, f:GetWidth() - 62)
  f.questContent:SetWidth(width)
  local y = 0
  local first = (f.page - 1) * PAGE_SIZE + 1
  local last = math.min(#f.filtered, first + PAGE_SIZE - 1)
  local visible = {}
  for index = first, last do
    local group = f.filtered[index]
    visible[#visible + 1] = { item = group }
    if f.expandedGroups[group.groupKey] then
      for _, member in ipairs(group.members) do
        if member.id ~= group.id then visible[#visible + 1] = { item = member, child = true } end
      end
    end
  end
  for poolIndex, entry in ipairs(visible) do
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
      row.name:SetWordWrap(true)
      row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      row.meta:SetPoint("TOPRIGHT", -8, -6)
      row.meta:SetWidth(140)
      row.meta:SetJustifyH("RIGHT")
      row.meta:SetJustifyV("TOP")
      row.meta:SetMaxLines(2)
      row.meta:SetWordWrap(true)
      row.variants = CreateFrame("Button", nil, row)
      row.variants:SetSize(140, 18)
      row.variants:SetPoint("TOPRIGHT", -8, -34)
      row.variants.label = row.variants:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      row.variants.label:SetPoint("RIGHT")
      row.variants:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "BLEND")
      row.variants:GetHighlightTexture():SetVertexColor(0.30, 0.42, 0.55, 0.20)
      row.variants:SetScript("OnClick", function()
        local key = row.item.groupKey
        f.expandedGroups[key] = not f.expandedGroups[key]
        paintRows()
      end)
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
        if self.item.members and #self.item.members > 1 then
          GameTooltip:AddLine("Same-title variants; NPCs or dialogue may differ. Click variants to choose a version.", 0.8, 0.82, 0.88, true)
        end
        GameTooltip:Show()
      end)
      row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
      questRows[poolIndex] = row
    end
    local q = entry.item
    row.item = q
    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT", entry.child and 24 or 8, -6)
    row.name:SetWidth(width - (entry.child and 182 or 166))
    local names = q.englishTitle or q.title
    if q.localizedTitle and q.localizedTitle ~= names then names = names .. "\n" .. q.localizedTitle end
    row.name:SetText(names)
    row.name:SetTextColor(unpack(COLORS.text))
    local state = q.reference and "Source reference" or q.inLog and L.inLog or q.completed and L.completed or q.accepted and L.accepted or L.inDatabase
    local locale = Addon.GetCatalogLocale and Addon.GetCatalogLocale() or Addon.GetTargetLocale()
    local language = q.titleLocale and q.titleLocale ~= locale and " · " .. string.upper(Addon.WH_LANGUAGE_MAP[q.titleLocale] or q.titleLocale) or ""
    row.meta:SetText("#" .. q.idStr .. language .. "  ·  " .. state)
    row.meta:SetTextColor(unpack(q.completed and COLORS.known or q.inLog and COLORS.new or COLORS.muted))
    local variants = q.members and #q.members > 1
    row.variants:SetShown(not not variants)
    if variants then
      row.variants.label:SetText(f.expandedGroups[q.groupKey] and "Hide variants <" or (#q.members .. " variants >"))
    end
    local h = math.max(28, row.name:GetStringHeight() + 12, row.meta:GetStringHeight() + 12)
    if variants then h = math.max(h, 56) end
    row:SetSize(width, h)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -y)
    row:Show()
    y = y + h + 3
  end
  f.questContent:SetHeight(math.max(1, y))
  f.questScroll:UpdateScrollChildRect()
  f.pageLabel:SetText(f.idCount > f.resultCount
    and string.format(L.groupedPage, f.page, f.pageCount, f.resultCount, f.idCount)
    or string.format(L.page, f.page, f.pageCount, f.resultCount))
  f.prevPage:SetEnabled(f.page > 1)
  f.nextPage:SetEnabled(f.page < f.pageCount)
  f.empty:SetText(L.empty)
  if f.resultCount == 0 then f.empty:Show() else f.empty:Hide() end
  f.rows = questRows
end

local function createLibraryWords(f)
  local view = CreateFrame("Frame", nil, f)
  f.wordsView = view
  view:SetPoint("TOPLEFT", 18, -91)
  view:SetPoint("BOTTOMRIGHT", -34, 34)
  view.wordFilter, view.filterButtons = "all", {}
  local label = view:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("TOPLEFT", 0, -7)
  label:SetText("Word / meaning")
  view.search = Addon.createEditBox(view)
  view.search:SetPoint("TOPLEFT", 92, 0)
  view.search:SetPoint("TOPRIGHT", 0, 0)
  view.search:SetText("")
  local timer
  view.search:SetScript("OnTextChanged", function()
    if timer then timer:Cancel() end
    timer = C_Timer.NewTimer(0.15, function()
      if f:IsShown() and f.tab == "words" then Addon.RefreshWordListView(view) end
    end)
  end)
  view.search:SetScript("OnEscapePressed", function() f:Hide() end)
  for index, mode in ipairs({ "all", "new", "learning", "known", "ignored" }) do
    local color = mode == "all" and COLORS.neutral or COLORS[mode]
    local button = Addon.createFlatButton(view, mode == "all" and "All" or Addon.STATUS_LABELS[mode], color)
    button:SetPoint("TOPLEFT", (index - 1) * 88, -39)
    button:SetSize(84, Addon.RoleButtonHeight())
    button:SetScript("OnClick", function()
      view.wordFilter = mode
      Addon.RefreshWordListView(view)
    end)
    view.filterButtons[mode] = button
  end
  view.scroll = CreateFrame("ScrollFrame", nil, view, "UIPanelScrollFrameTemplate")
  view.scroll:SetPoint("TOPLEFT", 0, -79)
  view.scroll:SetPoint("BOTTOMRIGHT", -16, 24)
  if view.scroll.SetClipsChildren then view.scroll:SetClipsChildren(true) end
  view.content = CreateFrame("Frame", nil, view.scroll)
  view.content:SetSize(500, 1)
  view.scroll:SetScrollChild(view.content)
  view.truncated = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  view.truncated:SetPoint("BOTTOMLEFT", 0, 0)
  view.truncated:SetPoint("BOTTOMRIGHT", 0, 0)
  view.truncated:SetJustifyH("LEFT")
  view:Hide()
end

local function refreshView(resetPage)
  local f = questsFrame
  if not f or not f:IsShown() then return end
  local words = f.tab == "words"
  for key, tab in pairs(f.libraryTabs) do
    tab.selected = key == f.tab
    tab:SetChecked(tab.selected)
  end
  f.viewTitle:SetText(({ my = "My quests", all = "All in game quests", words = "Words" })[f.tab])
  f.hint:SetText(words and "Click words · Edit meaning and learning status." or L.hint)
  for _, control in ipairs({ f.searchLabel, f.search, f.questScroll, f.prevPage, f.nextPage, f.pageLabel }) do
    control:SetShown(not words)
  end
  f.wordsView:SetShown(words)
  f.currentOnlyCheck:SetShown(f.tab == "my")
  f.currentOnlyLabel:SetShown(f.tab == "my")
  if words then
    f.note:SetText("Words and vocabulary are saved separately for each language.")
    f.wordsView.wordLocale = Addon.GetCatalogLocale()
    Addon.RefreshWordListView(f.wordsView)
    return
  end
  local query = Addon.utf8Lower(Addon.trim(f.search:GetText()))
  f.filtered = {}
  for _, q in ipairs(catalog) do
    if matchesFilter(q, f.filter) and (not f.currentOnly or f.tab ~= "my" or q.inLog)
        and (query == "" or q.searchText:find(query, 1, true) or q.idStr:find(query, 1, true)) then
      f.filtered[#f.filtered + 1] = q
    end
  end
  f.idCount = #f.filtered
  f.filtered = groupVariants(f.filtered)
  f.resultCount = #f.filtered
  f.pageCount = math.max(1, math.ceil(f.resultCount / PAGE_SIZE))
  f.page = resetPage and 1 or math.max(1, math.min(f.page or 1, f.pageCount))
  f.currentOnlyCheck:SetChecked(f.currentOnly)
  f.note:SetText(f.tab == "my" and "Current quests and IDs marked completed by the game. Same-title variants are grouped."
    or "All stored quests for this game client. Same-title variants are grouped.")
  f.questScroll:SetVerticalScroll(0)
  paintRows()
end

function Addon.refreshQuestBrowser()
  if not questsFrame or not questsFrame:IsShown() then return end
  if questsFrame.tab ~= "words" then catalog = buildCatalog(questsFrame.tab) end
  refreshView(false)
end

function Addon.SetQuestLibraryTab(tab)
  if not questsFrame or (tab ~= "my" and tab ~= "all" and tab ~= "words") then return false end
  questsFrame.tab, questsFrame.filter, questsFrame.page = tab, tab == "my" and "my" or "database", 1
  Addon.refreshQuestBrowser()
  return true
end

function Addon.SetQuestLibraryCurrentOnly(value)
  if not questsFrame then return end
  questsFrame.currentOnly = not not value
  refreshView(true)
end

-- Retain the existing filter API for callers; the library UI uses two tabs.
function Addon.SetQuestCatalogFilter(filter)
  if not questsFrame or not ({ database = true, log = true, completed = true, history = true })[filter] then return end
  questsFrame.tab = filter == "database" and "all" or "my"
  questsFrame.filter, questsFrame.currentOnly = filter, false
  catalog = buildCatalog(questsFrame.tab)
  refreshView(true)
end

local function layout()
  local f = questsFrame
  local previous
  for _, key in ipairs({ "my", "all", "words" }) do
    local tab = f.libraryTabs[key]
    tab:ClearAllPoints()
    if previous then tab:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -6)
    else tab:SetPoint("TOPLEFT", f, "TOPRIGHT", -6, -100) end
    previous = tab
  end
  if f:IsShown() then
    if f.tab == "words" then Addon.RefreshWordListView(f.wordsView) else paintRows() end
  end
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
    f.tab, f.filter, f.page, f.libraryTabs, f.currentOnly = "my", "my", 1, {}, false
    f.expandedGroups = {}
    f.filtered, f.resultCount, f.idCount, f.pageCount = {}, 0, 0, 1
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 18, -14)
    title:SetPoint("TOPRIGHT", -40, -14)
    title:SetText("WORD HUNTER LIBRARY")
    f.catalogTitle = title
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 18, -37)
    hint:SetPoint("TOPRIGHT", -20, -37)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.hint)
    f.hint = hint
    f.viewTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.viewTitle:SetPoint("TOPLEFT", 18, -65)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Hide() end)
    for _, info in ipairs({ { "my", "My quests", "INV_Misc_GroupLooking" },
        { "all", "All in game quests", "INV_Misc_Book_09" }, { "words", "Words", "INV_Inscription_Tradeskill01" } }) do
      local key = info[1]
      local tab = Addon.CreateBookSideTab("Interface\\Icons\\" .. info[3], function() Addon.SetQuestLibraryTab(key) end, f)
      tab:SetFrameLevel(f:GetFrameLevel() + 2)
      tab:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(info[2])
        GameTooltip:Show()
      end)
      tab:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
      f.libraryTabs[key] = tab
    end
    f.currentOnlyCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    f.currentOnlyCheck:SetSize(20, 20)
    f.currentOnlyCheck:SetScript("OnClick", function(self) Addon.SetQuestLibraryCurrentOnly(self:GetChecked()) end)
    f.currentOnlyLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.currentOnlyLabel:SetPoint("TOPRIGHT", -18, -65)
    f.currentOnlyCheck:SetPoint("RIGHT", f.currentOnlyLabel, "LEFT", -2, 0)
    f.currentOnlyLabel:SetText("Show only current quests in quest log")
    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 18, -98)
    label:SetText(L.search)
    f.searchLabel = label
    f.search = Addon.createEditBox(f)
    f.search:SetPoint("TOPLEFT", 110, -91)
    f.search:SetPoint("TOPRIGHT", -20, -91)
    f.search:SetText("")
    local searchTimer
    f.search:SetScript("OnTextChanged", function()
      if searchTimer then searchTimer:Cancel() end
      searchTimer = C_Timer.NewTimer(0.15, function() refreshView(true) end)
    end)
    f.search:SetScript("OnEscapePressed", function() f:Hide() end)
    f.questScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.questScroll:SetPoint("TOPLEFT", 18, -123)
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
    createLibraryWords(f)
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
