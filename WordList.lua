local Addon = WordHunterWoW_Addon
local COLORS = Addon.COLORS
local STATUS_LABELS = Addon.STATUS_LABELS
local LABELS = Addon.LABELS

local listFrame
local listRows = {}
local listFilter = "all"

local function updateListFilters()
  if not listFrame then return end
  for mode, button in pairs(listFrame.filterButtons) do
    local color = mode == "all" and COLORS.neutral or COLORS[mode]
    Addon.styleFlatButton(button, color, listFilter == mode)
  end
end

local function refreshWordList()
  if not listFrame then return end
  local query = Addon.utf8Lower(Addon.trim(listFrame.search:GetText()))
  local hideIgnored = WordHunterWoWDB.settings.hideIgnored == true
  local items = {}
  -- Fold the sort key once per surviving row. Doing it inside the comparator
  -- instead runs it O(n log n) times over a dictionary of ~74k entries.
  Addon.ForEachEffectiveWord(function(key, entry)
    local status = Addon.EffectiveStatus(entry)
    if listFilter ~= "all" and listFilter ~= status then return end
    if listFilter == "all" and hideIgnored and status == "ignored" then return end
    local word = entry.word or key
    local sortKey = Addon.utf8Lower(word)
    if query ~= "" then
      local haystack = sortKey .. " " .. Addon.utf8Lower(entry.translation or "")
      if not haystack:find(query, 1, true) then return end
    end
    items[#items + 1] = { key = key, entry = entry, status = status, sortKey = sortKey }
  end)
  table.sort(items, function(a, b) return a.sortKey < b.sortKey end)
  for _, row in ipairs(listRows) do row:Hide() end
  local y = 0
  for index, item in ipairs(items) do
    if index > 200 then break end
    local row = listRows[index]
    if not row then
      row = CreateFrame("Button", nil, listFrame.content)
      row:SetHeight(22)
      row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      row.name:SetPoint("TOPLEFT", 2, 0)
      row.name:SetJustifyH("LEFT")
      row.name:SetMaxLines(1)
      row.name:SetWordWrap(false)
      row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      row.meta:SetPoint("RIGHT", -2, 0)
      row.meta:SetJustifyH("RIGHT")
      row.meta:SetMaxLines(1)
      row.meta:SetWordWrap(false)
      row:SetScript("OnClick", function(self)
        local entry = self.entry
        Addon.openEditor(entry.word or self.key, entry.context, entry.questId, entry.questTitle)
      end)
      listRows[index] = row
    end
    row.key = item.key
    row.entry = item.entry
    local color = COLORS[item.status] or COLORS.new
    row.name:SetText(item.entry.word or item.key)
    row.name:SetTextColor(color[1], color[2], color[3])
    row.meta:SetText(Addon.trim(item.entry.translation or ""))
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", 0, y)
    row:Show()
    y = y - 23
  end
  listFrame.content:SetHeight(math.max(1, -y + 16))
  listFrame.content:SetWidth(math.max(300, listFrame:GetWidth() - 60))
  listFrame.scroll:UpdateScrollChildRect()
end
Addon.refreshWordList = refreshWordList

function Addon.toggleWordList()
  if not listFrame then
    listFrame = CreateFrame("Frame", "WordHunterWoWList", UIParent, "BackdropTemplate")
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
    Addon.MakeResizable(listFrame, "list", 420, 350, 700, 650)
    do
      local debounce
      listFrame:HookScript("OnSizeChanged", function(self)
        self.content:SetWidth(math.max(300, self:GetWidth() - 60))
        self.scroll:UpdateScrollChildRect()
        if debounce then debounce:Cancel() end
        debounce = C_Timer.NewTimer(0.15, function()
          if self:IsShown() then refreshWordList() end
        end)
      end)
      listFrame.resizeHandle:HookScript("OnMouseUp", function()
        if debounce then debounce:Cancel() end
        if listFrame:IsShown() then refreshWordList() end
      end)
    end
    listFrame:Hide()

    local brand = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    brand:SetPoint("TOPLEFT", 18, -12)
    brand:SetText(LABELS.listTitle)

    local close = CreateFrame("Button", nil, listFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() listFrame:Hide() end)

    local searchLabel = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", 18, -40)
    searchLabel:SetText(LABELS.search)

    listFrame.search = Addon.createEditBox(listFrame)
    listFrame.search:SetPoint("TOPLEFT", 18, -56)
    listFrame.search:SetPoint("TOPRIGHT", -18, -56)
    listFrame.search:SetScript("OnTextChanged", function() refreshWordList() end)
    listFrame.search:SetScript("OnEscapePressed", function()
      Addon.CloseAll()
    end)

    listFrame.filterButtons = {}
    local modes = { "all", "new", "learning", "known", "ignored" }
    for index, mode in ipairs(modes) do
      local color = mode == "all" and COLORS.neutral or COLORS[mode]
      local button = Addon.createFlatButton(
        listFrame,
        mode == "all" and LABELS.all or STATUS_LABELS[mode],
        color
      )
      button:SetSize(64, 22)
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
    listFrame.hideIgnored:SetChecked(WordHunterWoWDB.settings.hideIgnored == true)
    listFrame.hideIgnored:SetScript("OnClick", function(self)
      WordHunterWoWDB.settings.hideIgnored = self:GetChecked() and true or false
      refreshWordList()
    end)

    listFrame.scroll = CreateFrame("ScrollFrame", nil, listFrame, "UIPanelScrollFrameTemplate")
    listFrame.scroll:SetPoint("TOPLEFT", 18, -158)
    listFrame.scroll:SetPoint("BOTTOMRIGHT", -34, 18)
    if listFrame.scroll.SetClipsChildren then listFrame.scroll:SetClipsChildren(true) end
    listFrame.content = CreateFrame("Frame", nil, listFrame.scroll)
    listFrame.content:SetWidth(400)
    listFrame.content:SetHeight(1)
    if listFrame.content.SetClipsChildren then listFrame.content:SetClipsChildren(true) end
    listFrame.scroll:SetScrollChild(listFrame.content)

  end
  if listFrame:IsShown() then
    listFrame:Hide()
  else
    updateListFilters()
    listFrame.hideIgnored:SetChecked(WordHunterWoWDB.settings.hideIgnored == true)
    Addon.PlaceFrame(listFrame, "list")
    refreshWordList()
    listFrame:Show()
    listFrame.scroll:UpdateScrollChildRect()
    C_Timer.After(0, function() listFrame.scroll:UpdateScrollChildRect() end)
  end
end
