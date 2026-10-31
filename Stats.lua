local Addon = WordHunterWoW_Addon
local COLORS = Addon.COLORS
local STATUS_LABELS = Addon.STATUS_LABELS
local LABELS = Addon.LABELS

LABELS.statsTabOverview = "Overview"
LABELS.statsTabGrowth = "Growth"
LABELS.statsTabForecast = "Forecast"
LABELS.statsTabRecall = "Recall"
LABELS.statsKnownTrend = "Known words"
LABELS.statsKnownTrendNote = "so far, and at the recent pace"
LABELS.statsMarkedPerDay = "Marked Known per day"
LABELS.statsVocabulary = "Vocabulary over time"
LABELS.statsByStatusNote = "coloured by what the word is now"
LABELS.statsForecastTitle = "Ready for Known, next 30 days"
LABELS.statsHorizonTitle = "Learning words, ready within"
LABELS.statsNextReady = "Next to be ready"
LABELS.statsRatingsPerDay = "Recall ratings per day"
LABELS.statsRatingSpread = "How the ratings were given"
LABELS.statsHardest = "Hardest words"
LABELS.statsNoDifficult = "None yet"
LABELS.statsNoData = "Nothing to show yet"
LABELS.statsNoKnown = "No word is marked Known yet"
LABELS.statsToday = "today"
LABELS.statsNow = "now"
LABELS.statsEstimate = "Estimate"

local DAY = 24 * 60 * 60
local HISTORY_DAYS = 90
local RECENT_DAYS = 30
-- How far ahead the Known count is carried at its recent pace, and how far the
-- readiness forecast looks.
local PROJECT_DAYS = 30
local FORECAST_DAYS = 30
-- The same fourteen days the editor waits before it offers Known.
local READY_AFTER_DAYS = 14

local STACK_ORDER = { "known", "learning", "new", "ignored" }
local ROW_ORDER = { "new", "learning", "known", "ignored" }
-- Bottom to top in the stacked bars: what is settled at the foot, the rest above.
local CHART_ORDER = { "known", "learning", "ignored", "new" }

local WEAK = { 0.93, 0.42, 0.38 }
local MUTED = { 0.55, 0.60, 0.68 }
-- Where a Learning word is expected to be ready, as "within N days". The last
-- bucket, past the table, is everything later and everything with no sign yet.
local HORIZONS = {
  { days = 0, label = "Now", title = "Ready now" },
  { days = 7, label = "1 week", title = "Ready within a week" },
  { days = 30, label = "1 month", title = "Ready within a month" },
  { days = 90, label = "3 months", title = "Ready within 3 months" },
  { days = 180, label = "6 months", title = "Ready within 6 months" },
  { days = 365, label = "1 year", title = "Ready within a year" },
}

local TILE_HEIGHT = 46

-- The parts of the window drawn in a theme colour, so a theme change reaches
-- them the next time the window opens. Charts do their own in Charts.lua.
local themed = {}

-- `ground` marks a card's ground, which the stone themes draw as stone, and
-- `quiet` a rule that the stone themes leave out because a plate says it already.
local function themedTexture(texture, role, scale, ground, quiet)
  themed[#themed + 1] = { texture = texture, role = role, scale = scale, ground = ground, quiet = quiet }
  return texture
end

local plates = {}
local hints = {}

local headings = {}

local function themedHeading(fs)
  headings[#headings + 1] = fs
  return fs
end

local function applyTheme()
  local theme = Addon.ChartTheme()
  for _, item in ipairs(themed) do
    if item.ground then
      Addon.Kit.Ground(item.texture, theme, item.role)
    else
      local c = theme[item.role]
      local hidden = item.quiet and theme.kit == "stone" and Addon.Kit.CanPlate()
      item.texture:SetColorTexture(c[1], c[2], c[3], hidden and 0 or (c[4] or 1) * (item.scale or 1))
    end
  end
  local onPlate = false
  for _, plate in ipairs(plates) do onPlate = Addon.Kit.PaintPlate(plate, theme) end
  -- Grey text is for a plain ground; on the plate it is the cream of the game's own captions.
  for _, hint in ipairs(hints) do
    if onPlate then hint:SetTextColor(0.82, 0.78, 0.66) else hint:SetTextColor(0.5, 0.5, 0.5) end
  end
  for _, fs in ipairs(headings) do fs:SetTextColor(theme.head[1], theme.head[2], theme.head[3]) end
  Addon.RecolorOutlines()
end

local statsFrame

local function startOfDay(now)
  local parts = date("*t", now)
  parts.hour, parts.min, parts.sec, parts.isdst = 0, 0, 0, nil
  return time(parts)
end

-- How many whole days before today a moment falls: 0 for today, 1 for
-- yesterday. A moment from the future (a clock that was set back) is today.
local function dayOffset(moment, today)
  if moment >= today then return 0 end
  return math.ceil((today - moment) / DAY)
end

local function dayText(stats, offset, full)
  return date(full and "%d.%m.%Y" or "%d.%m", stats.today - offset * DAY + DAY / 2)
end

local function emptyCounts()
  return { new = 0, learning = 0, known = 0, ignored = 0 }
end

-- A span of days as a person says it.
local function spanText(days)
  if days < 60 then return string.format("%d d", math.max(1, math.ceil(days))) end
  if days < 700 then return string.format("%d mo", math.floor(days / 30.4 + 0.5)) end
  return string.format("%.1f yr", days / 365)
end

-- The next round figure above the Known count, to aim at.
local function nextMilestone(known)
  local step = known < 500 and 50 or (known < 2000 and 100 or (known < 5000 and 250 or 500))
  return (math.floor(known / step) + 1) * step
end

-- Everything the four pages draw, from one walk over the words and one over the
-- recall rows. Nothing is kept per word: the walk goes over the whole shipped
-- dictionary too (tens of thousands of entries) and only the player's own words
-- count, so each is folded into counters as it goes by.
local function computeStats(now)
  local today = startOfDay(now)
  local readyAfter = Addon.GetReadyAfter and Addon.GetReadyAfter() or 5
  local stats = {
    now = now, today = today, readyAfter = readyAfter,
    total = 0, byStatus = emptyCounts(),
    readyForKnown = 0, added7 = 0, added30 = 0,
    addedByDay = {}, base = emptyCounts(), oldestAdded = 0,
    knownByDay = {}, oldestKnown = 0,
    forecastMet = {}, forecastEstimated = {}, forecastLater = 0,
    horizon = {}, top = {}, nextReady = {},
  }
  for offset = 0, HISTORY_DAYS - 1 do
    stats.addedByDay[offset] = emptyCounts()
    stats.knownByDay[offset] = 0
  end
  for offset = 0, FORECAST_DAYS do
    stats.forecastMet[offset], stats.forecastEstimated[offset] = 0, 0
  end
  for index = 1, #HORIZONS + 1 do stats.horizon[index] = { met = 0, guessed = 0 } end

  local top = stats.top
  Addon.ForEachEffectiveWord(function(key, entry, isDictionary)
    if isDictionary then return end
    local status = Addon.EffectiveStatus(entry)
    stats.total = stats.total + 1
    stats.byStatus[status] = (stats.byStatus[status] or 0) + 1
    local count = entry.encounterCount or 0

    local first = entry.firstSeenAt or entry.updatedAt or 0
    if now - first <= 7 * DAY then stats.added7 = stats.added7 + 1 end
    if now - first <= 30 * DAY then stats.added30 = stats.added30 + 1 end
    local day = first > 0 and dayOffset(first, today) or HISTORY_DAYS
    if day < HISTORY_DAYS then
      if day > stats.oldestAdded then stats.oldestAdded = day end
      local bucket = stats.addedByDay[day]
      bucket[status] = (bucket[status] or 0) + 1
    else
      stats.base[status] = (stats.base[status] or 0) + 1
    end

    if status == "known" then
      local changed = entry.statusChangedAt or entry.updatedAt or first
      if changed > 0 then
        local offset = dayOffset(changed, today)
        if offset < HISTORY_DAYS then stats.knownByDay[offset] = stats.knownByDay[offset] + 1 end
        if offset > stats.oldestKnown then stats.oldestKnown = offset end
      end
    elseif status == "learning" then
      -- The same chain the editor reads, and it has to stay the same one: the
      -- editor offers Known from `statusChangedAt or updatedAt`, and this
      -- counted from `statusChangedAt or firstSeenAt`. For an entry the build
      -- that wrote it gave no statusChangedAt, those are two different
      -- fourteen-day marks, and the page said "3 ready" over a list the editor
      -- offered on eleven of them. A bug with no error attached.
      local since = entry.statusChangedAt or entry.updatedAt or entry.firstSeenAt or now
      -- The same two conditions the editor uses, and they have to stay the same
      -- two: this count is the header of a page whose rows the editor labels
      -- one at a time. Both read the setting rather than a five written twice.
      local enough = count >= readyAfter
      if enough and now - since >= READY_AFTER_DAYS * DAY then
        stats.readyForKnown = stats.readyForKnown + 1
      end

      -- When it will be ready. The waiting time is known; the quests are not,
      -- so a word still short of them is placed by how often it has turned up
      -- since it was first met, and drawn lighter for it being a guess.
      local waiting = math.max(0, math.ceil((since + READY_AFTER_DAYS * DAY - now) / DAY))
      local ready
      local guessed = not enough
      if enough then
        ready = waiting
      else
        local met = first > 0 and first or now
        local rate = count / math.max(1, (now - met) / DAY)
        if rate > 0 then
          ready = math.max(waiting, math.ceil((readyAfter - count) / rate))
        end
      end
      if ready and ready <= FORECAST_DAYS then
        local list = guessed and stats.forecastEstimated or stats.forecastMet
        list[ready] = list[ready] + 1
      else
        stats.forecastLater = stats.forecastLater + 1
      end

      -- The three that will be ready soonest, once not already: what is worth
      -- keeping an eye on. A five-slot-style insertion, not a list of them all.
      if ready and ready > 0 then
        local list = stats.nextReady
        if #list < 3 or ready < list[#list].ready then
          local at = #list + 1
          for i = 1, #list do
            if ready < list[i].ready or (ready == list[i].ready and count > list[i].count) then at = i break end
          end
          table.insert(list, at, { word = entry.word or key, ready = ready, count = count, guessed = guessed })
          if #list > 3 then table.remove(list) end
        end
      end

      -- The same estimate, over a longer view than the thirty days.
      local at = #HORIZONS + 1
      if ready then
        for index, horizon in ipairs(HORIZONS) do
          if ready <= horizon.days then at = index break end
        end
      end
      local slot = stats.horizon[at]
      if guessed then slot.guessed = slot.guessed + 1 else slot.met = slot.met + 1 end
    end

    -- Keep only the five best seen so far, rather than every entry. The old
    -- version appended all of them -- the whole shipped dictionary, ~74,000 --
    -- and sorted the lot to take five, which is a visible hitch every time the
    -- window is opened. An insertion into a five-slot list costs nothing.
    if #top < 5 or count > (top[#top].encounterCount or 0) then
      local at = #top + 1
      for i = 1, #top do
        if count > (top[i].encounterCount or 0) then at = i break end
      end
      table.insert(top, at, entry)
      if #top > 5 then table.remove(top) end
    end
  end)

  -- The pace the Known count has kept lately, over the days there are data for:
  -- a profile three days old has not had thirty days to average over.
  local gained, gained7 = 0, 0
  for offset = 0, RECENT_DAYS - 1 do
    gained = gained + stats.knownByDay[offset]
    if offset < 7 then gained7 = gained7 + stats.knownByDay[offset] end
  end
  stats.knownGained30, stats.knownGained7 = gained, gained7
  -- How many days the pace stands on: a profile ten days old has ten.
  stats.paceDays = math.max(1, math.min(RECENT_DAYS, stats.oldestKnown + 1))
  stats.knownRate = gained / stats.paceDays
  stats.knownRate7 = gained7 / math.min(7, stats.paceDays)
  stats.known = stats.byStatus.known or 0

  local met7, met30 = 0, 0
  for offset = 0, FORECAST_DAYS do
    local n = stats.forecastMet[offset] + stats.forecastEstimated[offset]
    if offset <= 7 then met7 = met7 + n end
    met30 = met30 + n
  end
  stats.readyWithin7, stats.readyWithin30 = met7, met30

  local recall = { byDay = {}, byScore = { 0, 0, 0, 0, 0 }, total = 0, sum = 0, words = 0 }
  for offset = 0, RECENT_DAYS - 1 do recall.byDay[offset] = { weak = 0, mid = 0, good = 0 } end
  for _, row in pairs(Addon.GetRecallTable()) do
    if type(row) == "table" and type(row.ratings) == "table" then
      local rated = false
      for _, rating in ipairs(row.ratings) do
        local score = type(rating) == "table" and tonumber(rating.score)
        if score and score >= 1 and score <= 5 then
          score = math.floor(score + 0.5)
          rated = true
          recall.total = recall.total + 1
          recall.sum = recall.sum + score
          recall.byScore[score] = recall.byScore[score] + 1
          local at = tonumber(rating.at)
          if at then
            local offset = dayOffset(at, today)
            if offset < RECENT_DAYS then
              local key = score <= 2 and "weak" or (score == 3 and "mid" or "good")
              recall.byDay[offset][key] = recall.byDay[offset][key] + 1
            end
          end
        end
      end
      if rated then recall.words = recall.words + 1 end
    end
  end
  stats.recall = recall
  -- Counted off the recall rows, not in the walk above: there are a few
  -- hundred of those at most, against the dictionary's tens of thousands.
  stats.hardest = Addon.DifficultWords and Addon.DifficultWords() or {}
  stats.difficult = #stats.hardest
  return stats
end

-- ---------------------------------------------------------------------------
-- Building blocks

local function text(parent, template, x, y, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", template)
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

local function heading(page, label, y, hint)
  local plate = page:CreateTexture(nil, "BACKGROUND", nil, 1)
  plate:SetPoint("TOPLEFT", page, "TOPLEFT", 12, y + 5)
  plate:SetPoint("TOPRIGHT", page, "TOPRIGHT", -14, y + 5)
  plate:SetHeight(24)
  plates[#plates + 1] = plate
  local fs = themedHeading(text(page, "GameFontNormal", 22, y))
  fs:SetText(label)
  if hint then
    local sub = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("BOTTOMLEFT", fs, "BOTTOMRIGHT", 8, 1)
    sub:SetText(hint)
    hints[#hints + 1] = sub
    fs.hint = sub
  end
  return fs
end

-- The plate for a heading whose text sits `bottom` units up from the foot.
local function footPlate(page, bottom)
  local plate = page:CreateTexture(nil, "BACKGROUND", nil, 1)
  plates[#plates + 1] = plate
  plate:SetHeight(24)
  plate:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 12, bottom - 5)
  plate:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -14, bottom - 5)
  return plate
end

local function divider(page, y)
  local line = themedTexture(page:CreateTexture(nil, "ARTWORK"), "rule", nil, false, true)
  line:SetPoint("TOPLEFT", 18, y)
  line:SetPoint("TOPRIGHT", -18, y)
  line:SetHeight(1)
end

local function note(page, y, lines)
  local fs = text(page, "GameFontDisableSmall", 18, y)
  fs:SetPoint("TOPRIGHT", -18, y)
  fs:SetWordWrap(true)
  fs:SetJustifyV("TOP")
  fs:SetHeight(lines * 13)
  return fs
end

-- A line of text held to the foot of the page, `bottom` units up from it.
local function footLine(page, bottom, lines, template)
  local fs = page:CreateFontString(nil, "OVERLAY", template or "GameFontDisableSmall")
  fs:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 18, bottom)
  fs:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -18, bottom)
  fs:SetJustifyH("LEFT")
  fs:SetJustifyV("BOTTOM")
  fs:SetWordWrap(lines > 1)
  fs:SetHeight(lines * 13)
  return fs
end

-- A chart of a fixed height, or with `bottom` given one that takes whatever
-- height the page has left above that many units from its foot.
local function chartAt(page, y, height, options, bottom)
  options = options or {}
  if not bottom then options.height = height end
  local chart = Addon.CreateBarChart(page, options)
  chart:SetPoint("TOPLEFT", page, "TOPLEFT", 12, y)
  chart:SetPoint("TOPRIGHT", page, "TOPRIGHT", -14, y)
  if bottom then
    chart:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 12, bottom)
    chart:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -14, bottom)
  end
  return chart
end

local function legendAt(page, y)
  local legend = Addon.CreateChartLegend(page)
  legend:SetPoint("TOPLEFT", page, "TOPLEFT", 18, y)
  legend:SetPoint("TOPRIGHT", page, "TOPRIGHT", -18, y)
  return legend
end

-- A title with its legend under it; returns the legend and where a chart
-- under them starts.
local function section(page, y, title, hint)
  local head = heading(page, title, y, hint)
  local legend = legendAt(page, y - 24)
  return legend, y - 42, head
end

local function statusLegend()
  local entries = {}
  for _, status in ipairs(CHART_ORDER) do
    entries[#entries + 1] = { color = COLORS[status], text = STATUS_LABELS[status] }
  end
  return entries
end

local function statusSegments(counts)
  local segments = {}
  for _, status in ipairs(CHART_ORDER) do
    segments[#segments + 1] = { value = counts[status] or 0, color = COLORS[status], label = STATUS_LABELS[status] }
  end
  return segments
end

local function newPage(frame)
  local page = CreateFrame("Frame", nil, frame)
  page:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -66)
  page:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 22)
  page:Hide()
  return page
end

-- A row of figure cards across the top of a page: the number first, what it
-- counts under it, and a small change beside it when there is one.
local function buildTiles(page, y, count, icons)
  local row = { tiles = {}, count = count }
  for index = 1, count do
    local tile = CreateFrame("Frame", nil, page)
    tile:SetHeight(TILE_HEIGHT)
    local ground = themedTexture(tile:CreateTexture(nil, "BACKGROUND"), "card", nil, true)
    ground:SetAllPoints()
    Addon.AddOutline(tile, 0.8)
    tile:EnableMouse(true)
    tile.hover = tile:CreateTexture(nil, "HIGHLIGHT")
    tile.hover:SetAllPoints()
    tile.hover:SetColorTexture(1, 1, 1, 0.06)
    tile.hover:Hide()
    tile:SetScript("OnEnter", function(self)
      local tip = self.tip
      if not tip then return end
      self.hover:Show()
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:SetText(tip.title, 1, 1, 1)
      for _, line in ipairs(tip.lines) do GameTooltip:AddLine(line, 0.82, 0.82, 0.82, true) end
      GameTooltip:Show()
    end)
    tile:SetScript("OnLeave", function(self)
      self.hover:Hide()
      GameTooltip:Hide()
    end)
    -- What the figure is about, as an item is drawn: an icon, in a rim that takes
    -- the colour of the status it belongs to.
    tile.icon = Addon.Kit.IconFrame(tile, 28)
    tile.icon:SetPoint("LEFT", 7, 0)
    tile.iconPath = icons and icons[index]
    tile.value = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    tile.value:SetPoint("TOPLEFT", 41, -6)
    tile.delta = tile:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tile.delta:SetPoint("BOTTOMLEFT", tile.value, "BOTTOMRIGHT", 6, 1)
    tile.caption = tile:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tile.caption:SetPoint("BOTTOMLEFT", 41, 7)
    tile.caption:SetPoint("BOTTOMRIGHT", -5, 7)
    tile.caption:SetJustifyH("LEFT")
    tile.caption:SetWordWrap(false)
    row.tiles[index] = tile
  end
  function row.layout()
    local gap = 6
    local width = ((page:GetWidth() or 0) - 36 - gap * (count - 1)) / count
    if width < 20 then return end
    for index, tile in ipairs(row.tiles) do
      tile:ClearAllPoints()
      tile:SetPoint("TOPLEFT", page, "TOPLEFT", 18 + (index - 1) * (width + gap), y)
      tile:SetWidth(width)
    end
  end
  -- `tip` is { title, lines } for the tooltip; `deltaColor` tints the small
  -- change beside the figure (green unless the caller says otherwise).
  function row.set(index, value, caption, delta, accent, tip, deltaColor)
    local tile = row.tiles[index]
    tile.value:SetText(value)
    tile.caption:SetText(caption or "")
    tile.delta:SetText(delta or "")
    deltaColor = deltaColor or COLORS.known
    tile.delta:SetTextColor(deltaColor[1], deltaColor[2], deltaColor[3])
    tile.tip = tip
    Addon.Kit.SetIcon(tile.icon, tile.iconPath or "INV_Misc_QuestionMark", accent or { 0.62, 0.58, 0.50 })
  end
  page:SetScript("OnSizeChanged", row.layout)
  page:SetScript("OnShow", row.layout)
  row.layout()
  return row
end

local function paceText(rate)
  return rate >= 10 and string.format("%d", math.floor(rate + 0.5)) or string.format("%.1f", rate)
end

-- The Known count over the days behind and the days ahead, one column a day,
-- with the days ahead carried on at the recent pace; plus the same columns for
-- a strip of how many were marked each day. Returns the two chart data tables.
local function knownTrend(stats, back)
  local known, rate = stats.known, stats.knownRate
  local totals, newer = {}, 0
  for offset = 0, back - 1 do
    totals[offset] = known - newer
    newer = newer + stats.knownByDay[offset]
  end
  local step = back > 60 and 15 or 10
  local bars, strip, labels, values, texts = {}, {}, {}, {}, {}
  for index = 1, back do
    local offset = back - index
    local gained = stats.knownByDay[offset]
    local title = dayText(stats, offset, true)
    bars[index] = { title = title, lines = { gained > 0 and string.format("+%d marked Known that day", gained) or "None marked that day" } }
    strip[index] = { title = title, segments = { { value = gained, color = COLORS.known, label = "Marked Known" } } }
    values[index] = totals[offset]
    if offset % step == 0 then labels[index] = offset == 0 and LABELS.statsToday or dayText(stats, offset) end
  end
  for ahead = 1, PROJECT_DAYS do
    local index = back + ahead
    local projected = known + rate * ahead
    local title = dayText(stats, -ahead, true) .. "  (estimate)"
    bars[index] = { title = title, lines = { "At the pace of the last 30 days" } }
    strip[index] = {
      title = title,
      segments = { { value = rate, color = COLORS.known, alpha = 0.45, label = "Estimate", text = string.format("%.1f", rate) } },
    }
    values[index] = projected
    texts[index] = "~" .. math.floor(projected + 0.5)
    if ahead % 10 == 0 then labels[index] = "+" .. ahead end
  end
  local trend = {
    bars = bars, xLabels = labels, yFit = true, emptyText = LABELS.statsNoKnown,
    shadeFrom = back + 1,
    shadeLabel = rate > 0 and string.format("%s: %s a day%s", LABELS.statsEstimate, paceText(rate),
      stats.paceDays < 7 and " (rough)" or "") or LABELS.statsEstimate,
    lines = { {
      values = values, texts = texts, color = COLORS.known, label = "Known words",
      from = back, marks = { back, back + PROJECT_DAYS },
    } },
  }
  local bars2 = { bars = strip, shadeFrom = back + 1, caption = LABELS.statsMarkedPerDay, captionRight = true }
  return trend, bars2
end

local function knownLegend()
  return {
    { color = COLORS.known, line = true, text = "Known words" },
    { color = COLORS.known, line = true, alpha = 0.6, text = "At the recent pace" },
  }
end

-- ---------------------------------------------------------------------------
-- Overview

local function buildOverview(frame)
  local page = newPage(frame)
  page.tiles = buildTiles(page, -2, 3, { "INV_Misc_Book_09", "INV_Misc_PocketWatch_01", "INV_Misc_Spyglass_02" })

  local bar = CreateFrame("Frame", nil, page)
  bar:SetPoint("TOPLEFT", 18, -58)
  bar:SetPoint("TOPRIGHT", -18, -58)
  bar:SetHeight(14)
  local ground = themedTexture(bar:CreateTexture(nil, "BACKGROUND"), "track")
  ground:SetAllPoints()
  bar.parts = {}
  for _, status in ipairs(STACK_ORDER) do
    bar.parts[status] = bar:CreateTexture(nil, "ARTWORK")
  end
  Addon.AddOutline(bar, 1)
  function bar:Update()
    local counts, total = self.counts, self.total or 0
    local width = self:GetWidth() or 0
    if not counts or total <= 0 or width < 2 then return end
    local theme = Addon.ChartTheme()
    for _, status in ipairs(STACK_ORDER) do
      Addon.Kit.Gloss(self.parts[status], COLORS[status], 0.92, theme)
    end
    local x, running = 0, 0
    for _, status in ipairs(STACK_ORDER) do
      running = running + (counts[status] or 0)
      local edge = math.floor(running / total * width + 0.5)
      local part = self.parts[status]
      part:ClearAllPoints()
      part:SetPoint("TOPLEFT", self, "TOPLEFT", x, 0)
      part:SetSize(math.max(edge - x, 0.01), 14)
      part:SetShown(edge > x)
      Addon.Kit.GlossShown(part, edge > x)
      x = edge
    end
  end
  bar:SetScript("OnSizeChanged", bar.Update)
  page.stack = bar

  page.rows = {}
  for index, status in ipairs(ROW_ORDER) do
    local y = -80 - (index - 1) * 16
    local dot = page:CreateTexture(nil, "ARTWORK")
    dot:SetColorTexture(COLORS[status][1], COLORS[status][2], COLORS[status][3], 1)
    dot:SetSize(8, 8)
    dot:SetPoint("TOPLEFT", 18, y - 2)
    local label = text(page, "GameFontNormalSmall", 32, y)
    label:SetText(STATUS_LABELS[status])
    label:SetTextColor(0.78, 0.82, 0.88)
    local percent = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    percent:SetPoint("TOPRIGHT", -18, y)
    percent:SetWidth(48)
    percent:SetJustifyH("RIGHT")
    local value = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    value:SetPoint("TOPRIGHT", -72, y)
    value:SetTextColor(COLORS[status][1], COLORS[status][2], COLORS[status][3])
    page.rows[status] = { value = value, percent = percent, dot = dot }
  end

  divider(page, -148)
  local legend, chartY = section(page, -156, LABELS.statsKnownTrend, LABELS.statsKnownTrendNote)
  legend:SetEntries(knownLegend())
  page.chart = chartAt(page, chartY, nil, { totalLabel = "Words" }, 74)

  page.milestone = footLine(page, 42, 2)
  -- The difficult-words figure keeps a row of its own, label left and number
  -- right, which is where the older page had it and what the window's tests read.
  page.facts = footLine(page, 24, 1)
  page.facts:ClearAllPoints()
  page.facts:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 18, 24)
  page.facts:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -150, 24)
  page.facts:SetWordWrap(false)
  local difficult = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  difficult:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -18, 24)
  local difficultName = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  difficultName:SetPoint("BOTTOMRIGHT", difficult, "BOTTOMLEFT", -6, 0)
  difficultName:SetText(LABELS.difficultWords)
  page.extras = { difficult = difficult }
  page.top = footLine(page, 6, 1, "GameFontHighlightSmall")

  function page.refresh(stats)
    local known, total = stats.known, stats.total
    local rate = stats.knownRate
    local pace = rate > 0
    local target = nextMilestone(known)
    local days = pace and (target - known) / rate or nil

    local pace7 = stats.knownRate7
    local paceNote = stats.paceDays < RECENT_DAYS
      and string.format("Averaged over the %d days there is data for, so it is still rough.", stats.paceDays)
      or "Averaged over the last 30 days."
    page.tiles.set(1, tostring(known),
      total > 0 and string.format("Known, %d%% of all", math.floor(known / total * 100 + 0.5)) or "Known",
      stats.knownGained7 > 0 and string.format("+%d wk", stats.knownGained7) or nil, COLORS.known,
      { title = "Known words", lines = {
        string.format("%d of your %d words are marked Known (%.1f%%).", known, total, total > 0 and known / total * 100 or 0),
        string.format("%d of them were marked in the last 7 days, %d in the last 30.", stats.knownGained7, stats.knownGained30),
      } })
    page.tiles.set(2, pace and (paceText(rate) .. "/day") or "-",
      pace and "marked, 30 days" or "no pace yet",
      pace and string.format("wk %s", paceText(pace7)) or nil, COLORS.known,
      { title = "Your pace", lines = pace and {
        string.format("About %s words a day are being marked Known. %s", paceText(rate), paceNote),
        string.format("The last 7 days: %s a day, %s.", paceText(pace7),
          pace7 >= rate and "as fast or faster" or "slower than the average"),
        "The estimate on the chart carries this pace forward. It is a trend, not a promise.",
      } or { "No word has been marked Known lately, so there is nothing to carry forward." } },
      pace7 >= rate and COLORS.known or COLORS.learning)
    page.tiles.set(3, tostring(target),
      days and (days <= 365 and "next goal, " .. dayText(stats, -math.ceil(days)) or "goal: over a year")
        or "next Known goal", nil, COLORS.learning,
      { title = "Next goal", lines = {
        days and string.format("%d more Known words to reach %d: about %s at the current pace.", target - known, target,
          days <= 365 and (spanText(days) .. ", on " .. dayText(stats, -math.ceil(days), true)) or "more than a year")
          or string.format("%d more Known words to reach %d. Mark some Known to get an estimate.", target - known, target),
      } })

    bar.counts, bar.total = stats.byStatus, stats.total
    bar:Update()
    for status, row in pairs(page.rows) do
      -- Drawn again every time, not only when built: the colours can be changed
      -- in the settings with this window open.
      local color = COLORS[status]
      row.dot:SetColorTexture(color[1], color[2], color[3], 1)
      Addon.Kit.Speckle(row.dot, Addon.ChartTheme())
      row.value:SetTextColor(color[1], color[2], color[3])
      local count = stats.byStatus[status] or 0
      row.value:SetText(tostring(count))
      row.percent:SetText(stats.total > 0 and string.format("%.1f%%", count / stats.total * 100) or "")
    end

    local trend = knownTrend(stats, RECENT_DAYS)
    page.chart:SetData(trend)
    if pace then
      page.milestone:SetText(string.format(
        "%d marked Known in the last %d days, about %s a day. At that pace %d Known comes around %s. A trend, not a promise.",
        stats.knownGained30, stats.paceDays, paceText(rate), target,
        days <= 365 and dayText(stats, -math.ceil(days), true) or "after a year"))
    else
      page.milestone:SetText("Nothing has been marked Known lately, so there is no pace to carry forward.")
    end

    page.facts:SetText(string.format("+%d words in 7 days, +%d in 30", stats.added7, stats.added30))
    page.extras.difficult:SetText(tostring(stats.difficult))

    local parts = {}
    for index = 1, #stats.top do
      local entry = stats.top[index]
      local color = COLORS[entry.status or "new"] or COLORS.new
      local function byte(value) return math.floor(value * 255 + 0.5) end
      parts[index] = string.format("|cff%02x%02x%02x%s|r |cff8c94a0%d|r", byte(color[1]), byte(color[2]), byte(color[3]),
        entry.word or "", entry.encounterCount or 0)
    end
    page.top:SetText(#parts > 0 and (LABELS.mostEncountered .. ":  " .. table.concat(parts, "   ")) or "")
  end
  return page
end

-- ---------------------------------------------------------------------------
-- Growth

local function buildGrowth(frame)
  local page = newPage(frame)
  page.tiles = buildTiles(page, -2, 3, { "INV_Misc_Book_09", "INV_Misc_Spyglass_03", "INV_Misc_Book_11" })

  local legend, chartY = section(page, -58, LABELS.statsKnownTrend, LABELS.statsKnownTrendNote)
  legend:SetEntries(knownLegend())
  page.chart = chartAt(page, chartY, 124, { totalLabel = "Words", bottomPad = 15 })
  page.strip = chartAt(page, chartY - 126, 44, { totalLabel = "Words", bottomPad = 2 })

  divider(page, chartY - 180)
  local legend2, chart2Y, head2 = section(page, chartY - 188, LABELS.statsVocabulary)
  page.vocabHead = head2
  legend2:SetEntries(statusLegend())
  page.chart2 = chartAt(page, chart2Y, nil, { totalLabel = "Words" }, 4)

  function page.refresh(stats)
    local known, rate = stats.known, stats.knownRate
    local pace = rate > 0
    local learning = stats.byStatus.learning or 0
    local ahead = math.floor(rate * PROJECT_DAYS + 0.5)
    page.tiles.set(1, "+" .. stats.knownGained30, "marked, 30 days", nil, COLORS.known,
      { title = "Marked Known, last 30 days", lines = {
        string.format("%d words changed to Known in the last 30 days, counted on the day you marked them.", stats.knownGained30),
        "The bars under the chart show them day by day.",
      } })
    page.tiles.set(2, pace and ("~" .. (known + ahead)) or tostring(known),
      "Known in 30 days", pace and ("+" .. ahead) or nil, COLORS.known,
      { title = "Known in 30 days", lines = pace and {
        string.format("%d Known now, plus %d at %s a day.", known, ahead, paceText(rate)),
        "A straight line from your recent pace. A trend, not a promise.",
      } or { "No pace to carry forward yet." } })
    page.tiles.set(3, pace and learning > 0 and spanText(learning / rate) or "-",
      learning > 0 and string.format("all %d Learning", learning) or "nothing Learning", nil, COLORS.learning,
      { title = "The Learning pile", lines = pace and learning > 0 and {
        string.format("At %s a day, moving all %d Learning words to Known would take about %s.", paceText(rate), learning,
          spanText(learning / rate)),
        "Some will end up Ignored instead, so read it as an upper bound.",
      } or { "Nothing is Learning, or there is no pace to work from." } })

    -- As far back as there is anything to show, and no further.
    local back = math.max(RECENT_DAYS, math.min(HISTORY_DAYS, stats.oldestKnown + 3))
    local trend, strip = knownTrend(stats, back)
    page.chart:SetData(trend)
    page.strip:SetData(strip)

    -- The pool as it stood each evening: run forward from the words older than
    -- the window, adding each day's new ones.
    local running = { new = stats.base.new, learning = stats.base.learning, known = stats.base.known, ignored = stats.base.ignored }
    -- From the day the oldest word was met, not from ninety days back: a
    -- profile ten weeks old would otherwise open on three weeks of nothing.
    local span = math.max(RECENT_DAYS, math.min(HISTORY_DAYS, stats.oldestAdded + 3))
    local step = span > 60 and 15 or (span > 30 and 10 or 5)
    local bars, labels = {}, {}
    for offset = HISTORY_DAYS - 1, 0, -1 do
      local added = stats.addedByDay[offset]
      for _, status in ipairs(STACK_ORDER) do
        running[status] = running[status] + added[status]
      end
      if offset < span then
        local index = span - offset
        bars[index] = {
          title = dayText(stats, offset, true),
          segments = statusSegments(running),
          lines = { string.format("+%d that day", added.new + added.learning + added.known + added.ignored) },
        }
        if offset % step == 0 then labels[index] = offset == 0 and LABELS.statsToday or dayText(stats, offset) end
      end
    end
    page.chart2:SetData({ bars = bars, xLabels = labels, emptyText = LABELS.statsNoData })
    if page.vocabHead.hint then
      page.vocabHead.hint:SetText(string.format("%d words, +%d in 7 days, +%d in 30", stats.total, stats.added7, stats.added30))
    end
  end
  return page
end

-- ---------------------------------------------------------------------------
-- Forecast

local function buildForecast(frame)
  local page = newPage(frame)
  page.tiles = buildTiles(page, -2, 3, { "INV_Scroll_05", "INV_Misc_Note_02", "INV_Misc_Map_01" })

  local legend, chartY = section(page, -58, LABELS.statsForecastTitle)
  page.legend = legend
  page.chart = chartAt(page, chartY, 120, { totalLabel = "Words" })
  page.explain = note(page, chartY - 124, 2)

  divider(page, chartY - 156)
  local legend2, chart2Y = section(page, chartY - 164, LABELS.statsHorizonTitle)
  page.legend2 = legend2
  page.chart2 = chartAt(page, chart2Y, nil, { totalLabel = "Words", values = true }, 78)

  -- The three words that will be ready soonest, held to the foot of the page.
  page.nextRule = themedTexture(page:CreateTexture(nil, "ARTWORK"), "rule", nil, false, true)
  page.nextRule:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 18, 70)
  page.nextRule:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -18, 70)
  page.nextRule:SetHeight(1)
  footPlate(page, 50)
  local head = themedHeading(page:CreateFontString(nil, "OVERLAY", "GameFontNormal"))
  head:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 22, 50)
  head:SetJustifyH("LEFT")
  head:SetText(LABELS.statsNextReady)
  page.nextRows = {}
  for index = 1, 3 do
    local bottom = 6 + (3 - index) * 14
    local name = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 18, bottom)
    name:SetJustifyH("LEFT")
    local detail = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    detail:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -18, bottom)
    detail:SetJustifyH("RIGHT")
    page.nextRows[index] = { name = name, detail = detail }
  end

  function page.refresh(stats)
    local readyNote = string.format("Ready means seen in at least %d quests and Learning for %d days.",
      stats.readyAfter, READY_AFTER_DAYS)
    local enough30 = 0
    for offset = 0, FORECAST_DAYS do enough30 = enough30 + stats.forecastMet[offset] end
    page.tiles.set(1, tostring(stats.forecastMet[0] + stats.forecastEstimated[0]), "ready now", nil, COLORS.known,
      { title = "Ready now", lines = { readyNote, "Moving a word to Known is still up to you: the editor offers it." } })
    page.tiles.set(2, tostring(stats.readyWithin7), "within a week", nil, COLORS.known,
      { title = "Ready within a week", lines = { readyNote, "Includes the words that are ready now." } })
    page.tiles.set(3, tostring(stats.readyWithin30), "within a month", nil, COLORS.known,
      { title = "Ready within a month", lines = {
        readyNote,
        string.format("%d of these already have enough quests; the other %d are estimated from how often the word has turned up so far.",
          enough30, stats.readyWithin30 - enough30),
      } })

    page.legend:SetEntries({
      { color = COLORS.known, text = "Enough quests seen" },
      { color = COLORS.known, alpha = 0.45, text = "Estimated" },
      { color = COLORS.text, line = true, text = "Added up" },
    })
    local bars, labels, cumulative = {}, {}, {}
    local running = 0
    for offset = 0, FORECAST_DAYS do
      local met, guessed = stats.forecastMet[offset], stats.forecastEstimated[offset]
      running = running + met + guessed
      local index = offset + 1
      bars[index] = {
        title = offset == 0 and "Today" or string.format("In %d days  (%s)", offset, dayText(stats, -offset, true)),
        segments = {
          { value = met, color = COLORS.known, label = "Enough quests seen" },
          { value = guessed, color = COLORS.known, alpha = 0.45, label = "Estimated" },
        },
      }
      cumulative[index] = running
      if offset % 5 == 0 then labels[index] = offset == 0 and LABELS.statsNow or ("+" .. offset) end
    end
    page.chart:SetData({
      bars = bars, xLabels = labels, emptyText = "No word is waiting to be ready",
      lines = { { values = cumulative, color = COLORS.text, label = "Added up", marks = { 1, FORECAST_DAYS + 1 } } },
    })
    page.explain:SetText(readyNote .. " Paler bars are a guess from how often the word has turned up so far.")

    page.legend2:SetEntries({
      { color = COLORS.known, text = "Enough quests seen" },
      { color = COLORS.known, alpha = 0.45, text = "Estimated" },
      { color = COLORS.learning, alpha = 0.55, text = "Not within a year" },
    })
    local bars2, labels2 = {}, {}
    local scale = 0
    for index, horizon in ipairs(HORIZONS) do
      local slot = stats.horizon[index]
      scale = math.max(scale, slot.met + slot.guessed)
      bars2[index] = {
        title = horizon.title,
        segments = {
          { value = slot.met, color = COLORS.known, label = "Enough quests seen" },
          { value = slot.guessed, color = COLORS.known, alpha = 0.45, label = "Estimated" },
        },
      }
      labels2[index] = horizon.label
    end
    -- What lies beyond a year is most of the pile and would flatten the rest:
    -- the bar runs off the top, and its figure is in the label.
    local later = stats.horizon[#HORIZONS + 1]
    local laterCount = later.met + later.guessed
    local last = #HORIZONS + 1
    bars2[last] = {
      title = "Not within a year",
      segments = { { value = laterCount, color = COLORS.learning, alpha = 0.55, label = "Words" } },
      lines = { "No sign yet of enough quests in that time, at the rate they turn up now." },
    }
    labels2[last] = string.format("Later  %d", laterCount)
    page.chart2:SetData({
      bars = bars2, xLabels = labels2, yMax = scale, emptyText = LABELS.statsNoData,
    })

    for index, row in ipairs(page.nextRows) do
      local item = stats.nextReady[index]
      if item then
        row.name:SetText(item.word)
        row.name:SetTextColor(COLORS.learning[1], COLORS.learning[2], COLORS.learning[3])
        row.detail:SetText(item.guessed
          and string.format("%d of %d quests, about %s", item.count, stats.readyAfter, spanText(item.ready))
          or string.format("%d quests, ready in %s", item.count, spanText(item.ready)))
      elseif index == 1 then
        row.name:SetText("No Learning word is close to ready")
        row.name:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
        row.detail:SetText("")
      else
        row.name:SetText("")
        row.detail:SetText("")
      end
    end
  end
  return page
end

-- ---------------------------------------------------------------------------
-- Recall

local function buildRecall(frame)
  local page = newPage(frame)
  page.tiles = buildTiles(page, -2, 3, { "INV_Letter_15", "INV_Misc_Gear_01", "Ability_Marksmanship" })

  local legend, chartY = section(page, -58, LABELS.statsRatingsPerDay)
  legend:SetEntries({
    { color = COLORS.known, text = "4-5  knew it" },
    { color = COLORS.learning, text = "3" },
    { color = WEAK, text = "1-2  hardly" },
  })
  page.chart = chartAt(page, chartY, 128, { totalLabel = "Ratings" })

  heading(page, LABELS.statsRatingSpread, chartY - 138)
  page.chart2 = chartAt(page, chartY - 158, nil, { totalLabel = "Ratings", values = true }, 38)

  page.divider = themedTexture(page:CreateTexture(nil, "ARTWORK"), "rule", nil, false, true)
  page.divider:SetHeight(1)
  page.hardPlate = footPlate(page, 10)
  page.hardHead = themedHeading(page:CreateFontString(nil, "OVERLAY", "GameFontNormal"))
  page.hardHead:SetJustifyH("LEFT")
  page.hardHead:SetText(LABELS.statsHardest)
  page.hardRows = {}
  for index = 1, 5 do
    local name = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetJustifyH("LEFT")
    name:SetMaxLines(1)
    name:SetWordWrap(false)
    local value = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    value:SetJustifyH("RIGHT")
    page.hardRows[index] = { name = name, value = value }
  end

  -- The list sits at the foot of the page and is only as tall as it has rows;
  -- the chart above it takes what is left, so a short list does not leave a
  -- hole under it.
  local function layoutHardest(rows)
    local top = 6 + rows * 16
    for index, row in ipairs(page.hardRows) do
      local bottom = 6 + (rows - index) * 16
      row.name:ClearAllPoints()
      row.name:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 18, bottom)
      row.name:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -90, bottom)
      row.value:ClearAllPoints()
      row.value:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -18, bottom)
      row.name:SetShown(index <= rows)
      row.value:SetShown(index <= rows)
    end
    page.hardHead:ClearAllPoints()
    page.hardHead:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 22, top + 4)
    page.hardPlate:ClearAllPoints()
    page.hardPlate:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 12, top - 1)
    page.hardPlate:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -14, top - 1)
    page.divider:ClearAllPoints()
    page.divider:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 18, top + 24)
    page.divider:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -18, top + 24)
    page.chart2:ClearAllPoints()
    page.chart2:SetPoint("TOPLEFT", page, "TOPLEFT", 12, chartY - 158)
    page.chart2:SetPoint("TOPRIGHT", page, "TOPRIGHT", -14, chartY - 158)
    page.chart2:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 12, top + 32)
    page.chart2:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -14, top + 32)
  end
  layoutHardest(1)

  function page.refresh(stats)
    local recall = stats.recall
    if recall.total > 0 then
      local knew = recall.byScore[4] + recall.byScore[5]
      local average = recall.sum / recall.total
      page.tiles.set(1, tostring(recall.total), string.format("ratings, %d words", recall.words), nil, { 0.62, 0.58, 0.50 },
        { title = "Recall ratings", lines = {
          "Each rating is your answer to \"did you know this word?\", from 1 (hardly) to 5 (knew it).",
          string.format("%d ratings so far, on %d different words.", recall.total, recall.words),
        } })
      page.tiles.set(2, string.format("%.1f", average), "average, of 5",
        nil, average < 2.5 and WEAK or (average < 3.5 and COLORS.learning or COLORS.known),
        { title = "Average rating", lines = { "The mean of every rating given. Under 2.5 means the words are mostly not sticking yet." } })
      page.tiles.set(3, string.format("%d%%", math.floor(knew / recall.total * 100 + 0.5)), "knew it (4-5)",
        nil, COLORS.known,
        { title = "Knew it", lines = { string.format("%d of %d ratings were a 4 or a 5.", knew, recall.total) } })
    else
      local none = { title = "No ratings yet", lines = { "The recall question comes after a word has been Learning for a day. Answer it from 1 to 5 and the figures fill in." } }
      page.tiles.set(1, "0", "ratings so far", nil, nil, none)
      page.tiles.set(2, "-", "average, of 5", nil, nil, none)
      page.tiles.set(3, "-", "knew it (4-5)", nil, nil, none)
    end

    local bars, labels = {}, {}
    for index = 1, RECENT_DAYS do
      local offset = RECENT_DAYS - index
      local day = recall.byDay[offset]
      bars[index] = {
        title = dayText(stats, offset, true),
        segments = {
          { value = day.good, color = COLORS.known, label = "4-5" },
          { value = day.mid, color = COLORS.learning, label = "3" },
          { value = day.weak, color = WEAK, label = "1-2" },
        },
      }
      if offset % 5 == 0 then labels[index] = offset == 0 and LABELS.statsToday or dayText(stats, offset) end
    end
    page.chart:SetData({
      bars = bars, xLabels = labels,
      emptyText = "The question comes after a word has been Learning for a day",
    })

    local bars2, labels2 = {}, {}
    local colors = { WEAK, WEAK, COLORS.learning, COLORS.known, COLORS.known }
    for score = 1, 5 do
      bars2[score] = {
        title = "Rated " .. score,
        segments = { { value = recall.byScore[score], color = colors[score], label = "Ratings" } },
      }
      labels2[score] = tostring(score)
    end
    page.chart2:SetData({ bars = bars2, xLabels = labels2, emptyText = LABELS.statsNoData })

    layoutHardest(math.max(1, math.min(5, #stats.hardest)))
    for index, row in ipairs(page.hardRows) do
      local item = stats.hardest[index]
      if item then
        row.name:SetText(item.word or "")
        row.name:SetTextColor(COLORS.learning[1], COLORS.learning[2], COLORS.learning[3])
        row.value:SetText(string.format("%.1f  (%d)", item.mean or 0, item.count or 0))
      elseif index == 1 then
        row.name:SetText(LABELS.statsNoDifficult)
        row.name:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
        row.value:SetText("")
      else
        row.name:SetText("")
        row.value:SetText("")
      end
    end
  end
  return page
end

-- ---------------------------------------------------------------------------
-- The window

local TAB_ORDER = { "overview", "growth", "forecast", "recall" }
local TAB_LABELS = {
  overview = "statsTabOverview", growth = "statsTabGrowth",
  forecast = "statsTabForecast", recall = "statsTabRecall",
}
local TAB_BUILDERS = { overview = buildOverview, growth = buildGrowth, forecast = buildForecast, recall = buildRecall }

-- A tab's three looks, one for each style a theme asks for: a box lit in the
-- accent colour, an underline in it, or a lighter filled block. Whichever, the
-- open page is the lit one and the others are dimmer, and a pointer over an
-- unlit one lifts its label towards the accent.
local function tabUnderline(button)
  if not button.underline then
    button.underline = button:CreateTexture(nil, "OVERLAY")
    button.underline:SetPoint("BOTTOMLEFT", 3, 2)
    button.underline:SetPoint("BOTTOMRIGHT", -3, 2)
    button.underline:SetHeight(2)
  end
  return button.underline
end

local function styleTab(button, active, hover)
  local theme = Addon.ChartTheme()
  local accent, dim = theme.accent, theme.dim
  local underline = tabUnderline(button)
  underline:Hide()
  local native = theme.kit == "stone" and Addon.Kit.AttachTabArt(button)
  if native then
    -- The art draws the tab; the button's own box is switched off. Lit is the
    -- pale cream the game gives a chosen tab, the rest stay the usual gold.
    button:SetBackdropColor(0, 0, 0, 0)
    button:SetBackdropBorderColor(0, 0, 0, 0)
    Addon.Kit.ShowTabArt(button, active and "active" or "inactive")
    button.label:SetTextColor(1, active and 0.94 or 0.82, active and 0.77 or 0)
    button.label:ClearAllPoints()
    button.label:SetPoint("CENTER", 0, 2)
    return
  end
  Addon.Kit.ShowTabArt(button, nil)
  button.label:ClearAllPoints()
  button.label:SetPoint("CENTER")
  if theme.tab == "underline" then
    button:SetBackdropColor(0, 0, 0, active and 0.30 or 0)
    button:SetBackdropBorderColor(0, 0, 0, 0)
    if active then
      underline:SetColorTexture(accent[1], accent[2], accent[3], 1)
      underline:Show()
    elseif hover then
      underline:SetColorTexture(accent[1], accent[2], accent[3], 0.35)
      underline:Show()
    end
  elseif theme.tab == "fill" then
    button:SetBackdropColor(active and 0.32 or 0.11, active and 0.33 or 0.12, active and 0.36 or 0.14, 1)
    button:SetBackdropBorderColor(0, 0, 0, 0)
  else
    button:SetBackdropColor(0, 0, 0, active and 0.55 or 0.30)
    if active then
      button:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.95)
    elseif hover then
      button:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.60)
    else
      button:SetBackdropBorderColor(theme.edge[1], theme.edge[2], theme.edge[3], math.max(theme.edge[4], 0.35))
    end
  end
  local label = (active or hover) and accent or dim
  button.label:SetTextColor(label[1], label[2], label[3])
end

local function styleTabs(frame)
  for _, key in ipairs(TAB_ORDER) do
    styleTab(frame.tabs[key], key == frame.tab, false)
  end
end

local function layoutTabs(frame)
  local width = ((frame:GetWidth() or 460) - 36 - 3 * 4) / 4
  for index, key in ipairs(TAB_ORDER) do
    local button = frame.tabs[key]
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", 18 + (index - 1) * (width + 4), -30)
    button:SetSize(width, Addon.ChartTheme().kit == "stone" and Addon.Kit.CanTabs() and 32 or Addon.RoleButtonHeight())
  end
end

local function showTab(frame, key)
  frame.tab = key
  Addon.statsTab = key
  for name, page in pairs(frame.pages) do page:SetShown(name == key) end
  styleTabs(frame)
end

-- The shoulder buttons of a controller walk the tabs, the way they do in the
-- settings window.
function Addon.StatsStepTab(step)
  if not statsFrame then return end
  local at = 1
  for index, key in ipairs(TAB_ORDER) do if key == statsFrame.tab then at = index end end
  showTab(statsFrame, TAB_ORDER[(at - 1 + step) % #TAB_ORDER + 1])
end

local function buildWindow()
  -- The same chrome as the word list, the editor and the library, rather
  -- than a plain frame wearing the DialogFrame border while every other
  -- window here wears the native skin. The theme was reaching the reader and
  -- the library and skipping this one, which is what made it look bolted on.
  statsFrame = Addon.CreateNativeWindow("WordHunterWoWStats", "library", LABELS.statsTitle)
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
  Addon.ApplyWindowScale("statsScale")
  -- Four pages of charts need more room than the one list of figures did. The
  -- floor also lifts a smaller size saved by an earlier build, which a plain
  -- default never would.
  Addon.MakeResizable(statsFrame, "stats", 440, 550, 760, 860)
  statsFrame:Hide()

  local brand = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  brand:SetPoint("TOPLEFT", 18, -12)
  brand:SetText(LABELS.statsTitle)
  -- Under a native title bar the window already says its own name.
  if rawget(statsFrame, "whwNativeStyle") then brand:Hide() end

  local close = Addon.NativeCloseButton(statsFrame)
  close:SetPoint("TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function() statsFrame:Hide() end)

  statsFrame.tabs, statsFrame.pages = {}, {}
  for _, key in ipairs(TAB_ORDER) do
    local button = Addon.createFlatButton(statsFrame, LABELS[TAB_LABELS[key]], COLORS.neutral)
    button:SetScript("OnClick", function() showTab(statsFrame, key) end)
    -- createFlatButton's own leave handler restyles against the selected word,
    -- which a tab has none of, and would drop the lit state the moment the
    -- pointer left.
    button:SetScript("OnLeave", function() styleTabs(statsFrame) end)
    button:SetScript("OnEnter", function(self)
      if key ~= statsFrame.tab then styleTab(self, false, true) end
    end)
    statsFrame.tabs[key] = button
    statsFrame.pages[key] = TAB_BUILDERS[key](statsFrame)
  end
  -- The figures under the overview chart, where the older page had them.
  statsFrame.extraRows = statsFrame.pages.overview.extras
  statsFrame:HookScript("OnSizeChanged", layoutTabs)
  layoutTabs(statsFrame)
  showTab(statsFrame, Addon.statsTab or "overview")
end

-- The player changed the background style while the window exists: redo every
-- colour in it, and draw the pages again so the charts pick the new ones up.
function Addon.RefreshStatsTheme()
  if not statsFrame then return end
  applyTheme()
  layoutTabs(statsFrame)
  styleTabs(statsFrame)
  if statsFrame.stats and statsFrame:IsShown() then
    for _, page in pairs(statsFrame.pages) do page.refresh(statsFrame.stats) end
  end
end

function Addon.toggleStats()
  if not statsFrame then buildWindow() end
  if statsFrame:IsShown() then
    statsFrame:Hide()
    return
  end
  local stats = computeStats(time())
  statsFrame.stats = stats
  applyTheme()
  styleTabs(statsFrame)
  for _, page in pairs(statsFrame.pages) do page.refresh(stats) end
  Addon.PlaceFrame(statsFrame, "stats")
  layoutTabs(statsFrame)
  statsFrame:Show()
  statsFrame:Raise()
end
