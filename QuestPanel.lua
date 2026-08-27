local Addon = WordHunterWoW_Addon
local COLORS = Addon.COLORS
local LABELS = Addon.LABELS

local panel
local wordButtons = {}
local enBits = {}
local TOKEN_H = 18
local TOKEN_STEP = 18

local function tokenFont(fs)
  local path, size, flags = GameFontHighlight:GetFont()
  if path then fs:SetFont(path, size or 12, flags) end
  fs:SetShadowColor(0, 0, 0, 0.9)
  fs:SetShadowOffset(1, -1)
end

local function sentenceForWord(text, word)
  local needle = strlower(word)
  for sentence in tostring(text or ""):gmatch("[^\r\n%.%!%?]+[%.%!%?]?") do
    if strlower(sentence):find(needle, 1, true) then return Addon.trim(sentence) end
  end
  return Addon.trim(text)
end

local function refreshPanel()
  if not panel or not Addon.lastQuest then return end
  local lastQuest = Addon.lastQuest
  panel.title:SetText(lastQuest.title or "Quest")
  for _, button in ipairs(wordButtons) do button:Hide() end

  local integrated = Addon.GetIntegratedLayout and Addon.GetIntegratedLayout() and panel.enScroll and panel.enScroll:IsShown()
  local contentWidth = math.max(200, (integrated and (panel:GetWidth() / 2) or panel:GetWidth()) - 48)
  panel.content:SetWidth(contentWidth)
  if panel.enContent then
    local enWidth = math.max(180, (integrated and (panel:GetWidth() / 2) or panel:GetWidth()) - 48)
    panel.enContent:SetWidth(enWidth)
    local qid = lastQuest.id
    local entry = WordHunterWoW_QuestEN and qid and WordHunterWoW_QuestEN[tonumber(qid)]
    local enTitle = LABELS.englishHeader
    local enBody = "English text is not available for this quest."
    if entry then
      enTitle = entry.title or LABELS.englishHeader
      enBody = entry.description or ""
      if entry.objectives and entry.objectives ~= "" then
        enBody = enBody .. (enBody ~= "" and "\n\n" or "") .. entry.objectives
      end
    end
    panel.enTitle:SetText(enTitle)
    for _, bit in ipairs(enBits) do bit:Hide() end
    local ex, ey, eused = 0, 0, 0
    for token in tostring(enBody):gmatch("%S+") do
      eused = eused + 1
      local bit = enBits[eused]
      if not bit then
        bit = CreateFrame("Frame", nil, panel.enContent)
        bit.text = bit:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        bit.text:SetPoint("CENTER")
        tokenFont(bit.text)
        bit.text:SetTextColor(0.92, 0.92, 0.92)
        bit.text:SetWordWrap(false)
        enBits[eused] = bit
      end
      bit.text:SetText(token)
      local width = math.min(enWidth, math.ceil(bit.text:GetStringWidth()) + 6)
      if ex > 0 and ex + width > enWidth then
        ex = 0
        ey = ey - TOKEN_STEP
      end
      bit:ClearAllPoints()
      bit:SetPoint("TOPLEFT", ex, ey)
      bit:SetSize(width, TOKEN_H)
      bit:Show()
      ex = ex + width + 2
    end
    panel.enContent:SetHeight(math.max(28, -ey + 28))
    panel.enScroll:UpdateScrollChildRect()
  end
  local x, y, used = 0, 0, 0
  local savedCount = 0
  local countedWords = {}
  for token in tostring(lastQuest.text or ""):gmatch("%S+") do
    used = used + 1
    local button = wordButtons[used]
    if not button then
      button = CreateFrame("Button", nil, panel.content)
      button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      button.text:SetPoint("CENTER")
      tokenFont(button.text)
      button.text:SetWordWrap(false)
      button.underline = button:CreateTexture(nil, "ARTWORK")
      button.underline:SetHeight(2)
      button.underline:SetPoint("BOTTOMLEFT", 1, 1)
      button.underline:SetPoint("BOTTOMRIGHT", -1, 1)
      button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      wordButtons[used] = button
    end
    button:SetHeight(TOKEN_H)

    button.text:SetText(token)
    local width = math.min(contentWidth, math.ceil(button.text:GetStringWidth()) + 6)
    if x > 0 and x + width > contentWidth then
      x = 0
      y = y - TOKEN_STEP
    end
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", x, y)
    button:SetWidth(width)
    x = x + width + 2

    local word = Addon.cleanWord(token)
    local key = Addon.wordKey(word)
    local entry = Addon.GetEffectiveWord(key)
    if entry then
      if not countedWords[key] then
        countedWords[key] = true
        savedCount = savedCount + 1
      end
      local color = COLORS[entry.status] or COLORS.new
      button.text:SetTextColor(color[1], color[2], color[3])
      button.underline:SetColorTexture(color[1], color[2], color[3], 0.9)
      button.underline:Show()
    else
      button.text:SetTextColor(0.92, 0.92, 0.92)
      button.underline:Hide()
    end
    button.word = word
    button:SetScript("OnClick", function(self)
      Addon.openEditor(self.word, sentenceForWord(lastQuest.text, self.word), lastQuest.id, lastQuest.title)
    end)
    button:SetEnabled(word ~= "")
    button:Show()
  end
  local contentHeight = math.max(28, -y + 28)
  panel.content:SetHeight(contentHeight)
  panel.scroll:UpdateScrollChildRect()
  panel.meta:SetText(string.format(LABELS.saved, savedCount))
  local hasSavedSize = WordHunterWoWDB and WordHunterWoWDB.settings and WordHunterWoWDB.settings.frames and WordHunterWoWDB.settings.frames["panel"]
  if not hasSavedSize or not hasSavedSize.h then
    panel:SetHeight(math.min(560, math.max(230, contentHeight + 136)))
  end
  if contentHeight < 410 then panel.scroll:SetVerticalScroll(0) end
end
Addon.refreshPanel = refreshPanel

local function trackQuestEncounters(quest)
  local now = time()
  local seen = {}
  local changed = false
  for token in tostring(quest.text or ""):gmatch("%S+") do
    local key = Addon.wordKey(token)
    local item = Addon.GetWordsTable()[key]
    if item and not seen[key] then
      seen[key] = true
      Addon.recordEncounter(item, quest.id, quest.title, now)
      changed = true
    end
  end
  if changed then Addon.rebuildExport() end
end

local function readCurrentQuest(questLogId)
  local questId = GetQuestID and GetQuestID() or 0
  local title = GetTitleText and GetTitleText() or ""
  local description = GetQuestText and GetQuestText() or ""
  local objectives = GetObjectiveText and GetObjectiveText() or ""
  if questLogId and questLogId > 0 and GetQuestLogQuestText then
    questId = questLogId
    local questLogIndex = C_QuestLog.GetLogIndexForQuestID(questId)
    if questLogIndex then
      description, objectives = GetQuestLogQuestText(questLogIndex)
    else
      description, objectives = GetQuestLogQuestText()
    end
    title = C_QuestLog.GetTitleForQuestID(questId) or title
  elseif QuestInfoFrame and QuestInfoFrame.questLog and GetQuestLogQuestText then
    questId = C_QuestLog.GetSelectedQuest() or questId
    description, objectives = GetQuestLogQuestText()
    title = C_QuestLog.GetTitleForQuestID(questId) or title
  end
  local function normalizeQuestText(t)
    t = tostring(t or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    t = t:gsub(">[ \t]*\n[ \t]*(%S)", ">\n\n%1")
    return t
  end
  local desc = normalizeQuestText(description)
  local obj = normalizeQuestText(objectives)
  local text = Addon.trim(desc .. (desc ~= "" and obj ~= "" and "\n\n" or "") .. obj)
  text = text:gsub("\n\n\n+", "\n\n")
  if text == "" and GetProgressText then text = Addon.trim(normalizeQuestText(GetProgressText())) end
  if text == "" and GetRewardText then text = Addon.trim(normalizeQuestText(GetRewardText())) end
  if text == "" then return end
  Addon.lastQuest = { id = questId or 0, title = Addon.trim(title), text = text }
  trackQuestEncounters(Addon.lastQuest)
  refreshPanel()
  if Addon.ApplyIntegratedLayout then Addon.ApplyIntegratedLayout() end
  panel:Show()
end
Addon.readCurrentQuest = readCurrentQuest

local questInfoHooked
local questMapHooked

function Addon.hookQuestUi()
  if not questInfoHooked and type(QuestInfo_ShowDescriptionText) == "function" then
    questInfoHooked = true
    hooksecurefunc("QuestInfo_ShowDescriptionText", function()
      C_Timer.After(0, readCurrentQuest)
    end)
  end
  if not questMapHooked and type(QuestMapFrame_ShowQuestDetails) == "function" then
    questMapHooked = true
    hooksecurefunc("QuestMapFrame_ShowQuestDetails", function()
      C_Timer.After(0, function()
        local questId = QuestMapFrame_GetDetailQuestID and QuestMapFrame_GetDetailQuestID()
        if not questId or questId == 0 then questId = C_QuestLog.GetSelectedQuest() end
        if questId and questId > 0 then
          readCurrentQuest(questId)
        end
      end)
    end)
  end
end

function Addon.createPanel()
  panel = CreateFrame("Frame", "WordHunterWoWFrame", UIParent, "BackdropTemplate")
  Addon.panel = panel
  panel:SetFrameStrata("FULLSCREEN_DIALOG")
  panel:SetFrameLevel(20)
  panel:SetToplevel(true)
  panel:SetClampedToScreen(true)
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    Addon.SaveFramePosition(self, Addon.LayoutKey("panel"))
  end)
  Addon.setBackdrop(panel)
  Addon.SetupEscapeClose(panel)
  local panelDef = Addon.LAYOUT_DEFAULTS.npc.panel
  panel:SetSize(panelDef.w, panelDef.h)
  panel:SetPoint("CENTER", UIParent, "CENTER", -200, 0)
  Addon.MakeResizable(panel, "panel", 400, 230, 1200, 800)
  panel:HookScript("OnSizeChanged", function()
    if panel:IsShown() then refreshPanel() end
  end)
  panel:Hide()

  panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  panel.title:SetPoint("TOPLEFT", 18, -12)
  panel.title:SetPoint("TOPRIGHT", -18, -12)
  panel.title:SetHeight(21)
  panel.title:SetJustifyH("LEFT")
  panel.title:SetMaxLines(1)
  panel.title:SetWordWrap(false)

  panel.meta = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  panel.meta:SetPoint("TOPLEFT", 18, -36)
  panel.meta:SetPoint("TOPRIGHT", -140, -36)
  panel.meta:SetHeight(14)
  panel.meta:SetJustifyH("LEFT")
  panel.meta:SetMaxLines(1)

  local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function()
    panel:Hide()
    if Addon.editor then Addon.editor:Hide() end
  end)

  panel.enTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  panel.enTitle:SetPoint("TOPLEFT", 18, -12)
  panel.enTitle:SetPoint("RIGHT", panel, "CENTER", -12, 0)
  panel.enTitle:SetHeight(21)
  panel.enTitle:SetJustifyH("LEFT")
  panel.enTitle:SetMaxLines(1)
  panel.enTitle:SetWordWrap(false)
  panel.enTitle:SetText(LABELS.englishHeader)

  panel.enScroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  panel.enScroll:SetPoint("TOPLEFT", 18, -40)
  panel.enScroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOM", -20, 72)
  panel.enContent = CreateFrame("Frame", nil, panel.enScroll)
  panel.enContent:SetWidth(360)
  panel.enContent:SetHeight(1)
  panel.enScroll:SetScrollChild(panel.enContent)

  panel.divider = panel:CreateTexture(nil, "ARTWORK")
  panel.divider:SetColorTexture(0.20, 0.30, 0.43, 0.55)
  panel.divider:SetWidth(1)
  panel.divider:SetPoint("TOP", panel, "TOP", 0, -52)
  panel.divider:SetPoint("BOTTOM", panel, "BOTTOM", 0, 72)

  panel.scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  panel.scroll:SetPoint("TOPLEFT", panel, "TOP", 8, -58)
  panel.scroll:SetPoint("BOTTOMRIGHT", -32, 72)
  panel.content = CreateFrame("Frame", nil, panel.scroll)
  panel.content:SetWidth(382)
  panel.content:SetHeight(1)
  panel.scroll:SetScrollChild(panel.content)

  local footerLine = panel:CreateTexture(nil, "ARTWORK")
  footerLine:SetColorTexture(0.20, 0.30, 0.43, 0.55)
  footerLine:SetPoint("BOTTOMLEFT", 18, 67)
  footerLine:SetPoint("BOTTOMRIGHT", -18, 67)
  footerLine:SetHeight(1)

  local statuses = { "new", "learning", "known", "ignored" }
  for index, status in ipairs(statuses) do
    local color = COLORS[status]
    local dot = panel:CreateTexture(nil, "ARTWORK")
    dot:SetColorTexture(color[1], color[2], color[3], 1)
    dot:SetSize(7, 7)
    dot:SetPoint("BOTTOMLEFT", 18 + (index - 1) * 96, 50)
    local legend = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    legend:SetPoint("LEFT", dot, "RIGHT", 5, 0)
    legend:SetText(Addon.STATUS_LABELS[status])
    legend:SetTextColor(0.78, 0.82, 0.88)
  end

  local copyQuest = Addon.createActionButton(panel, LABELS.copyQuest)
  copyQuest:SetSize(118, 26)
  copyQuest:SetPoint("BOTTOMRIGHT", -18, 8)
  copyQuest:SetScript("OnClick", function()
    if Addon.lastQuest then Addon.showCopyText(LABELS.copyQuest, Addon.lastQuest.text) end
  end)

  local wordsBtn = Addon.createActionButton(panel, LABELS.wordsButton)
  wordsBtn:SetSize(52, 26)
  wordsBtn:SetPoint("RIGHT", copyQuest, "LEFT", -6, 0)
  wordsBtn:SetScript("OnClick", function()
    if Addon.listFrame and Addon.listFrame:IsShown() then
      Addon.listFrame:Hide()
    else
      Addon.toggleWordList()
    end
  end)

  local statsBtn = Addon.createActionButton(panel, LABELS.statsButton)
  statsBtn:SetSize(52, 26)
  statsBtn:SetPoint("RIGHT", wordsBtn, "LEFT", -6, 0)
  statsBtn:SetScript("OnClick", function()
    if Addon.statsFrame and Addon.statsFrame:IsShown() then
      Addon.statsFrame:Hide()
    else
      Addon.toggleStats()
    end
  end)

  function Addon.ApplyIntegratedLayout()
    if not panel then return end
    local hasEN = type(WordHunterWoW_QuestEN) == "table"
    local integrated = Addon.GetIntegratedLayout() and hasEN
    if integrated then
      panel.enScroll:Show()
      panel.enTitle:Show()
      panel.divider:Show()
      panel.title:ClearAllPoints()
      panel.title:SetPoint("TOPLEFT", panel, "TOP", 12, -12)
      panel.title:SetPoint("TOPRIGHT", -40, -12)
      panel.meta:ClearAllPoints()
      panel.meta:SetPoint("BOTTOMLEFT", 18, 15)
      panel.scroll:ClearAllPoints()
      panel.scroll:SetPoint("TOPLEFT", panel, "TOP", 8, -36)
      panel.scroll:SetPoint("BOTTOMRIGHT", -32, 72)
      panel.enScroll:ClearAllPoints()
      panel.enScroll:SetPoint("TOPLEFT", 18, -36)
      panel.enScroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOM", -20, 72)
      Addon.PlaceFrame(panel, "panel")
      if Addon.enPanel then Addon.enPanel:Hide() end
    else
      panel.enScroll:Hide()
      panel.enTitle:Hide()
      panel.divider:Hide()
      panel.title:ClearAllPoints()
      panel.title:SetPoint("TOPLEFT", 18, -12)
      panel.title:SetPoint("TOPRIGHT", -18, -12)
      panel.meta:ClearAllPoints()
      panel.meta:SetPoint("TOPLEFT", 18, -36)
      panel.meta:SetPoint("TOPRIGHT", -140, -36)
      panel.scroll:ClearAllPoints()
      panel.scroll:SetPoint("TOPLEFT", 18, -58)
      panel.scroll:SetPoint("BOTTOMRIGHT", -32, 72)
      if panel:GetWidth() > 700 then
        panel:SetSize(430, 240)
      end
    end
     if panel:IsShown() then refreshPanel() end
  end

  Addon.ApplyIntegratedLayout()
end
