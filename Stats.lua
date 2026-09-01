local Addon = WordHunterWoW_Addon
local COLORS = Addon.COLORS
local STATUS_LABELS = Addon.STATUS_LABELS
local LABELS = Addon.LABELS

local statsFrame

local function computeStats(now)
  local total = 0
  local byStatus = { new = 0, learning = 0, known = 0, ignored = 0 }
  local readyForKnown, added7, added30 = 0, 0, 0
  local top = {}
  Addon.ForEachEffectiveWord(function(_, entry)
    total = total + 1
    local status = Addon.EffectiveStatus(entry)
    byStatus[status] = (byStatus[status] or 0) + 1
    if status == "learning" then
      local learningSince = entry.statusChangedAt or entry.firstSeenAt or now
      if (entry.encounterCount or 0) >= 5 and now - learningSince >= 14 * 24 * 60 * 60 then
        readyForKnown = readyForKnown + 1
      end
    end
    local first = entry.firstSeenAt or entry.updatedAt or 0
    if now - first <= 7 * 24 * 60 * 60 then added7 = added7 + 1 end
    if now - first <= 30 * 24 * 60 * 60 then added30 = added30 + 1 end
    -- Keep only the five best seen so far, rather than every entry. The old
    -- version appended all of them -- the whole shipped dictionary, ~74,000 --
    -- and sorted the lot to take five, which is a visible hitch every time the
    -- window is opened. An insertion into a five-slot list costs nothing.
    local count = entry.encounterCount or 0
    if #top < 5 or count > (top[#top].encounterCount or 0) then
      local at = #top + 1
      for i = 1, #top do
        if count > (top[i].encounterCount or 0) then at = i break end
      end
      table.insert(top, at, entry)
      if #top > 5 then table.remove(top) end
    end
  end)
  local best = top
  return {
    total = total,
    byStatus = byStatus,
    readyForKnown = readyForKnown,
    added7 = added7,
    added30 = added30,
    top = best,
  }
end

function Addon.toggleStats()
  if not statsFrame then
    statsFrame = CreateFrame("Frame", "WordHunterWoWStats", UIParent, "BackdropTemplate")
    Addon.statsFrame = statsFrame
    statsFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    statsFrame:SetFrameLevel(22)
    statsFrame:SetClampedToScreen(true)
    statsFrame:SetMovable(true)
    statsFrame:EnableMouse(true)
    statsFrame:RegisterForDrag("LeftButton")
    statsFrame:SetScript("OnDragStart", statsFrame.StartMoving)
    statsFrame:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      Addon.SaveFramePosition(self, Addon.LayoutKey("stats"))
    end)
    Addon.setBackdrop(statsFrame)
    Addon.SetupEscapeClose(statsFrame)
    Addon.PlaceFrame(statsFrame, "stats")
    Addon.MakeResizable(statsFrame, "stats", 340, 380, 650, 700)
    statsFrame:Hide()

    local brand = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    brand:SetPoint("TOPLEFT", 18, -12)
    brand:SetText(LABELS.statsTitle)

    local close = CreateFrame("Button", nil, statsFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() statsFrame:Hide() end)

    statsFrame.summary = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    statsFrame.summary:SetPoint("TOPLEFT", 18, -42)
    statsFrame.summary:SetPoint("TOPRIGHT", -18, -42)
    statsFrame.summary:SetJustifyH("LEFT")

    statsFrame.statusRows = {}
    local statuses = { "new", "learning", "known", "ignored" }
    for index, status in ipairs(statuses) do
      local y = -66 - (index - 1) * 32
      local group = CreateFrame("Frame", nil, statsFrame)
      group:SetPoint("TOPLEFT", 0, y)
      group:SetSize(340, 26)
      local dot = group:CreateTexture(nil, "ARTWORK")
      dot:SetColorTexture(COLORS[status][1], COLORS[status][2], COLORS[status][3], 1)
      dot:SetSize(8, 8)
      dot:SetPoint("TOPLEFT", 18, -2)
      local label = group:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      label:SetPoint("LEFT", dot, "RIGHT", 8, 0)
      label:SetText(STATUS_LABELS[status])
      label:SetTextColor(0.78, 0.82, 0.88)
      local value = group:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      value:SetPoint("TOPRIGHT", -18, -2)
      value:SetTextColor(COLORS[status][1], COLORS[status][2], COLORS[status][3])
      local barBg = group:CreateTexture(nil, "BACKGROUND")
      barBg:SetColorTexture(0.12, 0.16, 0.22, 1)
      barBg:SetPoint("BOTTOMLEFT", 18, 0)
      barBg:SetSize(304, 3)
      local bar = group:CreateTexture(nil, "ARTWORK")
      bar:SetColorTexture(COLORS[status][1], COLORS[status][2], COLORS[status][3], 0.85)
      bar:SetPoint("LEFT", barBg, "LEFT")
      bar:SetSize(0, 3)
      statsFrame.statusRows[status] = { value = value, bar = bar }
    end

    local divider1 = statsFrame:CreateTexture(nil, "ARTWORK")
    divider1:SetColorTexture(0.20, 0.30, 0.43, 0.55)
    divider1:SetPoint("TOPLEFT", 18, -196)
    divider1:SetPoint("TOPRIGHT", -18, -196)
    divider1:SetHeight(1)

    statsFrame.extraRows = {}
    local extras = {
      { key = "readyForKnown", label = LABELS.readyForKnown },
      { key = "added7", label = LABELS.added7 },
      { key = "added30", label = LABELS.added30 },
    }
    for index, extra in ipairs(extras) do
      local y = -208 - (index - 1) * 20
      local label = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      label:SetPoint("TOPLEFT", 18, y)
      label:SetText(extra.label)
      local value = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      value:SetPoint("TOPRIGHT", -18, y)
      statsFrame.extraRows[extra.key] = value
    end

    local divider2 = statsFrame:CreateTexture(nil, "ARTWORK")
    divider2:SetColorTexture(0.20, 0.30, 0.43, 0.55)
    divider2:SetPoint("TOPLEFT", 18, -272)
    divider2:SetPoint("TOPRIGHT", -18, -272)
    divider2:SetHeight(1)

    local mostLabel = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mostLabel:SetPoint("TOPLEFT", 18, -282)
    mostLabel:SetText(LABELS.mostEncountered)

    statsFrame.topRows = {}
    for index = 1, 5 do
      local y = -300 - (index - 1) * 20
      local name = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      name:SetPoint("TOPLEFT", 18, y)
      name:SetPoint("TOPRIGHT", -70, y)
      name:SetJustifyH("LEFT")
      name:SetMaxLines(1)
      name:SetWordWrap(false)
      local value = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      value:SetPoint("TOPRIGHT", -18, y)
      statsFrame.topRows[index] = { name = name, value = value }
    end
  end
  if statsFrame:IsShown() then
    statsFrame:Hide()
  else
    local now = time()
    local stats = computeStats(now)
    statsFrame.summary:SetText(string.format(LABELS.statsSummary, stats.total))
    local maxStatus = 1
    for _, count in pairs(stats.byStatus) do
      if count > maxStatus then maxStatus = count end
    end
    for status, row in pairs(statsFrame.statusRows) do
      local count = stats.byStatus[status] or 0
      row.value:SetText(tostring(count))
      row.bar:SetWidth(math.floor((count / maxStatus) * 302))
    end
    statsFrame.extraRows.readyForKnown:SetText(tostring(stats.readyForKnown))
    statsFrame.extraRows.added7:SetText(tostring(stats.added7))
    statsFrame.extraRows.added30:SetText(tostring(stats.added30))
    for index, row in ipairs(statsFrame.topRows) do
      local entry = stats.top[index]
      if entry then
        local color = COLORS[entry.status or "new"] or COLORS.new
        row.name:SetText(entry.word or "")
        row.name:SetTextColor(color[1], color[2], color[3])
        row.value:SetText(string.format("%d quests", entry.encounterCount or 0))
      else
        row.name:SetText("")
        row.value:SetText("")
      end
    end
    Addon.PlaceFrame(statsFrame, "stats")
    statsFrame:Show()
    statsFrame:Raise()
  end
end
