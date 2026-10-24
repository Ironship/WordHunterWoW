local Addon = WordHunterWoW_Addon
local COLORS = Addon.COLORS
local STATUS_LABELS = Addon.STATUS_LABELS
local LABELS = Addon.LABELS
local unpack = unpack or table.unpack

local listFrame
local listFilter = "all"
local FILTER_MODES = { "all", "new", "learning", "known", "ignored" }
local ROW_HEIGHT = 23

-- The saved variables are created at ADDON_LOADED, while the slash commands
-- that reach this file are registered as it loads. A /whw typed on the loading
-- screen therefore arrives before there is a settings table to read -- the
-- same fault shape issues.test.lua records as its second entry, in the one
-- remaining place that still read the table straight through.
local function hideIgnoredSetting()
  return type(WordHunterWoWDB) == "table" and type(WordHunterWoWDB.settings) == "table"
    and WordHunterWoWDB.settings.hideIgnored == true
end

local function updateListFilters(view)
  local listFrame = view or listFrame
  local listFilter = view and view.wordFilter or listFilter
  if not listFrame then return end
  for mode, button in pairs(listFrame.filterButtons) do
    local color = mode == "all" and COLORS.neutral or COLORS[mode]
    Addon.styleFlatButton(button, color, listFilter == mode)
  end
end

local function layoutWordListView(listFrame)
  if not listFrame then return end
  if not listFrame:IsShown() then return end
  local listRows = rawget(listFrame, "rows") or {}
  listFrame.rows = listRows
  local items = rawget(listFrame, "wordItems") or {}
  local locale = rawget(listFrame, "wordLocale") or Addon.GetTargetLocale()
  local pageSize = math.max(1, math.floor(listFrame.scroll:GetHeight() / ROW_HEIGHT))
  local oldSize = rawget(listFrame, "wordPageSize") or pageSize
  local page = rawget(listFrame, "wordPage") or 1
  if oldSize ~= pageSize then page = math.floor((page - 1) * oldSize / pageSize) + 1 end
  local pages = math.max(1, math.ceil(#items / pageSize))
  page = math.max(1, math.min(page, pages))
  listFrame.wordPage, listFrame.wordPageSize, listFrame.wordPageCount = page, pageSize, pages
  local filters = {}
  for _, mode in ipairs(FILTER_MODES) do filters[#filters + 1] = listFrame.filterButtons[mode] end
  Addon.SpreadButtons(listFrame, filters, rawget(listFrame, "wordFilterY") or -39,
    rawget(listFrame, "wordListMargin") or 0, 6)
  for _, row in ipairs(listRows) do
    row:Hide()
    row.entry, row.key = nil, nil
  end
  local y = 0
  local first = (page - 1) * pageSize + 1
  for index = 1, math.min(pageSize, #items - first + 1) do
    local key = items[first + index - 1]
    local entry = Addon.GetEffectiveWord(key, locale)
    local item = { key = key, entry = entry, status = Addon.EffectiveStatus(entry) }
    local row = listRows[index]
    if not row then
      row = CreateFrame("Button", nil, listFrame.content)
      row:SetHeight(22)
      row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "BLEND")
      row:GetHighlightTexture():SetVertexColor(0.30, 0.42, 0.55, 0.20)
      row.statusDot = row:CreateTexture(nil, "ARTWORK")
      row.statusDot:SetSize(4, 4)
      row.statusDot:SetPoint("LEFT", 2, 0)
      row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      -- The word itself is the thing this window exists to be read, so it is
      -- body, not label. HighlightSmall stays for the white it brings; only
      -- the size moves, from 10 up to the 12 the quest panel has always drawn
      -- the same word at. The meta beside it stays at 10 -- it is meta.
      Addon.ApplyFontRole(row.name, "body")
      row.name:SetPoint("TOPLEFT", 12, 0)
      row.name:SetPoint("RIGHT", row, "CENTER", -8, 0)
      row.name:SetJustifyH("LEFT")
      row.name:SetMaxLines(1)
      row.name:SetWordWrap(false)
      row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      row.meta:SetPoint("RIGHT", -2, 0)
      row.meta:SetPoint("LEFT", row, "CENTER", 8, 0)
      row.meta:SetTextColor(unpack(COLORS.muted))
      row.meta:SetJustifyH("RIGHT")
      row.meta:SetMaxLines(1)
      row.meta:SetWordWrap(false)
      row:SetScript("OnClick", function(self)
        local entry = self.entry
        Addon.openEditor(entry.word or self.key, entry.context, entry.questId, entry.questTitle, { locale = self.wordLocale })
      end)
      listRows[index] = row
    end
    row.key = item.key
    row.entry = item.entry
    row.wordLocale = locale
    local color = COLORS[item.status] or COLORS.new
    row.name:SetText(item.entry.word or item.key)
    row.name:SetTextColor(unpack(COLORS.text))
    row.statusDot:SetColorTexture(color[1], color[2], color[3], 1)
    row.meta:SetText(Addon.trim(item.entry.translation or ""))
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", 0, y)
    row:Show()
    y = y - ROW_HEIGHT
  end
  listFrame.content:SetHeight(math.max(1, -y))
  -- The library view is already inset; do not subtract window margins again.
  listFrame.content:SetWidth(math.max(1, listFrame.scroll:GetWidth()))
  listFrame.scroll:SetVerticalScroll(0)
  listFrame.scroll:UpdateScrollChildRect()
  if rawget(listFrame, "prevPage") then
    listFrame.prevPage:SetEnabled(page > 1)
    listFrame.nextPage:SetEnabled(page < pages)
    listFrame.truncated:SetText(string.format("Page %d / %d\n%d words", page, pages, #items))
    listFrame.truncated:Show()
  end
end
Addon.LayoutWordListView = layoutWordListView

function Addon.StepWordListPage(view, delta)
  view.wordPage = math.max(1, math.min((rawget(view, "wordPage") or 1) + delta,
    rawget(view, "wordPageCount") or 1))
  if Addon.GamePadUI then Addon.GamePadUI.Clear() end
  layoutWordListView(view)
end

function Addon.SetupWordListView(view, margin, bottom)
  view.wordListMargin = margin
  view.prevPage = Addon.createActionButton(view, LABELS.prevWord)
  view.prevPage:SetSize(80, Addon.RoleButtonHeight())
  view.prevPage:SetPoint("BOTTOMLEFT", margin, bottom)
  view.prevPage:SetScript("OnClick", function() Addon.StepWordListPage(view, -1) end)
  view.nextPage = Addon.createActionButton(view, LABELS.nextWord)
  view.nextPage:SetSize(80, Addon.RoleButtonHeight())
  view.nextPage:SetPoint("BOTTOMRIGHT", -margin, bottom)
  view.nextPage:SetScript("OnClick", function() Addon.StepWordListPage(view, 1) end)
  view.truncated:ClearAllPoints()
  view.truncated:SetPoint("LEFT", view.prevPage, "RIGHT", 8, 0)
  view.truncated:SetPoint("RIGHT", view.nextPage, "LEFT", -8, 0)
  view.truncated:SetJustifyH("CENTER")
  view.scroll:HookScript("OnSizeChanged", function() layoutWordListView(view) end)
  view.scroll:HookScript("OnMouseWheel", function(_, delta)
    if delta ~= 0 then Addon.StepWordListPage(view, delta > 0 and -1 or 1) end
  end)
  view:HookScript("OnHide", function()
    view.wordItems = nil
    for _, row in ipairs(rawget(view, "rows") or {}) do row.entry, row.key = nil, nil end
  end)
end

local function refreshWordListView(listFrame)
  if not listFrame or not listFrame:IsShown() then return end
  if not rawget(listFrame, "prevPage") then Addon.SetupWordListView(listFrame, 0, 0) end
  local mode = rawget(listFrame, "wordFilter") or "all"
  local locale = rawget(listFrame, "wordLocale") or Addon.GetTargetLocale()
  local query = Addon.utf8Lower(Addon.trim(listFrame.search:GetText()))
  local hideIgnored = hideIgnoredSetting()
  if rawget(listFrame, "lastWordQuery") ~= query or rawget(listFrame, "lastWordFilter") ~= mode
      or rawget(listFrame, "lastWordLocale") ~= locale or rawget(listFrame, "lastHideIgnored") ~= hideIgnored then
    listFrame.wordPage = 1
  end
  listFrame.lastWordQuery, listFrame.lastWordFilter = query, mode
  listFrame.lastWordLocale, listFrame.lastHideIgnored = locale, hideIgnored
  updateListFilters(listFrame)
  -- Keep only existing keys; resolve the handful of visible entries at paint time.
  local items = {}
  Addon.ForEachEffectiveWord(function(key, entry)
    local status = Addon.EffectiveStatus(entry)
    if mode ~= "all" and mode ~= status then return end
    if mode == "all" and hideIgnored and status == "ignored" then return end
    if query ~= "" then
      local haystack = Addon.utf8Lower((entry.word or key) .. " " .. (entry.translation or ""))
      if not haystack:find(query, 1, true) then return end
    end
    items[#items + 1] = key
  end, locale)
  -- Keys are already casefolded by wordKey, including umlauts and eszett.
  table.sort(items)
  listFrame.wordItems = items
  layoutWordListView(listFrame)
end
Addon.RefreshWordListView = refreshWordListView
local function refreshWordList()
  if listFrame then
    listFrame.wordFilter = listFilter
    refreshWordListView(listFrame)
  end
  local library = Addon.questsFrame
  if library and library:IsShown() and library.tab == "words" then refreshWordListView(library.wordsView) end
end
Addon.refreshWordList = refreshWordList

function Addon.toggleWordList()
  if not listFrame then
    listFrame = Addon.CreateNativeWindow("WordHunterWoWList", "library", LABELS.wordsTitle or "Word Hunter - Words")
    Addon.listFrame = listFrame
    listFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    listFrame:SetFrameLevel(22)
    listFrame:SetClampedToScreen(true)
    listFrame:SetMovable(true)
    listFrame:EnableMouse(true)
    listFrame:RegisterForDrag("LeftButton")
    listFrame:SetScript("OnDragStart", listFrame.StartMoving)
    listFrame:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      Addon.SaveFramePosition(self, Addon.LayoutKey("list"))
    end)
    if listFrame.SetClipsChildren then listFrame:SetClipsChildren(true) end
    Addon.setBackdrop(listFrame)
    Addon.SetupEscapeClose(listFrame)
    Addon.PlaceFrame(listFrame, "list")
    Addon.ApplyWindowScale("listScale")
    Addon.MakeResizable(listFrame, "list", 420, 350, 700, 650)
    listFrame:Hide()

    local brand = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    brand:SetPoint("TOPLEFT", 18, -12)
    brand:SetText(LABELS.listTitle)
    if rawget(listFrame, 'whwNativeStyle') then brand:Hide() end

    local close = Addon.NativeCloseButton(listFrame)
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() listFrame:Hide() end)

    local searchLabel = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", 18, -40)
    searchLabel:SetText(LABELS.search)

    listFrame.search = Addon.CreateSearchBox(listFrame)
    listFrame.search:SetPoint("TOPLEFT", 18, -56)
    listFrame.search:SetPoint("TOPRIGHT", -18, -56)
    -- Search changes the results; resizing only lays out the current page.
    do
      local debounce
      Addon.SetSearchChanged(listFrame.search, function(self)
        if debounce then debounce:Cancel() end
        debounce = C_Timer.NewTimer(0.15, function()
          -- The box can be gone, or the panel closed, by the time this fires.
          if listFrame:IsShown() then refreshWordList() end
        end)
      end)
    end
    listFrame.search:SetScript("OnEscapePressed", function()
      Addon.CloseAll()
    end)

    listFrame.filterButtons = {}
    listFrame.wordFilterY = -94
    for index, mode in ipairs(FILTER_MODES) do
      local color = mode == "all" and COLORS.neutral or COLORS[mode]
      local button = Addon.createFlatButton(
        listFrame,
        mode == "all" and LABELS.all or STATUS_LABELS[mode],
        color
      )
      button:SetSize(64, Addon.RoleButtonHeight())
      button:SetPoint("TOPLEFT", 18 + (index - 1) * 68, -94)
      button.mode = mode
      button:SetScript("OnClick", function(self)
        listFilter = self.mode
        updateListFilters()
        refreshWordList()
      end)
      listFrame.filterButtons[mode] = button
    end

    listFrame.hideIgnored = CreateFrame("CheckButton", "WordHunterWoWHideIgnored", listFrame, "UICheckButtonTemplate")
    listFrame.hideIgnored:SetPoint("TOPLEFT", 16, -124)
    listFrame.hideIgnored:SetHitRectInsets(0, -80, 0, 0)
    _G[listFrame.hideIgnored:GetName() .. "Text"]:SetText(LABELS.hideIgnored)
    listFrame.hideIgnored:SetChecked(hideIgnoredSetting())
    listFrame.hideIgnored:SetScript("OnClick", function(self)
      local on = self:GetChecked() and true or false
      if type(WordHunterWoWDB) == "table" and type(WordHunterWoWDB.settings) == "table" then
        WordHunterWoWDB.settings.hideIgnored = on
      end
      refreshWordList()
    end)

    listFrame.scroll = Addon.CreateStyledScrollFrame(listFrame)
    listFrame.truncated = listFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    listFrame.truncated:SetPoint("BOTTOMLEFT", 18, 8)
    listFrame.truncated:SetPoint("BOTTOMRIGHT", -34, 8)
    listFrame.truncated:SetJustifyH("LEFT")
    listFrame.truncated:Hide()

    listFrame.scroll:SetPoint("TOPLEFT", 18, -158)
    -- Keep the content inset clear of the page controls below it.
    listFrame.scroll:SetPoint("BOTTOMRIGHT", -34, 56)
    listFrame.contentInset = Addon.CreateContentInset(listFrame, listFrame.scroll)
    if listFrame.scroll.SetClipsChildren then listFrame.scroll:SetClipsChildren(true) end
    listFrame.content = CreateFrame("Frame", nil, listFrame.scroll)
    listFrame.content:SetWidth(400)
    listFrame.content:SetHeight(1)
    if listFrame.content.SetClipsChildren then listFrame.content:SetClipsChildren(true) end
    listFrame.scroll:SetScrollChild(listFrame.content)
    Addon.SetupWordListView(listFrame, 18, 12)
    if Addon.WindowInputHint then
      local inputHint = Addon.WindowInputHint(listFrame)
      Addon.WatchInputHints(listFrame, function()
        local padding = Addon.GamePadHintsEnabled() and math.max(36, inputHint:GetStringHeight() + 8) or 0
        listFrame.scroll:SetPoint("BOTTOMRIGHT", -34, 56 + padding)
        listFrame.prevPage:SetPoint("BOTTOMLEFT", 18, 12 + padding)
        listFrame.nextPage:SetPoint("BOTTOMRIGHT", -18, 12 + padding)
      end)
    end
  end
  if listFrame:IsShown() then
    listFrame:Hide()
  else
    updateListFilters()
    listFrame.hideIgnored:SetChecked(hideIgnoredSetting())
    Addon.PlaceFrame(listFrame, "list")
    -- Show first, then fill. The refresh declines to work on a hidden window --
    -- that is what stops a closed list from walking the dictionary on every
    -- save -- so refreshing before Show left the list empty on opening.
    listFrame:Show()
    refreshWordList()
    listFrame.scroll:UpdateScrollChildRect()
    C_Timer.After(0, function() listFrame.scroll:UpdateScrollChildRect() end)
  end
end
